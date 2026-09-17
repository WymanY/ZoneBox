import XCTest
@testable import ZoneBoxCore

final class WorkspaceCaptureEligibilityTests: XCTestCase {
    func testAccessoryAndProhibitedAppsAreNotCaptured() {
        XCTAssertFalse(
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: "com.example.menubar",
                activationPolicy: .accessory
            )
        )
        XCTAssertFalse(
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: "com.example.agent",
                activationPolicy: .prohibited
            )
        )
    }

    func testRegularAppsRemainEligibleEvenWithMenuBarExtras() {
        XCTAssertTrue(
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: "com.todesktop.230313mzl4w4u92",
                activationPolicy: .regular,
                presentation: .init(lsUIElement: true)
            )
        )
    }

    func testRuntimeAccessoryWinsOverFalseLSUIElement() {
        XCTAssertFalse(
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: "com.example.menubar",
                activationPolicy: .accessory,
                presentation: .init(lsUIElement: false, lsBackgroundOnly: false)
            )
        )
    }

    func testMissingRuntimePolicyFallsBackToInfoPlist() {
        XCTAssertFalse(
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: "com.example.lsuielement",
                activationPolicy: nil,
                presentation: .init(lsUIElement: true)
            )
        )
        XCTAssertFalse(
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: "com.example.background",
                activationPolicy: nil,
                presentation: .init(lsBackgroundOnly: true)
            )
        )
        XCTAssertTrue(
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: "com.apple.Terminal",
                activationPolicy: nil,
                presentation: .init()
            )
        )
    }

    func testEmptyBundleIDIsNeverCaptured() {
        XCTAssertFalse(
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: "",
                activationPolicy: .regular
            )
        )
        XCTAssertFalse(
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: nil,
                activationPolicy: .regular
            )
        )
    }

    func testInfoPlistFlagsParseCommonEncodings() {
        XCTAssertTrue(WorkspaceCaptureEligibility.boolFlag(true))
        XCTAssertTrue(WorkspaceCaptureEligibility.boolFlag(NSNumber(value: 1)))
        XCTAssertTrue(WorkspaceCaptureEligibility.boolFlag("YES"))
        XCTAssertFalse(WorkspaceCaptureEligibility.boolFlag(false))
        XCTAssertFalse(WorkspaceCaptureEligibility.boolFlag(0))
        XCTAssertFalse(WorkspaceCaptureEligibility.boolFlag("NO"))
        XCTAssertFalse(WorkspaceCaptureEligibility.boolFlag(nil))
    }

    func testAccessoryWindowsAreDroppedBeforeCaptureRules() {
        let zone = ResolvedZone(
            zoneID: UUID(),
            number: 1,
            frameAX: CGRect(x: 0, y: 0, width: 500, height: 500)
        )
        let cursor = ProfileCapture.WindowSample(
            identity: WindowIdentity(
                pid: 1,
                windowNumber: 10,
                bundleID: "com.todesktop.230313mzl4w4u92"
            ),
            frameAX: zone.frameAX
        )
        let menuBarOnly = ProfileCapture.WindowSample(
            identity: WindowIdentity(
                pid: 2,
                windowNumber: 11,
                bundleID: "com.example.menubar"
            ),
            frameAX: zone.frameAX
        )
        let policies: [String: WorkspaceCaptureEligibility.ActivationPolicy] = [
            "com.todesktop.230313mzl4w4u92": .regular,
            "com.example.menubar": .accessory,
        ]
        let capturable = [cursor, menuBarOnly].filter { sample in
            WorkspaceCaptureEligibility.shouldCapture(
                bundleID: sample.identity.bundleID,
                activationPolicy: sample.identity.bundleID.flatMap { policies[$0] }
            )
        }

        let rules = ProfileCapture.rules(windows: capturable, zones: [zone])
        XCTAssertEqual(rules.map(\.bundleID), ["com.todesktop.230313mzl4w4u92"])
    }
}
