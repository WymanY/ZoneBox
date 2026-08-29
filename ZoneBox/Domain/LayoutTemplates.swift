import Foundation

public enum LayoutTemplates {
    public static func editorPresets() -> [Layout] {
        [columns(2), columns(3), rows(2), grid2x2(), priority3(), focus()]
    }

    public static func all() -> [Layout] {
        [columns(2), columns(3), rows(2), rows(3), grid2x2(), priority3(), focus()]
    }

    public static func matchingEditorPresetIndex(for layout: Layout, workAreaAX: CGRect) -> Int? {
        guard let candidate = canvasGeometry(for: layout, workAreaAX: workAreaAX) else { return nil }
        return editorPresets().firstIndex { preset in
            guard let reference = canvasGeometry(for: preset, workAreaAX: workAreaAX) else { return false }
            return candidate.elementsEqual(reference) { lhs, rhs in
                lhs.number == rhs.number && approximatelyEqual(lhs.rect, rhs.rect)
            }
        }
    }

    /// Extra editor-toolbar chip: the layout currently in use, when it is saved
    /// but does not match one of the built-in preset geometries.
    public static func editorToolbarSavedLayout(
        original: Layout?,
        isNew: Bool,
        workAreaAX: CGRect
    ) -> Layout? {
        guard !isNew, let original else { return nil }
        let hasZones = original.zones.contains { $0.name != "__creating" }
        guard hasZones else { return nil }
        if matchingEditorPresetIndex(for: original, workAreaAX: workAreaAX) != nil {
            return nil
        }
        return original
    }

    /// Compact zone rectangles for toolbar/menu thumbnails.
    /// y = 0 is the top of the work area, matching the layout editor canvas.
    public static func thumbnailGeometry(for layout: Layout) -> [(number: Int, rect: NormalizedRect)] {
        canvasGeometry(for: layout, workAreaAX: CGRect(x: 0, y: 0, width: 1000, height: 1000)) ?? []
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

    public static func fill() -> Layout {
        Layout(
            name: WindowOrganize.fillName,
            kind: .canvas,
            zones: [
                Zone(number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1)),
            ]
        )
    }

    public static func split65() -> Layout {
        let zones = (1...2).map { Zone(number: $0) }
        return Layout(
            name: WindowOrganize.split65Name,
            kind: .grid,
            zones: zones,
            grid: GridSpec(
                rows: 1,
                columns: 2,
                rowWeights: [10_000],
                columnWeights: [6_500, 3_500],
                cellMap: [[0, 1]]
            )
        )
    }

    public static func priority60() -> Layout {
        let zones = (1...3).map { Zone(number: $0) }
        return Layout(
            name: WindowOrganize.priority60Name,
            kind: .grid,
            zones: zones,
            grid: GridSpec(
                rows: 2,
                columns: 2,
                rowWeights: [5_000, 5_000],
                columnWeights: [6_000, 4_000],
                cellMap: [[0, 1], [0, 2]]
            )
        )
    }

    public static func focusStack() -> Layout {
        let zones = (1...2).map { Zone(number: $0) }
        return Layout(
            name: WindowOrganize.focusStackName,
            kind: .grid,
            zones: zones,
            grid: GridSpec(
                rows: 1,
                columns: 2,
                rowWeights: [10_000],
                columnWeights: [6_000, 4_000],
                cellMap: [[0, 1]]
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

    private static func canvasGeometry(
        for layout: Layout,
        workAreaAX: CGRect
    ) -> [(number: Int, rect: NormalizedRect)]? {
        let canvas: Layout
        if layout.kind == .grid {
            guard let converted = try? layout.convertingGridToCanvas(workAreaAX: workAreaAX) else { return nil }
            canvas = converted
        } else {
            canvas = layout
        }
        let zones = canvas.zones
            .filter { $0.name != "__creating" }
            .sorted { $0.number < $1.number }
        var geometry: [(number: Int, rect: NormalizedRect)] = []
        geometry.reserveCapacity(zones.count)
        for zone in zones {
            guard let rect = zone.canvasRect else { return nil }
            geometry.append((zone.number, rect))
        }
        return geometry
    }

    private static func approximatelyEqual(
        _ lhs: NormalizedRect,
        _ rhs: NormalizedRect,
        tolerance: Double = 0.000_001
    ) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance
            && abs(lhs.y - rhs.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}
