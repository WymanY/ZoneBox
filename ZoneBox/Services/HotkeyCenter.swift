import AppKit
import Carbon
import ZoneBoxCore

@MainActor
final class HotkeyCenter {
    unowned var runtime: AppRuntime!
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var voiceOverObservation: NSKeyValueObservation?
    private static weak var shared: HotkeyCenter?

    func start() {
        Self.shared = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            DispatchQueue.main.async {
                HotkeyCenter.shared?.handle(id: hotKeyID.id)
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)

        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new, .initial]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reregister() }
        }
        reregister()
    }

    func stop() {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        voiceOverObservation?.invalidate()
        voiceOverObservation = nil
    }

    func reregister() {
        unregisterAll()
        guard !NSWorkspace.shared.isVoiceOverEnabled else {
            runtime.menuBar?.reloadMenu()
            return
        }
        let settings = runtime.settings
        register(id: 100, chord: settings.editorHotkey)
        register(id: 101, chord: settings.previousZoneHotkey)
        register(id: 102, chord: settings.nextZoneHotkey)
        register(id: 103, chord: settings.cycleBackwardHotkey)
        register(id: 104, chord: settings.cycleForwardHotkey)
        register(id: 105, chord: settings.unsnapHotkey)
        if settings.snapZoneHotkeysEnabled {
            for (index, code) in AppSettings.zoneKeyCodes.enumerated() {
                register(id: UInt32(1 + index), chord: KeyChord(keyCode: code, carbonModifiers: settings.editorHotkey.carbonModifiers))
            }
        }
        runtime.menuBar?.reloadMenu()
    }

    private func register(id: UInt32, chord: KeyChord) {
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: OSType(0x5A424F58), id: id) // 'ZBOX'
        let status = RegisterEventHotKey(
            UInt32(chord.keyCode),
            chord.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            hotKeys[id] = hotKeyRef
        }
    }

    private func unregisterAll() {
        for ref in hotKeys.values {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
    }

    private func handle(id: UInt32) {
        guard runtime.trust.isTrusted() || id == 100 else { return }
        switch id {
        case 100:
            runtime.openEditor()
        case 101:
            runtime.snapAdjacent(delta: -1)
        case 102:
            runtime.snapAdjacent(delta: 1)
        case 103:
            runtime.engine.cycleWindowsInFocusedZone(delta: -1)
        case 104:
            runtime.engine.cycleWindowsInFocusedZone(delta: 1)
        case 105:
            runtime.engine.unsnapFocused()
        case 1...9:
            runtime.engine.snapFocused(to: Int(id))
        default:
            break
        }
    }
}
