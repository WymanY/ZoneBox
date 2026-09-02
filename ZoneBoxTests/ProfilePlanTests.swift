import XCTest
@testable import ZoneBoxCore

final class ProfilePlanTests: XCTestCase {
    func testConsumesBundleQueuesAcrossDisplaysWithoutReusingWindows() {
        let firstDisplay = UUID()
        let secondDisplay = UUID()
        let layoutID = UUID()
        let firstZone = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 100, height: 100))
        let secondZone = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 100, y: 0, width: 100, height: 100))
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: firstDisplay), layoutID: layoutID, rules: [rule("browser", firstZone)]),
            ProfileSection(space: SpaceKey(displayID: secondDisplay), layoutID: layoutID, rules: [rule("browser", secondZone)]),
        ])
        let front = sample(pid: 1, number: 1, bundleID: "browser")
        let back = sample(pid: 2, number: 2, bundleID: "browser")

        let outcome = ProfilePlan.make(
            profile: profile,
            zonesBySection: [firstDisplay: [firstZone], secondDisplay: [secondZone]],
            candidates: [front, back]
        )

        XCTAssertEqual(outcome.sections.flatMap(\.placements).map(\.identity), [front.identity, back.identity])
        XCTAssertEqual(outcome.sections.flatMap(\.placements).map(\.targetFrameAX), [firstZone.frameAX, secondZone.frameAX])
        XCTAssertTrue(outcome.missingBundleIDs.isEmpty)
    }

    func testReportsMissingStaleAndDisconnectedSections() {
        let activeDisplay = UUID()
        let disconnected = UUID()
        let layoutID = UUID()
        let fallbackZone = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 0, y: 0, width: 200, height: 100))
        let stale = AppPlacementRule(bundleID: "stale", zoneID: UUID(), zoneNumber: 99)
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(
                space: SpaceKey(displayID: activeDisplay),
                layoutID: layoutID,
                rules: [AppPlacementRule(bundleID: "editor", zoneID: UUID(), zoneNumber: 2), stale]
            ),
            ProfileSection(space: SpaceKey(displayID: disconnected), layoutID: layoutID, rules: [rule("browser", fallbackZone)]),
        ])

        let outcome = ProfilePlan.make(profile: profile, zonesBySection: [activeDisplay: [fallbackZone]], candidates: [])

        XCTAssertEqual(outcome.missingBundleIDs, ["editor"])
        XCTAssertEqual(outcome.staleRules, [stale])
        XCTAssertEqual(outcome.skippedDisplayIDs, [disconnected])
    }

    func testMissingBundleIDsAreDeduplicated() {
        let display = UUID()
        let zone = ResolvedZone(zoneID: UUID(), number: 1, frameAX: .zero)
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), layoutID: UUID(), rules: [rule("app", zone), rule("app", zone)]),
        ])
        let outcome = ProfilePlan.make(profile: profile, zonesBySection: [display: [zone]], candidates: [])
        XCTAssertEqual(outcome.missingBundleIDs, ["app"])
    }

    func testIgnoresOlderBackgroundAssignmentForTheSameZone() throws {
        let display = UUID()
        let zone = ResolvedZone(
            zoneID: UUID(),
            number: 1,
            frameAX: CGRect(x: 0, y: 0, width: 500, height: 500)
        )
        let front = sample(pid: 1, number: 1, bundleID: "factory")
        let hidden = sample(pid: 2, number: 2, bundleID: "browser")
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(
                space: SpaceKey(displayID: display),
                layoutID: UUID(),
                rules: [rule("factory", zone), rule("browser", zone)]
            ),
        ])

        let outcome = ProfilePlan.make(
            profile: profile,
            zonesBySection: [display: [zone]],
            candidates: [front, hidden]
        )

        let placement = try XCTUnwrap(outcome.sections.first?.placements.first)
        XCTAssertEqual(placement.identity, front.identity)
        XCTAssertEqual(outcome.sections.first?.placements.count, 1)
        XCTAssertTrue(outcome.missingBundleIDs.isEmpty)
    }

    func testFallsBackFromStaleZoneIDToZoneNumber() throws {
        let display = UUID()
        let fallback = ResolvedZone(
            zoneID: UUID(),
            number: 2,
            frameAX: CGRect(x: 300, y: 50, width: 200, height: 150)
        )
        let candidate = sample(pid: 1, number: 1, bundleID: "app")
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(
                space: SpaceKey(displayID: display),
                layoutID: UUID(),
                rules: [AppPlacementRule(bundleID: "app", zoneID: UUID(), zoneNumber: 2)]
            ),
        ])

        let outcome = ProfilePlan.make(
            profile: profile,
            zonesBySection: [display: [fallback]],
            candidates: [candidate]
        )
        XCTAssertEqual(try XCTUnwrap(outcome.sections.first?.placements.first?.targetFrameAX), fallback.frameAX)
        XCTAssertTrue(outcome.staleRules.isEmpty)
    }

    func testCaptureKeepsOnlyFrontmostWindowAssignedToOneZone() {
        let zone = ResolvedZone(
            zoneID: UUID(),
            number: 1,
            frameAX: CGRect(x: 0, y: 0, width: 500, height: 500)
        )
        let front = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 1, bundleID: "front"),
            frameAX: zone.frameAX
        )
        let hidden = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 2, windowNumber: 2, bundleID: "hidden"),
            frameAX: zone.frameAX
        )

        let rules = ProfileCapture.rules(windows: [front, hidden], zones: [zone])

        XCTAssertEqual(rules.map(\.bundleID), ["front"])
    }

    private func rule(_ bundleID: String, _ zone: ResolvedZone) -> AppPlacementRule {
        AppPlacementRule(bundleID: bundleID, zoneID: zone.zoneID, zoneNumber: zone.number)
    }

    private func sample(pid: pid_t, number: UInt32, bundleID: String) -> ProfileCapture.WindowSample {
        ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: pid, windowNumber: number, bundleID: bundleID),
            frameAX: .zero
        )
    }
}
