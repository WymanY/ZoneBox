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
    public var shakeToSnapEnabled: Bool
    public var shakeIntensity: Int
    public var quickSnapperEnabled: Bool
    public var magneticResizeEnabled: Bool
    public var magneticThresholdPoints: Int
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
    public var uiLanguage: AppLanguagePreference
    public var editorHotkey: KeyChord
    public var snapZoneHotkeysEnabled: Bool
    public var nextZoneHotkey: KeyChord
    public var previousZoneHotkey: KeyChord
    public var cycleForwardHotkey: KeyChord
    public var cycleBackwardHotkey: KeyChord
    public var unsnapHotkey: KeyChord
    public var organizeHotkey: KeyChord

    public static let controlOption: UInt32 = CarbonModifier.controlOption

    public static let `default` = AppSettings(
        schemaVersion: 1,
        snapEnabled: true,
        snapOnShiftDrag: true,
        snapOnRightClickDrag: true,
        shakeToSnapEnabled: true,
        shakeIntensity: ShakeProfile.defaultIntensity,
        quickSnapperEnabled: true,
        magneticResizeEnabled: true,
        magneticThresholdPoints: 12,
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
        uiLanguage: .system,
        editorHotkey: KeyChord(keyCode: 6, carbonModifiers: controlOption),
        snapZoneHotkeysEnabled: true,
        nextZoneHotkey: KeyChord(keyCode: 124, carbonModifiers: controlOption),
        previousZoneHotkey: KeyChord(keyCode: 123, carbonModifiers: controlOption),
        cycleForwardHotkey: KeyChord(keyCode: 30, carbonModifiers: controlOption),
        cycleBackwardHotkey: KeyChord(keyCode: 33, carbonModifiers: controlOption),
        unsnapHotkey: KeyChord(keyCode: 32, carbonModifiers: controlOption),
        organizeHotkey: KeyChord(keyCode: HardwareKeyCode.o, carbonModifiers: controlOption)
    )

    public static let zoneKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
}

extension AppSettings {
    public init(from decoder: Decoder) throws {
        let defaults = AppSettings.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? defaults.schemaVersion
        snapEnabled = try c.decodeIfPresent(Bool.self, forKey: .snapEnabled) ?? defaults.snapEnabled
        snapOnShiftDrag = try c.decodeIfPresent(Bool.self, forKey: .snapOnShiftDrag) ?? defaults.snapOnShiftDrag
        snapOnRightClickDrag = try c.decodeIfPresent(Bool.self, forKey: .snapOnRightClickDrag) ?? defaults.snapOnRightClickDrag
        shakeToSnapEnabled = try c.decodeIfPresent(Bool.self, forKey: .shakeToSnapEnabled) ?? defaults.shakeToSnapEnabled
        shakeIntensity = ShakeProfile.clampedIntensity(
            try c.decodeIfPresent(Int.self, forKey: .shakeIntensity) ?? defaults.shakeIntensity
        )
        quickSnapperEnabled = try c.decodeIfPresent(Bool.self, forKey: .quickSnapperEnabled) ?? defaults.quickSnapperEnabled
        magneticResizeEnabled = try c.decodeIfPresent(Bool.self, forKey: .magneticResizeEnabled) ?? defaults.magneticResizeEnabled
        magneticThresholdPoints = try c.decodeIfPresent(Int.self, forKey: .magneticThresholdPoints) ?? defaults.magneticThresholdPoints
        gutterPoints = try c.decodeIfPresent(Int.self, forKey: .gutterPoints) ?? defaults.gutterPoints
        overlapPolicy = try c.decodeIfPresent(OverlapPolicy.self, forKey: .overlapPolicy) ?? defaults.overlapPolicy
        showZoneNumbers = try c.decodeIfPresent(Bool.self, forKey: .showZoneNumbers) ?? defaults.showZoneNumbers
        inactiveFillOpacity = try c.decodeIfPresent(Double.self, forKey: .inactiveFillOpacity) ?? defaults.inactiveFillOpacity
        activeFillOpacity = try c.decodeIfPresent(Double.self, forKey: .activeFillOpacity) ?? defaults.activeFillOpacity
        zoneFillColorHex = try c.decodeIfPresent(String.self, forKey: .zoneFillColorHex) ?? defaults.zoneFillColorHex
        zoneBorderColorHex = try c.decodeIfPresent(String.self, forKey: .zoneBorderColorHex) ?? defaults.zoneBorderColorHex
        restoreSizeOnUnsnap = try c.decodeIfPresent(Bool.self, forKey: .restoreSizeOnUnsnap) ?? defaults.restoreSizeOnUnsnap
        snapDialogs = try c.decodeIfPresent(Bool.self, forKey: .snapDialogs) ?? defaults.snapDialogs
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? defaults.excludedBundleIDs
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        uiLanguage = try c.decodeIfPresent(AppLanguagePreference.self, forKey: .uiLanguage) ?? .system
        editorHotkey = try c.decodeIfPresent(KeyChord.self, forKey: .editorHotkey) ?? defaults.editorHotkey
        snapZoneHotkeysEnabled = try c.decodeIfPresent(Bool.self, forKey: .snapZoneHotkeysEnabled) ?? defaults.snapZoneHotkeysEnabled
        nextZoneHotkey = try c.decodeIfPresent(KeyChord.self, forKey: .nextZoneHotkey) ?? defaults.nextZoneHotkey
        previousZoneHotkey = try c.decodeIfPresent(KeyChord.self, forKey: .previousZoneHotkey) ?? defaults.previousZoneHotkey
        cycleForwardHotkey = try c.decodeIfPresent(KeyChord.self, forKey: .cycleForwardHotkey) ?? defaults.cycleForwardHotkey
        cycleBackwardHotkey = try c.decodeIfPresent(KeyChord.self, forKey: .cycleBackwardHotkey) ?? defaults.cycleBackwardHotkey
        unsnapHotkey = try c.decodeIfPresent(KeyChord.self, forKey: .unsnapHotkey) ?? defaults.unsnapHotkey
        organizeHotkey = try c.decodeIfPresent(KeyChord.self, forKey: .organizeHotkey) ?? defaults.organizeHotkey
    }
}
