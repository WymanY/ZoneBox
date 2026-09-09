import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class ZoneOccupancyTests: XCTestCase {
    private let zone3 = ResolvedZone(
        zoneID: UUID(),
        number: 3,
        frameAX: CGRect(x: 0, y: 400, width: 500, height: 500)
    )
    private let zone4 = ResolvedZone(
        zoneID: UUID(),
        number: 4,
        frameAX: CGRect(x: 0, y: 0, width: 500, height: 400)
    )
    private let zone2 = ResolvedZone(
        zoneID: UUID(),
        number: 2,
        frameAX: CGRect(x: 500, y: 400, width: 500, height: 500)
    )

    func testWindowFillingZoneIsOccupied() {
        let window = CGRect(x: 8, y: 408, width: 484, height: 484)
        XCTAssertTrue(ZoneOccupancy.occupies(window, zone: zone3.frameAX))
        XCTAssertEqual(ZoneOccupancy.preferredZone(for: window, in: [zone2, zone3, zone4])?.number, 3)
    }

    func testPartialOverlapIsNotStickyOccupancy() {
        let window = CGRect(x: 0, y: 200, width: 500, height: 250)
        XCTAssertFalse(ZoneOccupancy.occupies(window, zone: zone3.frameAX))
        XCTAssertFalse(ZoneOccupancy.occupies(window, zone: zone4.frameAX))
        XCTAssertNil(ZoneOccupancy.preferredZone(for: window, in: [zone3, zone4]))
    }

    func testSeamPointIsNotInterior() {
        let point = CGPoint(x: 250, y: 400)
        XCTAssertTrue(zone3.frameAX.contains(point) || zone4.frameAX.contains(point))
        XCTAssertFalse(ZoneOccupancy.containsInterior(point, zone: zone4.frameAX))
        XCTAssertFalse(ZoneOccupancy.containsInterior(point, zone: zone3.frameAX))
    }

    func testExactOuterMatchBeatsInnerFill() {
        let outer = ResolvedZone(
            zoneID: UUID(),
            number: 1,
            frameAX: CGRect(x: 0, y: 0, width: 1000, height: 1000)
        )
        let inner = ResolvedZone(
            zoneID: UUID(),
            number: 2,
            frameAX: CGRect(x: 100, y: 100, width: 200, height: 200)
        )
        XCTAssertEqual(
            ZoneOccupancy.preferredZone(for: outer.frameAX, in: [outer, inner])?.number,
            1
        )
    }
}
