import XCTest
@testable import ZoneBoxCore

@MainActor
final class LanguageCenterTests: XCTestCase {
    func testApplyPreferenceUpdatesLanguageAndPosts() {
        let saved = LanguageCenter.preference
        defer { LanguageCenter.shared.applyPreference(saved) }

        let posted = expectation(forNotification: LanguageCenter.didChangeNotification, object: LanguageCenter.shared)
        LanguageCenter.shared.applyPreference(.chineseSimplified)

        XCTAssertEqual(LanguageCenter.preference, .chineseSimplified)
        XCTAssertEqual(LanguageCenter.language, .chineseSimplified)
        XCTAssertEqual(L10n.text(.menuQuit), "退出 ZoneBox")
        wait(for: [posted], timeout: 1)
    }

    func testRefreshWithoutChangeDoesNotPost() {
        let saved = LanguageCenter.preference
        defer { LanguageCenter.shared.applyPreference(saved) }

        LanguageCenter.shared.applyPreference(.english)
        let posted = expectation(forNotification: LanguageCenter.didChangeNotification, object: LanguageCenter.shared)
        posted.isInverted = true
        LanguageCenter.shared.refresh()

        XCTAssertEqual(LanguageCenter.language, .english)
        wait(for: [posted], timeout: 0.2)
    }

    func testLanguageIsReadableOffTheMainActor() async {
        let saved = LanguageCenter.preference
        defer { LanguageCenter.shared.applyPreference(saved) }

        LanguageCenter.shared.applyPreference(.english)
        let language = await Task.detached { LanguageCenter.language }.value
        XCTAssertEqual(language, .english)
    }
}
