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
    unowned var runtime: HotkeyRuntimeHosting!
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var monitors: [Any] = []
    private var voiceOverObservation: NSKeyValueObservation?
    private var lastHandled: (id: UInt32, time: TimeInterval)?
    private var voiceOverEnabled = false
    private var recordingPaused = false
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
        voiceOverEnabled = NSWorkspace.shared.isVoiceOverEnabled
        rebuildChordIndex()
        registerAll()
        installKeyMonitors()
        runtime.reloadMenu()
    }

    func setRecordingPaused(_ paused: Bool) {
        recordingPaused = paused
        reregister()
    }

    private func rebuildChordIndex() {
        let trusted = runtime.isTrusted()
        chordIndex = ShortcutCatalog.carbonHotkeys(from: runtime.settings).filter { pair in
            (trusted || ShortcutCatalog.trustExemptIDs.contains(pair.id))
                && !recordingPaused
                && !ShortcutVoiceOverPolicy.shouldPause(chord: pair.chord, voiceOverEnabled: voiceOverEnabled)
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
        let trusted = runtime.isTrusted()
        var registered = 0
        for pair in ShortcutCatalog.carbonHotkeys(from: runtime.settings) {
            if !trusted && !ShortcutCatalog.trustExemptIDs.contains(pair.id) { continue }
            if recordingPaused { continue }
            if ShortcutVoiceOverPolicy.shouldPause(chord: pair.chord, voiceOverEnabled: voiceOverEnabled) { continue }
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
            if consume, runtime.isEditorEditingMetrics {
                return event
            }
            if consume {
                return handleEscape(event, consume: true)
            }
            return handleEscape(event, consume: false)
        }

        if runtime.engine.isQuickSnapperShowing,
           let number = QuickSnapperReducer.zoneNumber(forKeyCode: event.keyCode),
           !flags.contains(.command)
        {
            runtime.engine.handleQuickSnapper(.digit(number))
            return consume ? nil : event
        }

        if runtime.engine.isOverlayArmed,
           let number = QuickSnapperReducer.zoneNumber(forKeyCode: event.keyCode),
           !flags.contains(.command)
        {
            if !event.isARepeat {
                runtime.engine.handleOverlayDigit(number)
            }
            return consume ? nil : event
        }

        if runtime.engine.isOverlayArmed,
           event.keyCode == HardwareKeyCode.tab,
           !flags.contains(.command),
           !flags.contains(.control),
           !flags.contains(.option)
        {
            if !event.isARepeat {
                runtime.engine.handleCycleLayout(flags.contains(.shift) ? -1 : 1)
            }
            return consume ? nil : event
        }

        if runtime.engine.isQuickSnapperShowing,
           event.keyCode == HardwareKeyCode.tab,
           !flags.contains(.command),
           !flags.contains(.control),
           !flags.contains(.option)
        {
            if !event.isARepeat {
                runtime.engine.handleQuickSnapper(.cycleLayout(flags.contains(.shift) ? -1 : 1))
            }
            return consume ? nil : event
        }

        if let id = ShortcutCatalog.hotkeyID(
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
            if event.isARepeat,
               ShortcutCatalog.editorSaveChord.matches(
                   keyCode: event.keyCode,
                   carbonModifiers: modifiers
               ) || ShortcutCatalog.isEditorUndoChord(
                   keyCode: event.keyCode,
                   carbonModifiers: modifiers
               ) || ShortcutCatalog.isEditorRedoChord(
                   keyCode: event.keyCode,
                   carbonModifiers: modifiers
               )
            {
                return nil
            }
            if event.isARepeat, event.keyCode != HardwareKeyCode.tab {
                if HardwareKeyCode.isEditorNudge(event.keyCode) {
                    if runtime.handleEditorKey(event) { return nil }
                    return event
                }
                return event.keyCode == HardwareKeyCode.delete
                    || event.keyCode == HardwareKeyCode.forwardDelete
                    || event.keyCode == HardwareKeyCode.return
                    || event.keyCode == HardwareKeyCode.keypadEnter
                    || HardwareKeyCode.isEditorPaneNavigation(event.keyCode)
                    ? nil
                    : event
            }
            if runtime.handleEditorKey(event) { return nil }
        }

        return event
    }

    private func handleEscape(_ event: NSEvent, consume: Bool) -> NSEvent? {
        let action = ShortcutRouteContext.escapeAction(
            ShortcutRouteContext(
                shortcutsPanelIsKey: runtime.shortcutPanelIsKey,
                editorClaimsKeyboard: runtime.editorClaimsKeyboard,
                appHasKeyWindow: NSApp.keyWindow != nil,
                quickSnapperShowing: runtime.engine.isQuickSnapperShowing,
                isRecordingHotkey: runtime.isRecordingHotkey,
                settingsIsKey: runtime.settingsIsKey,
                onboardingIsKey: runtime.onboardingIsKey,
                consoleIsVisible: runtime.consoleIsVisible,
                dividerDragging: runtime.divider.isDragging
            )
        )
        switch action {
        case .cancelHotkeyRecording:
            _ = runtime.cancelHotkeyRecordingIfNeeded()
        case .closeShortcuts:
            _ = runtime.closeShortcutPanelIfOpen()
        case .cancelEditor:
            runtime.cancelEditor()
        case .dismissQuickSnapper:
            runtime.engine.handleQuickSnapper(.dismiss)
        case .cancelDivider:
            runtime.divider.cancelDrag()
        case .closeSettings:
            _ = runtime.closeSettingsIfOpen()
        case .closeOnboarding:
            _ = runtime.closeOnboardingIfOpen()
        case .closeConsole:
            _ = runtime.closeConsoleIfOpen()
        case .cancelSnap:
            runtime.engine.cancelSession()
        case .ignore:
            break
        }
        if !consume {
            return nil
        }
        return action == .ignore ? event : nil
    }

    func handle(id: UInt32) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastHandled, lastHandled.id == id, now - lastHandled.time < Self.dedupWindow {
            return
        }
        lastHandled = (id, now)

        guard runtime.isTrusted() || ShortcutCatalog.trustExemptIDs.contains(id) else { return }
        switch id {
        case ShortcutCatalog.editorHotkeyID:
            Log.hotkey.info("Editor shortcut received trusted=\(self.runtime.isTrusted(), privacy: .public)")
            runtime.openEditorForFocusedWindow()
        case ShortcutCatalog.previousZoneHotkeyID:
            runtime.engine.snapAdjacent(delta: -1)
        case ShortcutCatalog.nextZoneHotkeyID:
            runtime.engine.snapAdjacent(delta: 1)
        case ShortcutCatalog.cycleBackwardHotkeyID:
            runtime.engine.cycleWindowsInFocusedZone(delta: -1)
        case ShortcutCatalog.cycleForwardHotkeyID:
            runtime.engine.cycleWindowsInFocusedZone(delta: 1)
        case ShortcutCatalog.unsnapHotkeyID:
            runtime.engine.unsnapFocused()
        case ShortcutCatalog.shortcutsPanelHotkeyID:
            runtime.toggleShortcutPanel()
        case ShortcutCatalog.quickSnapperHotkeyID:
            runtime.engine.handleQuickSnapper(.invoke)
        case ShortcutCatalog.organizeHotkeyID:
            runtime.organizeWindowsFromHotkey()
        case ShortcutCatalog.applyWorkspaceHotkeyID:
            runtime.workspace.applyCurrentOrMostRecent()
        case 1...9:
            if runtime.engine.isQuickSnapperShowing {
                runtime.engine.handleQuickSnapper(.digit(Int(id)))
            } else {
                runtime.engine.snapFocused(to: Int(id))
            }
        default:
            break
        }
    }
}
