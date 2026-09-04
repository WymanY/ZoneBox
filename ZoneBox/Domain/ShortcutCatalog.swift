import Foundation

/// Carbon `modifiers` bits used by `RegisterEventHotKey` / `KeyChord`.
/// Kept in Core so tests can assert Sequoia-legal chords without AppKit.
public enum CarbonModifier {
    public static let command: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000
    public static let controlOption: UInt32 = control | option
    public static let mask: UInt32 = command | shift | option | control
}

public enum HardwareKeyCode {
    public static let a: UInt16 = 0
    public static let s: UInt16 = 1
    public static let d: UInt16 = 2
    public static let e: UInt16 = 14
    public static let z: UInt16 = 6
    public static let o: UInt16 = 31
    public static let p: UInt16 = 35
    public static let w: UInt16 = 13
    public static let u: UInt16 = 32
    public static let h: UInt16 = 4
    public static let m: UInt16 = 46
    public static let leftBracket: UInt16 = 33
    public static let rightBracket: UInt16 = 30
    public static let slash: UInt16 = 44
    public static let comma: UInt16 = 43
    public static let q: UInt16 = 12
    public static let minus: UInt16 = 27
    public static let backslash: UInt16 = 42
    public static let `return`: UInt16 = 36
    public static let keypadEnter: UInt16 = 76
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let delete: UInt16 = 51
    public static let escape: UInt16 = 53
    public static let forwardDelete: UInt16 = 117
    public static let left: UInt16 = 123
    public static let right: UInt16 = 124
    public static let down: UInt16 = 125
    public static let up: UInt16 = 126
    public static let rightCommand: UInt16 = 54
    public static let command: UInt16 = 55
    public static let shift: UInt16 = 56
    public static let capsLock: UInt16 = 57
    public static let option: UInt16 = 58
    public static let control: UInt16 = 59
    public static let rightShift: UInt16 = 60
    public static let rightOption: UInt16 = 61
    public static let rightControl: UInt16 = 62
    public static let function: UInt16 = 63

    public static func isEditorPaneNavigation(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case a, s, d, w: true
        default: false
        }
    }

    public static func isEditorNudge(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case left, right, up, down: true
        default: false
        }
    }

    public static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case rightCommand, command, shift, capsLock, option, control, rightShift, rightOption, rightControl, function:
            true
        default:
            false
        }
    }
}

public extension KeyChord {
    static let modifierMask = CarbonModifier.mask

    func matches(keyCode: UInt16, carbonModifiers: UInt32) -> Bool {
        self.keyCode == keyCode
            && (self.carbonModifiers & Self.modifierMask) == (carbonModifiers & Self.modifierMask)
    }

    /// Key-cap glyphs from left to right, modifiers then the key.
    var displayCaps: [String] {
        var caps: [String] = []
        let mods = carbonModifiers & Self.modifierMask
        if mods & CarbonModifier.control != 0 { caps.append("⌃") }
        if mods & CarbonModifier.option != 0 { caps.append("⌥") }
        if mods & CarbonModifier.shift != 0 { caps.append("⇧") }
        if mods & CarbonModifier.command != 0 { caps.append("⌘") }
        caps.append(Self.glyph(for: keyCode))
        return caps
    }

    /// US-ANSI hardware key codes → a short cap label.
    static func glyph(for keyCode: UInt16) -> String {
        switch keyCode {
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case HardwareKeyCode.a: return "A"
        case HardwareKeyCode.s: return "S"
        case HardwareKeyCode.d: return "D"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case HardwareKeyCode.z: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 45: return "N"
        case 46: return "M"
        case HardwareKeyCode.q: return "Q"
        case HardwareKeyCode.w: return "W"
        case 14: return "E"
        case 15: return "R"
        case 17: return "T"
        case 16: return "Y"
        case HardwareKeyCode.u: return "U"
        case 34: return "I"
        case HardwareKeyCode.o: return "O"
        case 35: return "P"
        case HardwareKeyCode.leftBracket: return "["
        case HardwareKeyCode.rightBracket: return "]"
        case HardwareKeyCode.slash: return "/"
        case HardwareKeyCode.comma: return ","
        case 47: return "."
        case 42: return "\\"
        case 41: return ";"
        case 39: return "'"
        case 24: return "="
        case 27: return "-"
        case 50: return "`"
        case HardwareKeyCode.tab: return "⇥"
        case HardwareKeyCode.escape: return "esc"
        case HardwareKeyCode.delete: return "⌫"
        case HardwareKeyCode.forwardDelete: return "⌦"
        case HardwareKeyCode.return, HardwareKeyCode.keypadEnter: return "↩"
        case HardwareKeyCode.space: return "space"
        case HardwareKeyCode.left: return "←"
        case HardwareKeyCode.right: return "→"
        case HardwareKeyCode.down: return "↓"
        case HardwareKeyCode.up: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return "•"
        }
    }

    /// Sequoia rejects chords whose only modifiers are Shift and/or Option (`-9868`).
    var isSequoiaLegal: Bool {
        let mods = carbonModifiers & Self.modifierMask
        guard mods != 0 else { return false }
        return (mods & (CarbonModifier.control | CarbonModifier.command)) != 0
    }
}

public enum ShortcutCustomizationID: String, Sendable, CaseIterable, Equatable {
    case openEditor
    case previousZone
    case nextZone
    case cycleBackward
    case cycleForward
    case unsnap
    case showShortcuts
    case quickSnapper
    case organizeWindows
    case applyWorkspace
    case snapZones
    case openSettings
}

public enum ShortcutSurface: String, Sendable, CaseIterable, Equatable {
    case global
    case editor
    case snap
    case application

    public var titleKey: L10nKey {
        switch self {
        case .global: .shortcutsSectionGlobal
        case .editor: .shortcutsSectionEditor
        case .snap: .shortcutsSectionSnap
        case .application: .shortcutsSectionApp
        }
    }
}

public enum ShortcutBinding: Equatable, Sendable {
    case chord(KeyChord)
    case gesture(L10nKey)
}

public struct ShortcutSpec: Equatable, Sendable, Identifiable {
    public var id: String
    public var surface: ShortcutSurface
    public var titleKey: L10nKey
    public var titleArgument: Int?
    public var hotkeyID: UInt32?
    public var binding: ShortcutBinding

    public init(
        id: String,
        surface: ShortcutSurface,
        titleKey: L10nKey,
        titleArgument: Int? = nil,
        hotkeyID: UInt32? = nil,
        binding: ShortcutBinding
    ) {
        self.id = id
        self.surface = surface
        self.titleKey = titleKey
        self.titleArgument = titleArgument
        self.hotkeyID = hotkeyID
        self.binding = binding
    }

    public func title(language: AppLanguage) -> String {
        let template = L10n.text(titleKey, language: language)
        if let titleArgument {
            return String(format: template, locale: language.locale, titleArgument)
        }
        return template
    }
}

public enum ShortcutCatalog {
    public static let editorHotkeyID: UInt32 = 100
    public static let previousZoneHotkeyID: UInt32 = 101
    public static let nextZoneHotkeyID: UInt32 = 102
    public static let cycleBackwardHotkeyID: UInt32 = 103
    public static let cycleForwardHotkeyID: UInt32 = 104
    public static let unsnapHotkeyID: UInt32 = 105
    public static let shortcutsPanelHotkeyID: UInt32 = 106
    public static let quickSnapperHotkeyID: UInt32 = 107
    public static let organizeHotkeyID: UInt32 = 108
    public static let settingsHotkeyID: UInt32 = 109
    public static let applyWorkspaceHotkeyID: UInt32 = 110
    public static let editorSaveChord = KeyChord(
        keyCode: HardwareKeyCode.s,
        carbonModifiers: CarbonModifier.command
    )
    public static let editorUndoChord = KeyChord(
        keyCode: HardwareKeyCode.z,
        carbonModifiers: CarbonModifier.command
    )
    public static let editorUndoAlternateChord = KeyChord(
        keyCode: HardwareKeyCode.z,
        carbonModifiers: CarbonModifier.control
    )
    public static let editorRedoChord = KeyChord(
        keyCode: HardwareKeyCode.z,
        carbonModifiers: CarbonModifier.command | CarbonModifier.shift
    )
    public static let editorRedoAlternateChord = KeyChord(
        keyCode: HardwareKeyCode.z,
        carbonModifiers: CarbonModifier.control | CarbonModifier.shift
    )
    public static let editorDuplicateChord = KeyChord(
        keyCode: HardwareKeyCode.d,
        carbonModifiers: CarbonModifier.command
    )
    public static let editorSelectAllChord = KeyChord(
        keyCode: HardwareKeyCode.a,
        carbonModifiers: CarbonModifier.command
    )
    public static let editorSplitVerticalChord = KeyChord(
        keyCode: HardwareKeyCode.backslash,
        carbonModifiers: CarbonModifier.command | CarbonModifier.shift
    )
    public static let editorSplitHorizontalChord = KeyChord(
        keyCode: HardwareKeyCode.minus,
        carbonModifiers: CarbonModifier.command
    )

    public static func isEditorUndoChord(keyCode: UInt16, carbonModifiers: UInt32) -> Bool {
        editorUndoChord.matches(keyCode: keyCode, carbonModifiers: carbonModifiers)
            || editorUndoAlternateChord.matches(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    public static func isEditorRedoChord(keyCode: UInt16, carbonModifiers: UInt32) -> Bool {
        editorRedoChord.matches(keyCode: keyCode, carbonModifiers: carbonModifiers)
            || editorRedoAlternateChord.matches(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    /// IDs that must fire even when Accessibility is not granted.
    public static let trustExemptIDs: Set<UInt32> = [editorHotkeyID, shortcutsPanelHotkeyID, organizeHotkeyID]

    public static func items(from settings: AppSettings) -> [ShortcutSpec] {
        var items: [ShortcutSpec] = [
            ShortcutSpec(
                id: "openEditor",
                surface: .global,
                titleKey: .shortcutOpenEditor,
                hotkeyID: editorHotkeyID,
                binding: .chord(settings.editorHotkey)
            ),
            ShortcutSpec(
                id: "previousZone",
                surface: .global,
                titleKey: .shortcutPreviousZone,
                hotkeyID: previousZoneHotkeyID,
                binding: .chord(settings.previousZoneHotkey)
            ),
            ShortcutSpec(
                id: "nextZone",
                surface: .global,
                titleKey: .shortcutNextZone,
                hotkeyID: nextZoneHotkeyID,
                binding: .chord(settings.nextZoneHotkey)
            ),
            ShortcutSpec(
                id: "cycleBackward",
                surface: .global,
                titleKey: .shortcutCycleBackward,
                hotkeyID: cycleBackwardHotkeyID,
                binding: .chord(settings.cycleBackwardHotkey)
            ),
            ShortcutSpec(
                id: "cycleForward",
                surface: .global,
                titleKey: .shortcutCycleForward,
                hotkeyID: cycleForwardHotkeyID,
                binding: .chord(settings.cycleForwardHotkey)
            ),
            ShortcutSpec(
                id: "unsnap",
                surface: .global,
                titleKey: .shortcutUnsnap,
                hotkeyID: unsnapHotkeyID,
                binding: .chord(settings.unsnapHotkey)
            ),
            ShortcutSpec(
                id: "showShortcuts",
                surface: .global,
                titleKey: .shortcutShowShortcuts,
                hotkeyID: shortcutsPanelHotkeyID,
                binding: .chord(settings.shortcutsPanelHotkey)
            ),
            ShortcutSpec(
                id: "quickSnapper",
                surface: .global,
                titleKey: .shortcutQuickSnapper,
                hotkeyID: quickSnapperHotkeyID,
                binding: .chord(settings.quickSnapperHotkey)
            ),
            ShortcutSpec(
                id: "applyWorkspace",
                surface: .global,
                titleKey: .shortcutApplyWorkspace,
                hotkeyID: applyWorkspaceHotkeyID,
                binding: .chord(settings.applyWorkspaceHotkey)
            ),
        ]

        if WindowOrganize.isPubliclyAvailable {
            items.append(
                ShortcutSpec(
                    id: "organizeWindows",
                    surface: .global,
                    titleKey: .shortcutOrganizeWindows,
                    hotkeyID: organizeHotkeyID,
                    binding: .chord(settings.organizeHotkey)
                )
            )
        }

        items.append(
            ShortcutSpec(
                id: "openSettings",
                surface: .application,
                titleKey: .shortcutSettings,
                binding: .chord(settings.settingsHotkey)
            )
        )

        if settings.snapZoneHotkeysEnabled {
            for (index, code) in AppSettings.zoneKeyCodes.enumerated() {
                let number = index + 1
                items.append(
                    ShortcutSpec(
                        id: "snapZone\(number)",
                        surface: .global,
                        titleKey: .shortcutSnapZone,
                        titleArgument: number,
                        hotkeyID: UInt32(number),
                        binding: .chord(KeyChord(keyCode: code, carbonModifiers: settings.zoneHotkeyModifiers))
                    )
                )
            }
        }

        items.append(contentsOf: [
            ShortcutSpec(
                id: "editorCancel",
                surface: .editor,
                titleKey: .shortcutEditorCancel,
                binding: .chord(KeyChord(keyCode: HardwareKeyCode.escape, carbonModifiers: 0))
            ),
            ShortcutSpec(
                id: "editorCycle",
                surface: .editor,
                titleKey: .shortcutEditorCycle,
                binding: .chord(KeyChord(keyCode: HardwareKeyCode.tab, carbonModifiers: 0))
            ),
            ShortcutSpec(
                id: "editorCycleBack",
                surface: .editor,
                titleKey: .shortcutEditorCycleBack,
                binding: .chord(KeyChord(keyCode: HardwareKeyCode.tab, carbonModifiers: CarbonModifier.shift))
            ),
            ShortcutSpec(
                id: "editorDelete",
                surface: .editor,
                titleKey: .shortcutEditorDelete,
                binding: .chord(KeyChord(keyCode: HardwareKeyCode.delete, carbonModifiers: 0))
            ),
            ShortcutSpec(
                id: "editorSave",
                surface: .editor,
                titleKey: .shortcutEditorSave,
                binding: .chord(editorSaveChord)
            ),
            ShortcutSpec(
                id: "editorUndo",
                surface: .editor,
                titleKey: .shortcutEditorUndo,
                binding: .chord(editorUndoChord)
            ),
            ShortcutSpec(
                id: "editorRedo",
                surface: .editor,
                titleKey: .shortcutEditorRedo,
                binding: .chord(editorRedoChord)
            ),
            ShortcutSpec(
                id: "editorNewPane",
                surface: .editor,
                titleKey: .shortcutEditorNewPane,
                binding: .gesture(.shortcutGestureClickEmpty)
            ),
            ShortcutSpec(
                id: "editorDuplicate",
                surface: .editor,
                titleKey: .shortcutEditorDuplicate,
                binding: .chord(editorDuplicateChord)
            ),
            ShortcutSpec(
                id: "editorSplitVertical",
                surface: .editor,
                titleKey: .shortcutEditorSplitVertical,
                binding: .chord(editorSplitVerticalChord)
            ),
            ShortcutSpec(
                id: "editorSplitHorizontal",
                surface: .editor,
                titleKey: .shortcutEditorSplitHorizontal,
                binding: .chord(editorSplitHorizontalChord)
            ),
            ShortcutSpec(
                id: "editorNudge",
                surface: .editor,
                titleKey: .shortcutEditorNudge,
                binding: .gesture(.shortcutGestureArrowKeys)
            ),
            ShortcutSpec(
                id: "editorMarquee",
                surface: .editor,
                titleKey: .shortcutEditorMarquee,
                binding: .gesture(.shortcutGestureCommandDrag)
            ),
            ShortcutSpec(
                id: "editorSnapOff",
                surface: .editor,
                titleKey: .shortcutEditorSnapOff,
                binding: .gesture(.shortcutGestureControlHold)
            ),
            ShortcutSpec(
                id: "editorZoomHeight",
                surface: .editor,
                titleKey: .shortcutEditorZoomHeight,
                binding: .gesture(.shortcutGestureScroll)
            ),
            ShortcutSpec(
                id: "editorZoomWidth",
                surface: .editor,
                titleKey: .shortcutEditorZoomWidth,
                binding: .gesture(.shortcutGestureHorizontalScroll)
            ),
            ShortcutSpec(
                id: "shiftDrag",
                surface: .snap,
                titleKey: .shortcutSnapShiftDrag,
                binding: .gesture(.shortcutGestureShiftDrag)
            ),
            ShortcutSpec(
                id: "overlayDigit",
                surface: .snap,
                titleKey: .shortcutSnapOverlayDigit,
                binding: .gesture(.shortcutGestureOverlayDigit)
            ),
            ShortcutSpec(
                id: "cycleLayout",
                surface: .snap,
                titleKey: .shortcutSnapCycleLayout,
                binding: .gesture(.shortcutGestureCycleLayout)
            ),
            ShortcutSpec(
                id: "layoutStrip",
                surface: .snap,
                titleKey: .shortcutSnapLayoutStrip,
                binding: .gesture(.shortcutGestureLayoutStrip)
            ),
            ShortcutSpec(
                id: "rightClickDrag",
                surface: .snap,
                titleKey: .shortcutSnapRightClick,
                binding: .gesture(.shortcutGestureRightClick)
            ),
            ShortcutSpec(
                id: "shakeToSnap",
                surface: .snap,
                titleKey: .shortcutSnapShake,
                binding: .gesture(.shortcutGestureShake)
            ),
            ShortcutSpec(
                id: "gridDraw",
                surface: .snap,
                titleKey: .shortcutSnapGridDraw,
                binding: .gesture(.shortcutGestureGridDraw)
            ),
            ShortcutSpec(
                id: "magneticResize",
                surface: .snap,
                titleKey: .shortcutSnapMagneticResize,
                binding: .gesture(.shortcutGestureMagneticResize)
            ),
            ShortcutSpec(
                id: "quit",
                surface: .application,
                titleKey: .shortcutQuit,
                binding: .chord(KeyChord(keyCode: HardwareKeyCode.q, carbonModifiers: CarbonModifier.command))
            ),
        ])

        return items
    }

    public static func carbonHotkeys(from settings: AppSettings) -> [(id: UInt32, chord: KeyChord)] {
        items(from: settings).compactMap { item in
            guard let id = item.hotkeyID, case .chord(let chord) = item.binding else { return nil }
            return (id, chord)
        }
    }

    public static func hotkeyID(
        matching keyCode: UInt16,
        carbonModifiers: UInt32,
        settings: AppSettings
    ) -> UInt32? {
        hotkeyID(matching: keyCode, carbonModifiers: carbonModifiers, chords: carbonHotkeys(from: settings))
    }

    public static func hotkeyID(
        matching keyCode: UInt16,
        carbonModifiers: UInt32,
        chords: [(id: UInt32, chord: KeyChord)]
    ) -> UInt32? {
        for pair in chords {
            if pair.chord.matches(keyCode: keyCode, carbonModifiers: carbonModifiers) {
                return pair.id
            }
        }
        return nil
    }

    public static func allowsKeyRepeat(hotkeyID: UInt32) -> Bool {
        switch hotkeyID {
        case previousZoneHotkeyID, nextZoneHotkeyID, cycleBackwardHotkeyID, cycleForwardHotkeyID:
            true
        default:
            false
        }
    }

    public static func grouped(from settings: AppSettings) -> [(surface: ShortcutSurface, items: [ShortcutSpec])] {
        let all = items(from: settings)
        return ShortcutSurface.allCases.compactMap { surface in
            let group = all.filter { $0.surface == surface }
            return group.isEmpty ? nil : (surface, group)
        }
    }

    public static func customizableBindings(from settings: AppSettings) -> [(id: ShortcutCustomizationID, titleKey: L10nKey, chord: KeyChord)] {
        storedBindings(from: settings).filter { binding in
            binding.id != .organizeWindows || WindowOrganize.isPubliclyAvailable
        }
    }

    private static func storedBindings(from settings: AppSettings) -> [(id: ShortcutCustomizationID, titleKey: L10nKey, chord: KeyChord)] {
        [
            (.openEditor, .shortcutOpenEditor, settings.editorHotkey),
            (.previousZone, .shortcutPreviousZone, settings.previousZoneHotkey),
            (.nextZone, .shortcutNextZone, settings.nextZoneHotkey),
            (.cycleBackward, .shortcutCycleBackward, settings.cycleBackwardHotkey),
            (.cycleForward, .shortcutCycleForward, settings.cycleForwardHotkey),
            (.unsnap, .shortcutUnsnap, settings.unsnapHotkey),
            (.showShortcuts, .shortcutShowShortcuts, settings.shortcutsPanelHotkey),
            (.quickSnapper, .shortcutQuickSnapper, settings.quickSnapperHotkey),
            (.organizeWindows, .shortcutOrganizeWindows, settings.organizeHotkey),
            (.applyWorkspace, .shortcutApplyWorkspace, settings.applyWorkspaceHotkey),
            (.openSettings, .shortcutSettings, settings.settingsHotkey),
            (.snapZones, .shortcutSnapZones, KeyChord(keyCode: AppSettings.zoneKeyCodes[0], carbonModifiers: settings.zoneHotkeyModifiers)),
        ]
    }

    public static func chord(for id: ShortcutCustomizationID, in settings: AppSettings) -> KeyChord {
        storedBindings(from: settings).first { $0.id == id }!.chord
    }

    public static func applying(_ chord: KeyChord, to id: ShortcutCustomizationID, in settings: AppSettings) -> AppSettings {
        var next = settings
        let normalized = KeyChord(
            keyCode: chord.keyCode,
            carbonModifiers: chord.carbonModifiers & KeyChord.modifierMask
        )
        switch id {
        case .openEditor: next.editorHotkey = normalized
        case .previousZone: next.previousZoneHotkey = normalized
        case .nextZone: next.nextZoneHotkey = normalized
        case .cycleBackward: next.cycleBackwardHotkey = normalized
        case .cycleForward: next.cycleForwardHotkey = normalized
        case .unsnap: next.unsnapHotkey = normalized
        case .showShortcuts: next.shortcutsPanelHotkey = normalized
        case .quickSnapper: next.quickSnapperHotkey = normalized
        case .organizeWindows: next.organizeHotkey = normalized
        case .applyWorkspace: next.applyWorkspaceHotkey = normalized
        case .openSettings: next.settingsHotkey = normalized
        case .snapZones: next.zoneHotkeyModifiers = normalized.carbonModifiers
        }
        return next
    }

    public static func resetting(_ id: ShortcutCustomizationID, in settings: AppSettings) -> AppSettings {
        applying(chord(for: id, in: .default), to: id, in: settings)
    }

    public static func resettingAll(in settings: AppSettings) -> AppSettings {
        ShortcutCustomizationID.allCases.reduce(settings) { resetting($1, in: $0) }
    }

    public static func validate(_ chord: KeyChord, replacing id: ShortcutCustomizationID, in settings: AppSettings) -> ShortcutBindingIssue? {
        let normalized = KeyChord(
            keyCode: chord.keyCode,
            carbonModifiers: chord.carbonModifiers & KeyChord.modifierMask
        )
        if id == .snapZones {
            let probe = KeyChord(keyCode: AppSettings.zoneKeyCodes[0], carbonModifiers: normalized.carbonModifiers)
            if !probe.isSequoiaLegal { return .sequoiaIllegal }
        } else if !normalized.isSequoiaLegal {
            return .sequoiaIllegal
        }

        let next = applying(normalized, to: id, in: settings)
        if let reserved = reservedSystemConflict(in: next) {
            return .reservedSystem(reserved)
        }

        var seen: [KeyChord: ShortcutCustomizationID] = [:]
        for binding in customizableBindings(from: next) {
            if binding.id == .snapZones {
                let modifiers = binding.chord.carbonModifiers & KeyChord.modifierMask
                for code in AppSettings.zoneKeyCodes {
                    let zoneChord = KeyChord(keyCode: code, carbonModifiers: modifiers)
                    if let existing = seen[zoneChord] {
                        return .duplicate(existing)
                    }
                    seen[zoneChord] = .snapZones
                }
                continue
            }
            let chord = KeyChord(
                keyCode: binding.chord.keyCode,
                carbonModifiers: binding.chord.carbonModifiers & KeyChord.modifierMask
            )
            if let existing = seen[chord] {
                return .duplicate(existing == id ? binding.id : existing)
            }
            seen[chord] = binding.id
        }
        return nil
    }

    public static func reservedSystemConflict(in settings: AppSettings) -> String? {
        for pair in carbonHotkeys(from: settings) {
            if let name = ReservedSystemHotkeys.displayName(matching: pair.chord) {
                return name
            }
        }
        return nil
    }
}

public enum ShortcutEscapeAction: Equatable, Sendable {
    case cancelHotkeyRecording
    case closeShortcuts
    case cancelEditor
    case dismissQuickSnapper
    case cancelSnap
    case cancelDivider
    case closeSettings
    case closeOnboarding
    case closeConsole
    case ignore
}

public struct ShortcutRouteContext: Equatable, Sendable {
    public var shortcutsPanelIsKey: Bool
    public var editorClaimsKeyboard: Bool
    public var appHasKeyWindow: Bool
    public var quickSnapperShowing: Bool
    public var isRecordingHotkey: Bool
    public var settingsIsKey: Bool
    public var onboardingIsKey: Bool
    public var consoleIsVisible: Bool
    public var dividerDragging: Bool

    public init(
        shortcutsPanelIsKey: Bool,
        editorClaimsKeyboard: Bool,
        appHasKeyWindow: Bool,
        quickSnapperShowing: Bool = false,
        isRecordingHotkey: Bool = false,
        settingsIsKey: Bool = false,
        onboardingIsKey: Bool = false,
        consoleIsVisible: Bool = false,
        dividerDragging: Bool = false
    ) {
        self.shortcutsPanelIsKey = shortcutsPanelIsKey
        self.editorClaimsKeyboard = editorClaimsKeyboard
        self.appHasKeyWindow = appHasKeyWindow
        self.quickSnapperShowing = quickSnapperShowing
        self.isRecordingHotkey = isRecordingHotkey
        self.settingsIsKey = settingsIsKey
        self.onboardingIsKey = onboardingIsKey
        self.consoleIsVisible = consoleIsVisible
        self.dividerDragging = dividerDragging
    }

    public static func escapeAction(_ context: ShortcutRouteContext) -> ShortcutEscapeAction {
        if context.isRecordingHotkey { return .cancelHotkeyRecording }
        if context.shortcutsPanelIsKey { return .closeShortcuts }
        if context.editorClaimsKeyboard { return .cancelEditor }
        if context.quickSnapperShowing { return .dismissQuickSnapper }
        if context.dividerDragging { return .cancelDivider }
        if context.settingsIsKey { return .closeSettings }
        if context.onboardingIsKey { return .closeOnboarding }
        if context.consoleIsVisible { return .closeConsole }
        if !context.appHasKeyWindow { return .cancelSnap }
        return .ignore
    }
}
