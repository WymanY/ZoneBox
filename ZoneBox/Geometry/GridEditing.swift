import CoreGraphics
import Foundation

public enum GridAxis: Equatable, Sendable {
    /// Vertical grid line / column split.
    case vertical
    /// Horizontal grid line / row split.
    case horizontal
}

public struct GridLineHit: Equatable, Sendable {
    public var axis: GridAxis
    public var afterIndex: Int

    public init(axis: GridAxis, afterIndex: Int) {
        self.axis = axis
        self.afterIndex = afterIndex
    }
}

/// Mutates a proportional GridSpec while keeping it a gapless, overlap-free tiling.
public enum GridEditing {
    public static let minFraction = ZoneSplit.minSize
    public static let weightTotal = 10_000
    /// Keep a split pane usable, but allow many successive cuts. 5% of the
    /// whole work area was blocking the 5th+ split of a shrinking cell.
    public static var minWeight: Int { 80 }

    public static func empty(name: String = "Grid") -> Layout {
        Layout(
            name: name,
            kind: .grid,
            zones: [Zone(number: 1)],
            grid: GridSpec(
                rows: 1,
                columns: 1,
                rowWeights: [weightTotal],
                columnWeights: [weightTotal],
                cellMap: [[0]]
            )
        )
    }

    public static func split(
        _ layout: Layout,
        normalizedX x: Double,
        normalizedY y: Double,
        axis: GridAxis
    ) -> Layout? {
        guard layout.kind == .grid, var spec = layout.grid else { return nil }
        guard let row = index(containing: y, in: spec.rowWeights),
              let col = index(containing: x, in: spec.columnWeights)
        else { return nil }
        let clicked = spec.cellMap[row][col]
        let box = zoneBox(clicked, in: spec)

        switch axis {
        case .vertical:
            guard spec.columns < 16 || !needsInsertedLine(spec.columnWeights, at: x, spanning: box.c0...box.c1) else { return nil }
            guard let split = splitting(spec.columnWeights, spanning: box.c0...box.c1, at: x) else { return nil }
            let newIndex = layout.zones.count
            if split.insertsLine {
                spec.cellMap = spec.cellMap.map { rowCells in
                    var next = rowCells
                    next.insert(rowCells[split.afterIndex], at: split.afterIndex + 1)
                    return next
                }
                spec.columns += 1
                spec.columnWeights = split.weights
            }
            for r in 0..<spec.cellMap.count {
                for c in (split.afterIndex + 1)..<spec.cellMap[r].count where spec.cellMap[r][c] == clicked {
                    spec.cellMap[r][c] = newIndex
                }
            }
        case .horizontal:
            guard spec.rows < 16 || !needsInsertedLine(spec.rowWeights, at: y, spanning: box.r0...box.r1) else { return nil }
            guard let split = splitting(spec.rowWeights, spanning: box.r0...box.r1, at: y) else { return nil }
            let newIndex = layout.zones.count
            if split.insertsLine {
                spec.cellMap.insert(spec.cellMap[split.afterIndex], at: split.afterIndex + 1)
                spec.rows += 1
                spec.rowWeights = split.weights
            }
            for r in (split.afterIndex + 1)..<spec.cellMap.count {
                for c in 0..<spec.cellMap[r].count where spec.cellMap[r][c] == clicked {
                    spec.cellMap[r][c] = newIndex
                }
            }
        }

        return addingZone(to: layout, spec: spec)
    }

    public static func moveLine(
        _ layout: Layout,
        axis: GridAxis,
        afterIndex: Int,
        toNormalized t: Double
    ) -> Layout? {
        guard layout.kind == .grid, var spec = layout.grid else { return nil }
        switch axis {
        case .vertical:
            guard afterIndex >= 0, afterIndex < spec.columns - 1 else { return nil }
            guard let weights = moving(spec.columnWeights, afterIndex: afterIndex, to: t) else { return nil }
            spec.columnWeights = weights
        case .horizontal:
            guard afterIndex >= 0, afterIndex < spec.rows - 1 else { return nil }
            guard let weights = moving(spec.rowWeights, afterIndex: afterIndex, to: t) else { return nil }
            spec.rowWeights = weights
        }
        return replacing(spec, in: layout)
    }

    public static func merge(_ layout: Layout, zoneIDs: Set<UUID>) -> Layout? {
        guard layout.kind == .grid, var spec = layout.grid else { return nil }
        let indices = Set(zoneIDs.compactMap { id in layout.zones.firstIndex(where: { $0.id == id }) })
        guard indices.count >= 2 else { return nil }

        var r0 = Int.max, r1 = Int.min, c0 = Int.max, c1 = Int.min
        for r in 0..<spec.rows {
            for c in 0..<spec.columns where indices.contains(spec.cellMap[r][c]) {
                r0 = min(r0, r); r1 = max(r1, r)
                c0 = min(c0, c); c1 = max(c1, c)
            }
        }
        guard r0 <= r1, c0 <= c1 else { return nil }

        for r in r0...r1 {
            for c in c0...c1 {
                if !indices.contains(spec.cellMap[r][c]) { return nil }
            }
        }
        for r in 0..<spec.rows {
            for c in 0..<spec.columns where indices.contains(spec.cellMap[r][c]) {
                if r < r0 || r > r1 || c < c0 || c > c1 { return nil }
            }
        }

        let keep = indices.min()!
        for r in r0...r1 {
            for c in c0...c1 {
                spec.cellMap[r][c] = keep
            }
        }
        return replacing(spec, in: layout)
    }

    public static func deleteZone(_ layout: Layout, id: UUID) -> Layout? {
        guard layout.kind == .grid, let spec = layout.grid else { return nil }
        guard let idx = layout.zones.firstIndex(where: { $0.id == id }) else { return nil }
        let unique = Set(spec.cellMap.flatMap { $0 })
        guard unique.count > 1 else { return nil }
        guard let neighbor = bestNeighbor(of: idx, spec: spec) else { return nil }
        return merge(layout, zoneIDs: [id, layout.zones[neighbor].id])
    }

    public static func hitLine(
        normalizedX x: Double,
        normalizedY y: Double,
        spec: GridSpec,
        slop: Double
    ) -> GridLineHit? {
        hitLine(normalizedX: x, normalizedY: y, spec: spec, slopX: slop, slopY: slop)
    }

    public static func hitLine(
        normalizedX x: Double,
        normalizedY y: Double,
        spec: GridSpec,
        slopX: Double,
        slopY: Double
    ) -> GridLineHit? {
        guard let row = index(containing: y, in: spec.rowWeights),
              let col = index(containing: x, in: spec.columnWeights)
        else { return nil }

        var best: (hit: GridLineHit, distance: Double)?
        func consider(_ hit: GridLineHit, distance: Double) {
            let limit = hit.axis == .vertical ? slopX : slopY
            guard distance <= limit else { return }
            if best == nil || distance < best!.distance {
                best = (hit, distance)
            }
        }

        let colPrefix = prefix(spec.columnWeights)
        for c in 0..<(spec.columns - 1) {
            if spec.cellMap[row][c] == spec.cellMap[row][c + 1] { continue }
            consider(GridLineHit(axis: .vertical, afterIndex: c), distance: abs(x - colPrefix[c + 1]))
        }
        let rowPrefix = prefix(spec.rowWeights)
        for r in 0..<(spec.rows - 1) {
            if spec.cellMap[r][col] == spec.cellMap[r + 1][col] { continue }
            consider(GridLineHit(axis: .horizontal, afterIndex: r), distance: abs(y - rowPrefix[r + 1]))
        }
        return best?.hit
    }

    public static func zoneIndex(
        normalizedX x: Double,
        normalizedY y: Double,
        spec: GridSpec
    ) -> Int? {
        guard let row = index(containing: y, in: spec.rowWeights),
              let col = index(containing: x, in: spec.columnWeights)
        else { return nil }
        return spec.cellMap[row][col]
    }

    public static func zoneID(
        normalizedX x: Double,
        normalizedY y: Double,
        layout: Layout
    ) -> UUID? {
        guard let spec = layout.grid,
              let idx = zoneIndex(normalizedX: x, normalizedY: y, spec: spec),
              layout.zones.indices.contains(idx)
        else { return nil }
        return layout.zones[idx].id
    }

    public static func normalizedRects(
        for layout: Layout,
        workAreaAX: CGRect = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
    ) -> [UUID: NormalizedRect] {
        guard let resolved = try? resolveLayout(layout, workAreaAX: workAreaAX, gutter: 0) else { return [:] }
        return Dictionary(uniqueKeysWithValues: resolved.map { zone in
            (zone.zoneID, NormalizedRect.normalize(zone.frameAX, in: workAreaAX))
        })
    }

    public static func convertingCanvasToGrid(_ layout: Layout) -> Layout {
        if layout.kind == .grid, layout.grid != nil {
            return layout
        }

        let zones = layout.zones.filter { $0.name != "__creating" }
        let rects: [(index: Int, id: UUID, number: Int, rect: NormalizedRect)] = zones.compactMap { zone in
            guard let rect = zone.canvasRect else { return nil }
            return (zones.firstIndex(where: { $0.id == zone.id }) ?? 0, zone.id, zone.number, rect)
        }
        if rects.isEmpty {
            return preservingIdentity(empty(name: layout.name), from: layout)
        }

        var xs = [0.0, 1.0]
        var ys = [0.0, 1.0]
        for item in rects {
            xs.append(contentsOf: [item.rect.x, item.rect.x + item.rect.width])
            ys.append(contentsOf: [item.rect.y, item.rect.y + item.rect.height])
        }
        xs = uniqueEdges(xs)
        ys = uniqueEdges(ys)
        xs = cappedEdges(xs)
        ys = cappedEdges(ys)

        let columns = xs.count - 1
        let rows = ys.count - 1
        var cellMap = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let cell = NormalizedRect(
                    x: xs[c],
                    y: ys[r],
                    width: xs[c + 1] - xs[c],
                    height: ys[r + 1] - ys[r]
                )
                cellMap[r][c] = bestZoneIndex(covering: cell, in: rects)
            }
        }

        let spec = GridSpec(
            rows: rows,
            columns: columns,
            rowWeights: weights(from: ys),
            columnWeights: weights(from: xs),
            cellMap: cellMap
        )
        var next = layout
        next.kind = .grid
        next.zones = rects.map { Zone(id: $0.id, number: $0.number, canvasRect: nil) }
        next.grid = spec
        next = compacting(next)
        next = reindexed(next)
        for i in next.zones.indices {
            next.zones[i].number = i + 1
            next.zones[i].canvasRect = nil
        }
        guard let grid = next.grid, (try? grid.validated(zoneCount: next.zones.count)) != nil else {
            return preservingIdentity(empty(name: layout.name), from: layout)
        }
        next.updatedAt = Date()
        return next
    }

    public static func canSplit(
        spec: GridSpec,
        normalizedX x: Double,
        normalizedY y: Double,
        axis: GridAxis
    ) -> Bool {
        guard let row = index(containing: y, in: spec.rowWeights),
              let col = index(containing: x, in: spec.columnWeights)
        else { return false }
        let box = zoneBox(spec.cellMap[row][col], in: spec)
        switch axis {
        case .vertical:
            guard spec.columns < 16 || !needsInsertedLine(spec.columnWeights, at: x, spanning: box.c0...box.c1) else {
                return false
            }
            return splitting(spec.columnWeights, spanning: box.c0...box.c1, at: x) != nil
        case .horizontal:
            guard spec.rows < 16 || !needsInsertedLine(spec.rowWeights, at: y, spanning: box.r0...box.r1) else {
                return false
            }
            return splitting(spec.rowWeights, spanning: box.r0...box.r1, at: y) != nil
        }
    }
}

private extension GridEditing {
    static func preservingIdentity(_ layout: Layout, from original: Layout) -> Layout {
        var next = layout
        next.id = original.id
        next.name = original.name
        next.createdAt = original.createdAt
        return next
    }

    static func uniqueEdges(_ values: [Double], tolerance: Double = 0.01) -> [Double] {
        let clamped = values.map { min(max($0, 0), 1) }.sorted()
        var out: [Double] = []
        for value in clamped {
            if let last = out.last, abs(value - last) <= tolerance { continue }
            out.append(value)
        }
        if out.first != 0 { out.insert(0, at: 0) }
        if let last = out.last, abs(last - 1) > tolerance {
            out.append(1)
        } else if !out.isEmpty {
            out[out.count - 1] = 1
        }
        if let first = out.first, first != 0 {
            out[0] = 0
        }
        return out
    }

    static func cappedEdges(_ edges: [Double]) -> [Double] {
        var edges = edges
        while edges.count - 1 > 16 {
            var best = 1
            var bestGap = Double.greatestFiniteMagnitude
            for i in 1..<(edges.count - 1) {
                let gap = min(edges[i] - edges[i - 1], edges[i + 1] - edges[i])
                if gap < bestGap {
                    bestGap = gap
                    best = i
                }
            }
            edges.remove(at: best)
        }
        return edges
    }

    static func weights(from edges: [Double]) -> [Int] {
        var raw: [Int] = []
        raw.reserveCapacity(max(0, edges.count - 1))
        for i in 0..<(edges.count - 1) {
            raw.append(max(1, Int(((edges[i + 1] - edges[i]) * Double(weightTotal)).rounded())))
        }
        return renormalized(raw)
    }

    static func bestZoneIndex(
        covering cell: NormalizedRect,
        in zones: [(index: Int, id: UUID, number: Int, rect: NormalizedRect)]
    ) -> Int {
        let cx = cell.x + cell.width / 2
        let cy = cell.y + cell.height / 2
        for (offset, zone) in zones.enumerated() {
            if cx >= zone.rect.x,
               cx <= zone.rect.x + zone.rect.width,
               cy >= zone.rect.y,
               cy <= zone.rect.y + zone.rect.height {
                return offset
            }
        }

        var best = 0
        var bestArea = -1.0
        for (offset, zone) in zones.enumerated() {
            let overlap = intersectionArea(cell, zone.rect)
            if overlap > bestArea {
                bestArea = overlap
                best = offset
            }
        }
        if bestArea > 0 { return best }

        var nearest = 0
        var nearestDistance = Double.greatestFiniteMagnitude
        for (offset, zone) in zones.enumerated() {
            let dx = (zone.rect.x + zone.rect.width / 2) - cx
            let dy = (zone.rect.y + zone.rect.height / 2) - cy
            let distance = dx * dx + dy * dy
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = offset
            }
        }
        return nearest
    }

    static func intersectionArea(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Double {
        let x0 = max(lhs.x, rhs.x)
        let y0 = max(lhs.y, rhs.y)
        let x1 = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let y1 = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let w = x1 - x0
        let h = y1 - y0
        guard w > 0, h > 0 else { return 0 }
        return w * h
    }

    static func prefix(_ weights: [Int]) -> [Double] {
        var out = [0.0]
        out.reserveCapacity(weights.count + 1)
        var sum = 0
        for weight in weights {
            sum += weight
            out.append(Double(sum) / Double(weightTotal))
        }
        return out
    }

    static func index(containing t: Double, in weights: [Int]) -> Int? {
        guard !weights.isEmpty else { return nil }
        if t < 0 { return nil }
        let marks = prefix(weights)
        if t >= 1 { return weights.count - 1 }
        for i in 0..<weights.count where t >= marks[i] && t < marks[i + 1] {
            return i
        }
        return weights.count - 1
    }

    static func zoneBox(_ index: Int, in spec: GridSpec) -> (r0: Int, r1: Int, c0: Int, c1: Int) {
        var r0 = Int.max, r1 = Int.min, c0 = Int.max, c1 = Int.min
        for r in 0..<spec.rows {
            for c in 0..<spec.columns where spec.cellMap[r][c] == index {
                r0 = min(r0, r); r1 = max(r1, r)
                c0 = min(c0, c); c1 = max(c1, c)
            }
        }
        if r0 == Int.max {
            return (0, max(spec.rows - 1, 0), 0, max(spec.columns - 1, 0))
        }
        return (r0, r1, c0, c1)
    }

    static func needsInsertedLine(_ weights: [Int], at t: Double, spanning range: ClosedRange<Int>) -> Bool {
        splitting(weights, spanning: range, at: t)?.insertsLine == true
    }

    static func splitting(
        _ weights: [Int],
        spanning range: ClosedRange<Int>,
        at t: Double
    ) -> (weights: [Int], afterIndex: Int, insertsLine: Bool)? {
        let marks = prefix(weights)
        let start = marks[range.lowerBound]
        let end = marks[range.upperBound + 1]
        let span = end - start
        guard span > 0 else { return nil }
        let local = (t - start) / span
        guard local > 0, local < 1 else { return nil }

        let total = range.reduce(0) { $0 + weights[$1] }
        let leftTotal = Int((Double(total) * local).rounded())
        let rightTotal = total - leftTotal
        guard leftTotal >= minWeight, rightTotal >= minWeight else { return nil }

        if let idx = index(containing: t, in: weights), range.contains(idx) {
            let cellStart = marks[idx]
            let cellEnd = marks[idx + 1]
            if abs(t - cellStart) <= 0.000_001 {
                return idx > range.lowerBound ? (weights, idx - 1, false) : nil
            }
            if abs(t - cellEnd) <= 0.000_001 {
                return idx < range.upperBound ? (weights, idx, false) : nil
            }
            let cellSpan = cellEnd - cellStart
            if cellSpan > 0 {
                let cellLocal = (t - cellStart) / cellSpan
                let cellWeight = weights[idx]
                let left = Int((Double(cellWeight) * cellLocal).rounded())
                let right = cellWeight - left
                if left >= minWeight, right >= minWeight {
                    var next = weights
                    next[idx] = left
                    next.insert(right, at: idx + 1)
                    return (renormalized(next), idx, true)
                }
            }
        }

        // A merged zone can span several existing lines. Collapse only as a
        // last resort, and only when that still leaves two usable panes.
        return nil
    }

    static func moving(_ weights: [Int], afterIndex: Int, to t: Double) -> [Int]? {
        guard afterIndex >= 0, afterIndex < weights.count - 1 else { return nil }
        let marks = prefix(weights)
        let start = marks[afterIndex]
        let pairSum = weights[afterIndex] + weights[afterIndex + 1]
        let raw = Int(((t - start) * Double(weightTotal)).rounded())
        let left = min(max(raw, minWeight), pairSum - minWeight)
        guard left >= minWeight, pairSum - left >= minWeight else { return nil }
        var next = weights
        next[afterIndex] = left
        next[afterIndex + 1] = pairSum - left
        return renormalized(next)
    }

    static func renormalized(_ weights: [Int]) -> [Int] {
        let positives = weights.map { max($0, 1) }
        let sum = positives.reduce(0, +)
        guard sum > 0 else { return positives }
        if sum == weightTotal { return positives }
        var scaled = positives.map { Int((Double($0) * Double(weightTotal) / Double(sum)).rounded()) }
        scaled = scaled.map { max($0, 1) }
        let diff = weightTotal - scaled.reduce(0, +)
        if diff != 0, let idx = scaled.indices.max(by: { scaled[$0] < scaled[$1] }) {
            scaled[idx] = max(1, scaled[idx] + diff)
        }
        return scaled
    }

    static func addingZone(to layout: Layout, spec: GridSpec) -> Layout? {
        var next = layout
        let number = (layout.zones.map(\.number).max() ?? 0) + 1
        next.zones.append(Zone(number: number))
        return replacing(spec, in: next)
    }

    static func replacing(_ spec: GridSpec, in layout: Layout) -> Layout? {
        var next = layout
        next.kind = .grid
        next.grid = spec
        next.updatedAt = Date()
        next = compacting(next)
        next = reindexed(next)
        for i in next.zones.indices {
            next.zones[i].number = i + 1
        }
        guard let grid = next.grid, (try? grid.validated(zoneCount: next.zones.count)) != nil else {
            return nil
        }
        return next
    }

    static func compacting(_ layout: Layout) -> Layout {
        guard var spec = layout.grid else { return layout }
        var changed = true
        while changed {
            changed = false
            var c = spec.columns - 2
            while c >= 0 {
                if (0..<spec.rows).allSatisfy({ spec.cellMap[$0][c] == spec.cellMap[$0][c + 1] }) {
                    spec.columnWeights[c] += spec.columnWeights[c + 1]
                    spec.columnWeights.remove(at: c + 1)
                    for r in 0..<spec.rows { spec.cellMap[r].remove(at: c + 1) }
                    spec.columns -= 1
                    changed = true
                }
                c -= 1
            }
            var r = spec.rows - 2
            while r >= 0 {
                if spec.cellMap[r] == spec.cellMap[r + 1] {
                    spec.rowWeights[r] += spec.rowWeights[r + 1]
                    spec.rowWeights.remove(at: r + 1)
                    spec.cellMap.remove(at: r + 1)
                    spec.rows -= 1
                    changed = true
                }
                r -= 1
            }
        }
        spec.rowWeights = renormalized(spec.rowWeights)
        spec.columnWeights = renormalized(spec.columnWeights)
        var next = layout
        next.grid = spec
        return next
    }

    static func reindexed(_ layout: Layout) -> Layout {
        guard var spec = layout.grid else { return layout }
        let used = Array(Set(spec.cellMap.flatMap { $0 })).sorted()
        var map: [Int: Int] = [:]
        for (new, old) in used.enumerated() { map[old] = new }
        spec.cellMap = spec.cellMap.map { row in row.map { map[$0] ?? $0 } }
        var next = layout
        next.grid = spec
        next.zones = used.compactMap { index in
            layout.zones.indices.contains(index) ? layout.zones[index] : nil
        }
        return next
    }

    static func bestNeighbor(of index: Int, spec: GridSpec) -> Int? {
        var shared: [Int: Int] = [:]
        for r in 0..<spec.rows {
            for c in 0..<spec.columns where spec.cellMap[r][c] == index {
                let candidates = [(r, c - 1), (r, c + 1), (r - 1, c), (r + 1, c)]
                for (nr, nc) in candidates {
                    guard (0..<spec.rows).contains(nr), (0..<spec.columns).contains(nc) else { continue }
                    let other = spec.cellMap[nr][nc]
                    if other != index {
                        shared[other, default: 0] += 1
                    }
                }
            }
        }
        return shared.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }?.key
    }
}
