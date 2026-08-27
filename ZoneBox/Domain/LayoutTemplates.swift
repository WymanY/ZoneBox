import Foundation

public enum LayoutTemplates {
    public static func all() -> [Layout] {
        [columns(2), columns(3), rows(2), rows(3), grid2x2(), priority3(), focus()]
    }

    public static func columns(_ count: Int) -> Layout {
        let weights = evenWeights(count)
        let map = [Array(0..<count)]
        let zones = (1...count).map { Zone(number: $0) }
        return Layout(
            name: "Columns \(count)",
            kind: .grid,
            zones: zones,
            grid: GridSpec(rows: 1, columns: count, rowWeights: [10_000], columnWeights: weights, cellMap: map)
        )
    }

    public static func rows(_ count: Int) -> Layout {
        let weights = evenWeights(count)
        let map = (0..<count).map { [$0] }
        let zones = (1...count).map { Zone(number: $0) }
        return Layout(
            name: "Rows \(count)",
            kind: .grid,
            zones: zones,
            grid: GridSpec(rows: count, columns: 1, rowWeights: weights, columnWeights: [10_000], cellMap: map)
        )
    }

    public static func grid2x2() -> Layout {
        let zones = (1...4).map { Zone(number: $0) }
        return Layout(
            name: "Grid 2×2",
            kind: .grid,
            zones: zones,
            grid: GridSpec(
                rows: 2,
                columns: 2,
                rowWeights: [5_000, 5_000],
                columnWeights: [5_000, 5_000],
                cellMap: [[0, 1], [2, 3]]
            )
        )
    }

    public static func priority3() -> Layout {
        let zones = (1...3).map { Zone(number: $0) }
        return Layout(
            name: "Priority 3",
            kind: .grid,
            zones: zones,
            grid: GridSpec(
                rows: 2,
                columns: 2,
                rowWeights: [5_000, 5_000],
                columnWeights: [5_000, 5_000],
                cellMap: [[0, 1], [0, 2]]
            )
        )
    }

    public static func focus() -> Layout {
        Layout(
            name: "Focus",
            kind: .canvas,
            zones: [
                Zone(number: 1, canvasRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)),
            ]
        )
    }

    public static func emptyCanvas(name: String = "Canvas") -> Layout {
        Layout(name: name, kind: .canvas, zones: [])
    }

    public static func defaultForVisible(width: Double, height: Double) -> Layout {
        width >= height ? columns(2) : rows(2)
    }

    private static func evenWeights(_ count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let base = 10_000 / count
        var weights = Array(repeating: base, count: count)
        weights[count / 2] += 10_000 - base * count
        return weights
    }
}
