import XCTest
@testable import ZoneBoxCore

final class ScaffoldTests: XCTestCase {
    func testCoreLoggerSubsystem() {
        XCTAssertEqual(Log.subsystem, AppIdentity.bundleID)
    }

    func testDebugAndReleaseUseSeparateSupportDirectories() {
        XCTAssertEqual(AppIdentity.releaseBundleID, "com.fancyzone.app")
        XCTAssertEqual(AppIdentity.debugBundleID, "com.fancyzone.app.debug")
        XCTAssertEqual(AppIdentity.defaultSupportDirectory.lastPathComponent, AppIdentity.bundleID)
        XCTAssertNotEqual(AppIdentity.debugBundleID, AppIdentity.releaseBundleID)
        XCTAssertTrue(AppIdentity.ownBundleIDs.contains(AppIdentity.releaseBundleID))
        XCTAssertTrue(AppIdentity.ownBundleIDs.contains(AppIdentity.debugBundleID))
    }

    func testDefaultExclusionsKeepBothAppIdentitiesOutOfWindowActions() {
        XCTAssertTrue(AppSettings.default.excludedBundleIDs.contains(AppIdentity.releaseBundleID))
        XCTAssertTrue(AppSettings.default.excludedBundleIDs.contains(AppIdentity.debugBundleID))
    }

    func testFakeScreenStoresFrames() {
        let screen = FakeScreen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            backingScale: 2,
            originIsZero: true
        )
        XCTAssertTrue(screen.originIsZero)
        XCTAssertEqual(screen.frame.width, 1440)
    }

    func testDefaultExclusionsKeepSystemSettingsOutOfWindowActions() {
        XCTAssertTrue(AppSettings.default.excludedBundleIDs.contains("com.apple.systempreferences"))
        XCTAssertTrue(AppSettings.default.excludedBundleIDs.contains("com.apple.Settings"))
        XCTAssertFalse(AppSettings.default.excludedBundleIDs.contains("com.apple.reminders"))
        XCTAssertFalse(AppSettings.default.excludedBundleIDs.contains("com.apple.dt.Xcode"))
    }
}
