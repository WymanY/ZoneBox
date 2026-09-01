import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class CanvasSnappingTests: XCTestCase {
    private let sibling = NormalizedRect(x: 0.0, y: 0.1, width: 0.4, height: 0.4)

    func testSnapsLeftEdgeToSiblingRightInsideThreshold() {
        let moving = NormalizedRect(x: 0.405, y: 0.1, width: 0.2, height: 0.3)
        let result = CanvasSnapping.snapping(
            moving,
            intent: .move,
            candidates: .from(rects: [sibling]),
            thresholdX: 0.01,
            thresholdY: 0.01
        )
        XCTAssertEqual(result.rect.x, sibling.maxX, accuracy: 0.0001)
        XCTAssertEqual(result.rect.width, moving.width, accuracy: 0.0001)
        XCTAssertTrue(result.hitX.contains { abs($0 - sibling.maxX) < 0.0001 })
    }

    func testDoesNotSnapOutsideThreshold() {
        let moving = NormalizedRect(x: 0.43, y: 0.1, width: 0.2, height: 0.3)
        let result = CanvasSnapping.snapping(
            moving,
            intent: .move,
            candidates: .from(rects: [sibling]),
            thresholdX: 0.01,
            thresholdY: 0.01
        )
        XCTAssertEqual(result.rect.x, moving.x, accuracy: 0.0001)
        XCTAssertTrue(result.hitX.isEmpty)
    }

    func testSnapsAtExactThreshold() {
        let moving = NormalizedRect(x: 0.41, y: 0.1, width: 0.2, height: 0.3)
        let result = CanvasSnapping.snapping(
            moving,
            intent: .move,
            candidates: .from(rects: [sibling]),
            thresholdX: 0.01,
            thresholdY: 0.01
        )
        XCTAssertEqual(result.rect.x, sibling.maxX, accuracy: 0.0001)
    }

    func testSnapsToWorkAreaCenterAndEdges() {
        let centered = NormalizedRect(x: 0.395, y: 0.004, width: 0.2, height: 0.2)
        let result = CanvasSnapping.snapping(
            centered,
            intent: .move,
            candidates: .from(rects: []),
            thresholdX: 0.01,
            thresholdY: 0.01
        )
        XCTAssertEqual(result.rect.midX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.rect.y, 0, accuracy: 0.0001)
        XCTAssertTrue(result.hitX.contains { abs($0 - 0.5) < 0.0001 })
        XCTAssertTrue(result.hitY.contains { abs($0 - 0) < 0.0001 })
    }

    func testMoveKeepsSizeWhileEdgesOnlyMoveRequestedSides() {
        let moving = NormalizedRect(x: 0.405, y: 0.1, width: 0.2, height: 0.3)
        let moved = CanvasSnapping.snapping(
            moving,
            intent: .move,
            candidates: .from(rects: [sibling]),
            thresholdX: 0.01,
            thresholdY: 0
        )
        XCTAssertEqual(moved.rect.width, moving.width, accuracy: 0.0001)
        XCTAssertEqual(moved.rect.height, moving.height, accuracy: 0.0001)

        let resized = CanvasSnapping.snapping(
            moving,
            intent: .edges(left: true, right: false, top: false, bottom: false),
            candidates: .from(rects: [sibling]),
            thresholdX: 0.01,
            thresholdY: 0.01
        )
        XCTAssertEqual(resized.rect.x, sibling.maxX, accuracy: 0.0001)
        XCTAssertEqual(resized.rect.maxX, moving.maxX, accuracy: 0.0001)
    }

    func testZeroThresholdDisablesSnapping() {
        let moving = NormalizedRect(x: 0.405, y: 0.1, width: 0.2, height: 0.3)
        let result = CanvasSnapping.snapping(
            moving,
            intent: .move,
            candidates: .from(rects: [sibling]),
            thresholdX: 0,
            thresholdY: 0
        )
        XCTAssertEqual(result.rect, moving)
        XCTAssertTrue(result.hitX.isEmpty)
        XCTAssertTrue(result.hitY.isEmpty)
    }

    func testAbandonsEdgeSnapWhenItWouldCollapseBelowMinSize() {
        let tiny = NormalizedRect(x: 0.395, y: 0.1, width: 0.051, height: 0.3)
        let result = CanvasSnapping.snapping(
            tiny,
            intent: .edges(left: false, right: true, top: false, bottom: false),
            candidates: .from(rects: [sibling]),
            thresholdX: 0.02,
            thresholdY: 0,
            minSize: 0.05
        )
        XCTAssertEqual(result.rect, tiny)
        XCTAssertTrue(result.hitX.isEmpty)
    }
}
