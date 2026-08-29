import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class GridEditingTests: XCTestCase {
    private let small = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let large = CGRect(x: 12, y: 34, width: 1920, height: 1080)

    func testEmptyIsValidatedOneCell() throws {
        let layout = GridEditing.empty()
        XCTAssertEqual(layout.kind, .grid)
        XCTAssertEqual(layout.zones.count, 1)
        let spec = try XCTUnwrap(layout.grid)
        XCTAssertEqual(try spec.validated(zoneCount: 1).cellMap, [[0]])
        XCTAssertEqual(spec.rowWeights, [10_000])
        XCTAssertEqual(spec.columnWeights, [10_000])
    }

    func testVerticalSplitOnOneCell() throws {
        let split = try XCTUnwrap(GridEditing.split(GridEditing.empty(), normalizedX: 0.4, normalizedY: 0.5, axis: .vertical))
        let spec = try XCTUnwrap(split.grid)
        XCTAssertEqual(split.zones.count, 2)
        XCTAssertEqual(spec.rows, 1)
        XCTAssertEqual(spec.columns, 2)
        XCTAssertEqual(spec.cellMap, [[0, 1]])
        XCTAssertEqual(spec.columnWeights.reduce(0, +), 10_000)
        XCTAssertEqual(spec.rowWeights.reduce(0, +), 10_000)
        XCTAssertEqual(spec.columnWeights[0], 4_000)
        XCTAssertEqual(spec.columnWeights[1], 6_000)
        try spec.validated(zoneCount: 2)
        try assertTilesWorkArea(split, workArea: small)
    }

    func testHorizontalSplitOnOneCell() throws {
        let split = try XCTUnwrap(GridEditing.split(GridEditing.empty(), normalizedX: 0.5, normalizedY: 0.25, axis: .horizontal))
        let spec = try XCTUnwrap(split.grid)
        XCTAssertEqual(split.zones.count, 2)
        XCTAssertEqual(spec.cellMap, [[0], [1]])
        XCTAssertEqual(spec.rowWeights, [2_500, 7_500])
        try spec.validated(zoneCount: 2)
        try assertTilesWorkArea(split, workArea: large)
    }

    func testHorizontalSplitInsideMergedZone() throws {
        var layout = try XCTUnwrap(GridEditing.split(GridEditing.empty(), normalizedX: 0.5, normalizedY: 0.5, axis: .vertical))
        layout = try XCTUnwrap(GridEditing.split(layout, normalizedX: 0.25, normalizedY: 0.5, axis: .horizontal))
        XCTAssertTrue(GridEditing.canSplit(spec: try XCTUnwrap(layout.grid), normalizedX: 0.75, normalizedY: 0.35, axis: .horizontal))
        let split = try XCTUnwrap(GridEditing.split(layout, normalizedX: 0.75, normalizedY: 0.35, axis: .horizontal))
        let spec = try XCTUnwrap(split.grid)
        XCTAssertEqual(split.zones.count, 4)
        XCTAssertEqual(spec.columns, 2)
        XCTAssertGreaterThanOrEqual(spec.rows, 2)
        let rightZones = Set(spec.cellMap.map { $0[1] })
        XCTAssertEqual(rightZones.count, 2)
        try spec.validated(zoneCount: 4)
        try assertTilesWorkArea(split, workArea: small)
    }

    func testSplitIgnoresEdgesBelowMinimum() {
        XCTAssertNil(GridEditing.split(GridEditing.empty(), normalizedX: 0.004, normalizedY: 0.5, axis: .vertical))
        XCTAssertNil(GridEditing.split(GridEditing.empty(), normalizedX: 0.996, normalizedY: 0.5, axis: .vertical))
        XCTAssertNil(GridEditing.split(GridEditing.empty(), normalizedX: 0.5, normalizedY: 0.004, axis: .horizontal))
    }

    func testRepeatedHalvesKeepSplittingPastFivePercentCells() throws {
        var layout = GridEditing.empty()
        for expected in 2...7 {
            let spec = try XCTUnwrap(layout.grid)
            let last = Double(spec.columnWeights.dropLast().reduce(0, +)) / 10_000
            let width = Double(spec.columnWeights.last ?? 10_000) / 10_000
            let x = last + width * 0.5
            XCTAssertTrue(GridEditing.canSplit(spec: spec, normalizedX: x, normalizedY: 0.5, axis: .vertical))
            layout = try XCTUnwrap(GridEditing.split(layout, normalizedX: x, normalizedY: 0.5, axis: .vertical))
            XCTAssertEqual(layout.zones.count, expected)
            try XCTUnwrap(layout.grid).validated(zoneCount: expected)
        }
        let spec = try XCTUnwrap(layout.grid)
        XCTAssertEqual(spec.columns, 7)
        XCTAssertGreaterThanOrEqual(spec.columnWeights.min() ?? 0, 1)
        XCTAssertEqual(spec.columnWeights.reduce(0, +), 10_000)
        try assertTilesWorkArea(layout, workArea: small)
    }

    func testManySpreadSplitsFillTheRow() throws {
        var layout = GridEditing.empty()
        for i in 1...12 {
            let x = Double(i) / 13.0
            layout = try XCTUnwrap(GridEditing.split(layout, normalizedX: x, normalizedY: 0.5, axis: .vertical))
        }
        let spec = try XCTUnwrap(layout.grid)
        XCTAssertEqual(layout.zones.count, 13)
        XCTAssertEqual(spec.columns, 13)
        try spec.validated(zoneCount: 13)
        try assertTilesWorkArea(layout, workArea: large)
    }

    func testCanSplitAllowsReuseAfterSixteenLines() throws {
        var layout = GridEditing.empty()
        var x = 1.0 / 32.0
        for _ in 0..<15 {
            layout = try XCTUnwrap(GridEditing.split(layout, normalizedX: x, normalizedY: 0.5, axis: .vertical))
            x += 1.0 / 32.0
        }
        let spec = try XCTUnwrap(layout.grid)
        XCTAssertEqual(spec.columns, 16)
        XCTAssertTrue(GridEditing.canSplit(spec: spec, normalizedX: 0.75, normalizedY: 0.25, axis: .horizontal))
        XCTAssertFalse(GridEditing.canSplit(spec: spec, normalizedX: 0.98, normalizedY: 0.5, axis: .vertical))
    }

    func testMergedZoneKeepsOtherColumnsWhenSplit() throws {
        var layout = try XCTUnwrap(GridEditing.split(GridEditing.empty(), normalizedX: 0.5, normalizedY: 0.5, axis: .vertical))
        layout = try XCTUnwrap(GridEditing.split(layout, normalizedX: 0.25, normalizedY: 0.5, axis: .horizontal))
        let before = try XCTUnwrap(layout.grid)
        XCTAssertEqual(before.cellMap[0][1], before.cellMap[1][1])
        let split = try XCTUnwrap(GridEditing.split(layout, normalizedX: 0.75, normalizedY: 0.5, axis: .vertical))
        let spec = try XCTUnwrap(split.grid)
        XCTAssertEqual(spec.columns, 3)
        XCTAssertEqual(spec.rows, 2)
        XCTAssertEqual(spec.columnWeights.reduce(0, +), 10_000)
        XCTAssertNotEqual(spec.cellMap[0][1], spec.cellMap[0][2])
        try spec.validated(zoneCount: split.zones.count)
        try assertTilesWorkArea(split, workArea: small)
    }

    func testSplitKeepsUnclickedMergedZoneIntact() throws {
        var layout = try XCTUnwrap(GridEditing.split(GridEditing.empty(), normalizedX: 0.5, normalizedY: 0.5, axis: .vertical))
        layout = try XCTUnwrap(GridEditing.split(layout, normalizedX: 0.25, normalizedY: 0.5, axis: .horizontal))
        let spec = try XCTUnwrap(layout.grid)
        XCTAssertEqual(spec.rows, 2)
        XCTAssertEqual(spec.columns, 2)
        XCTAssertEqual(spec.cellMap[0][1], spec.cellMap[1][1], "right column stays one zone across the new row")
        XCTAssertNotEqual(spec.cellMap[0][0], spec.cellMap[1][0])
        XCTAssertEqual(layout.zones.count, 3)
        try spec.validated(zoneCount: 3)
        try assertTilesWorkArea(layout, workArea: small)
    }

    func testMoveVerticalLineKeepsCoverage() throws {
        let start = try XCTUnwrap(GridEditing.split(GridEditing.empty(), normalizedX: 0.5, normalizedY: 0.5, axis: .vertical))
        let moved = try XCTUnwrap(GridEditing.moveLine(start, axis: .vertical, afterIndex: 0, toNormalized: 0.3))
        let spec = try XCTUnwrap(moved.grid)
        XCTAssertEqual(spec.columnWeights.reduce(0, +), 10_000)
        XCTAssertEqual(spec.columnWeights[0], 3_000)
        XCTAssertEqual(spec.columnWeights[1], 7_000)
        try assertTilesWorkArea(moved, workArea: small)
        try assertTilesWorkArea(moved, workArea: large)
    }

    func testMoveHorizontalLineKeepsCoverage() throws {
        let start = try XCTUnwrap(GridEditing.split(GridEditing.empty(), normalizedX: 0.5, normalizedY: 0.5, axis: .horizontal))
        let moved = try XCTUnwrap(GridEditing.moveLine(start, axis: .horizontal, afterIndex: 0, toNormalized: 0.7))
        let spec = try XCTUnwrap(moved.grid)
        XCTAssertEqual(spec.rowWeights, [7_000, 3_000])
        try assertTilesWorkArea(moved, workArea: large)
    }

    func testMergeTwoCellsAndCompact() throws {
        let split = try XCTUnwrap(GridEditing.split(GridEditing.empty(), normalizedX: 0.5, normalizedY: 0.5, axis: .vertical))
        let merged = try XCTUnwrap(GridEditing.merge(split, zoneIDs: Set(split.zones.map(\.id))))
        let spec = try XCTUnwrap(merged.grid)
        XCTAssertEqual(merged.zones.count, 1)
        XCTAssertEqual(spec.rows, 1)
        XCTAssertEqual(spec.columns, 1)
        XCTAssertEqual(spec.cellMap, [[0]])
        try spec.validated(zoneCount: 1)
        try assertTilesWorkArea(merged, workArea: small)
    }

    func testMergeFourCells() throws {
        let layout = LayoutTemplates.grid2x2()
        let merged = try XCTUnwrap(GridEditing.merge(layout, zoneIDs: Set(layout.zones.map(\.id))))
        XCTAssertEqual(merged.zones.count, 1)
        XCTAssertEqual(merged.grid?.cellMap, [[0]])
        try assertTilesWorkArea(merged, workArea: large)
    }

    func testNonRectangularMergeIsRejected() throws {
        let layout = LayoutTemplates.priority3()
        // Left stacked zone plus only the top-right cell is an L, not a rectangle.
        let ids = [layout.zones[0].id, layout.zones[1].id]
        XCTAssertNil(GridEditing.merge(layout, zoneIDs: Set(ids)))
        XCTAssertEqual(layout.grid?.cellMap, [[0, 1], [0, 2]])
    }

    func testDeleteMergesIntoNeighborWithoutHoles() throws {
        let start = LayoutTemplates.columns(3)
        let deleted = try XCTUnwrap(GridEditing.deleteZone(start, id: start.zones[1].id))
        XCTAssertEqual(deleted.zones.count, 2)
        try XCTUnwrap(deleted.grid).validated(zoneCount: 2)
        try assertTilesWorkArea(deleted, workArea: small)
        XCTAssertNil(GridEditing.deleteZone(GridEditing.empty(), id: GridEditing.empty().zones[0].id))
    }

    func testCanvasRoundTripKeepsColumnGeometry() throws {
        let canvas = try LayoutTemplates.columns(3).convertingGridToCanvas(workAreaAX: small)
        let grid = GridEditing.convertingCanvasToGrid(canvas)
        XCTAssertEqual(grid.kind, .grid)
        XCTAssertEqual(grid.zones.count, 3)
        XCTAssertEqual(grid.grid?.rows, 1)
        XCTAssertEqual(grid.grid?.columns, 3)
        try XCTUnwrap(grid.grid).validated(zoneCount: 3)
        try assertTilesWorkArea(grid, workArea: small)
        try assertTilesWorkArea(grid, workArea: large)
    }

    func testCanvasToGridFillsWorkAreaFromFocus() throws {
        let grid = GridEditing.convertingCanvasToGrid(LayoutTemplates.focus())
        XCTAssertEqual(grid.kind, .grid)
        XCTAssertEqual(grid.zones.count, 1)
        XCTAssertEqual(grid.grid?.cellMap, [[0]])
        try assertTilesWorkArea(grid, workArea: small)
    }

    func testResolvedFramesFillDifferentWorkAreas() throws {
        var layout = try XCTUnwrap(GridEditing.split(GridEditing.empty(), normalizedX: 0.3, normalizedY: 0.5, axis: .vertical))
        layout = try XCTUnwrap(GridEditing.split(layout, normalizedX: 0.7, normalizedY: 0.4, axis: .horizontal))
        try assertTilesWorkArea(layout, workArea: small)
        try assertTilesWorkArea(layout, workArea: large)
    }

    private func assertTilesWorkArea(_ layout: Layout, workArea: CGRect) throws {
        let resolved = try resolveLayout(layout, workAreaAX: workArea, gutter: 0)
        XCTAssertEqual(resolved.count, layout.zones.count)
        var union = resolved[0].frameAX
        for zone in resolved {
            XCTAssertGreaterThan(zone.frameAX.width, 0)
            XCTAssertGreaterThan(zone.frameAX.height, 0)
            XCTAssertGreaterThanOrEqual(zone.frameAX.minX, workArea.minX - 0.6)
            XCTAssertLessThanOrEqual(zone.frameAX.maxX, workArea.maxX + 0.6)
            XCTAssertGreaterThanOrEqual(zone.frameAX.minY, workArea.minY - 0.6)
            XCTAssertLessThanOrEqual(zone.frameAX.maxY, workArea.maxY + 0.6)
            union = union.union(zone.frameAX)
            for other in resolved where other.zoneID != zone.zoneID {
                let overlap = zone.frameAX.intersection(other.frameAX)
                XCTAssertTrue(overlap.isNull || overlap.width < 0.6 || overlap.height < 0.6)
            }
        }
        XCTAssertEqual(union.minX, workArea.minX, accuracy: 0.6)
        XCTAssertEqual(union.minY, workArea.minY, accuracy: 0.6)
        XCTAssertEqual(union.maxX, workArea.maxX, accuracy: 0.6)
        XCTAssertEqual(union.maxY, workArea.maxY, accuracy: 0.6)
    }
}
