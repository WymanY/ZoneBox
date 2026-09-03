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
        XCTAssertEqual(
            ProfilePlan.restorableBundleIDs(
                profile: profile,
                availableDisplayIDs: [activeDisplay]
            ),
            Set(["editor", "stale"])
        )
    }

    func testRestorableBundleIDsIgnoreSkippedDisplays() {
        let active = UUID()
        let disconnected = UUID()
        let zone = ResolvedZone(zoneID: UUID(), number: 1, frameAX: .zero)
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: active), layoutID: UUID(), rules: [rule("editor", zone)]),
            ProfileSection(space: SpaceKey(displayID: disconnected), layoutID: UUID(), rules: [rule("hidden.app", zone)]),
        ])

        XCTAssertEqual(
            ProfilePlan.restorableBundleIDs(profile: profile, availableDisplayIDs: [active]),
            Set(["editor"])
        )
    }

    func testUnreachableLeftoverWindowsAreNotReopened() {
        XCTAssertTrue(
            ProfilePlan.isUnreachableLeftoverWindow(isMinimized: false, isHiddenApp: false, isFullscreen: false)
        )
        XCTAssertTrue(
            ProfilePlan.isUnreachableLeftoverWindow(isMinimized: false, isHiddenApp: false, isFullscreen: true)
        )
        XCTAssertFalse(
            ProfilePlan.isUnreachableLeftoverWindow(isMinimized: true, isHiddenApp: false, isFullscreen: false)
        )
        XCTAssertFalse(
            ProfilePlan.isUnreachableLeftoverWindow(isMinimized: false, isHiddenApp: true, isFullscreen: false)
        )
        XCTAssertEqual(
            ProfilePlan.openAction(
                bundleID: "browser",
                missingBundleIDs: ["browser"],
                runningBundleIDs: ["browser"],
                launchMissingApps: true
            ),
            .reopen
        )
    }

    func testKeepsConnectedSectionWhenEverySavedWindowIsMissing() {
        let display = UUID()
        let layoutID = UUID()
        let zone = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 200, height: 100))
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), layoutID: layoutID, rules: [rule("editor", zone)]),
        ])

        let outcome = ProfilePlan.make(profile: profile, zonesBySection: [display: [zone]], candidates: [])

        XCTAssertEqual(outcome.sections.map(\.displayID), [display])
        XCTAssertEqual(outcome.sections.map(\.layoutID), [layoutID])
        XCTAssertTrue(outcome.sections.first?.placements.isEmpty ?? false)
        XCTAssertEqual(outcome.missingBundleIDs, ["editor"])
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

    func testWindowAlreadyInZoneKeepsItInsteadOfFrontmostWindow() throws {
        let display = UUID()
        let left = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 500))
        let right = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 500))
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), layoutID: UUID(), rules: [rule("browser", left), rule("browser", right)]),
        ])
        let frontInRight = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 1, bundleID: "browser"),
            frameAX: right.frameAX
        )
        let backInLeft = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 2, bundleID: "browser"),
            frameAX: left.frameAX
        )

        let outcome = ProfilePlan.make(
            profile: profile,
            zonesBySection: [display: [left, right]],
            candidates: [frontInRight, backInLeft]
        )

        let placements = try XCTUnwrap(outcome.sections.first?.placements)
        XCTAssertEqual(placements.map(\.identity), [backInLeft.identity, frontInRight.identity])
        XCTAssertEqual(placements.map(\.targetFrameAX), [left.frameAX, right.frameAX])
    }

    func testWindowOnSectionDisplayBeatsWindowOnAnotherDisplay() throws {
        let display = UUID()
        let zone = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 500))
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), layoutID: UUID(), rules: [rule("browser", zone)]),
        ])
        let frontElsewhere = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 1, bundleID: "browser"),
            frameAX: CGRect(x: 2000, y: 0, width: 300, height: 300)
        )
        let backOnDisplay = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 2, bundleID: "browser"),
            frameAX: CGRect(x: 100, y: 100, width: 100, height: 100)
        )

        let outcome = ProfilePlan.make(
            profile: profile,
            zonesBySection: [display: [zone]],
            candidates: [frontElsewhere, backOnDisplay]
        )

        XCTAssertEqual(outcome.sections.first?.placements.map(\.identity), [backOnDisplay.identity])
    }

    func testFrontmostWindowWinsWhenNoWindowIsNearAnyZone() {
        let display = UUID()
        let zone = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 500))
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), layoutID: UUID(), rules: [rule("browser", zone)]),
        ])
        let front = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 1, bundleID: "browser"),
            frameAX: CGRect(x: 2000, y: 0, width: 300, height: 300)
        )
        let back = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 2, bundleID: "browser"),
            frameAX: CGRect(x: 3000, y: 0, width: 300, height: 300)
        )

        let outcome = ProfilePlan.make(profile: profile, zonesBySection: [display: [zone]], candidates: [front, back])

        XCTAssertEqual(outcome.sections.first?.placements.map(\.identity), [front.identity])
    }

    func testRunningAppWithoutWindowsShouldReopenInsteadOfLaunch() {
        XCTAssertEqual(
            ProfilePlan.openAction(
                bundleID: "com.alicloud.smartdrive",
                missingBundleIDs: ["com.alicloud.smartdrive"],
                runningBundleIDs: ["com.alicloud.smartdrive"],
                launchMissingApps: true
            ),
            .reopen
        )
        XCTAssertEqual(
            ProfilePlan.openAction(
                bundleID: "com.openai.codex",
                missingBundleIDs: ["com.openai.codex"],
                runningBundleIDs: [],
                launchMissingApps: true
            ),
            .launch
        )
        XCTAssertEqual(
            ProfilePlan.openAction(
                bundleID: "com.alicloud.smartdrive",
                missingBundleIDs: ["com.alicloud.smartdrive"],
                runningBundleIDs: ["com.alicloud.smartdrive"],
                launchMissingApps: false
            ),
            .none
        )
        XCTAssertEqual(
            ProfilePlan.openAction(
                bundleID: "present.app",
                missingBundleIDs: ["other.app"],
                runningBundleIDs: ["present.app"],
                launchMissingApps: true
            ),
            .none
        )
    }

    func testSuggestedWorkspaceNameJoinsCapturedAppsInOrder() {
        XCTAssertEqual(
            WorkspaceProfile.suggestedName(appNames: ["ChatGPT", "Notes", "阿里云盘"], fallback: "Workspace"),
            "ChatGPT+Notes+阿里云盘"
        )
        XCTAssertEqual(
            WorkspaceProfile.suggestedName(appNames: [" ChatGPT ", "chatgpt", "Notes"], fallback: "Workspace"),
            "ChatGPT+Notes"
        )
        XCTAssertEqual(
            WorkspaceProfile.suggestedName(appNames: ["", "  "], fallback: "Workspace"),
            "Workspace"
        )
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
