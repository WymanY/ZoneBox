import XCTest
@testable import ZoneBoxCore

final class WindowNumberAllowlistTests: XCTestCase {
    func testReplacePublishesSnapshot() {
        let allowlist = WindowNumberAllowlist()
        XCTAssertEqual(allowlist.current(), [])
        allowlist.replace([42])
        XCTAssertEqual(allowlist.current(), [42])
        XCTAssertTrue(allowlist.contains(42))
        XCTAssertFalse(allowlist.contains(7))
    }

    func testReplaceClearsPreviousIDs() {
        let allowlist = WindowNumberAllowlist()
        allowlist.replace([42])
        allowlist.replace([])
        XCTAssertEqual(allowlist.current(), [])
        XCTAssertFalse(allowlist.contains(42))
    }
}
