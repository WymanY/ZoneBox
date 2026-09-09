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
}
