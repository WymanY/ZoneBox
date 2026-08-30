import XCTest
@testable import ZoneBoxCore

final class SettingsStoreTests: XCTestCase {
    func testDefaultDirectoryFollowsAppIdentity() {
        let store = SettingsStore()
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().lastPathComponent, AppIdentity.bundleID)
        XCTAssertEqual(store.fileURL.lastPathComponent, "settings.json")
    }
}
