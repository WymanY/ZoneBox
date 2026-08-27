import XCTest
@testable import ZoneBoxCore

final class ZoneSplitTests: XCTestCase {
    func testVerticalSeamKeepsOuterEdges() {
        let left = NormalizedRect(x: 0, y: 0.1, width: 0.5, height: 0.8)
        let right = NormalizedRect(x: 0.5, y: 0.1, width: 0.5, height: 0.8)
        let pair = ZoneSplit.movingVerticalSeam(left: left, right: right, to: 0.3)
        XCTAssertEqual(pair.left.x, 0, accuracy: 1e-12)
        XCTAssertEqual(pair.left.width, 0.3, accuracy: 1e-12)
        XCTAssertEqual(pair.right.x, 0.3, accuracy: 1e-12)
        XCTAssertEqual(pair.right.x + pair.right.width, 1, accuracy: 1e-12)
        XCTAssertEqual(pair.left.y, left.y)
        XCTAssertEqual(pair.left.height, left.height)
        XCTAssertEqual(pair.right.height, right.height)
    }

    func testVerticalSeamRespectsMinWidth() {
        let left = NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let right = NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let pair = ZoneSplit.movingVerticalSeam(left: left, right: right, to: 0.001)
        XCTAssertEqual(pair.left.width, ZoneSplit.minSize, accuracy: 1e-12)
        XCTAssertEqual(pair.right.x, ZoneSplit.minSize, accuracy: 1e-12)
    }

    func testHorizontalSeamKeepsOuterEdges() {
        let top = NormalizedRect(x: 0, y: 0, width: 1, height: 0.4)
        let bottom = NormalizedRect(x: 0, y: 0.4, width: 1, height: 0.6)
        let pair = ZoneSplit.movingHorizontalSeam(top: top, bottom: bottom, to: 0.7)
        XCTAssertEqual(pair.top.y, 0, accuracy: 1e-12)
        XCTAssertEqual(pair.top.height, 0.7, accuracy: 1e-12)
        XCTAssertEqual(pair.bottom.y, 0.7, accuracy: 1e-12)
        XCTAssertEqual(pair.bottom.y + pair.bottom.height, 1, accuracy: 1e-12)
        XCTAssertEqual(pair.top.width, 1, accuracy: 1e-12)
        XCTAssertEqual(pair.bottom.width, 1, accuracy: 1e-12)
    }

    func testHorizontalSeamRespectsMinHeight() {
        let top = NormalizedRect(x: 0, y: 0, width: 1, height: 0.5)
        let bottom = NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5)
        let pair = ZoneSplit.movingHorizontalSeam(top: top, bottom: bottom, to: 0.99)
        XCTAssertEqual(pair.bottom.height, ZoneSplit.minSize, accuracy: 1e-12)
        XCTAssertEqual(pair.top.height, 1 - ZoneSplit.minSize, accuracy: 1e-12)
    }
}
