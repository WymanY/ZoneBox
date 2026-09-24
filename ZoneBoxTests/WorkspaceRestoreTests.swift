import XCTest
@testable import ZoneBoxCore

final class WorkspaceRestoreTests: XCTestCase {
    private let leftHalf = NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)

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
        let sections = [
            ProfileSection(space: SpaceKey(displayID: saved), rules: [
                AppPlacementRule(bundleID: "com.openai.codex", frame: leftHalf),
            ]),
        ]

        let remapped = WorkspaceRestore.remappedSections(
            sections,
            availableDisplayIDs: [live],
            fallbackDisplayID: live
        )

        XCTAssertEqual(remapped.map(\.space.displayID), [live])
        XCTAssertEqual(remapped.first?.rules, sections[0].rules)
    }

    func testConnectedSiblingDisplayIsNotStolenByADisconnectedSection() {
        let builtIn = UUID()
        let external = UUID()
        let sections = [
            ProfileSection(space: SpaceKey(displayID: builtIn), rules: [
                AppPlacementRule(bundleID: "notes", frame: leftHalf),
            ]),
            ProfileSection(space: SpaceKey(displayID: external), rules: [
                AppPlacementRule(bundleID: "browser", frame: leftHalf),
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
        let sections = [
            ProfileSection(space: SpaceKey(displayID: first), rules: [
                AppPlacementRule(bundleID: "one", frame: leftHalf),
            ]),
            ProfileSection(space: SpaceKey(displayID: second), rules: [
                AppPlacementRule(bundleID: "two", frame: leftHalf),
            ]),
        ]

        let remapped = WorkspaceRestore.remappedSections(
            sections,
            availableDisplayIDs: [live],
            fallbackDisplayID: live
        )

        XCTAssertEqual(remapped.map(\.space.displayID), [live, second])
    }

    func testTimeoutCoversSlowElectronColdLaunch() {
        XCTAssertGreaterThanOrEqual(WorkspaceRestore.launchTimeout, 45)
        XCTAssertEqual(WorkspaceRestore.launchRetryLimit, 3)
        XCTAssertEqual(WorkspaceRestore.maxRejectedAttempts, 3)
    }

    func testRemappedDisplayStillPlansFramesAndLaunchesMissingApps() {
        let saved = UUID()
        let live = UUID()
        let liveWorkArea = CGRect(x: 0, y: 0, width: 800, height: 400)
        let original = WorkspaceProfile(name: "Desk", sections: [
            ProfileSection(space: SpaceKey(displayID: saved), rules: [
                AppPlacementRule(bundleID: "com.openai.codex", frame: leftHalf),
                AppPlacementRule(bundleID: "com.todesktop.230313mzl4w4u92", frame: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)),
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
            workAreasBySection: [live: liveWorkArea],
            candidates: []
        )

        XCTAssertEqual(outcome.sections.map(\.displayID), [live])
        XCTAssertEqual(
            outcome.sections.first?.targetFramesAX,
            [CGRect(x: 0, y: 0, width: 400, height: 400), CGRect(x: 400, y: 0, width: 400, height: 400)]
        )
        XCTAssertTrue(outcome.sections.first?.placements.isEmpty ?? false)
        XCTAssertEqual(outcome.missingBundleIDs, ["com.openai.codex", "com.todesktop.230313mzl4w4u92"])
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
    }

    func testStackingOrderRaisesBackToFrontSoTheCapturedFrontmostStaysOnTop() {
        XCTAssertEqual(
            WorkspaceRestore.stackingOrder(["front", "mid", "back"]),
            ["back", "mid", "front"]
        )
        XCTAssertEqual(
            WorkspaceRestore.restoreActivationBundleIDs([
                "com.front",
                "com.front",
                "com.back",
            ]),
            ["com.back", "com.front"]
        )
        let windows = [
            WindowIdentity(pid: 1, windowNumber: 1, bundleID: "com.front"),
            WindowIdentity(pid: 2, windowNumber: 2, bundleID: "com.back"),
        ]
        XCTAssertEqual(
            WorkspaceRestore.restoreActivationProcessIDs(windows, bundleID: "com.front"),
            [1]
        )
        XCTAssertEqual(
            WorkspaceRestore.restoreActivationBundleIDs(windows.compactMap(\.bundleID)).last,
            "com.front"
        )
    }

    func testInterleavedABAKeepsCapturedFrontmostAppOnTop() {
        let frontA = WindowIdentity(pid: 11, windowNumber: 1, bundleID: "com.a")
        let midB = WindowIdentity(pid: 22, windowNumber: 2, bundleID: "com.b")
        let backA = WindowIdentity(pid: 11, windowNumber: 3, bundleID: "com.a")
        let captured = [frontA, midB, backA]

        XCTAssertEqual(
            WorkspaceRestore.restoreActivationBundleIDs(captured.compactMap(\.bundleID)),
            ["com.b", "com.a"]
        )
        XCTAssertEqual(
            WorkspaceRestore.restoreActivationBundleIDs(captured.compactMap(\.bundleID)).last,
            "com.a"
        )
        XCTAssertEqual(
            WorkspaceRestore.lastOccurrenceOrder(
                WorkspaceRestore.stackingOrder(captured.compactMap(\.bundleID))
            ),
            ["com.b", "com.a"]
        )
        XCTAssertEqual(
            WorkspaceRestore.restoreActivationProcessIDs(captured, bundleID: "com.a"),
            [11]
        )
        XCTAssertEqual(
            WorkspaceRestore.restoreActivationProcessIDs(captured, bundleID: "com.b"),
            [22]
        )

        let frontA1 = WindowIdentity(pid: 31, windowNumber: 4, bundleID: "com.a")
        let midB2 = WindowIdentity(pid: 32, windowNumber: 5, bundleID: "com.b")
        let backA2 = WindowIdentity(pid: 33, windowNumber: 6, bundleID: "com.a")
        let splitA = [frontA1, midB2, backA2]
        XCTAssertEqual(
            WorkspaceRestore.restoreActivationProcessIDs(splitA, bundleID: "com.a"),
            [33, 31]
        )
        XCTAssertEqual(
            WorkspaceRestore.restoreActivationProcessIDs(splitA, bundleID: "com.a").last,
            31
        )
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

    func testForegroundProcessIDsIncludeBothInstancesOfOneBundle() {
        let windows = [
            WindowIdentity(pid: 41, windowNumber: 1, bundleID: "com.example.app"),
            WindowIdentity(pid: 42, windowNumber: 2, bundleID: "com.example.app"),
            WindowIdentity(pid: 41, windowNumber: 3, bundleID: "com.example.app"),
            WindowIdentity(pid: 99, windowNumber: 4, bundleID: "com.other.app"),
        ]
        XCTAssertEqual(
            WorkspaceRestore.foregroundProcessIDs(windows, bundleID: "com.example.app"),
            [41, 42]
        )
    }

    func testRestoredAppsDoNotActivateEveryWindowOnOtherSpaces() {
        XCTAssertFalse(WorkspaceRestore.activateAllWindowsWhenForegroundingRestoredApps)
    }

    func testPreferredProcessUsesRestoredWindowPIDInsteadOfHelper() {
        let windowPID: pid_t = 98973
        let helperPID: pid_t = 1001
        let running = [
            WorkspaceRestore.RunningProcess(
                pid: helperPID,
                bundleID: "com.todesktop.230313mzl4w4u92",
                isRegular: false,
                isFinished: false,
                isHidden: false
            ),
            WorkspaceRestore.RunningProcess(
                pid: windowPID,
                bundleID: "com.todesktop.230313mzl4w4u92",
                isRegular: true,
                isFinished: false,
                isHidden: false
            ),
        ]
        XCTAssertEqual(
            WorkspaceRestore.preferredProcessIdentifier(
                bundleID: "com.todesktop.230313mzl4w4u92",
                restoredWindowPIDs: [windowPID],
                running: running
            ),
            windowPID
        )
    }

    func testPreferredProcessPrefersRegularVisibleAppWhenWindowPIDIsMissing() {
        let running = [
            WorkspaceRestore.RunningProcess(
                pid: 11,
                bundleID: "com.google.Chrome",
                isRegular: false,
                isFinished: false,
                isHidden: false
            ),
            WorkspaceRestore.RunningProcess(
                pid: 22,
                bundleID: "com.google.Chrome",
                isRegular: true,
                isFinished: false,
                isHidden: true
            ),
            WorkspaceRestore.RunningProcess(
                pid: 33,
                bundleID: "com.google.Chrome",
                isRegular: true,
                isFinished: false,
                isHidden: false
            ),
            WorkspaceRestore.RunningProcess(
                pid: 44,
                bundleID: "com.google.Chrome",
                isRegular: true,
                isFinished: true,
                isHidden: false
            ),
        ]
        XCTAssertEqual(
            WorkspaceRestore.preferredProcessIdentifier(
                bundleID: "com.google.Chrome",
                restoredWindowPIDs: [],
                running: running
            ),
            33
        )
    }

    func testPreferredProcessIgnoresOtherBundlesAndEmptyIDs() {
        let running = [
            WorkspaceRestore.RunningProcess(
                pid: 7,
                bundleID: "com.tencent.xinWeChat",
                isRegular: true,
                isFinished: false,
                isHidden: false
            ),
        ]
        XCTAssertNil(
            WorkspaceRestore.preferredProcessIdentifier(
                bundleID: "com.google.Chrome",
                restoredWindowPIDs: [7],
                running: running
            )
        )
        XCTAssertNil(
            WorkspaceRestore.preferredProcessIdentifier(
                bundleID: "  ",
                restoredWindowPIDs: [7],
                running: running
            )
        )
    }

    func testActivationOutcomeRecordsRejectionAndFrontmostMismatch() {
        XCTAssertEqual(
            WorkspaceRestore.activationOutcome(
                requestAccepted: false,
                requestedPID: 42,
                actualFrontmostPID: 7
            ),
            .rejected
        )
        XCTAssertEqual(
            WorkspaceRestore.activationOutcome(
                requestAccepted: true,
                requestedPID: 42,
                actualFrontmostPID: 7
            ),
            .acceptedButFrontmostMismatch
        )
        XCTAssertEqual(
            WorkspaceRestore.activationOutcome(
                requestAccepted: true,
                requestedPID: 42,
                actualFrontmostPID: 42
            ),
            .acceptedAndFrontmost
        )
        XCTAssertEqual(
            WorkspaceRestore.activationOutcome(
                requestAccepted: true,
                requestedPID: 42,
                actualFrontmostPID: nil
            ),
            .acceptedButFrontmostMismatch
        )
        XCTAssertEqual(
            WorkspaceRestore.activationOutcome(
                requestAccepted: false,
                requestedPID: 42,
                actualFrontmostPID: 42
            ),
            .acceptedAndFrontmost
        )
        // A helper or another instance can share the bundle ID but not the
        // restored window's process ID. Keep retrying in that case.
        XCTAssertTrue(WorkspaceRestore.shouldRetryActivation(
            WorkspaceRestore.activationOutcome(
                requestAccepted: true,
                requestedPID: 42,
                actualFrontmostPID: 43
            )
        ))
    }

    func testActivationRetryOnlyWhenRequestDidNotLand() {
        XCTAssertTrue(WorkspaceRestore.shouldRetryActivation(.rejected))
        XCTAssertTrue(WorkspaceRestore.shouldRetryActivation(.acceptedButFrontmostMismatch))
        XCTAssertFalse(WorkspaceRestore.shouldRetryActivation(.acceptedAndFrontmost))
        XCTAssertFalse(WorkspaceRestore.shouldRetryActivation(.noProcess))
        XCTAssertEqual(WorkspaceRestore.activationSettleDelay, 0.05)
    }
}
