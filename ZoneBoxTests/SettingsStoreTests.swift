import XCTest
@testable import ZoneBoxCore

final class SettingsStoreTests: XCTestCase {
    func testDefaultDirectoryFollowsAppIdentity() {
        let store = SettingsStore()
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().lastPathComponent, AppIdentity.bundleID)
        XCTAssertEqual(store.fileURL.lastPathComponent, "settings.json")
    }

    func testDecodingPersistedExclusionsAddsMissingAppIdentities() throws {
        let json = """
        {"schemaVersion":1,"excludedBundleIDs":["com.apple.dock","com.fancyzone.app","com.example.keep"]}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertTrue(settings.excludedBundleIDs.contains("com.apple.dock"))
        XCTAssertTrue(settings.excludedBundleIDs.contains("com.example.keep"))
        XCTAssertTrue(settings.excludedBundleIDs.contains(AppIdentity.releaseBundleID))
        XCTAssertTrue(settings.excludedBundleIDs.contains(AppIdentity.debugBundleID))
        XCTAssertEqual(settings.excludedBundleIDs.filter { $0 == AppIdentity.releaseBundleID }.count, 1)
    }
}
