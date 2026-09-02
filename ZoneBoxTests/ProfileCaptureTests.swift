import XCTest
@testable import ZoneBoxCore

final class ProfileCaptureTests: XCTestCase {
    private let leftID = UUID()
    private let rightID = UUID()

    func testExactAndMajorityCoverageProduceStableZoneThenZOrderRules() {
        let zones = [
            ResolvedZone(zoneID: leftID, number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 500)),
            ResolvedZone(zoneID: rightID, number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 500)),
        ]
        let frontRight = sample(pid: 1, number: 10, bundleID: "browser", frame: CGRect(x: 500, y: 0, width: 500, height: 500))
        let backLeft = sample(pid: 2, number: 20, bundleID: "editor", frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let secondRight = sample(pid: 3, number: 30, bundleID: "terminal", frame: CGRect(x: 490, y: 0, width: 510, height: 500))

        let rules = ProfileCapture.rules(windows: [frontRight, backLeft, secondRight], zones: zones)

        XCTAssertEqual(rules.map(\.bundleID), ["editor", "browser"])
        XCTAssertEqual(rules.map(\.zoneID), [leftID, rightID])
    }

    func testCoverageThresholdAndMissingBundleIDAreSkipped() {
        let zones = [ResolvedZone(zoneID: leftID, number: 1, frameAX: CGRect(x: 0, y: 0, width: 100, height: 100))]
        let exactlyHalf = sample(pid: 1, number: 1, bundleID: "kept", frame: CGRect(x: 50, y: 0, width: 100, height: 100))
        let below = sample(pid: 2, number: 2, bundleID: "skipped", frame: CGRect(x: 51, y: 0, width: 100, height: 100))
        let anonymous = sample(pid: 3, number: 3, bundleID: nil, frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(ProfileCapture.rules(windows: [exactlyHalf, below, anonymous], zones: zones).map(\.bundleID), ["kept"])
    }

    func testHighestCoverageWinsWhenZonesOverlap() {
        let zones = [
            ResolvedZone(zoneID: leftID, number: 1, frameAX: CGRect(x: 0, y: 0, width: 100, height: 100)),
            ResolvedZone(zoneID: rightID, number: 2, frameAX: CGRect(x: 40, y: 0, width: 100, height: 100)),
        ]
        let window = sample(pid: 1, number: 1, bundleID: "app", frame: CGRect(x: 20, y: 0, width: 160, height: 100))
        XCTAssertEqual(ProfileCapture.rules(windows: [window], zones: zones).first?.zoneID, rightID)
    }

    func testFullyCoveredBackWindowIsNotVisible() {
        let front = visibility(pid: 1, number: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let back = visibility(pid: 2, number: 2, frame: CGRect(x: 0, y: 0, width: 500, height: 500))

        let visible = ProfileCapture.visibleWindowIdentities(frontToBack: [front, back])

        XCTAssertEqual(visible, [front.identity])
    }

    func testAdjacentFrontWindowsCanJointlyCoverBackWindow() {
        let left = visibility(pid: 1, number: 1, frame: CGRect(x: 0, y: 0, width: 250, height: 500))
        let right = visibility(pid: 2, number: 2, frame: CGRect(x: 250, y: 0, width: 250, height: 500))
        let back = visibility(pid: 3, number: 3, frame: CGRect(x: 0, y: 0, width: 500, height: 500))

        let visible = ProfileCapture.visibleWindowIdentities(frontToBack: [left, right, back])

        XCTAssertEqual(visible, [left.identity, right.identity])
    }

    func testPartiallyCoveredBackWindowIsNotCaptured() {
        let front = visibility(pid: 1, number: 1, frame: CGRect(x: 0, y: 0, width: 450, height: 500))
        let back = visibility(pid: 2, number: 2, frame: CGRect(x: 0, y: 0, width: 500, height: 500))

        let visible = ProfileCapture.visibleWindowIdentities(frontToBack: [front, back])

        XCTAssertEqual(visible, [front.identity])
    }

    func testTransparentFrontWindowDoesNotHideBackWindow() {
        let front = visibility(
            pid: 1,
            number: 1,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            opacity: 0.5,
            isOpaqueOccluder: false
        )
        let back = visibility(pid: 2, number: 2, frame: CGRect(x: 0, y: 0, width: 500, height: 500))

        let visible = ProfileCapture.visibleWindowIdentities(frontToBack: [front, back])

        XCTAssertEqual(visible, [front.identity, back.identity])
    }

    func testFrontmostRulePerZoneRepairsOlderDuplicateAssignments() {
        let front = AppPlacementRule(bundleID: "factory", zoneID: rightID, zoneNumber: 2)
        let hidden = AppPlacementRule(bundleID: "browser", zoneID: rightID, zoneNumber: 2)
        let other = AppPlacementRule(bundleID: "editor", zoneID: leftID, zoneNumber: 1)

        XCTAssertEqual(
            ProfileCapture.frontmostRulesPerZone([front, hidden, other]),
            [front, other]
        )
    }

    private func sample(pid: pid_t, number: UInt32, bundleID: String?, frame: CGRect) -> ProfileCapture.WindowSample {
        ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: pid, windowNumber: number, bundleID: bundleID),
            frameAX: frame
        )
    }

    private func visibility(
        pid: pid_t,
        number: UInt32,
        frame: CGRect,
        opacity: Double = 1,
        isOpaqueOccluder: Bool = true
    ) -> ProfileCapture.VisibilitySample {
        ProfileCapture.VisibilitySample(
            identity: WindowIdentity(pid: pid, windowNumber: number, bundleID: "app.\(pid)"),
            frameAX: frame,
            opacity: opacity,
            isOpaqueOccluder: isOpaqueOccluder
        )
    }
}
