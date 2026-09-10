import XCTest
@testable import ZoneBoxCore

final class WorkspaceSwitcherTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()
    private let third = UUID()
    private let fourth = UUID()

    func testInvokeHighlightsActiveThenFirst() {
        let active = reduce(
            phase: .hidden,
            event: .invoke,
            ids: [first, second, third],
            active: second
        )
        XCTAssertEqual(active.phase, .browsing(highlight: 1))
        XCTAssertEqual(active.effects, [.show])

        let fallback = reduce(phase: .hidden, event: .invoke, ids: [first, second])
        XCTAssertEqual(fallback.phase, .browsing(highlight: 0))
        XCTAssertEqual(fallback.effects, [.show])
    }

    func testDigitAppliesMatchingProfileAndIgnoresOOB() {
        let hit = reduce(
            phase: .browsing(highlight: 0),
            event: .digit(2),
            ids: [first, second, third]
        )
        XCTAssertEqual(hit.phase, .hidden)
        XCTAssertEqual(hit.effects, [.hide, .apply(second)])

        let miss = reduce(
            phase: .browsing(highlight: 0),
            event: .digit(9),
            ids: [first, second]
        )
        XCTAssertEqual(miss.phase, .browsing(highlight: 0))
        XCTAssertEqual(miss.effects, [])
    }

    func testConfirmAppliesHighlightAndSecondInvokeMatchesConfirm() {
        let confirm = reduce(
            phase: .browsing(highlight: 2),
            event: .confirm,
            ids: [first, second, third]
        )
        XCTAssertEqual(confirm.effects, [.hide, .apply(third)])

        let again = reduce(
            phase: .browsing(highlight: 2),
            event: .invoke,
            ids: [first, second, third]
        )
        XCTAssertEqual(again.effects, [.hide, .apply(third)])
    }

    func testMoveWrapsThreeColumnGrid() {
        let ids = [first, second, third, fourth]
        let right = reduce(phase: .browsing(highlight: 3), event: .move(dx: 1, dy: 0), ids: ids)
        XCTAssertEqual(right.phase, .browsing(highlight: 0))

        let left = reduce(phase: .browsing(highlight: 0), event: .move(dx: -1, dy: 0), ids: ids)
        XCTAssertEqual(left.phase, .browsing(highlight: 3))

        let down = reduce(phase: .browsing(highlight: 0), event: .move(dx: 0, dy: 1), ids: ids)
        XCTAssertEqual(down.phase, .browsing(highlight: 3))

        let up = reduce(phase: .browsing(highlight: 3), event: .move(dx: 0, dy: -1), ids: ids)
        XCTAssertEqual(up.phase, .browsing(highlight: 0))
    }

    func testBeginSaveThenSaveAndEmptyNameBeeps() {
        let naming = reduce(
            phase: .browsing(highlight: 1),
            event: .beginSave,
            ids: [first, second],
            captureCount: 2,
            suggestedName: "Xcode+Safari"
        )
        XCTAssertEqual(naming.phase, .naming(text: "Xcode+Safari", highlight: 1))

        let saved = reduce(
            phase: .naming(text: "Desk", highlight: 1),
            event: .save,
            ids: [first, second],
            captureCount: 2
        )
        XCTAssertEqual(saved.phase, .hidden)
        XCTAssertEqual(saved.effects, [.hide, .capture(name: "Desk")])

        let empty = reduce(
            phase: .naming(text: "   ", highlight: 1),
            event: .save,
            ids: [first],
            captureCount: 2
        )
        XCTAssertEqual(empty.phase, .naming(text: "   ", highlight: 1))
        XCTAssertEqual(empty.effects, [.beep])
    }

    func testSaveWithZeroCaptureCountBeeps() {
        let out = reduce(
            phase: .naming(text: "Desk", highlight: 0),
            event: .save,
            ids: [first],
            captureCount: 0
        )
        XCTAssertEqual(out.phase, .naming(text: "Desk", highlight: 0))
        XCTAssertEqual(out.effects, [.beep])
    }

    func testUpdateHidesAndTargetsHighlight() {
        let out = reduce(
            phase: .browsing(highlight: 1),
            event: .update,
            ids: [first, second]
        )
        XCTAssertEqual(out.phase, .hidden)
        XCTAssertEqual(out.effects, [.hide, .updateProfile(second)])
    }

    func testDismissReturnsFromNamingThenHides() {
        let back = reduce(
            phase: .naming(text: "Desk", highlight: 1),
            event: .dismiss,
            ids: [first, second]
        )
        XCTAssertEqual(back.phase, .browsing(highlight: 1))
        XCTAssertEqual(back.effects, [])

        let hide = reduce(phase: .browsing(highlight: 1), event: .dismiss, ids: [first, second])
        XCTAssertEqual(hide.phase, .hidden)
        XCTAssertEqual(hide.effects, [.hide])
    }

    func testUntrustedOrBusyInvokeDoesNotShow() {
        let untrusted = reduce(phase: .hidden, event: .invoke, ids: [first], trusted: false)
        XCTAssertEqual(untrusted.phase, .hidden)
        XCTAssertEqual(untrusted.effects, [])

        let busy = reduce(phase: .hidden, event: .invoke, ids: [first], isIdle: false)
        XCTAssertEqual(busy.phase, .hidden)
        XCTAssertEqual(busy.effects, [.beep])
    }

    private func reduce(
        phase: WorkspaceSwitcherPhase,
        event: WorkspaceSwitcherEvent,
        ids: [UUID],
        active: UUID? = nil,
        isIdle: Bool = true,
        trusted: Bool = true,
        captureCount: Int = 1,
        suggestedName: String = "Workspace"
    ) -> WorkspaceSwitcherOutput {
        WorkspaceSwitcherReducer.reduce(
            WorkspaceSwitcherInput(
                phase: phase,
                event: event,
                profileIDs: ids,
                activeProfileID: active,
                isIdle: isIdle,
                trusted: trusted,
                captureCount: captureCount,
                suggestedName: suggestedName
            )
        )
    }
}

final class WorkspaceProfileArrangementTests: XCTestCase {
    func testSameArrangementIgnoresRuleOrder() {
        let display = UUID()
        let layout = UUID()
        let zone = UUID()
        let a = AppPlacementRule(bundleID: "a", zoneID: zone, zoneNumber: 1)
        let b = AppPlacementRule(bundleID: "b", zoneID: zone, zoneNumber: 2)
        let left = WorkspaceProfile(
            name: "Left",
            sections: [ProfileSection(space: SpaceKey(displayID: display), layoutID: layout, rules: [a, b])]
        )
        let right = WorkspaceProfile(
            name: "Right",
            sections: [ProfileSection(space: SpaceKey(displayID: display), layoutID: layout, rules: [b, a])]
        )
        XCTAssertTrue(left.hasSameArrangement(as: right))
    }

    func testDifferentDisplayOrLayoutIsNotSame() {
        let display = UUID()
        let layout = UUID()
        let otherLayout = UUID()
        let zone = UUID()
        let rule = AppPlacementRule(bundleID: "a", zoneID: zone, zoneNumber: 1)
        let base = WorkspaceProfile(
            name: "Base",
            sections: [ProfileSection(space: SpaceKey(displayID: display), layoutID: layout, rules: [rule])]
        )
        let otherDisplay = WorkspaceProfile(
            name: "Other display",
            sections: [ProfileSection(space: SpaceKey(displayID: UUID()), layoutID: layout, rules: [rule])]
        )
        let otherLayoutProfile = WorkspaceProfile(
            name: "Other layout",
            sections: [ProfileSection(space: SpaceKey(displayID: display), layoutID: otherLayout, rules: [rule])]
        )
        XCTAssertFalse(base.hasSameArrangement(as: otherDisplay))
        XCTAssertFalse(base.hasSameArrangement(as: otherLayoutProfile))
    }

    func testEmptySectionsAreNeverEqual() {
        let empty = WorkspaceProfile(name: "Empty", sections: [])
        XCTAssertFalse(empty.hasSameArrangement(as: empty))
        XCTAssertFalse(WorkspaceProfile.sameArrangement([], []))
    }
}
