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
        return copy
    }

    public func packedNumbers() -> Layout {
        var copy = self
        let sorted = copy.zones.sorted { $0.number < $1.number }
        copy.zones = sorted.enumerated().map { index, zone in
            var z = zone
            z.number = index + 1
            return z
        }
        return copy
    }
}
