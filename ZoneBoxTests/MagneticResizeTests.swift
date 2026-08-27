import XCTest
@testable import ZoneBoxCore

final class MagneticResizeTests: XCTestCase {
    private let zone = CGRect(x: 0, y: 0, width: 500, height: 800)

    func testNearEdgeSnaps() {
        let original = CGRect(x: 100, y: 100, width: 300, height: 300)
        let current = CGRect(x: 100, y: 100, width: 405, height: 300)
        let snapped = MagneticResize.snap(
            original: original,
            current: current,
            zoneFramesAX: [zone],
            threshold: 12
        )
        XCTAssertEqual(snapped.maxX, 500, accuracy: 0.01)
        XCTAssertEqual(snapped.minX, 100, accuracy: 0.01)
        XCTAssertEqual(snapped.height, 300, accuracy: 0.01)
    }

    func testFarEdgeDoesNotSnap() {
        let original = CGRect(x: 100, y: 100, width: 300, height: 300)
        let current = CGRect(x: 100, y: 100, width: 450, height: 300)
        let snapped = MagneticResize.snap(
            original: original,
            current: current,
            zoneFramesAX: [zone],
            threshold: 12
        )
        XCTAssertEqual(snapped, current)
    }

    func testUnchangedEdgesStayPut() {
        let original = CGRect(x: 80, y: 90, width: 200, height: 220)
        let current = CGRect(x: 80, y: 90, width: 200, height: 228)
        let snapped = MagneticResize.snap(
            original: original,
            current: current,
            zoneFramesAX: [zone],
            threshold: 12
        )
        XCTAssertEqual(snapped.minX, 80, accuracy: 0.01)
        XCTAssertEqual(snapped.width, 200, accuracy: 0.01)
        XCTAssertEqual(snapped.minY, 90, accuracy: 0.01)
    }
}
