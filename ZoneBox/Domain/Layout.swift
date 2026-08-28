import CoreGraphics
import Foundation

public enum GridValidationError: Error, Equatable {
    case empty
    case tooLarge
    case weightCountMismatch
    case nonPositiveWeight
    case weightsMustSumTo10000(actual: Int)
    case cellMapShape
    case indexOutOfRange(Int)
    case missingIndex(Int)
    case nonRectangularMerge(index: Int)
    case zoneCountMismatch
    case zoneNumbersNotPacked
}

public struct GridSpec: Codable, Hashable, Sendable {
    public var rows: Int
    public var columns: Int
    public var rowWeights: [Int]
    public var columnWeights: [Int]
    public var cellMap: [[Int]]

    public init(rows: Int, columns: Int, rowWeights: [Int], columnWeights: [Int], cellMap: [[Int]]) {
        self.rows = rows
        self.columns = columns
        self.rowWeights = rowWeights
        self.columnWeights = columnWeights
        self.cellMap = cellMap
    }

    public func validated(zoneCount: Int) throws -> GridSpec {
        guard rows >= 1, columns >= 1 else { throw GridValidationError.empty }
        guard rows <= 16, columns <= 16 else { throw GridValidationError.tooLarge }
        guard rowWeights.count == rows, columnWeights.count == columns else {
            throw GridValidationError.weightCountMismatch
        }
        guard rowWeights.allSatisfy({ $0 > 0 }), columnWeights.allSatisfy({ $0 > 0 }) else {
            throw GridValidationError.nonPositiveWeight
        }
        let rowSum = rowWeights.reduce(0, +)
        let colSum = columnWeights.reduce(0, +)
        guard rowSum == 10_000 else { throw GridValidationError.weightsMustSumTo10000(actual: rowSum) }
        guard colSum == 10_000 else { throw GridValidationError.weightsMustSumTo10000(actual: colSum) }
        guard cellMap.count == rows, cellMap.allSatisfy({ $0.count == columns }) else {
            throw GridValidationError.cellMapShape
        }

        var seen = Set<Int>()
        for row in cellMap {
            for idx in row {
                guard idx >= 0 else { throw GridValidationError.indexOutOfRange(idx) }
                if idx >= zoneCount { throw GridValidationError.indexOutOfRange(idx) }
                seen.insert(idx)
            }
        }
        for i in 0..<zoneCount {
            if !seen.contains(i) { throw GridValidationError.missingIndex(i) }
        }

        for idx in seen {
            var r0 = Int.max, r1 = Int.min, c0 = Int.max, c1 = Int.min
            for r in 0..<rows {
                for c in 0..<columns where cellMap[r][c] == idx {
                    r0 = min(r0, r); r1 = max(r1, r)
                    c0 = min(c0, c); c1 = max(c1, c)
                }
            }
            for r in r0...r1 {
                for c in c0...c1 {
                    if cellMap[r][c] != idx { throw GridValidationError.nonRectangularMerge(index: idx) }
                }
            }
            for r in 0..<rows {
                for c in 0..<columns where cellMap[r][c] == idx {
                    if r < r0 || r > r1 || c < c0 || c > c1 {
                        throw GridValidationError.nonRectangularMerge(index: idx)
                    }
                }
            }
        }
        return self
    }
}

public struct Layout: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: LayoutKind
    public var zones: [Zone]
    public var grid: GridSpec?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: LayoutKind,
        zones: [Zone],
        grid: GridSpec? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.zones = zones
        self.grid = grid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func convertingGridToCanvas(workAreaAX: CGRect) throws -> Layout {
        let resolved = try resolveLayout(self, workAreaAX: workAreaAX, gutter: 0)
        var copy = self
        copy.kind = .canvas
        copy.grid = nil
        copy.zones = resolved.map { z in
            Zone(
                id: z.zoneID,
                number: z.number,
                canvasRect: NormalizedRect.normalize(z.frameAX, in: workAreaAX)
            )
        }
        copy.updatedAt = Date()
        return copy.packedNumbers()
    }

    public func packedNumbers() -> Layout {
        var copy = self
        let sorted = copy.zones.sorted { lhs, rhs in
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        copy.zones = sorted.enumerated().map { index, zone in
            var z = zone
            z.number = index + 1
            return z
        }
        return copy
    }

    /// Tab / Shift+Tab order: painted zone numbers 1 -> 2 -> 3 -> 4, wrapping.
    /// Skips in-progress create drags.
    public func cycledZoneID(from selected: UUID?, forward: Bool) -> UUID? {
        let ordered = zones
            .filter { $0.name != "__creating" }
            .sorted { $0.number < $1.number }
        guard !ordered.isEmpty else { return nil }
        guard let selected, let idx = ordered.firstIndex(where: { $0.id == selected }) else {
            return forward ? ordered.first?.id : ordered.last?.id
        }
        let next = forward
            ? (idx + 1) % ordered.count
            : (idx - 1 + ordered.count) % ordered.count
        return ordered[next].id
    }

    public enum ArrowDirection: Sendable {
        case left, right, up, down
    }

    /// Arrow-key order: the spatially adjacent pane in that direction.
    /// Prefers the nearest pane that shares an edge in that direction, so a
    /// stacked pair still wins over a taller neighbor whose center is closer.
    public func neighborZoneID(from selected: UUID?, direction: ArrowDirection) -> UUID? {
        neighborZoneID(from: selected, direction: direction, rects: [:])
    }

    public func neighborZoneID(
        from selected: UUID?,
        direction: ArrowDirection,
        rects: [UUID: NormalizedRect]
    ) -> UUID? {
        let candidates = zones.compactMap { zone -> (id: UUID, number: Int, rect: NormalizedRect)? in
            guard zone.name != "__creating" else { return nil }
            guard let rect = rects[zone.id] ?? zone.canvasRect else { return nil }
            return (zone.id, zone.number, rect)
        }
        guard !candidates.isEmpty else { return nil }
        guard let selected,
              let current = candidates.first(where: { $0.id == selected })
        else {
            return candidates.min { lhs, rhs in
                if lhs.rect.y != rhs.rect.y { return lhs.rect.y < rhs.rect.y }
                if lhs.rect.x != rhs.rect.x { return lhs.rect.x < rhs.rect.x }
                return lhs.id.uuidString < rhs.id.uuidString
            }?.id
        }

        struct Neighbor {
            var id: UUID
            var gap: Double
            var across: Double
            var overlap: Double
            var number: Int
        }

        var neighbors: [Neighbor] = []
        neighbors.reserveCapacity(candidates.count)
        for zone in candidates where zone.id != current.id {
            let overlap = directionalOverlap(from: current.rect, to: zone.rect, direction: direction)
            let gap = edgeGap(from: current.rect, to: zone.rect, direction: direction)
            guard !containsOnAxis(current.rect, other: zone.rect, direction: direction) else { continue }
            guard isAhead(from: current.rect, to: zone.rect, direction: direction) else { continue }
            let across = crossAxisCenterDelta(from: current.rect, to: zone.rect, direction: direction)
            neighbors.append(
                Neighbor(
                    id: zone.id,
                    gap: max(0, gap),
                    across: across,
                    overlap: overlap,
                    number: zone.number
                )
            )
        }
        let aligned = neighbors.filter { $0.overlap > 0.000_001 }
        let pool = aligned.isEmpty ? neighbors : aligned
        return pool.min { lhs, rhs in
            if lhs.gap != rhs.gap { return lhs.gap < rhs.gap }
            if lhs.across != rhs.across { return lhs.across < rhs.across }
            return lhs.number < rhs.number
        }?.id ?? selected
    }

    private func directionalOverlap(
        from current: NormalizedRect,
        to other: NormalizedRect,
        direction: ArrowDirection
    ) -> Double {
        switch direction {
        case .left, .right:
            return overlap(current.y, current.y + current.height, other.y, other.y + other.height)
        case .up, .down:
            return overlap(current.x, current.x + current.width, other.x, other.x + other.width)
        }
    }

    private func edgeGap(
        from current: NormalizedRect,
        to other: NormalizedRect,
        direction: ArrowDirection
    ) -> Double {
        switch direction {
        case .right:
            return other.x - (current.x + current.width)
        case .left:
            return current.x - (other.x + other.width)
        case .down:
            return other.y - (current.y + current.height)
        case .up:
            return current.y - (other.y + other.height)
        }
    }

    /// A taller/wider pane that wraps this one is beside it, not in front.
    private func containsOnAxis(
        _ current: NormalizedRect,
        other: NormalizedRect,
        direction: ArrowDirection
    ) -> Bool {
        let epsilon = 0.000_001
        switch direction {
        case .left, .right:
            return other.x <= current.x + epsilon
                && other.x + other.width >= current.x + current.width - epsilon
        case .up, .down:
            return other.y <= current.y + epsilon
                && other.y + other.height >= current.y + current.height - epsilon
        }
    }

    private func isAhead(
        from current: NormalizedRect,
        to other: NormalizedRect,
        direction: ArrowDirection
    ) -> Bool {
        let origin = axisCenter(of: current, direction: direction)
        let target = axisCenter(of: other, direction: direction)
        switch direction {
        case .right, .down:
            return target > origin + 0.000_001
        case .left, .up:
            return target < origin - 0.000_001
        }
    }

    private func axisCenter(of rect: NormalizedRect, direction: ArrowDirection) -> Double {
        switch direction {
        case .left, .right:
            return rect.x + rect.width / 2
        case .up, .down:
            return rect.y + rect.height / 2
        }
    }

    private func crossAxisCenterDelta(
        from current: NormalizedRect,
        to other: NormalizedRect,
        direction: ArrowDirection
    ) -> Double {
        switch direction {
        case .left, .right:
            return abs((current.y + current.height / 2) - (other.y + other.height / 2))
        case .up, .down:
            return abs((current.x + current.width / 2) - (other.x + other.width / 2))
        }
    }

    private func overlap(_ a0: Double, _ a1: Double, _ b0: Double, _ b1: Double) -> Double {
        max(0, min(a1, b1) - max(a0, b0))
    }
}
