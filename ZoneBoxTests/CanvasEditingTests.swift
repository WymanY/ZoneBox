import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class CanvasEditingTests: XCTestCase {
    private let canvasSize = CGSize(width: 1000, height: 800)
    private let work = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testDefaultRectMatchesLegacyClickCreateSize() {
        let rect = CanvasEditing.defaultRect(centeredAt: (0.5, 0.5), canvasSize: canvasSize)
        let width = min(280, max(140, canvasSize.width * 0.28)) / canvasSize.width
        let height = min(200, max(110, canvasSize.height * 0.24)) / canvasSize.height
        XCTAssertEqual(rect.width, Double(width), accuracy: 0.0001)
        XCTAssertEqual(rect.height, Double(height), accuracy: 0.0001)
        XCTAssertEqual(rect.midX, 0.5, accuracy: 0.0001)
    }

    func testDuplicatingOffsetsAndAssignsNextNumber() throws {
        var layout = LayoutTemplates.emptyCanvas()
        let source = Zone(number: 1, canvasRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        layout.zones = [source]
        let result = try XCTUnwrap(CanvasEditing.duplicating(layout, ids: [source.id], offset: (0.02, 0.02)))
        XCTAssertEqual(result.layout.zones.count, 2)
        XCTAssertEqual(result.newIDs.count, 1)
        let copy = try XCTUnwrap(result.layout.zones.first(where: { $0.id == result.newIDs[0] }))
        XCTAssertEqual(copy.number, 2)
        XCTAssertEqual(try XCTUnwrap(copy.canvasRect).x, 0.12, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(copy.canvasRect).y, 0.12, accuracy: 0.0001)
    }

    func testDuplicatingFallsBackWhenOffsetWouldLeaveTheCanvas() throws {
        var layout = LayoutTemplates.emptyCanvas()
        let source = Zone(number: 1, canvasRect: NormalizedRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2))
        layout.zones = [source]
        let result = try XCTUnwrap(CanvasEditing.duplicating(layout, ids: [source.id], offset: (0.05, 0.05)))
        let copy = try XCTUnwrap(result.layout.zones.first(where: { $0.id == result.newIDs[0] }))
        XCTAssertEqual(try XCTUnwrap(copy.canvasRect).x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(copy.canvasRect).y, 0.8, accuracy: 0.0001)
    }

    func testSplittingHalvesWithoutGaps() throws {
        var layout = LayoutTemplates.emptyCanvas()
        let source = Zone(number: 1, canvasRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4))
        layout.zones = [source]
        let vertical = try XCTUnwrap(CanvasEditing.splitting(layout, id: source.id, axis: .vertical))
        let left = try XCTUnwrap(vertical.layout.zones.first(where: { $0.id == source.id })?.canvasRect)
        let right = try XCTUnwrap(vertical.layout.zones.first(where: { $0.id == vertical.newID })?.canvasRect)
        XCTAssertEqual(left.maxX, right.x, accuracy: 0.0001)
        XCTAssertEqual(left.width + right.width, 0.4, accuracy: 0.0001)
        XCTAssertNil(CanvasEditing.splitting(LayoutTemplates.columns(2), id: UUID(), axis: .vertical))
    }

    func testDeletingPacksNumbersAndCanEmptyTheLayout() {
        var layout = LayoutTemplates.emptyCanvas()
        let a = Zone(number: 1, canvasRect: NormalizedRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2))
        let b = Zone(number: 2, canvasRect: NormalizedRect(x: 0.3, y: 0.0, width: 0.2, height: 0.2))
        layout.zones = [a, b]
        let remaining = CanvasEditing.deleting(layout, ids: [a.id])
        XCTAssertEqual(remaining.zones.map(\.number), [1])
        XCTAssertTrue(CanvasEditing.deleting(remaining, ids: [remaining.zones[0].id]).zones.isEmpty)
    }
}
