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

    func testCapturedFrameRoundTripsThroughTheSameWorkArea() throws {
        let frame = CGRect(x: 317, y: 140, width: 903, height: 611)
        let window = sample(pid: 1, number: 1, bundleID: "app", frame: frame)

        let rule = ProfileCapture.rules(windows: [window], workAreaAX: workArea)[0]
        let restored = try XCTUnwrap(rule.frame).denormalize(in: workArea)

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

    func testThisDisplayScopeRequiresWindowsOnThePointerDisplay() {
        let builtIn = section(display: UUID(), app: "editor")
        let external = section(display: UUID(), app: "browser")
        let empty = UUID()

        XCTAssertTrue(
            ProfileCapture.offersThisDisplayScope(
                sections: [builtIn, external],
                pointerDisplayID: external.space.displayID
            )
        )
        XCTAssertFalse(
            ProfileCapture.offersThisDisplayScope(
                sections: [builtIn, external],
                pointerDisplayID: empty
            )
        )
        XCTAssertFalse(
            ProfileCapture.offersThisDisplayScope(
                sections: [builtIn],
                pointerDisplayID: builtIn.space.displayID
            )
        )
        XCTAssertFalse(
            ProfileCapture.offersThisDisplayScope(
                sections: [builtIn, external],
                pointerDisplayID: nil
            )
        )
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

    func testCapturedFramesOutsideTheWorkAreaRoundTripThroughStoreAndRestore() throws {
        let samples: [(bundleID: String, frame: CGRect)] = [
            ("interior", CGRect(x: 317, y: 140, width: 903, height: 611)),
            ("partial-top", CGRect(x: 100, y: 0, width: 800, height: 500)),
            ("partial-right", CGRect(x: 1000, y: 400, width: 600, height: 600)),
            ("oversized", CGRect(x: -80, y: -40, width: 1800, height: 1200)),
        ]
        let windows = samples.enumerated().map { index, sample in
            self.sample(
                pid: pid_t(index + 1),
                number: UInt32(index + 1),
                bundleID: sample.bundleID,
                frame: sample.frame
            )
        }
        let rules = ProfileCapture.rules(windows: windows, workAreaAX: workArea)
        XCTAssertEqual(rules.map(\.bundleID), samples.map(\.bundleID))

        let displayID = UUID()
        let profile = WorkspaceProfile(
            name: "Desk",
            sections: [ProfileSection(space: SpaceKey(displayID: displayID), rules: rules)]
        )
        let document = StoreDocument(layouts: [LayoutTemplates.columns(2)], profiles: [profile])
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zonebox-raw-frame-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LayoutStore(directory: dir)
        try store.save(document)
        let loadedProfile = try XCTUnwrap(try store.load().profiles.first)
        let loadedRules = try XCTUnwrap(loadedProfile.sections.first?.rules)
        XCTAssertEqual(loadedRules.map(\.bundleID), samples.map(\.bundleID))

        let oversized = try XCTUnwrap(loadedRules.first { $0.bundleID == "oversized" }?.frame)
        XCTAssertLessThan(oversized.x, 0)
        XCTAssertGreaterThan(oversized.width, 1)
        let partialTop = try XCTUnwrap(loadedRules.first { $0.bundleID == "partial-top" }?.frame)
        XCTAssertLessThan(partialTop.y, 0)
        let preview = WorkspaceLayoutPreview.snapshot(rules: loadedRules)
        let oversizedPane = try XCTUnwrap(preview.panes.first { $0.bundleID == "oversized" })
        XCTAssertEqual(oversizedPane.rect, oversized)
        XCTAssertLessThan(oversizedPane.rect.x, 0)

        let outcome = ProfilePlan.make(
            profile: loadedProfile,
            workAreasBySection: [displayID: workArea],
            candidates: windows
        )
        XCTAssertEqual(outcome.missingBundleIDs, [])
        let section = try XCTUnwrap(outcome.sections.first)
        XCTAssertEqual(section.placements.count, samples.count)
        XCTAssertEqual(section.targetFramesAX.count, samples.count)
        for (index, sample) in samples.enumerated() {
            for frame in [section.placements[index].targetFrameAX, section.targetFramesAX[index]] {
                XCTAssertEqual(frame.minX, sample.frame.minX, accuracy: 0.01)
                XCTAssertEqual(frame.minY, sample.frame.minY, accuracy: 0.01)
                XCTAssertEqual(frame.width, sample.frame.width, accuracy: 0.01)
                XCTAssertEqual(frame.height, sample.frame.height, accuracy: 0.01)
            }
        }
    }

    func testLayoutZonesStillClampIntoTheWorkArea() throws {
        let partial = layoutZone(
            NormalizedRect(
                x: 100.0 / 1440.0,
                y: (0.0 - 25.0) / 875.0,
                width: 800.0 / 1440.0,
                height: 500.0 / 875.0
            )
        )
        let partialFrame = try XCTUnwrap(try resolveLayout(partial, workAreaAX: workArea, gutter: 0).first).frameAX
        XCTAssertEqual(partialFrame.minX, 100, accuracy: 0.01)
        XCTAssertEqual(partialFrame.minY, 25, accuracy: 0.01)
        XCTAssertEqual(partialFrame.width, 800, accuracy: 0.01)
        XCTAssertEqual(partialFrame.height, 500, accuracy: 0.01)

        let overflow = layoutZone(
            NormalizedRect(
                x: 1000.0 / 1440.0,
                y: (400.0 - 25.0) / 875.0,
                width: 600.0 / 1440.0,
                height: 600.0 / 875.0
            )
        )
        let overflowFrame = try XCTUnwrap(try resolveLayout(overflow, workAreaAX: workArea, gutter: 0).first).frameAX
        XCTAssertEqual(overflowFrame.minX, 840, accuracy: 0.01)
        XCTAssertEqual(overflowFrame.minY, 300, accuracy: 0.01)
        XCTAssertEqual(overflowFrame.width, 600, accuracy: 0.01)
        XCTAssertEqual(overflowFrame.height, 600, accuracy: 0.01)

        let huge = layoutZone(
            NormalizedRect(
                x: -80.0 / 1440.0,
                y: (-40.0 - 25.0) / 875.0,
                width: 1800.0 / 1440.0,
                height: 1200.0 / 875.0
            )
        )
        let hugeFrame = try XCTUnwrap(try resolveLayout(huge, workAreaAX: workArea, gutter: 0).first).frameAX
        XCTAssertEqual(hugeFrame.minX, 0, accuracy: 0.01)
        XCTAssertEqual(hugeFrame.minY, 25, accuracy: 0.01)
        XCTAssertEqual(hugeFrame.width, 1440, accuracy: 0.01)
        XCTAssertEqual(hugeFrame.height, 875, accuracy: 0.01)
    }

    private func section(display: DisplayIdentity.ID, app: String) -> ProfileSection {
        ProfileSection(
            space: SpaceKey(displayID: display),
            rules: [AppPlacementRule(bundleID: app, frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))]
        )
    }

    private func layoutZone(_ rect: NormalizedRect) -> Layout {
        Layout(name: "Zone", kind: .canvas, zones: [Zone(number: 1, canvasRect: rect)])
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
