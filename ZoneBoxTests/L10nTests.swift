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
    }

    func testConsoleCopy() {
        XCTAssertEqual(L10n.text(.consoleSnap, language: .english), "Snap")
        XCTAssertEqual(L10n.text(.consoleSnap, language: .chineseSimplified), "吸附")
        XCTAssertEqual(L10n.text(.consoleEdit, language: .english), "Edit")
        XCTAssertEqual(L10n.text(.consoleEdit, language: .chineseSimplified), "编辑")
        XCTAssertEqual(L10n.text(.consolePreview, language: .english), "Preview")
        XCTAssertEqual(L10n.text(.consolePreview, language: .chineseSimplified), "预览")
        XCTAssertEqual(L10n.text(.consoleNew, language: .english), "New")
        XCTAssertEqual(L10n.text(.consoleNew, language: .chineseSimplified), "新建")
        XCTAssertEqual(L10n.text(.consoleNoDisplay, language: .english), "No display")
        XCTAssertEqual(L10n.text(.consoleNoDisplay, language: .chineseSimplified), "没有显示器")
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
        XCTAssertEqual(L10n.gutter(12, language: .english), "Gutter: 12 pt")
        XCTAssertEqual(L10n.gutter(12, language: .chineseSimplified), "间距：12 点")
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
}
