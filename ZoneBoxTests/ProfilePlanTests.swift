import XCTest
@testable import ZoneBoxCore

final class ProfilePlanTests: XCTestCase {
    private let workArea = CGRect(x: 0, y: 25, width: 1000, height: 800)
    private let leftHalf = NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
    private let rightHalf = NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)

    func testConsumesBundleQueuesAcrossDisplaysWithoutReusingWindows() {
        let firstDisplay = UUID()
        let secondDisplay = UUID()
        let secondWorkArea = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: firstDisplay), rules: [rule("browser", leftHalf)]),
            ProfileSection(space: SpaceKey(displayID: secondDisplay), rules: [rule("browser", rightHalf)]),
        ])
        let front = sample(pid: 1, number: 1, bundleID: "browser")
        let back = sample(pid: 2, number: 2, bundleID: "browser")

        let outcome = ProfilePlan.make(
            profile: profile,
            workAreasBySection: [firstDisplay: workArea, secondDisplay: secondWorkArea],
            candidates: [front, back]
        )

        XCTAssertEqual(outcome.sections.flatMap(\.placements).map(\.identity), [front.identity, back.identity])
        XCTAssertEqual(
            outcome.sections.flatMap(\.placements).map(\.targetFrameAX),
            [CGRect(x: 0, y: 25, width: 500, height: 800), CGRect(x: 2000, y: 0, width: 1000, height: 1000)]
        )
        XCTAssertTrue(outcome.missingBundleIDs.isEmpty)
    }

    func testReportsMissingAppsAndDisconnectedSections() {
        let activeDisplay = UUID()
        let disconnected = UUID()
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: activeDisplay), rules: [rule("editor", leftHalf)]),
            ProfileSection(space: SpaceKey(displayID: disconnected), rules: [rule("browser", rightHalf)]),
        ])

        let outcome = ProfilePlan.make(profile: profile, workAreasBySection: [activeDisplay: workArea], candidates: [])

        XCTAssertEqual(outcome.missingBundleIDs, ["editor"])
        XCTAssertEqual(outcome.skippedDisplayIDs, [disconnected])
        XCTAssertEqual(outcome.sections.first?.targetFramesAX, [CGRect(x: 0, y: 25, width: 500, height: 800)])
        XCTAssertEqual(
            ProfilePlan.restorableBundleIDs(profile: profile, availableDisplayIDs: [activeDisplay]),
            Set(["editor"])
        )
    }

    func testRestorableBundleIDsIgnoreSkippedDisplays() {
        let active = UUID()
        let disconnected = UUID()
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: active), rules: [rule("editor", leftHalf)]),
            ProfileSection(space: SpaceKey(displayID: disconnected), rules: [rule("hidden.app", leftHalf)]),
        ])

        XCTAssertEqual(
            ProfilePlan.restorableBundleIDs(profile: profile, availableDisplayIDs: [active]),
            Set(["editor"])
        )
    }

    func testUnreachableLeftoverWindowsAreNotReopened() {
        XCTAssertFalse(
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
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), rules: [rule("editor", leftHalf)]),
        ])

        let outcome = ProfilePlan.make(profile: profile, workAreasBySection: [display: workArea], candidates: [])

        XCTAssertEqual(outcome.sections.map(\.displayID), [display])
        XCTAssertEqual(outcome.sections.map(\.workAreaAX), [workArea])
        XCTAssertTrue(outcome.sections.first?.placements.isEmpty ?? false)
        XCTAssertEqual(outcome.missingBundleIDs, ["editor"])
    }

    func testMissingBundleIDsAreDeduplicated() {
        let display = UUID()
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), rules: [rule("app", leftHalf), rule("app", rightHalf)]),
        ])
        let outcome = ProfilePlan.make(profile: profile, workAreasBySection: [display: workArea], candidates: [])
        XCTAssertEqual(outcome.missingBundleIDs, ["app"])
    }

    func testFramesScaleWithTheLiveWorkArea() throws {
        let display = UUID()
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), rules: [
                rule("app", NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)),
            ]),
        ])
        let larger = CGRect(x: 100, y: 50, width: 2000, height: 1200)

        let outcome = ProfilePlan.make(
            profile: profile,
            workAreasBySection: [display: larger],
            candidates: [sample(pid: 1, number: 1, bundleID: "app")]
        )

        XCTAssertEqual(
            try XCTUnwrap(outcome.sections.first?.placements.first?.targetFrameAX),
            CGRect(x: 600, y: 650, width: 1000, height: 300)
        )
    }

    func testWindowAlreadyAtTheSavedFrameKeepsItInsteadOfFrontmostWindow() throws {
        let display = UUID()
        let leftFrame = leftHalf.denormalize(in: workArea)
        let rightFrame = rightHalf.denormalize(in: workArea)
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), rules: [rule("browser", leftHalf), rule("browser", rightHalf)]),
        ])
        let frontInRight = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 1, bundleID: "browser"),
            frameAX: rightFrame
        )
        let backInLeft = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 2, bundleID: "browser"),
            frameAX: leftFrame
        )

        let outcome = ProfilePlan.make(
            profile: profile,
            workAreasBySection: [display: workArea],
            candidates: [frontInRight, backInLeft]
        )

        let placements = try XCTUnwrap(outcome.sections.first?.placements)
        XCTAssertEqual(placements.map(\.identity), [backInLeft.identity, frontInRight.identity])
        XCTAssertEqual(placements.map(\.targetFrameAX), [leftFrame, rightFrame])
    }

    func testWindowOnSectionDisplayBeatsWindowOnAnotherDisplay() throws {
        let display = UUID()
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), rules: [rule("browser", leftHalf)]),
        ])
        let frontElsewhere = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 1, bundleID: "browser"),
            frameAX: CGRect(x: 2000, y: 0, width: 300, height: 300)
        )
        let backOnDisplay = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 2, bundleID: "browser"),
            frameAX: CGRect(x: 600, y: 100, width: 100, height: 100)
        )

        let outcome = ProfilePlan.make(
            profile: profile,
            workAreasBySection: [display: workArea],
            candidates: [frontElsewhere, backOnDisplay]
        )

        XCTAssertEqual(outcome.sections.first?.placements.map(\.identity), [backOnDisplay.identity])
    }

    func testFrontmostWindowWinsWhenNoWindowIsOnTheDisplay() {
        let display = UUID()
        let profile = WorkspaceProfile(name: "Work", sections: [
            ProfileSection(space: SpaceKey(displayID: display), rules: [rule("browser", leftHalf)]),
        ])
        let front = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 1, bundleID: "browser"),
            frameAX: CGRect(x: 2000, y: 0, width: 300, height: 300)
        )
        let back = ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: 1, windowNumber: 2, bundleID: "browser"),
            frameAX: CGRect(x: 3000, y: 0, width: 300, height: 300)
        )

        let outcome = ProfilePlan.make(profile: profile, workAreasBySection: [display: workArea], candidates: [front, back])

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
        XCTAssertEqual(
            ProfilePlan.openAction(
                bundleID: "com.apple.iphonesimulator",
                missingBundleIDs: ["com.apple.iphonesimulator"],
                runningBundleIDs: ["com.apple.iphonesimulator"],
                launchMissingApps: true
            ),
            .reopen
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

    private func rule(_ bundleID: String, _ frame: NormalizedRect) -> AppPlacementRule {
        AppPlacementRule(bundleID: bundleID, frame: frame)
    }

    private func sample(pid: pid_t, number: UInt32, bundleID: String) -> ProfileCapture.WindowSample {
        ProfileCapture.WindowSample(
            identity: WindowIdentity(pid: pid, windowNumber: number, bundleID: bundleID),
            frameAX: .zero
        )
    }
}
