import XCTest
@testable import ZoneBoxCore

final class SnapWindowEligibilityTests: XCTestCase {
    private let excluded = AppSettings.default.excludedBundleIDs
    private let welcome: UInt32 = 42

    func testOwnProcessIsNotSnappableByDefault() {
        XCTAssertFalse(
            SnapWindowEligibility.isSnappable(
                layer: 0,
                size: CGSize(width: 760, height: 560),
                pid: 99,
                ownPID: 99,
                windowNumber: welcome,
                bundleID: AppIdentity.debugBundleID,
                excludedBundleIDs: excluded,
                allowedWindowNumbers: []
            )
        )
    }

    func testWelcomeWindowIsSnappableWhenAllowlisted() {
        XCTAssertTrue(
            SnapWindowEligibility.isSnappable(
                layer: 0,
                size: CGSize(width: 760, height: 560),
                pid: 99,
                ownPID: 99,
                windowNumber: welcome,
                bundleID: AppIdentity.debugBundleID,
                excludedBundleIDs: excluded,
                allowedWindowNumbers: [welcome]
            )
        )
    }

    func testSettingsWindowStaysExcludedEvenWhenOwnProcessMatches() {
        XCTAssertFalse(
            SnapWindowEligibility.isSnappable(
                layer: 0,
                size: CGSize(width: 980, height: 720),
                pid: 99,
                ownPID: 99,
                windowNumber: 7,
                bundleID: AppIdentity.debugBundleID,
                excludedBundleIDs: excluded,
                allowedWindowNumbers: [welcome]
            )
        )
    }

    func testForeignWindowStillSnaps() {
        XCTAssertTrue(
            SnapWindowEligibility.isSnappable(
                layer: 0,
                size: CGSize(width: 800, height: 600),
                pid: 42,
                ownPID: 99,
                windowNumber: 3,
                bundleID: "com.apple.Terminal",
                excludedBundleIDs: excluded,
                allowedWindowNumbers: [welcome]
            )
        )
    }
}
