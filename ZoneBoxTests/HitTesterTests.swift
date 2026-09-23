import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class HitTesterTests: XCTestCase {
    private let outer = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 1000, height: 1000))
    private let inner = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 100, y: 100, width: 200, height: 200))
    private let side = ResolvedZone(zoneID: UUID(), number: 3, frameAX: CGRect(x: 600, y: 0, width: 400, height: 1000))

    func testNoZonesReturnsNoneForEveryPolicy() {
        for policy in OverlapPolicy.allCases {
            XCTAssertEqual(
                HitTester(policy: policy).target(at: CGPoint(x: 150, y: 150), zones: []),
                .none,
                "\(policy)"
            )
        }
    }

    func testPointOutsideEveryZoneReturnsNone() {
        for policy in OverlapPolicy.allCases {
            XCTAssertEqual(
                HitTester(policy: policy).target(at: CGPoint(x: -10, y: -10), zones: [outer, inner, side]),
                .none,
                "\(policy)"
            )
        }
    }

    func testSmallestAreaPrefersNestedZone() {
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(at: CGPoint(x: 150, y: 150), zones: [outer, inner]),
            .zone(inner)
        )
    }

    func testLargestAreaPrefersEnclosingZone() {
        XCTAssertEqual(
            HitTester(policy: .largestArea).target(at: CGPoint(x: 150, y: 150), zones: [outer, inner]),
            .zone(outer)
        )
    }

    func testClosestCenterPicksNearestMidpoint() {
        // outer center (500, 500) is 200pt away; side center (800, 500) is 100pt away.
        XCTAssertEqual(
            HitTester(policy: .closestCenterToCursor).target(at: CGPoint(x: 700, y: 500), zones: [outer, side]),
            .zone(side)
        )
    }

    func testOccupiedWindowSticksOnSeamInsteadOfNeighbor() {
        let left = ResolvedZone(zoneID: UUID(), number: 3, frameAX: CGRect(x: 0, y: 400, width: 500, height: 500))
        let top = ResolvedZone(zoneID: UUID(), number: 4, frameAX: CGRect(x: 0, y: 0, width: 500, height: 400))
        let window = CGRect(x: 8, y: 408, width: 484, height: 484)
        let seam = CGPoint(x: 250, y: 390)
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(at: seam, zones: [left, top], windowFrameAX: window),
            .zone(left)
        )
    }

    func testInteriorPointerLeavesOccupiedZone() {
        let left = ResolvedZone(zoneID: UUID(), number: 3, frameAX: CGRect(x: 0, y: 400, width: 500, height: 500))
        let right = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 400, width: 500, height: 500))
        let window = CGRect(x: 8, y: 408, width: 484, height: 484)
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(
                at: CGPoint(x: 750, y: 650),
                zones: [left, right],
                windowFrameAX: window
            ),
            .zone(right)
        )
    }

    func testInteriorPointerOnWindowPrefersCursorZone() {
        let left = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 800))
        let right = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 800))
        let window = CGRect(x: 350, y: 80, width: 600, height: 500)
        let titleBarInLeft = CGPoint(x: 400, y: 100)
        XCTAssertTrue(left.frameAX.contains(titleBarInLeft))
        XCTAssertTrue(window.contains(titleBarInLeft))
        XCTAssertTrue(ZoneOccupancy.containsInterior(titleBarInLeft, zone: left.frameAX))
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(
                at: titleBarInLeft,
                zones: [left, right],
                windowFrameAX: window
            ),
            .zone(left)
        )
    }

    func testInteriorPointerAboveWindowPrefersCursorZone() {
        let left = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 800))
        let right = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 800))
        let window = CGRect(x: 350, y: 80, width: 600, height: 500)
        let aboveTitleBarInLeft = CGPoint(x: 400, y: 40)
        XCTAssertTrue(left.frameAX.contains(aboveTitleBarInLeft))
        XCTAssertFalse(window.contains(aboveTitleBarInLeft))
        XCTAssertTrue(ZoneOccupancy.containsInterior(aboveTitleBarInLeft, zone: left.frameAX))
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(
                at: aboveTitleBarInLeft,
                zones: [left, right],
                windowFrameAX: window
            ),
            .zone(left)
        )
    }

    func testWindowContainmentBeatsFillingANeighborZone() {
        let narrowLeft = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 200, height: 800))
        let wideRight = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 200, y: 0, width: 800, height: 800))
        let window = CGRect(x: 20, y: 50, width: 680, height: 700)
        XCTAssertTrue(ZoneOccupancy.fills(window, zone: narrowLeft.frameAX))
        XCTAssertTrue(ZoneOccupancy.belongs(window, zone: wideRight.frameAX))
        XCTAssertGreaterThan(
            ZoneOccupancy.windowCoverage(window, zone: wideRight.frameAX),
            ZoneOccupancy.windowCoverage(window, zone: narrowLeft.frameAX)
        )
        XCTAssertTrue(ZoneOccupancy.containsInterior(CGPoint(x: 80, y: 80), zone: narrowLeft.frameAX))
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(
                at: CGPoint(x: 80, y: 80),
                zones: [narrowLeft, wideRight],
                windowFrameAX: window
            ),
            .zone(narrowLeft)
        )
        let seamInNarrow = CGPoint(x: 190, y: 80)
        XCTAssertTrue(narrowLeft.frameAX.contains(seamInNarrow))
        XCTAssertFalse(ZoneOccupancy.containsInterior(seamInNarrow, zone: narrowLeft.frameAX))
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(
                at: seamInNarrow,
                zones: [narrowLeft, wideRight],
                windowFrameAX: window
            ),
            .zone(wideRight)
        )
    }

    func testPointerFarFromWindowCanRetargetAwayFromMajorityZone() {
        let left = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 800))
        let right = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 800))
        let window = CGRect(x: 350, y: 80, width: 600, height: 500)
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(
                at: CGPoint(x: 120, y: 700),
                zones: [left, right],
                windowFrameAX: window
            ),
            .zone(left)
        )
    }


    func testInteriorPointerInTopPaneBeatsOccupiedBottomFill() {
        let pane2 = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 400))
        let pane4 = ResolvedZone(zoneID: UUID(), number: 4, frameAX: CGRect(x: 500, y: 400, width: 500, height: 400))
        let window = CGRect(x: 520, y: 120, width: 460, height: 580)
        let titleBarInPane2 = CGPoint(x: 750, y: 140)
        XCTAssertGreaterThan(
            ZoneOccupancy.windowCoverage(window, zone: pane4.frameAX),
            ZoneOccupancy.windowCoverage(window, zone: pane2.frameAX)
        )
        XCTAssertTrue(ZoneOccupancy.belongs(window, zone: pane4.frameAX))
        XCTAssertTrue(ZoneOccupancy.containsInterior(titleBarInPane2, zone: pane2.frameAX))
        XCTAssertTrue(window.contains(titleBarInPane2))
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(
                at: titleBarInPane2,
                zones: [pane2, pane4],
                windowFrameAX: window
            ),
            .zone(pane2)
        )
    }

    func testSeamPointerKeepsOccupiedBottomPane() {
        let pane2 = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 400))
        let pane4 = ResolvedZone(zoneID: UUID(), number: 4, frameAX: CGRect(x: 500, y: 400, width: 500, height: 400))
        let window = CGRect(x: 520, y: 120, width: 460, height: 580)
        let seamInPane2 = CGPoint(x: 750, y: 390)
        XCTAssertTrue(pane2.frameAX.contains(seamInPane2))
        XCTAssertFalse(ZoneOccupancy.containsInterior(seamInPane2, zone: pane2.frameAX))
        XCTAssertTrue(ZoneOccupancy.belongs(window, zone: pane4.frameAX))
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(
                at: seamInPane2,
                zones: [pane2, pane4],
                windowFrameAX: window
            ),
            .zone(pane4)
        )
    }

    func testMultiZoneSpanIgnoresWindowOccupancy() {
        let pane2 = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 400))
        let pane4 = ResolvedZone(zoneID: UUID(), number: 4, frameAX: CGRect(x: 500, y: 400, width: 500, height: 400))
        let window = CGRect(x: 520, y: 120, width: 460, height: 580)
        let span = SnapTarget.span(
            frameAX: CGRect(x: 500, y: 0, width: 500, height: 800),
            zoneIDs: [pane2.zoneID, pane4.zoneID]
        )
        XCTAssertEqual(
            HitTester(policy: .smallestArea).preferringOccupancy(
                span,
                at: CGPoint(x: 750, y: 140),
                windowFrameAX: window,
                zones: [pane2, pane4]
            ),
            span
        )
    }

    func testNestedWindowContainmentHonorsSmallestAreaPolicy() {
        let outer = ResolvedZone(
            zoneID: UUID(),
            number: 1,
            frameAX: CGRect(x: 0, y: 0, width: 1000, height: 1000)
        )
        let inner = ResolvedZone(
            zoneID: UUID(),
            number: 2,
            frameAX: CGRect(x: 200, y: 200, width: 200, height: 200)
        )
        XCTAssertEqual(
            HitTester(policy: .smallestArea).target(
                at: CGPoint(x: 300, y: 300),
                zones: [outer, inner],
                windowFrameAX: inner.frameAX
            ),
            .zone(inner)
        )
        XCTAssertEqual(
            HitTester(policy: .largestArea).target(
                at: CGPoint(x: 300, y: 300),
                zones: [outer, inner],
                windowFrameAX: inner.frameAX
            ),
            .zone(outer)
        )
    }
}
