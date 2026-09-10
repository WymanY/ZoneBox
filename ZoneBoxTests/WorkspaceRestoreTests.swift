import XCTest
@testable import ZoneBoxCore

final class WorkspaceRestoreTests: XCTestCase {
    func testReopenDoesNotLaunchASecondInstance() {
        XCTAssertEqual(WorkspaceRestore.openCommand(for: .reopen), .reopenRunning)
        XCTAssertEqual(WorkspaceRestore.openCommand(for: .launch), .launch)
        XCTAssertEqual(WorkspaceRestore.openCommand(for: .none), .none)
    }

    func testOpenFailureKeepsPendingWhenAppIsStillRunning() {
        XCTAssertEqual(
            WorkspaceRestore.openFailureDisposition(
                action: .launch,
                bundleID: "com.todesktop.230313mzl4w4u92",
                runningBundleIDs: ["com.todesktop.230313mzl4w4u92"]
            ),
            .keepWaiting
        )
        XCTAssertEqual(
            WorkspaceRestore.openFailureDisposition(
                action: .reopen,
                bundleID: "com.openai.codex",
                runningBundleIDs: []
            ),
            .keepWaiting
        )
        XCTAssertEqual(
            WorkspaceRestore.openFailureDisposition(
                action: .launch,
                bundleID: "com.apple.Notes",
                runningBundleIDs: []
            ),
            .giveUp
        )
    }

    func testLaunchRetriesUntilLimitThenStops() {
        XCTAssertTrue(
            WorkspaceRestore.shouldRetryLaunch(
                action: .launch,
                attempt: 1,
                runningBundleIDs: [],
                bundleID: "com.openai.codex"
            )
        )
        XCTAssertTrue(
            WorkspaceRestore.shouldRetryLaunch(
                action: .launch,
                attempt: 2,
                runningBundleIDs: [],
                bundleID: "com.openai.codex"
            )
        )
        XCTAssertFalse(
            WorkspaceRestore.shouldRetryLaunch(
                action: .launch,
                attempt: 3,
                runningBundleIDs: [],
                bundleID: "com.openai.codex"
            )
        )
        XCTAssertFalse(
            WorkspaceRestore.shouldRetryLaunch(
                action: .launch,
                attempt: 1,
                runningBundleIDs: ["com.openai.codex"],
                bundleID: "com.openai.codex"
            )
        )
        XCTAssertFalse(
            WorkspaceRestore.shouldRetryLaunch(
                action: .reopen,
                attempt: 1,
                runningBundleIDs: [],
                bundleID: "com.openai.codex"
            )
        )
    }

    func testReopenNudgeOnlyWhenStillPendingAndRunning() {
        XCTAssertTrue(
            WorkspaceRestore.shouldNudgeReopen(action: .reopen, stillPending: true, running: true)
        )
        XCTAssertFalse(
            WorkspaceRestore.shouldNudgeReopen(action: .reopen, stillPending: false, running: true)
        )
        XCTAssertFalse(
            WorkspaceRestore.shouldNudgeReopen(action: .reopen, stillPending: true, running: false)
        )
        XCTAssertFalse(
            WorkspaceRestore.shouldNudgeReopen(action: .launch, stillPending: true, running: true)
        )
    }

    func testHelperTerminationDoesNotCancelPendingRestore() {
        XCTAssertFalse(
            WorkspaceRestore.shouldDropPendingOnTermination(
                bundleID: "com.todesktop.230313mzl4w4u92",
                remainingRunningBundleIDs: ["com.todesktop.230313mzl4w4u92"]
            )
        )
        XCTAssertTrue(
            WorkspaceRestore.shouldDropPendingOnTermination(
                bundleID: "com.todesktop.230313mzl4w4u92",
                remainingRunningBundleIDs: []
            )
        )
        XCTAssertFalse(
            WorkspaceRestore.shouldDropPendingOnTermination(
                bundleID: nil,
                remainingRunningBundleIDs: []
            )
        )
        XCTAssertFalse(
            WorkspaceRestore.shouldDropPendingOnTermination(
                bundleID: "",
                remainingRunningBundleIDs: []
            )
        )
    }

    func testRejectedSplashReleasesReservationWithoutDroppingPending() {
        XCTAssertEqual(WorkspaceRestore.rejectedWindowDisposition(rejectedAttempts: 1), .retryAfterRestabilizing)
        XCTAssertEqual(WorkspaceRestore.rejectedWindowDisposition(rejectedAttempts: 2), .retryAfterRestabilizing)
        XCTAssertEqual(
            WorkspaceRestore.rejectedWindowDisposition(rejectedAttempts: 3),
            .ignoreThisWindowKeepPending
        )
    }

    func testSplashThatGrowsIntoDocumentWindowIsRevived() {
        let splash = CGRect(x: 100, y: 100, width: 200, height: 120)
        let document = CGRect(x: 0, y: 31, width: 900, height: 800)
        XCTAssertTrue(WorkspaceRestore.shouldReviveIgnoredWindow(previousFrame: splash, currentFrame: document))
        XCTAssertFalse(
            WorkspaceRestore.shouldReviveIgnoredWindow(
                previousFrame: document,
                currentFrame: document.insetBy(dx: 2, dy: 2)
            )
        )
    }

    func testClamshellRemapsFirstSectionOntoTheRemainingDisplay() {
        let saved = UUID()
        let live = UUID()
        let layoutID = UUID()
        let zone = ResolvedZone(zoneID: UUID(), number: 1, frameAX: .zero)
        let sections = [
            ProfileSection(space: SpaceKey(displayID: saved), layoutID: layoutID, rules: [
                AppPlacementRule(bundleID: "com.openai.codex", zoneID: zone.zoneID, zoneNumber: 1),
            ]),
        ]

        let remapped = WorkspaceRestore.remappedSections(
            sections,
            availableDisplayIDs: [live],
            fallbackDisplayID: live
        )

        XCTAssertEqual(remapped.map(\.space.displayID), [live])
        XCTAssertEqual(remapped.map(\.layoutID), [layoutID])
        XCTAssertEqual(remapped.first?.rules.map(\.bundleID), ["com.openai.codex"])
    }

    func testConnectedSiblingDisplayIsNotStolenByADisconnectedSection() {
        let builtIn = UUID()
        let external = UUID()
        let layoutID = UUID()
        let sections = [
            ProfileSection(space: SpaceKey(displayID: builtIn), layoutID: layoutID, rules: [
                AppPlacementRule(bundleID: "notes", zoneID: UUID(), zoneNumber: 1),
            ]),
            ProfileSection(space: SpaceKey(displayID: external), layoutID: layoutID, rules: [
                AppPlacementRule(bundleID: "browser", zoneID: UUID(), zoneNumber: 1),
            ]),
        ]

        let remapped = WorkspaceRestore.remappedSections(
            sections,
            availableDisplayIDs: [builtIn],
            fallbackDisplayID: builtIn
        )

        XCTAssertEqual(remapped.map(\.space.displayID), [builtIn, external])
    }

    func testTwoDisconnectedSectionsOnlyRemapTheFirstOntoFallback() {
        let first = UUID()
        let second = UUID()
        let live = UUID()
        let layoutID = UUID()
        let sections = [
            ProfileSection(space: SpaceKey(displayID: first), layoutID: layoutID, rules: [
                AppPlacementRule(bundleID: "one", zoneID: UUID(), zoneNumber: 1),
            ]),
            ProfileSection(space: SpaceKey(displayID: second), layoutID: layoutID, rules: [
                AppPlacementRule(bundleID: "two", zoneID: UUID(), zoneNumber: 1),
            ]),
        ]

        let remapped = WorkspaceRestore.remappedSections(
            sections,
            availableDisplayIDs: [live],
            fallbackDisplayID: live
        )

        XCTAssertEqual(remapped.map(\.space.displayID), [live, second])
    }

    func testLayoutStillAssignsAndFlashesWhenEveryAppIsStillLaunching() {
        XCTAssertTrue(WorkspaceRestore.shouldAssignLayout(displayAvailable: true, layoutExists: true))
        XCTAssertFalse(WorkspaceRestore.shouldAssignLayout(displayAvailable: false, layoutExists: true))
        XCTAssertFalse(WorkspaceRestore.shouldAssignLayout(displayAvailable: true, layoutExists: false))
        XCTAssertTrue(
            WorkspaceRestore.shouldFlashAssignedLayout(
                displayAvailable: true,
                layoutExists: true,
                organizeSucceeded: false,
                noMovableWindows: true
            )
        )
        XCTAssertTrue(
            WorkspaceRestore.shouldFlashAssignedLayout(
                displayAvailable: true,
                layoutExists: true,
                organizeSucceeded: true,
                noMovableWindows: false
            )
        )
        XCTAssertFalse(
            WorkspaceRestore.shouldFlashAssignedLayout(
                displayAvailable: true,
                layoutExists: true,
                organizeSucceeded: false,
                noMovableWindows: false
            )
        )
    }

    func testTimeoutCoversSlowElectronColdLaunch() {
        XCTAssertGreaterThanOrEqual(WorkspaceRestore.launchTimeout, 45)
        XCTAssertEqual(WorkspaceRestore.launchRetryLimit, 3)
        XCTAssertEqual(WorkspaceRestore.maxRejectedAttempts, 3)
    }

    func testRemappedDisplayStillPlansLayoutAndLaunchesMissingApps() {
        let saved = UUID()
        let live = UUID()
        let layoutID = UUID()
        let zone = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 400, height: 400))
        let original = WorkspaceProfile(name: "Desk", sections: [
            ProfileSection(space: SpaceKey(displayID: saved), layoutID: layoutID, rules: [
                AppPlacementRule(bundleID: "com.openai.codex", zoneID: zone.zoneID, zoneNumber: 1),
                AppPlacementRule(bundleID: "com.todesktop.230313mzl4w4u92", zoneID: zone.zoneID, zoneNumber: 1),
            ]),
        ])
        let remapped = WorkspaceRestore.remappedSections(
            original.sections,
            availableDisplayIDs: [live],
            fallbackDisplayID: live
        )
        let profile = WorkspaceProfile(
            id: original.id,
            name: original.name,
            sections: remapped,
            launchMissingApps: true
        )
        let outcome = ProfilePlan.make(
            profile: profile,
            zonesBySection: [live: [zone]],
            candidates: []
        )

        XCTAssertEqual(outcome.sections.map(\.displayID), [live])
        XCTAssertEqual(outcome.sections.map(\.layoutID), [layoutID])
        XCTAssertTrue(outcome.sections.first?.placements.isEmpty ?? false)
        XCTAssertEqual(outcome.missingBundleIDs, ["com.openai.codex"])
        XCTAssertEqual(
            ProfilePlan.openAction(
                bundleID: "com.openai.codex",
                missingBundleIDs: outcome.missingBundleIDs,
                runningBundleIDs: [],
                launchMissingApps: true
            ),
            .launch
        )
        XCTAssertEqual(
            ProfilePlan.openAction(
                bundleID: "com.openai.codex",
                missingBundleIDs: outcome.missingBundleIDs,
                runningBundleIDs: ["com.openai.codex"],
                launchMissingApps: true
            ),
            .reopen
        )
        XCTAssertTrue(WorkspaceRestore.shouldAssignLayout(displayAvailable: true, layoutExists: true))
    }

    func testForegroundBundleIDsPreserveFirstSeenOrderAndDropDuplicates() {
        XCTAssertEqual(
            WorkspaceRestore.foregroundBundleIDs([
                "com.apple.Notes",
                "",
                "com.electron.factory",
                "com.apple.Notes",
                "  com.google.Chrome  ",
                "com.electron.factory",
            ]),
            ["com.apple.Notes", "com.electron.factory", "com.google.Chrome"]
        )
        XCTAssertEqual(WorkspaceRestore.foregroundBundleIDs(["", "   "]), [])
    }

    func testRestoredAppsDoNotActivateEveryWindowOnOtherSpaces() {
        XCTAssertFalse(WorkspaceRestore.activateAllWindowsWhenForegroundingRestoredApps)
    }
}
