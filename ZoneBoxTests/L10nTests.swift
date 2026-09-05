import XCTest
@testable import ZoneBoxCore

final class L10nTests: XCTestCase {
    func testResolveChineseVariants() {
        XCTAssertEqual(AppLanguage.resolve(preferred: ["zh-Hans-CN"]), .chineseSimplified)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["zh-CN"]), .chineseSimplified)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["zh-Hant-TW"]), .chineseSimplified)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["zh"]), .chineseSimplified)
    }

    func testResolveEnglishAndFallback() {
        XCTAssertEqual(AppLanguage.resolve(preferred: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["en"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["fr-FR", "de"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: []), .english)
    }

    func testEnglishFirstWhenListedBeforeChinese() {
        XCTAssertEqual(AppLanguage.resolve(preferred: ["en-US", "zh-Hans"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["zh-Hans", "en"]), .chineseSimplified)
    }

    func testMenuStringsDifferByLanguage() {
        XCTAssertEqual(L10n.text(.menuOpenEditor, language: .english), "Open Layout Editor")
        XCTAssertEqual(L10n.text(.menuOpenEditor, language: .chineseSimplified), "打开布局编辑器")
        XCTAssertEqual(L10n.text(.menuQuit, language: .chineseSimplified), "退出 ZoneBox")
        XCTAssertEqual(L10n.text(.menuKeyboardShortcuts, language: .english), "Keyboard Shortcuts")
        XCTAssertEqual(L10n.text(.menuKeyboardShortcuts, language: .chineseSimplified), "键盘快捷键")
        XCTAssertEqual(L10n.text(.menuOrganizeWindows, language: .english), "Organize Windows")
        XCTAssertEqual(L10n.text(.menuOrganizeWindows, language: .chineseSimplified), "一键布局")
        XCTAssertEqual(L10n.text(.consoleOrganize, language: .english), "Organize")
        XCTAssertEqual(L10n.text(.consoleOrganize, language: .chineseSimplified), "一键布局")
    }

    func testOrganizeFeedbackCopy() {
        XCTAssertEqual(L10n.text(.organizeAdjustedTitle, language: .english), "Arrangement adjusted")
        XCTAssertEqual(L10n.text(.organizePartialTitle, language: .chineseSimplified), "已完成部分整理")
        XCTAssertEqual(
            L10n.organizeNeedsSpace("Reminders", language: .english),
            "Reminders needs more space, so it was placed in the primary area."
        )
        XCTAssertEqual(
            L10n.organizeKeptInPlace("Xcode", language: .chineseSimplified),
            "Xcode 未接受窗口调整，已保留原位并整理其他窗口。"
        )
        XCTAssertEqual(L10n.organizeIgnore("Reminders", language: .english), "Ignore Reminders")
        XCTAssertEqual(L10n.text(.organizeRestoreAction, language: .english), "Restore Layout")
        XCTAssertEqual(L10n.text(.organizeClose, language: .english), "Close")
        XCTAssertEqual(L10n.text(.organizeClose, language: .chineseSimplified), "关闭")
        XCTAssertEqual(
            L10n.workspaceSizeConstrained("阿里云盘", language: .chineseSimplified),
            "阿里云盘已移动到位，但其最小窗口尺寸大于当前分区。"
        )
    }

    func testConsoleCopy() {
        XCTAssertEqual(L10n.text(.consoleSnap, language: .english), "Snap")
        XCTAssertEqual(L10n.text(.consoleSnap, language: .chineseSimplified), "吸附")
        XCTAssertEqual(L10n.text(.consoleEdit, language: .english), "Edit")
        XCTAssertEqual(L10n.text(.consoleEdit, language: .chineseSimplified), "编辑")
        XCTAssertEqual(L10n.text(.consolePreview, language: .english), "Preview")
        XCTAssertEqual(L10n.text(.consolePreview, language: .chineseSimplified), "预览")
        XCTAssertEqual(L10n.text(.consoleNew, language: .english), "New Layout")
        XCTAssertEqual(L10n.text(.consoleNew, language: .chineseSimplified), "新建布局")
        XCTAssertEqual(L10n.text(.consoleNoDisplay, language: .english), "No display")
        XCTAssertEqual(L10n.text(.consoleNoDisplay, language: .chineseSimplified), "没有显示器")
        XCTAssertEqual(L10n.text(.consoleCurrentDisplay, language: .english), "Current Display")
        XCTAssertEqual(L10n.text(.consoleCurrentDisplay, language: .chineseSimplified), "当前显示器")
        XCTAssertEqual(L10n.text(.consoleOtherLayouts, language: .english), "Other Layouts")
        XCTAssertEqual(L10n.text(.consoleOtherLayouts, language: .chineseSimplified), "其他布局")
        XCTAssertEqual(L10n.unpinAll(3, language: .english), "Unpin All Windows (3)")
        XCTAssertEqual(L10n.unpinAll(3, language: .chineseSimplified), "取消所有窗口置顶（3）")
        XCTAssertEqual(L10n.text(.pinOnTop, language: .english), "Pin on top")
        XCTAssertEqual(L10n.text(.pinUnpin, language: .chineseSimplified), "取消置顶")
    }

    func testEditorTemplateToolbarCopy() {
        XCTAssertEqual(L10n.text(.editorFromTemplate, language: .english), "From Template")
        XCTAssertEqual(L10n.text(.editorFromTemplate, language: .chineseSimplified), "基于模板")
        XCTAssertEqual(L10n.text(.editorCustomLayout, language: .english), "Custom")
        XCTAssertEqual(L10n.text(.editorSaveCopy, language: .english), "Save Copy")
        XCTAssertEqual(L10n.text(.editorSaveCopy, language: .chineseSimplified), "另存副本")
    }

    func testSettingsSectionTitles() {
        XCTAssertEqual(L10n.text(.settingsSectionGeneral, language: .english), "General")
        XCTAssertEqual(L10n.text(.settingsSectionSnapping, language: .english), "Snapping")
        XCTAssertEqual(L10n.text(.settingsSectionOverlay, language: .english), "Overlay")
        XCTAssertEqual(L10n.text(.settingsSectionKeyboard, language: .english), "Keyboard")
        XCTAssertEqual(L10n.text(.settingsSectionGeneral, language: .chineseSimplified), "通用")
        XCTAssertEqual(L10n.text(.settingsSectionSnapping, language: .chineseSimplified), "吸附")
        XCTAssertEqual(L10n.text(.settingsSectionOverlay, language: .chineseSimplified), "覆盖层")
        XCTAssertEqual(L10n.text(.settingsSectionKeyboard, language: .chineseSimplified), "键盘")
        XCTAssertEqual(
            L10n.text(.settingsSnappingSubtitle, language: .chineseSimplified),
            "选择窗口如何进入分区，以及离开吸附时如何恢复。"
        )
        XCTAssertEqual(L10n.text(.settingsSnappingPreviewTitle, language: .english), "Snapping preview")
        XCTAssertEqual(L10n.text(.settingsAccessGranted, language: .chineseSimplified), "辅助功能权限：已授权")
        XCTAssertEqual(L10n.text(.settingsSnappingTriggersSection, language: .english), "Snap triggers")
        XCTAssertEqual(L10n.text(.settingsSnappingBehaviorSection, language: .chineseSimplified), "窗口行为")
        XCTAssertEqual(
            L10n.text(.settingsHoverPin, language: .english),
            "Show a pin button when hovering a window title bar"
        )
        XCTAssertEqual(L10n.text(.settingsHoverPin, language: .chineseSimplified), "悬停窗口标题栏时显示置顶按钮")
        XCTAssertEqual(L10n.text(.settingsBeta, language: .english), "Beta")
        XCTAssertEqual(L10n.text(.settingsBeta, language: .chineseSimplified), "Beta")
        XCTAssertEqual(L10n.text(.settingsWorkspaceShowDetails, language: .english), "Show details")
        XCTAssertEqual(L10n.text(.settingsWorkspaceShowDetails, language: .chineseSimplified), "查看详情")
        XCTAssertEqual(L10n.text(.settingsWorkspaceActive, language: .chineseSimplified), "最近应用")
        XCTAssertEqual(
            L10n.text(.settingsWorkspacesSubtitle, language: .chineseSimplified),
            "管理已保存的整桌排布。切换只在当次执行，不会持续固定窗口。"
        )
        XCTAssertEqual(
            String(format: L10n.text(.settingsWorkspaceZone, language: .chineseSimplified), 2),
            "分区 2"
        )
        XCTAssertEqual(
            L10n.text(.settingsHoverPinDetail, language: .english),
            "Shows a Screen Recording mirror above other apps. Clicks and scrolling go to the original window. Raise is best-effort, not a private always-on-top window level."
        )
        XCTAssertEqual(
            L10n.text(.settingsHoverPinDetail, language: .chineseSimplified),
            "用录屏权限做一层镜像画面。点击和滚动落到原窗口。前置是尽力而为，不是私有窗口层级置顶。"
        )
    }

    func testShortcutCustomizationCopy() {
        XCTAssertEqual(L10n.text(.settingsResetAllShortcuts, language: .english), "Reset All Shortcuts")
        XCTAssertEqual(L10n.text(.settingsResetAllShortcuts, language: .chineseSimplified), "还原全部快捷键")
        XCTAssertEqual(L10n.text(.settingsHotkeyRecording, language: .english), "Press a shortcut…")
        XCTAssertEqual(
            L10n.shortcutDuplicate("Unsnap window", language: .english),
            "That shortcut is already used by Unsnap window."
        )
        XCTAssertEqual(
            L10n.shortcutReserved("Spotlight", language: .chineseSimplified),
            "这个快捷键保留给 Spotlight。"
        )
    }

    func testUnchangedCopyWarningLocalized() {
        XCTAssertEqual(
            L10n.text(.editorCopyUnchangedMessage, language: .english),
            "This layout has no changes. Save an identical copy anyway? You can rename it below."
        )
        XCTAssertEqual(
            L10n.text(.editorCopyUnchangedMessage, language: .chineseSimplified),
            "当前布局没有变化。仍要保存一个相同的副本吗？可以在下方修改名称。"
        )
    }

    func testNewLayoutNamePromptLocalized() {
        XCTAssertEqual(L10n.text(.editorSaveNameTitle, language: .english), "Save Layout")
        XCTAssertEqual(L10n.text(.editorSaveNameTitle, language: .chineseSimplified), "保存布局")
        XCTAssertEqual(
            L10n.text(.editorSaveNameMessage, language: .chineseSimplified),
            "给布局起个名字。如果重名，ZoneBox 会自动加上序号。"
        )
    }

    func testLayoutDisplayNames() {
        XCTAssertEqual(L10n.layoutDisplayName("Columns 2", language: .chineseSimplified), "两列")
        XCTAssertEqual(L10n.layoutDisplayName("Rows 3", language: .chineseSimplified), "三行")
        XCTAssertEqual(L10n.layoutDisplayName("Focus", language: .chineseSimplified), "焦点")
        XCTAssertEqual(L10n.layoutDisplayName("Columns 2 Copy", language: .chineseSimplified), "两列 副本")
        XCTAssertEqual(L10n.layoutDisplayName("Columns 2 Copy 2", language: .chineseSimplified), "两列 副本 2")
        XCTAssertEqual(L10n.layoutDisplayName("Columns 2 Copy", language: .english), "Columns 2 Copy")
        XCTAssertEqual(L10n.layoutDisplayName("Custom Ultrawide", language: .chineseSimplified), "Custom Ultrawide")
    }

    func testDeleteLayoutCopy() {
        XCTAssertEqual(L10n.text(.menuDeleteLayout, language: .english), "Delete Current Layout…")
        XCTAssertEqual(L10n.text(.menuDeleteLayout, language: .chineseSimplified), "删除当前布局…")
        XCTAssertEqual(L10n.text(.editorDelete, language: .english), "Delete")
        XCTAssertEqual(L10n.text(.editorDelete, language: .chineseSimplified), "删除")
        XCTAssertEqual(
            String(format: L10n.text(.menuDeleteLayoutTitle, language: .english), "cool 2"),
            "Delete cool 2?"
        )
    }

    func testGutterFormat() {
        XCTAssertEqual(L10n.gutter(12, language: .english), "Space between zones: 12 pt")
        XCTAssertEqual(L10n.gutter(12, language: .chineseSimplified), "分区间距：12 点")
    }

    func testShakeIntensityFormat() {
        XCTAssertEqual(L10n.shakeIntensity(3, language: .english), "Shake force: 3")
        XCTAssertEqual(L10n.shakeIntensity(3, language: .chineseSimplified), "晃动力度：3")
    }

    func testPreferenceOverridesSystem() {
        XCTAssertEqual(
            LanguageCenter.resolveEffective(preference: .english, preferred: ["zh-Hans"]),
            .english
        )
        XCTAssertEqual(
            LanguageCenter.resolveEffective(preference: .chineseSimplified, preferred: ["en"]),
            .chineseSimplified
        )
        XCTAssertEqual(
            LanguageCenter.resolveEffective(preference: .system, preferred: ["zh-CN"]),
            .chineseSimplified
        )
    }

    func testEveryKeyHasBothLanguages() {
        for key in L10nKey.allCases {
            XCTAssertFalse(L10n.text(key, language: .english).isEmpty, "missing en \(key)")
            XCTAssertFalse(L10n.text(key, language: .chineseSimplified).isEmpty, "missing zh \(key)")
        }
    }

    func testWelcomeTourCopy() {
        XCTAssertEqual(L10n.text(.welcomeIntroTitle, language: .english), "Welcome to ZoneBox")
        XCTAssertEqual(L10n.text(.welcomeIntroTitle, language: .chineseSimplified), "欢迎使用 ZoneBox")
        XCTAssertEqual(L10n.text(.menuWelcomeTour, language: .english), "Welcome Tour…")
        XCTAssertEqual(L10n.text(.menuWelcomeTour, language: .chineseSimplified), "欢迎引导…")
        XCTAssertEqual(L10n.welcomeStepOf(2, 6, language: .english), "Step 2 of 6")
        XCTAssertEqual(L10n.welcomeStepOf(2, 6, language: .chineseSimplified), "第 2 步，共 6 步")
    }

    func testOnboardingCopyDoesNotMentionXcode() {
        XCTAssertEqual(
            L10n.text(.onboardingStep2Title, language: .english),
            "Turn on ZoneBox"
        )
        XCTAssertEqual(
            L10n.text(.onboardingStep2Title, language: .chineseSimplified),
            "打开 ZoneBox"
        )
        XCTAssertEqual(
            L10n.text(.onboardingStep2Detail, language: .english),
            "Find ZoneBox in the list and turn on its switch."
        )
        XCTAssertEqual(
            L10n.text(.onboardingStep2Detail, language: .chineseSimplified),
            "在列表里找到 ZoneBox，打开旁边的开关。"
        )

        for key in L10nKey.allCases {
            XCTAssertFalse(
                L10n.text(key, language: .english).localizedCaseInsensitiveContains("xcode"),
                "user-facing en copy still mentions Xcode: \(key)"
            )
            XCTAssertFalse(
                L10n.text(key, language: .chineseSimplified).localizedCaseInsensitiveContains("xcode"),
                "user-facing zh copy still mentions Xcode: \(key)"
            )
        }
    }
}
