import XCTest
@testable import ZoneBoxCore

final class ProfileCaptureTests: XCTestCase {
    private let workArea = CGRect(x: 0, y: 25, width: 1440, height: 875)

    func testWindowsAreSavedWhereTheyAreNotWhereTheActiveLayoutZonesAre() {
        // Left half + right half on a display whose active layout is a
        // 1 | 2/3 split: the halves must survive as halves.
        let chrome = sample(pid: 1, number: 1, bundleID: "com.google.Chrome", frame: CGRect(x: 0, y: 25, width: 720, height: 875))
        let cursor = sample(pid: 2, number: 2, bundleID: "com.todesktop.230313mzl4w4u92", frame: CGRect(x: 720, y: 25, width: 720, height: 875))

        let rules = ProfileCapture.rules(windows: [chrome, cursor], workAreaAX: workArea)

        XCTAssertEqual(rules.map(\.bundleID), ["com.google.Chrome", "com.todesktop.230313mzl4w4u92"])
        XCTAssertEqual(rules[0].frame, NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(rules[1].frame, NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
    }

    func testFullScreenWindowIsSavedAsTheWholeWorkArea() {
        let weChat = sample(pid: 1, number: 1, bundleID: "com.tencent.xinWeChat", frame: workArea)

        let rules = ProfileCapture.rules(windows: [weChat], workAreaAX: workArea)

        XCTAssertEqual(rules.map(\.frame), [NormalizedRect(x: 0, y: 0, width: 1, height: 1)])
    }

    func testCapturedFrameRoundTripsThroughTheSameWorkArea() {
        let frame = CGRect(x: 317, y: 140, width: 903, height: 611)
        let window = sample(pid: 1, number: 1, bundleID: "app", frame: frame)

        let rule = ProfileCapture.rules(windows: [window], workAreaAX: workArea)[0]
        let restored = rule.frame.denormalize(in: workArea)

        XCTAssertEqual(restored.minX, frame.minX, accuracy: 0.001)
        XCTAssertEqual(restored.minY, frame.minY, accuracy: 0.001)
        XCTAssertEqual(restored.width, frame.width, accuracy: 0.001)
        XCTAssertEqual(restored.height, frame.height, accuracy: 0.001)
    }

    func testRulesKeepZOrderAndSkipWindowsWithoutBundleID() {
        let front = sample(pid: 1, number: 1, bundleID: "front", frame: CGRect(x: 800, y: 100, width: 400, height: 400))
        let anonymous = sample(pid: 2, number: 2, bundleID: nil, frame: CGRect(x: 0, y: 25, width: 400, height: 400))
        let back = sample(pid: 3, number: 3, bundleID: "back", frame: CGRect(x: 0, y: 25, width: 400, height: 400))

        let rules = ProfileCapture.rules(windows: [front, anonymous, back], workAreaAX: workArea)

        XCTAssertEqual(rules.map(\.bundleID), ["front", "back"])
        XCTAssertEqual(ProfileCapture.rules(windows: [front], workAreaAX: .zero), [])
    }

    func testOverlappingWindowsAreBothSaved() {
        let front = sample(pid: 1, number: 1, bundleID: "front", frame: CGRect(x: 0, y: 25, width: 900, height: 875))
        let back = sample(pid: 2, number: 2, bundleID: "back", frame: CGRect(x: 600, y: 25, width: 840, height: 875))

        XCTAssertEqual(
            ProfileCapture.rules(windows: [front, back], workAreaAX: workArea).map(\.bundleID),
            ["front", "back"]
        )
    }

    func testReadingOrderGoesLeftToRightThenTopToBottom() {
        let topRight = AppPlacementRule(bundleID: "c", frame: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        let bottomRight = AppPlacementRule(bundleID: "b", frame: NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let left = AppPlacementRule(bundleID: "a", frame: NormalizedRect(x: 0.004, y: 0.01, width: 0.5, height: 1))

        XCTAssertEqual(
            AppPlacementRule.readingOrder([bottomRight, topRight, left]).map(\.bundleID),
            ["a", "c", "b"]
        )
    }

    func testRuleMatchingToleratesSmallDriftOnly() {
        let rule = AppPlacementRule(bundleID: "app", frame: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
        let nudged = AppPlacementRule(bundleID: "app", frame: NormalizedRect(x: 0.51, y: 0.01, width: 0.49, height: 0.99))
        let moved = AppPlacementRule(bundleID: "app", frame: NormalizedRect(x: 0.4, y: 0, width: 0.5, height: 1))
        let otherApp = AppPlacementRule(bundleID: "other", frame: rule.frame)

        XCTAssertTrue(rule.matches(nudged))
        XCTAssertFalse(rule.matches(moved))
        XCTAssertFalse(rule.matches(otherApp))
    }

    func testMaximizedFrontWindowHidesCoveredSnappedWindows() {
        let front = visibility(pid: 1, number: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let left = visibility(pid: 2, number: 2, frame: CGRect(x: 0, y: 0, width: 500, height: 800))
        let right = visibility(pid: 3, number: 3, frame: CGRect(x: 500, y: 0, width: 500, height: 800))
        let visible = ProfileCapture.visibleWindowIdentities(frontToBack: [front, left, right])
        XCTAssertEqual(visible, Set([front.identity]))
    }

    func testFullyCoveredBackWindowIsNotVisible() {
        let front = visibility(pid: 1, number: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let back = visibility(pid: 2, number: 2, frame: CGRect(x: 0, y: 0, width: 500, height: 500))

        let visible = ProfileCapture.visibleWindowIdentities(frontToBack: [front, back])

        XCTAssertEqual(visible, Set([front.identity]))
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

        XCTAssertEqual(visible, Set([front.identity]))
    }

    func testAdjacentSnappedWindowsRemainVisibleAcrossASharedSeam() {
        let left = visibility(pid: 1, number: 1, frame: CGRect(x: 0, y: 31, width: 709, height: 804))
        let right = visibility(pid: 2, number: 2, frame: CGRect(x: 708, y: 31, width: 732, height: 804))

        let visible = ProfileCapture.visibleWindowIdentities(frontToBack: [left, right])

        XCTAssertEqual(visible, [left.identity, right.identity])
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

    func testNewCaptureLimitedToOneDisplayKeepsOnlyThatSection() {
        let builtIn = section(display: UUID(), app: "editor")
        let external = section(display: UUID(), app: "browser")

        XCTAssertEqual(
            ProfileCapture.sections([builtIn, external], limitedTo: external.space.displayID),
            [external]
        )
        XCTAssertEqual(ProfileCapture.sections([builtIn, external], limitedTo: nil), [builtIn, external])
        XCTAssertEqual(ProfileCapture.sections([builtIn, external], limitedTo: UUID()), [])
    }

    func testRecaptureRefreshesConnectedDisplayAndKeepsUnpluggedSection() {
        let builtInID = UUID()
        let externalID = UUID()
        let oldBuiltIn = section(display: builtInID, app: "notes")
        let external = section(display: externalID, app: "browser")
        let newBuiltIn = section(display: builtInID, app: "editor")

        XCTAssertEqual(
            ProfileCapture.mergedRecaptureSections(
                existing: [oldBuiltIn, external],
                captured: [newBuiltIn],
                availableDisplayIDs: [builtInID]
            ),
            [newBuiltIn, external]
        )
    }

    func testRecaptureDropsAConnectedDisplayThatNoLongerHoldsWindows() {
        let builtInID = UUID()
        let externalID = UUID()
        let oldBuiltIn = section(display: builtInID, app: "notes")
        let oldExternal = section(display: externalID, app: "browser")
        let newExternal = section(display: externalID, app: "terminal")

        XCTAssertEqual(
            ProfileCapture.mergedRecaptureSections(
                existing: [oldBuiltIn, oldExternal],
                captured: [newExternal],
                availableDisplayIDs: [builtInID, externalID]
            ),
            [newExternal]
        )
    }

    func testRecaptureAddsANewlyConnectedDisplayAfterExistingSections() {
        let builtInID = UUID()
        let externalID = UUID()
        let oldBuiltIn = section(display: builtInID, app: "notes")
        let newBuiltIn = section(display: builtInID, app: "notes")
        let newExternal = section(display: externalID, app: "browser")

        XCTAssertEqual(
            ProfileCapture.mergedRecaptureSections(
                existing: [oldBuiltIn],
                captured: [newExternal, newBuiltIn],
                availableDisplayIDs: [builtInID, externalID]
            ),
            [newBuiltIn, newExternal]
        )
    }

    func testRecaptureWithNothingCapturedLeavesTheProfileUntouched() {
        let builtInID = UUID()
        let existing = [section(display: builtInID, app: "notes"), section(display: UUID(), app: "browser")]

        XCTAssertNil(
            ProfileCapture.mergedRecaptureSections(
                existing: existing,
                captured: [],
                availableDisplayIDs: [builtInID]
            )
        )
    }

    private func section(display: DisplayIdentity.ID, app: String) -> ProfileSection {
        ProfileSection(
            space: SpaceKey(displayID: display),
            rules: [AppPlacementRule(bundleID: app, frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))]
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
