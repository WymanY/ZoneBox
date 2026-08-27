import Foundation

public struct KeyChord: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var carbonModifiers: UInt32

    public init(keyCode: UInt16, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var snapEnabled: Bool
    public var snapOnShiftDrag: Bool
    public var snapOnRightClickDrag: Bool
    public var gutterPoints: Int
    public var overlapPolicy: OverlapPolicy
    public var showZoneNumbers: Bool
    public var inactiveFillOpacity: Double
    public var activeFillOpacity: Double
    public var zoneFillColorHex: String
    public var zoneBorderColorHex: String
    public var restoreSizeOnUnsnap: Bool
    public var snapDialogs: Bool
    public var excludedBundleIDs: [String]
    public var launchAtLogin: Bool
    public var editorHotkey: KeyChord
    public var snapZoneHotkeysEnabled: Bool
    public var nextZoneHotkey: KeyChord
    public var previousZoneHotkey: KeyChord
    public var cycleForwardHotkey: KeyChord
    public var cycleBackwardHotkey: KeyChord
    public var unsnapHotkey: KeyChord

    public static let controlOption: UInt32 = 0x1800

    public static let `default` = AppSettings(
        schemaVersion: 1,
        snapEnabled: true,
        snapOnShiftDrag: true,
        snapOnRightClickDrag: true,
        gutterPoints: 16,
        overlapPolicy: .smallestArea,
        showZoneNumbers: true,
        inactiveFillOpacity: 0.20,
        activeFillOpacity: 0.40,
        zoneFillColorHex: "#007AFF",
        zoneBorderColorHex: "#FFFFFF",
        restoreSizeOnUnsnap: true,
        snapDialogs: false,
        excludedBundleIDs: [
            "com.apple.dock",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.systempreferences",
            "com.apple.Settings",
            "com.apple.loginwindow",
            "com.apple.Wallpaper",
            "com.apple.Spotlight",
            "com.apple.screencaptureui",
            "com.apple.WindowManager",
            "com.fancyzone.app",
        ],
        launchAtLogin: false,
        editorHotkey: KeyChord(keyCode: 6, carbonModifiers: controlOption),
        snapZoneHotkeysEnabled: true,
        nextZoneHotkey: KeyChord(keyCode: 124, carbonModifiers: controlOption),
        previousZoneHotkey: KeyChord(keyCode: 123, carbonModifiers: controlOption),
        cycleForwardHotkey: KeyChord(keyCode: 30, carbonModifiers: controlOption),
        cycleBackwardHotkey: KeyChord(keyCode: 33, carbonModifiers: controlOption),
        unsnapHotkey: KeyChord(keyCode: 32, carbonModifiers: controlOption)
    )

    public static let zoneKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
}
