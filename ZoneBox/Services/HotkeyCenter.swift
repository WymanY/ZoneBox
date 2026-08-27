import AppKit
import Carbon
import ZoneBoxCore

/// Carbon `EventHandlerUPP` cannot capture context, so this trampoline hops to the main actor.
private func zoneBoxCarbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    HotkeyCenter.dispatch(id: hotKeyID.id)
    return noErr
}

enum KeyEventBridge {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= CarbonModifier.command }
        if flags.contains(.shift) { mods |= CarbonModifier.shift }
        if flags.contains(.option) { mods |= CarbonModifier.option }
        if flags.contains(.control) { mods |= CarbonModifier.control }
        return mods
    }
}

@MainActor
final class HotkeyCenter {
    unowned var runtime: AppRuntime!
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var monitors: [Any] = []
    private var voiceOverObservation: NSKeyValueObservation?
    private var lastHandled: (id: UInt32, time: TimeInterval)?
    private var globalChordsEnabled = false
    private var chordIndex: [(id: UInt32, chord: KeyChord)] = []
    private static weak var shared: HotkeyCenter?

    private static let signature: OSType = 0x5A424F58 // 'ZBOX'
    /// Wide enough to collapse Carbon + NSEvent for one physical press, short
    /// enough that a second Control+Option+/ can still toggle the panel.
    private static let dedupWindow: TimeInterval = 0.05

    nonisolated static func dispatch(id: UInt32) {
        DispatchQueue.main.async {
            HotkeyCenter.shared?.handle(id: id)
        }
    }

    func start() {
        Self.shared = self
        installCarbonHandlerIfNeeded()

        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new, .initial]) { [weak self] _, _ in
            guard let center = self else { return }
            DispatchQueue.main.async { center.reregister() }
        }
        reregister()
    }

    func stop() {
        unregisterAll()
        removeMonitors()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        voiceOverObservation?.invalidate()
        voiceOverObservation = nil
        if Self.shared === self { Self.shared = nil }
    }

    func reregister() {
        unregisterAll()
        removeMonitors()
        globalChordsEnabled = !NSWorkspace.shared.isVoiceOverEnabled
        rebuildChordIndex()
        if globalChordsEnabled {
            registerAll()
        }
        installKeyMonitors()
        runtime.menuBar?.reloadMenu()
    }

    private func rebuildChordIndex() {
        let trusted = runtime.trust.isTrusted()
        chordIndex = ShortcutCatalog.carbonHotkeys(from: runtime.settings).filter { pair in
            trusted || ShortcutCatalog.trustExemptIDs.contains(pair.id)
        }
    }

    private func installCarbonHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            zoneBoxCarbonHotKeyHandler,
            1,
            &spec,
            nil,
            &eventHandler
        )
        if status != noErr {
            Log.hotkey.error("InstallEventHandler failed status=\(status, privacy: .public)")
        }
    }

    private func registerAll() {
        let trusted = runtime.trust.isTrusted()
        var registered = 0
        for pair in ShortcutCatalog.carbonHotkeys(from: runtime.settings) {
            if !trusted && !ShortcutCatalog.trustExemptIDs.contains(pair.id) { continue }
            if register(id: pair.id, chord: pair.chord) {
                registered += 1
            }
        }
        Log.hotkey.info("Registered \(registered, privacy: .public) Carbon hotkeys trusted=\(trusted, privacy: .public)")
    }

    @discardableResult
    private func register(id: UInt32, chord: KeyChord) -> Bool {
        guard chord.isSequoiaLegal else {
            Log.hotkey.error("Skipped Sequoia-illegal hotkey id=\(id, privacy: .public)")
            return false
        }
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(chord.keyCode),
            chord.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            hotKeys[id] = hotKeyRef
            return true
        }
        Log.hotkey.error(
            "RegisterEventHotKey failed id=\(id, privacy: .public) status=\(status, privacy: .public) caps=\(chord.displayCaps.joined(), privacy: .public)"
        )
        return false
    }

    private func unregisterAll() {
        for ref in hotKeys.values {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
    }

    private func installKeyMonitors() {
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKeyEvent(event, consume: true) ?? event
        }) {
            monitors.append(local)
        }
        // Always listen globally so Escape can cancel a snap while VoiceOver
        // has Control+Option chords paused.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            _ = self?.handleKeyEvent(event, consume: false)
        }) {
            monitors.append(global)
        }
    }

    private func removeMonitors() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent, consume: Bool) -> NSEvent? {
        let modifiers = KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == HardwareKeyCode.escape, !flags.contains(.command), !flags.contains(.control) {
            if consume {
                switch ShortcutRouteContext.escapeAction(
                    ShortcutRouteContext(
                        shortcutsPanelIsKey: runtime.shortcutPanelIsKey,
                        editorClaimsKeyboard: runtime.editorClaimsKeyboard,
                        appHasKeyWindow: NSApp.keyWindow != nil
                    )
                ) {
                case .closeShortcuts:
                    _ = runtime.closeShortcutPanelIfOpen()
                    return nil
                case .cancelEditor:
                    runtime.cancelEditor()
                    return nil
                case .cancelSnap:
                    runtime.engine.cancelSession()
                    return nil
                case .ignore:
                    return event
                }
            }
            runtime.engine.cancelSession()
            return event
        }

        if globalChordsEnabled,
           let id = ShortcutCatalog.hotkeyID(
               matching: event.keyCode,
               carbonModifiers: modifiers,
               chords: chordIndex
           )
        {
            if event.isARepeat, !ShortcutCatalog.allowsKeyRepeat(hotkeyID: id) {
                return consume ? nil : event
            }
            handle(id: id)
            return consume ? nil : event
        }

        if consume, runtime.editorClaimsKeyboard {
            if event.isARepeat, event.keyCode != HardwareKeyCode.tab {
                return event.keyCode == HardwareKeyCode.delete
                    || event.keyCode == HardwareKeyCode.forwardDelete
                    || event.keyCode == HardwareKeyCode.return
                    || event.keyCode == HardwareKeyCode.keypadEnter
                    ? nil
                    : event
            }
            if runtime.handleEditorKey(event) { return nil }
        }

        return event
    }

    func handle(id: UInt32) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastHandled, lastHandled.id == id, now - lastHandled.time < Self.dedupWindow {
            return
        }
        lastHandled = (id, now)

        guard runtime.trust.isTrusted() || ShortcutCatalog.trustExemptIDs.contains(id) else { return }
        switch id {
        case ShortcutCatalog.editorHotkeyID:
            runtime.openEditor()
        case ShortcutCatalog.previousZoneHotkeyID:
            runtime.snapAdjacent(delta: -1)
        case ShortcutCatalog.nextZoneHotkeyID:
            runtime.snapAdjacent(delta: 1)
        case ShortcutCatalog.cycleBackwardHotkeyID:
            runtime.engine.cycleWindowsInFocusedZone(delta: -1)
        case ShortcutCatalog.cycleForwardHotkeyID:
            runtime.engine.cycleWindowsInFocusedZone(delta: 1)
        case ShortcutCatalog.unsnapHotkeyID:
            runtime.engine.unsnapFocused()
        case ShortcutCatalog.shortcutsPanelHotkeyID:
            runtime.toggleShortcutPanel()
        case 1...9:
            runtime.engine.snapFocused(to: Int(id))
        default:
            break
        }
    }
}
