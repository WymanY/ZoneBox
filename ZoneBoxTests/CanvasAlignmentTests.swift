import XCTest
@testable import ZoneBoxCore

final class CanvasAlignmentTests: XCTestCase {
    func testAligningToEdgesUsesUnionBounds() throws {
        let a = UUID()
        let b = UUID()
        let rects: [UUID: NormalizedRect] = [
            a: NormalizedRect(x: 0.1, y: 0.2, width: 0.2, height: 0.2),
            b: NormalizedRect(x: 0.4, y: 0.5, width: 0.2, height: 0.2),
        ]
        let left = CanvasAlignment.aligning(rects, to: .left)
        XCTAssertEqual(try XCTUnwrap(left[a]).x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(left[b]).x, 0.1, accuracy: 0.0001)
        let bottom = CanvasAlignment.aligning(rects, to: .bottom)
        XCTAssertEqual(try XCTUnwrap(bottom[a]).maxY, 0.7, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(bottom[b]).maxY, 0.7, accuracy: 0.0001)
    }

    func testMatchingSizeUsesPrimaryAndKeepsOrigin() throws {
        let primary = UUID()
        let other = UUID()
        let rects: [UUID: NormalizedRect] = [
            primary: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4),
            other: NormalizedRect(x: 0.5, y: 0.2, width: 0.1, height: 0.1),
        ]
        let matched = CanvasAlignment.matchingSize(rects, primary: primary, match: .both)
        let otherRect = try XCTUnwrap(matched[other])
        XCTAssertEqual(otherRect.width, 0.3, accuracy: 0.0001)
        XCTAssertEqual(otherRect.height, 0.4, accuracy: 0.0001)
        XCTAssertEqual(otherRect.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(otherRect.y, 0.2, accuracy: 0.0001)
    }

    func testDistributingRequiresThreeRects() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let pair: [UUID: NormalizedRect] = [
            a: NormalizedRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1),
            b: NormalizedRect(x: 0.8, y: 0.0, width: 0.1, height: 0.1),
        ]
        XCTAssertEqual(CanvasAlignment.distributing(pair, axis: .horizontal), pair)

        let triple: [UUID: NormalizedRect] = [
            a: NormalizedRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1),
            b: NormalizedRect(x: 0.3, y: 0.0, width: 0.1, height: 0.1),
            c: NormalizedRect(x: 0.8, y: 0.0, width: 0.1, height: 0.1),
        ]
        let distributed = CanvasAlignment.distributing(triple, axis: .horizontal)
        let mids = [a, b, c].compactMap { distributed[$0]?.midX }.sorted()
        XCTAssertEqual(mids[1] - mids[0], mids[2] - mids[1], accuracy: 0.0001)
        XCTAssertTrue(CanvasAlignment.aligning([:], to: .left).isEmpty)
    }
}
