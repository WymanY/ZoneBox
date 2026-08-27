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
