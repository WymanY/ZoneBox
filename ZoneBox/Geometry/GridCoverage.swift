import CoreGraphics

public struct GridCell: Equatable, Sendable {
    public var row: Int
    public var column: Int
    public var zoneIndex: Int
    public var ungutteredFrameAX: CGRect

    public init(row: Int, column: Int, zoneIndex: Int, ungutteredFrameAX: CGRect) {
        self.row = row
        self.column = column
        self.zoneIndex = zoneIndex
        self.ungutteredFrameAX = ungutteredFrameAX
    }
}

/// Maps a drag rectangle onto grid cells and returns the guttered union frame.
public enum GridCoverage {
    public static func cells(spec: GridSpec, workAreaAX: CGRect) -> [GridCell] {
        guard spec.rows > 0, spec.columns > 0,
              spec.rowWeights.count == spec.rows,
              spec.columnWeights.count == spec.columns,
              spec.cellMap.count == spec.rows,
              spec.cellMap.allSatisfy({ $0.count == spec.columns })
        else { return [] }

        var colPrefix = [CGFloat](repeating: 0, count: spec.columns + 1)
        var rowPrefix = [CGFloat](repeating: 0, count: spec.rows + 1)
        for c in 0..<spec.columns {
            colPrefix[c + 1] = colPrefix[c] + workAreaAX.width * CGFloat(spec.columnWeights[c]) / 10_000
        }
        for r in 0..<spec.rows {
            rowPrefix[r + 1] = rowPrefix[r] + workAreaAX.height * CGFloat(spec.rowWeights[r]) / 10_000
        }

        var result: [GridCell] = []
        result.reserveCapacity(spec.rows * spec.columns)
        for r in 0..<spec.rows {
            for c in 0..<spec.columns {
                let frame = CGRect(
                    x: workAreaAX.minX + colPrefix[c],
                    y: workAreaAX.minY + rowPrefix[r],
                    width: colPrefix[c + 1] - colPrefix[c],
                    height: rowPrefix[r + 1] - rowPrefix[r]
                )
                result.append(
                    GridCell(
                        row: r,
                        column: c,
                        zoneIndex: spec.cellMap[r][c],
                        ungutteredFrameAX: frame
                    )
                )
            }
        }
        return result
    }

    /// A zero-size rect is treated as a point: the cell containing that origin, if any.
    /// A line (zero width or height, but not both) is inflated to 1pt so it can hit cells.
    public static func coveredCells(dragRectAX: CGRect, cells: [GridCell]) -> [GridCell] {
        if dragRectAX.isNull { return [] }
        var rect = dragRectAX.standardized
        let directlyCovered: [GridCell]
        if rect.width <= 0 && rect.height <= 0 {
            let point = rect.origin
            directlyCovered = cells.filter { $0.ungutteredFrameAX.contains(point) }
        } else {
            if rect.width <= 0 {
                rect.origin.x -= 0.5
                rect.size.width = 1
            }
            if rect.height <= 0 {
                rect.origin.y -= 0.5
                rect.size.height = 1
            }
            directlyCovered = cells.filter { $0.ungutteredFrameAX.intersects(rect) }
        }

        // `cellMap` can merge several physical grid cells into one layout
        // zone. A zone is atomic for snapping: touching any mapped cell must
        // highlight and apply the complete zone, never a fractional rectangle.
        let coveredZoneIndices = Set(directlyCovered.map(\.zoneIndex))
        return cells.filter { coveredZoneIndices.contains($0.zoneIndex) }
    }

    /// Axis-aligned union of covered cells with gutter applied. `nil` if nothing is covered.
    public static func unionFrameAX(
        dragRectAX: CGRect,
        cells: [GridCell],
        gutter: CGFloat,
        workAreaAX: CGRect
    ) -> CGRect? {
        unionFrameAX(
            cells: coveredCells(dragRectAX: dragRectAX, cells: cells),
            gutter: gutter,
            workAreaAX: workAreaAX
        )
    }

    public static func unionFrameAX(
        cells: [GridCell],
        gutter: CGFloat,
        workAreaAX: CGRect
    ) -> CGRect? {
        guard let first = cells.first else { return nil }
        var union = first.ungutteredFrameAX
        for cell in cells.dropFirst() {
            union = union.union(cell.ungutteredFrameAX)
        }
        return Gutter.apply(union, gutter: gutter, workAreaAX: workAreaAX)
    }
}
