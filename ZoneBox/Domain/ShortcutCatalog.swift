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
    public static let z: UInt16 = 6
    public static let w: UInt16 = 13
    public static let u: UInt16 = 32
    public static let leftBracket: UInt16 = 33
    public static let rightBracket: UInt16 = 30
    public static let slash: UInt16 = 44
    public static let comma: UInt16 = 43
    public static let q: UInt16 = 12
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

    public static func isEditorPaneNavigation(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case a, s, d, w: true
        default: false
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
        case HardwareKeyCode.s: return "S"
        case HardwareKeyCode.a: return "A"
        case HardwareKeyCode.d: return "D"
        case HardwareKeyCode.w: return "W"
        case HardwareKeyCode.z: return "Z"
        case HardwareKeyCode.u: return "U"
        case HardwareKeyCode.q: return "Q"
        case HardwareKeyCode.leftBracket: return "["
        case HardwareKeyCode.rightBracket: return "]"
        case HardwareKeyCode.slash: return "/"
        case HardwareKeyCode.comma: return ","
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
    public static let editorSaveChord = KeyChord(
        keyCode: HardwareKeyCode.s,
        carbonModifiers: CarbonModifier.command
    )

    /// IDs that must fire even when Accessibility is not granted.
    public static let trustExemptIDs: Set<UInt32> = [editorHotkeyID, shortcutsPanelHotkeyID]

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
                binding: .chord(
                    KeyChord(keyCode: HardwareKeyCode.slash, carbonModifiers: settings.editorHotkey.carbonModifiers)
                )
            ),
            ShortcutSpec(
                id: "quickSnapper",
                surface: .global,
                titleKey: .shortcutQuickSnapper,
                hotkeyID: quickSnapperHotkeyID,
                binding: .chord(
                    KeyChord(keyCode: HardwareKeyCode.space, carbonModifiers: settings.editorHotkey.carbonModifiers)
                )
            ),
        ]

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
                        binding: .chord(KeyChord(keyCode: code, carbonModifiers: settings.editorHotkey.carbonModifiers))
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
                id: "settings",
                surface: .application,
                titleKey: .shortcutSettings,
                binding: .chord(KeyChord(keyCode: HardwareKeyCode.comma, carbonModifiers: CarbonModifier.command))
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
}

public enum ShortcutEscapeAction: Equatable, Sendable {
    case closeShortcuts
    case cancelEditor
    case dismissQuickSnapper
    case cancelSnap
    case ignore
}

public struct ShortcutRouteContext: Equatable, Sendable {
    public var shortcutsPanelIsKey: Bool
    public var editorClaimsKeyboard: Bool
    public var appHasKeyWindow: Bool
    public var quickSnapperShowing: Bool

    public init(
        shortcutsPanelIsKey: Bool,
        editorClaimsKeyboard: Bool,
        appHasKeyWindow: Bool,
        quickSnapperShowing: Bool = false
    ) {
        self.shortcutsPanelIsKey = shortcutsPanelIsKey
        self.editorClaimsKeyboard = editorClaimsKeyboard
        self.appHasKeyWindow = appHasKeyWindow
        self.quickSnapperShowing = quickSnapperShowing
    }

    public static func escapeAction(_ context: ShortcutRouteContext) -> ShortcutEscapeAction {
        if context.shortcutsPanelIsKey { return .closeShortcuts }
        if context.editorClaimsKeyboard { return .cancelEditor }
        if context.quickSnapperShowing { return .dismissQuickSnapper }
        if !context.appHasKeyWindow { return .cancelSnap }
        return .ignore
    }
}
