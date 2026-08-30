import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class GutterTests: XCTestCase {
    private let work = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testOuterEdgesStayFlushToWorkArea() {
        let left = CGRect(x: 0, y: 0, width: 500, height: 800)
        let right = CGRect(x: 500, y: 0, width: 500, height: 800)
        let frames = Gutter.apply([left, right], gutter: 16, workAreaAX: work)
        XCTAssertEqual(frames[0].minX, 0, accuracy: 0.01)
        XCTAssertEqual(frames[0].minY, 0, accuracy: 0.01)
        XCTAssertEqual(frames[0].maxY, 800, accuracy: 0.01)
        XCTAssertEqual(frames[1].maxX, 1000, accuracy: 0.01)
        XCTAssertEqual(frames[1].minY, 0, accuracy: 0.01)
        XCTAssertEqual(frames[1].maxY, 800, accuracy: 0.01)
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 16, accuracy: 0.01)
    }

    func testInteriorZoneKeepsHalfGapOnSharedEdgesOnly() {
        let top = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let bottom = CGRect(x: 0, y: 400, width: 1000, height: 400)
        let frames = Gutter.apply([top, bottom], gutter: 20, workAreaAX: work)
        XCTAssertEqual(frames[0].minX, 0, accuracy: 0.01)
        XCTAssertEqual(frames[0].maxX, 1000, accuracy: 0.01)
        XCTAssertEqual(frames[1].minX, 0, accuracy: 0.01)
        XCTAssertEqual(frames[1].maxX, 1000, accuracy: 0.01)
        XCTAssertEqual(frames[1].minY - frames[0].maxY, 20, accuracy: 0.01)
    }

    func testZeroGutterLeavesRectsUnchanged() {
        let rect = CGRect(x: 100, y: 80, width: 300, height: 240)
        XCTAssertEqual(Gutter.apply(rect, gutter: 0, workAreaAX: work), rect)
    }

    func testFullWorkAreaZoneStaysFlushWithGutter() {
        let frame = Gutter.apply(work, gutter: 16, workAreaAX: work)
        XCTAssertEqual(frame, work)
    }
}
