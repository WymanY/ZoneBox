import XCTest
@testable import ZoneBoxCore

final class GridCoverageTests: XCTestCase {
    private let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let gutter: CGFloat = 16

    func testOneCellCoverageMatchesGutteredCell() {
        let cells = twoColumnCells()
        let drag = CGRect(x: 20, y: 20, width: 80, height: 80)
        let frame = GridCoverage.unionFrameAX(
            dragRectAX: drag,
            cells: cells,
            gutter: gutter,
            workAreaAX: work
        )
        let expected = Gutter.apply(cells[0].ungutteredFrameAX, gutter: gutter, workAreaAX: work)
        XCTAssertEqual(frame, expected)
    }

    func testTwoCellSpanUnionsCoveredCells() {
        let cells = twoColumnCells()
        let drag = CGRect(x: 100, y: 40, width: 600, height: 120)
        let frame = GridCoverage.unionFrameAX(
            dragRectAX: drag,
            cells: cells,
            gutter: gutter,
            workAreaAX: work
        )
        let union = cells[0].ungutteredFrameAX.union(cells[1].ungutteredFrameAX)
        XCTAssertEqual(frame, Gutter.apply(union, gutter: gutter, workAreaAX: work))
    }

    func testZeroAreaOutsideCellsDoesNotSnap() {
        let cells = twoColumnCells()
        let frame = GridCoverage.unionFrameAX(
            dragRectAX: CGRect(x: 2000, y: 2000, width: 0, height: 0),
            cells: cells,
            gutter: gutter,
            workAreaAX: work
        )
        XCTAssertNil(frame)
        XCTAssertTrue(
            GridCoverage.coveredCells(
                dragRectAX: CGRect(x: 2000, y: 2000, width: 0, height: 0),
                cells: cells
            ).isEmpty
        )
    }

    func testPointInsideCellCoversThatCell() {
        let cells = twoColumnCells()
        let covered = GridCoverage.coveredCells(
            dragRectAX: CGRect(x: 100, y: 100, width: 0, height: 0),
            cells: cells
        )
        XCTAssertEqual(covered.count, 1)
        XCTAssertEqual(covered.first?.column, 0)
    }

    func testPointInsideMergedZoneExpandsToEveryMappedCell() {
        let spec = GridSpec(
            rows: 2,
            columns: 2,
            rowWeights: [5_000, 5_000],
            columnWeights: [5_000, 5_000],
            cellMap: [[0, 1], [0, 2]]
        )
        let cells = GridCoverage.cells(spec: spec, workAreaAX: work)
        let covered = GridCoverage.coveredCells(
            dragRectAX: CGRect(x: 100, y: 100, width: 0, height: 0),
            cells: cells
        )

        XCTAssertEqual(covered.map(\.row), [0, 1])
        XCTAssertEqual(Set(covered.map(\.column)), [0])

        let union = GridCoverage.unionFrameAX(
            dragRectAX: CGRect(x: 100, y: 100, width: 0, height: 0),
            cells: cells,
            gutter: gutter,
            workAreaAX: work
        )
        let expected = Gutter.apply(
            CGRect(x: 0, y: 0, width: 500, height: 800),
            gutter: gutter,
            workAreaAX: work
        )
        XCTAssertEqual(union, expected)
    }

    private func twoColumnCells() -> [GridCell] {
        let spec = GridSpec(
            rows: 1,
            columns: 2,
            rowWeights: [10_000],
            columnWeights: [5_000, 5_000],
            cellMap: [[0, 1]]
        )
        return GridCoverage.cells(spec: spec, workAreaAX: work)
    }
}
