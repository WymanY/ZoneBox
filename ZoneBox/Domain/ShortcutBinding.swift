import Foundation

public enum ShortcutBindingIssue: Equatable, Sendable {
    case sequoiaIllegal
    case duplicate(ShortcutCustomizationID)
    case reservedSystem(String)

    public func message(language: AppLanguage) -> String {
        switch self {
        case .sequoiaIllegal:
            return L10n.text(.shortcutErrorSequoia, language: language)
        case .duplicate(let id):
            return L10n.shortcutDuplicate(L10n.text(id.titleKey, language: language), language: language)
        case .reservedSystem(let name):
            return L10n.shortcutReserved(name, language: language)
        }
    }
}

public extension ShortcutCustomizationID {
    var titleKey: L10nKey {
        switch self {
        case .openEditor: .shortcutOpenEditor
        case .previousZone: .shortcutPreviousZone
        case .nextZone: .shortcutNextZone
        case .cycleBackward: .shortcutCycleBackward
        case .cycleForward: .shortcutCycleForward
        case .unsnap: .shortcutUnsnap
        case .showShortcuts: .shortcutShowShortcuts
        case .quickSnapper: .shortcutQuickSnapper
        case .organizeWindows: .shortcutOrganizeWindows
        case .applyWorkspace: .shortcutApplyWorkspace
        case .snapZones: .shortcutSnapZones
        case .openSettings: .shortcutSettings
        }
    }
}

public enum ReservedSystemHotkeys {
    public static let reserved: [(chord: KeyChord, name: String)] = [
        (KeyChord(keyCode: HardwareKeyCode.space, carbonModifiers: CarbonModifier.command), "Spotlight"),
        (KeyChord(keyCode: HardwareKeyCode.space, carbonModifiers: CarbonModifier.command | CarbonModifier.shift), "Spotlight"),
        (KeyChord(keyCode: HardwareKeyCode.escape, carbonModifiers: CarbonModifier.command | CarbonModifier.option), "Force Quit"),
        (KeyChord(keyCode: HardwareKeyCode.tab, carbonModifiers: CarbonModifier.command), "App Switcher"),
        (KeyChord(keyCode: HardwareKeyCode.tab, carbonModifiers: CarbonModifier.command | CarbonModifier.shift), "App Switcher"),
        (KeyChord(keyCode: 3, carbonModifiers: CarbonModifier.control), "Mission Control"),
        (KeyChord(keyCode: HardwareKeyCode.up, carbonModifiers: CarbonModifier.control), "Mission Control"),
        (KeyChord(keyCode: HardwareKeyCode.down, carbonModifiers: CarbonModifier.control), "Application Windows"),
        (KeyChord(keyCode: HardwareKeyCode.left, carbonModifiers: CarbonModifier.control), "Switch Space"),
        (KeyChord(keyCode: HardwareKeyCode.right, carbonModifiers: CarbonModifier.control), "Switch Space"),
        (KeyChord(keyCode: 20, carbonModifiers: CarbonModifier.command | CarbonModifier.shift), "Screenshot"),
        (KeyChord(keyCode: 21, carbonModifiers: CarbonModifier.command | CarbonModifier.shift), "Screenshot"),
        (KeyChord(keyCode: 23, carbonModifiers: CarbonModifier.command | CarbonModifier.shift), "Screenshot"),
        (KeyChord(keyCode: 22, carbonModifiers: CarbonModifier.command | CarbonModifier.shift), "Screenshot"),
        (KeyChord(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.command), "Undo"),
        (KeyChord(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.command | CarbonModifier.shift), "Redo"),
        (KeyChord(keyCode: 8, carbonModifiers: CarbonModifier.command), "Copy"),
        (KeyChord(keyCode: 9, carbonModifiers: CarbonModifier.command), "Paste"),
        (KeyChord(keyCode: 7, carbonModifiers: CarbonModifier.command), "Cut"),
        (KeyChord(keyCode: HardwareKeyCode.a, carbonModifiers: CarbonModifier.command), "Select All"),
        (KeyChord(keyCode: HardwareKeyCode.s, carbonModifiers: CarbonModifier.command), "Save"),
        (KeyChord(keyCode: HardwareKeyCode.q, carbonModifiers: CarbonModifier.command), "Quit"),
        (KeyChord(keyCode: HardwareKeyCode.w, carbonModifiers: CarbonModifier.command), "Close Window"),
        (KeyChord(keyCode: HardwareKeyCode.h, carbonModifiers: CarbonModifier.command), "Hide"),
        (KeyChord(keyCode: HardwareKeyCode.m, carbonModifiers: CarbonModifier.command), "Minimize"),
    ]

    public static func displayName(matching chord: KeyChord) -> String? {
        reserved.first(where: { $0.chord == chord })?.name
    }
}

public enum ShortcutVoiceOverPolicy {
    public static func shouldPause(chord: KeyChord, voiceOverEnabled: Bool) -> Bool {
        guard voiceOverEnabled else { return false }
        let mods = chord.carbonModifiers & KeyChord.modifierMask
        let controlOption = CarbonModifier.control | CarbonModifier.option
        return (mods & controlOption) == controlOption
    }
}
