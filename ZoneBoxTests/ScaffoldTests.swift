import XCTest
@testable import ZoneBoxCore

final class ScaffoldTests: XCTestCase {
    func testCoreLoggerSubsystem() {
        XCTAssertEqual(Log.subsystem, "com.fancyzone.app")
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
