import XCTest
@testable import ZoneBoxCore

final class ZoneScrollZoomTests: XCTestCase {
    func testDefaultAxisIsHeightEvenIfCallerHasDeltaX() {
        XCTAssertEqual(ZoneScrollZoom.axes(option: false, shift: false), .height)
    }

    func testShiftSelectsWidthOnly() {
        XCTAssertEqual(ZoneScrollZoom.axes(option: false, shift: true), .width)
    }

    func testOptionSelectsBothAndWinsOverShift() {
        XCTAssertEqual(ZoneScrollZoom.axes(option: true, shift: false), .both)
        XCTAssertEqual(ZoneScrollZoom.axes(option: true, shift: true), .both)
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
