import Foundation

public enum AppLanguagePreference: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case english
    case chineseSimplified
}

public enum AppLanguage: String, Sendable, Equatable, CaseIterable {
    case english = "en"
    case chineseSimplified = "zh-Hans"

    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .chineseSimplified: Locale(identifier: "zh_CN")
        }
    }

    /// First supported language in the preferred list; Chinese (any script) maps to Simplified.
    public static func resolve(preferred: [String]) -> AppLanguage {
        for raw in preferred {
            let lower = raw.replacingOccurrences(of: "_", with: "-").lowercased()
            if lower == "zh" || lower.hasPrefix("zh-") { return .chineseSimplified }
            let code = Locale(identifier: raw).language.languageCode?.identifier.lowercased()
            if code == "zh" { return .chineseSimplified }
            if code == "en" || lower == "en" || lower.hasPrefix("en-") { return .english }
        }
        return .english
    }
}

public enum L10nKey: String, Sendable, CaseIterable {
    case statusTooltip
    case statusTooltipNeedsAccess
    case menuEnableAccessibility
    case menuSnapEnabled
    case menuHotkeysPausedVO
    case menuOpenEditor
    case menuPreviewZones
    case menuLayouts
    case menuNewCanvas
    case menuSettings
    case menuQuit

    case settingsTitle
    case settingsAccessBanner
    case settingsShowGuide
    case settingsEnableSnapping
    case settingsShiftDrag
    case settingsRightClick
    case settingsShowNumbers
    case settingsRestoreSize
    case settingsGutter
    case settingsHotkeys
    case settingsOpenAccess
    case settingsLaunchAtLogin
    case settingsLanguage
    case settingsLanguageSystem
    case settingsLanguageEnglish
    case settingsLanguageChinese

    case onboardingWindowTitle
    case onboardingTitle
    case onboardingSubtitle
    case onboardingPathCaption
    case onboardingStep1Title
    case onboardingStep1Detail
    case onboardingStep2Title
    case onboardingStep2Detail
    case onboardingStep3Title
    case onboardingStep3Detail
    case onboardingMockHeader
    case onboardingStatusNeedsPermission
    case onboardingStatusWaiting
    case onboardingStatusGranted
    case onboardingStatusNeedsRelaunch
    case onboardingStatusDebugger
    case onboardingOpenSettings
    case onboardingOpenSettingsAgain
    case onboardingNotNow
    case onboardingQuitRelaunch
    case onboardingContinue
    case onboardingQuitRelaunchApp
    case onboardingOpenSettingsAgainShort
    case onboardingQuitOpenWithoutDebugger
    case onboardingIveTurnedItOn
    case onboardingStepAccessibility

    case editorColumns2
    case editorColumns3
    case editorRows2
    case editorGrid2x2
    case editorPriority
    case editorFocus
    case editorSave
    case editorSaveCopy
    case editorCancel
    case editorHint
    case editorGridProtected
    case editorSaveTooltip
    case editorSaveCopyTooltip
    case editorSaveDisabledTooltip

    case layoutColumns
    case layoutRows
    case layoutGrid2x2
    case layoutPriority3
    case layoutFocus
    case layoutCanvas
    case layoutCopy
}

public enum L10n {
    public static func text(_ key: L10nKey, language: AppLanguage = LanguageCenter.language) -> String {
        table(language)[key] ?? table(.english)[key] ?? key.rawValue
    }

    public static func gutter(_ points: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.settingsGutter, language: language), locale: language.locale, points)
    }

    public static func columns(_ count: Int, language: AppLanguage = LanguageCenter.language) -> String {
        if language == .chineseSimplified {
            switch count {
            case 2: return "两列"
            case 3: return "三列"
            default: return "\(count) 列"
            }
        }
        return String(format: text(.layoutColumns, language: language), locale: language.locale, count)
    }

    public static func rows(_ count: Int, language: AppLanguage = LanguageCenter.language) -> String {
        if language == .chineseSimplified {
            switch count {
            case 2: return "两行"
            case 3: return "三行"
            default: return "\(count) 行"
            }
        }
        return String(format: text(.layoutRows, language: language), locale: language.locale, count)
    }

    public static func canvas(_ index: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.layoutCanvas, language: language), locale: language.locale, index)
    }

    public static func stepAccessibility(_ number: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.onboardingStepAccessibility, language: language), locale: language.locale, number)
    }

    /// Localize a stored layout name. Canonical storage stays English (`Columns 2`, `Canvas 3 Copy`).
    public static func layoutDisplayName(_ stored: String, language: AppLanguage = LanguageCenter.language) -> String {
        let copyWord = text(.layoutCopy, language: .english)
        var rest = stored
        var copySuffix = ""
        if let range = rest.range(of: " \(copyWord)", options: .backwards) {
            let after = String(rest[range.upperBound...])
            rest = String(rest[..<range.lowerBound])
            let localizedCopy = text(.layoutCopy, language: language)
            copySuffix = after.isEmpty ? " \(localizedCopy)" : " \(localizedCopy)\(after)"
        }

        let localized: String
        if rest == "Focus" {
            localized = text(.layoutFocus, language: language)
        } else if rest == "Grid 2×2" || rest == "Grid 2x2" {
            localized = text(.layoutGrid2x2, language: language)
        } else if rest == "Priority 3" {
            localized = text(.layoutPriority3, language: language)
        } else if rest.hasPrefix("Columns "), let n = Int(rest.dropFirst("Columns ".count)) {
            localized = columns(n, language: language)
        } else if rest.hasPrefix("Rows "), let n = Int(rest.dropFirst("Rows ".count)) {
            localized = rows(n, language: language)
        } else if rest.hasPrefix("Canvas "), let n = Int(rest.dropFirst("Canvas ".count)) {
            localized = canvas(n, language: language)
        } else {
            localized = rest
        }
        return localized + copySuffix
    }

    private static func table(_ language: AppLanguage) -> [L10nKey: String] {
        switch language {
        case .english: english
        case .chineseSimplified: chinese
        }
    }

    private static let english: [L10nKey: String] = [
        .statusTooltip: "ZoneBox",
        .statusTooltipNeedsAccess: "ZoneBox needs Accessibility to snap windows",
        .menuEnableAccessibility: "Enable Accessibility to Snap Windows…",
        .menuSnapEnabled: "Snap Enabled",
        .menuHotkeysPausedVO: "Hotkeys paused — VoiceOver on",
        .menuOpenEditor: "Open Layout Editor",
        .menuPreviewZones: "Preview Zones",
        .menuLayouts: "Layouts",
        .menuNewCanvas: "New Canvas Layout…",
        .menuSettings: "Settings…",
        .menuQuit: "Quit ZoneBox",

        .settingsTitle: "ZoneBox Settings",
        .settingsAccessBanner: "Snapping is off until Accessibility is allowed. Open the guide to turn on the ZoneBox switch.",
        .settingsShowGuide: "Show Accessibility Guide…",
        .settingsEnableSnapping: "Enable snapping",
        .settingsShiftDrag: "Hold Shift while dragging to snap",
        .settingsRightClick: "Right-click while dragging to snap",
        .settingsShowNumbers: "Show zone numbers",
        .settingsRestoreSize: "Restore size when unsnapping",
        .settingsGutter: "Gutter: %d pt",
        .settingsHotkeys: "Hotkeys (Control+Option): 1–9 snap focused window, Z editor, U unsnap, arrows next/previous zone.\nPaused automatically while VoiceOver is on.",
        .settingsOpenAccess: "Open Accessibility Settings",
        .settingsLaunchAtLogin: "Launch at login",
        .settingsLanguage: "Language",
        .settingsLanguageSystem: "Follow System",
        .settingsLanguageEnglish: "English",
        .settingsLanguageChinese: "简体中文",

        .onboardingWindowTitle: "Enable Accessibility",
        .onboardingTitle: "Allow ZoneBox to arrange windows",
        .onboardingSubtitle: "macOS requires Accessibility permission before ZoneBox can move and resize other apps. This stays on your Mac — nothing is uploaded.",
        .onboardingPathCaption: "Enable this exact build (Xcode Debug ≠ a copy in /Applications):",
        .onboardingStep1Title: "Open Accessibility settings",
        .onboardingStep1Detail: "Use the button below. System Settings opens to Privacy & Security → Accessibility.",
        .onboardingStep2Title: "Turn on THIS ZoneBox",
        .onboardingStep2Detail: "You may see several ZoneBox rows (Xcode Debug, another folder, /Applications). Enable the one that matches the path above.",
        .onboardingStep3Title: "Don’t test with Xcode Run",
        .onboardingStep3Detail: "Stop in Xcode, then Quit & Open without Debugger — or Finder-open the .app. The debugger makes macOS ignore an already-on switch.",
        .onboardingMockHeader: "Accessibility",
        .onboardingStatusNeedsPermission: "Snapping is paused until Accessibility is allowed.",
        .onboardingStatusWaiting: "Waiting for the switch next to ZoneBox…",
        .onboardingStatusGranted: "Accessibility is on. You can snap windows now.",
        .onboardingStatusNeedsRelaunch: "The switch can be on while this process still isn’t trusted. Quit & Relaunch (not Xcode Run) applies the grant.",
        .onboardingStatusDebugger: "Xcode is debugging this process. macOS often keeps Accessibility off for the debug session even when the ZoneBox switch is already on.",
        .onboardingOpenSettings: "Open Accessibility Settings",
        .onboardingOpenSettingsAgain: "Open Accessibility Settings again",
        .onboardingNotNow: "Not now",
        .onboardingQuitRelaunch: "Quit & Relaunch",
        .onboardingContinue: "Continue",
        .onboardingQuitRelaunchApp: "Quit & Relaunch ZoneBox",
        .onboardingOpenSettingsAgainShort: "Open Settings again",
        .onboardingQuitOpenWithoutDebugger: "Quit & Open without Debugger",
        .onboardingIveTurnedItOn: "I've turned it on",
        .onboardingStepAccessibility: "Step %d",

        .editorColumns2: "Columns 2",
        .editorColumns3: "Columns 3",
        .editorRows2: "Rows 2",
        .editorGrid2x2: "2×2",
        .editorPriority: "Priority",
        .editorFocus: "Focus",
        .editorSave: "Save",
        .editorSaveCopy: "Save Copy",
        .editorCancel: "Cancel",
        .editorHint: "Drag an edge or corner to resize. Scroll changes height, Shift+scroll changes width, Option+scroll changes both. × deletes. Esc exits.",
        .editorGridProtected: "Grid layouts are protected; saving creates a copy and does not overwrite the original.",
        .editorSaveTooltip: "Save layout",
        .editorSaveCopyTooltip: "Save changes as a new layout",
        .editorSaveDisabledTooltip: "Create at least one zone before saving",

        .layoutColumns: "Columns %d",
        .layoutRows: "Rows %d",
        .layoutGrid2x2: "Grid 2×2",
        .layoutPriority3: "Priority 3",
        .layoutFocus: "Focus",
        .layoutCanvas: "Canvas %d",
        .layoutCopy: "Copy",
    ]

    private static let chinese: [L10nKey: String] = [
        .statusTooltip: "ZoneBox",
        .statusTooltipNeedsAccess: "ZoneBox 需要辅助功能才能吸附窗口",
        .menuEnableAccessibility: "开启辅助功能以吸附窗口…",
        .menuSnapEnabled: "启用吸附",
        .menuHotkeysPausedVO: "快捷键已暂停 — VoiceOver 开启中",
        .menuOpenEditor: "打开布局编辑器",
        .menuPreviewZones: "预览分区",
        .menuLayouts: "布局",
        .menuNewCanvas: "新建画布布局…",
        .menuSettings: "设置…",
        .menuQuit: "退出 ZoneBox",

        .settingsTitle: "ZoneBox 设置",
        .settingsAccessBanner: "未允许辅助功能时无法吸附。请打开引导，打开 ZoneBox 开关。",
        .settingsShowGuide: "显示辅助功能引导…",
        .settingsEnableSnapping: "启用吸附",
        .settingsShiftDrag: "拖动窗口时按住 Shift 吸附",
        .settingsRightClick: "拖动窗口时右键吸附",
        .settingsShowNumbers: "显示分区编号",
        .settingsRestoreSize: "取消吸附时恢复原来的大小",
        .settingsGutter: "间距：%d 点",
        .settingsHotkeys: "快捷键（Control+Option）：1–9 吸附当前窗口，Z 打开编辑器，U 取消吸附，方向键切换分区。\n开启 VoiceOver 时自动暂停。",
        .settingsOpenAccess: "打开辅助功能设置",
        .settingsLaunchAtLogin: "登录时启动",
        .settingsLanguage: "语言",
        .settingsLanguageSystem: "跟随系统",
        .settingsLanguageEnglish: "English",
        .settingsLanguageChinese: "简体中文",

        .onboardingWindowTitle: "开启辅助功能",
        .onboardingTitle: "允许 ZoneBox 排列窗口",
        .onboardingSubtitle: "macOS 要求先开启辅助功能，ZoneBox 才能移动和调整其他应用的窗口。权限只留在这台 Mac 上，不会上传。",
        .onboardingPathCaption: "请开启这一份构建（Xcode Debug 和 /Applications 里的副本不是同一个）：",
        .onboardingStep1Title: "打开辅助功能设置",
        .onboardingStep1Detail: "点下面的按钮。系统设置会打开到“隐私与安全性 → 辅助功能”。",
        .onboardingStep2Title: "打开这一份 ZoneBox",
        .onboardingStep2Detail: "列表里可能有多行 ZoneBox（Xcode Debug、其他文件夹、/Applications）。请打开与上面路径一致的那一行。",
        .onboardingStep3Title: "不要用 Xcode Run 来验证",
        .onboardingStep3Detail: "在 Xcode 里 Stop，然后“退出并以非调试方式打开”，或用 Finder 打开 .app。调试器会让系统忽略已经打开的开关。",
        .onboardingMockHeader: "辅助功能",
        .onboardingStatusNeedsPermission: "未允许辅助功能时，吸附会暂停。",
        .onboardingStatusWaiting: "正在等待 ZoneBox 旁边的开关…",
        .onboardingStatusGranted: "辅助功能已开启，可以吸附窗口了。",
        .onboardingStatusNeedsRelaunch: "开关打开后，当前进程仍可能未被信任。退出并重新打开（不要用 Xcode Run）才会生效。",
        .onboardingStatusDebugger: "Xcode 正在调试此进程。即使 ZoneBox 开关已打开，macOS 也经常不把辅助功能授予调试会话。",
        .onboardingOpenSettings: "打开辅助功能设置",
        .onboardingOpenSettingsAgain: "再次打开辅助功能设置",
        .onboardingNotNow: "稍后再说",
        .onboardingQuitRelaunch: "退出并重新打开",
        .onboardingContinue: "继续",
        .onboardingQuitRelaunchApp: "退出并重新打开 ZoneBox",
        .onboardingOpenSettingsAgainShort: "再次打开设置",
        .onboardingQuitOpenWithoutDebugger: "退出并以非调试方式打开",
        .onboardingIveTurnedItOn: "我已打开开关",
        .onboardingStepAccessibility: "第 %d 步",

        .editorColumns2: "两列",
        .editorColumns3: "三列",
        .editorRows2: "两行",
        .editorGrid2x2: "2×2",
        .editorPriority: "优先",
        .editorFocus: "焦点",
        .editorSave: "保存",
        .editorSaveCopy: "另存副本",
        .editorCancel: "取消",
        .editorHint: "拖动边缘或角落缩放格子。滚动改高度，Shift+滚动改宽度，Option+滚动同时改。× 删除。Esc 退出",
        .editorGridProtected: "Grid 布局受保护；修改后会创建副本，不会覆盖原布局。",
        .editorSaveTooltip: "保存布局",
        .editorSaveCopyTooltip: "将修改保存为新布局",
        .editorSaveDisabledTooltip: "至少创建一个区域后才能保存",

        .layoutColumns: "%d 列",
        .layoutRows: "%d 行",
        .layoutGrid2x2: "2×2 网格",
        .layoutPriority3: "优先三分",
        .layoutFocus: "焦点",
        .layoutCanvas: "画布 %d",
        .layoutCopy: "副本",
    ]
}
