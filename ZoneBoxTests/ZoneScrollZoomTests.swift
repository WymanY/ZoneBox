import XCTest
@testable import ZoneBoxCore

final class ZoneScrollZoomTests: XCTestCase {
    func testVerticalScrollSelectsHeightEvenWithLeakedDeltaX() {
        XCTAssertEqual(ZoneScrollZoom.axes(deltaX: 1.2, deltaY: 8), .height)
    }

    func testHorizontalScrollSelectsWidth() {
        XCTAssertEqual(ZoneScrollZoom.axes(deltaX: 8, deltaY: 1.2), .width)
    }

    func testAmbiguousDiagonalScrollDoesNotPickAnAxis() {
        XCTAssertNil(ZoneScrollZoom.axes(deltaX: 6, deltaY: 5))
        XCTAssertNil(ZoneScrollZoom.axes(deltaX: 0, deltaY: 0))
    }

    func testHeightOnlyScaleDoesNotTouchXOrWidth() {
        let rect = NormalizedRect(x: 0.2, y: 0.25, width: 0.4, height: 0.3)
        let zoomed = rect.scaled(
            widthFactor: nil,
            heightFactor: 1.25,
            anchorX: 0.9,
            anchorY: 0.4
        )
        XCTAssertEqual(zoomed.x, rect.x)
        XCTAssertEqual(zoomed.width, rect.width)
        XCTAssertGreaterThan(zoomed.height, rect.height)
    }

    func testWidthOnlyScaleDoesNotTouchYOrHeight() {
        let rect = NormalizedRect(x: 0.2, y: 0.25, width: 0.4, height: 0.3)
        let zoomed = rect.scaled(
            widthFactor: 0.8,
            heightFactor: nil,
            anchorX: 0.4,
            anchorY: 0.9
        )
        XCTAssertEqual(zoomed.y, rect.y)
        XCTAssertEqual(zoomed.height, rect.height)
        XCTAssertLessThan(zoomed.width, rect.width)
    }
}
