import Foundation

public enum CanvasAlignment {
    public enum Edge: Sendable {
        case left, centerX, right, top, centerY, bottom
    }

    public enum SizeMatch: Sendable {
        case width, height, both
    }

    public enum Axis: Sendable {
        case horizontal, vertical
    }

    public static func aligning(_ rects: [UUID: NormalizedRect], to edge: Edge) -> [UUID: NormalizedRect] {
        guard !rects.isEmpty else { return rects }
        let bounds = union(of: rects.values)
        var result: [UUID: NormalizedRect] = [:]
        for (id, rect) in rects {
            var next = rect
            switch edge {
            case .left:
                next.x = bounds.x
            case .centerX:
                next.x = bounds.midX - next.width / 2
            case .right:
                next.x = bounds.maxX - next.width
            case .top:
                next.y = bounds.y
            case .centerY:
                next.y = bounds.midY - next.height / 2
            case .bottom:
                next.y = bounds.maxY - next.height
            }
            result[id] = next.clamped()
        }
        return result
    }

    public static func matchingSize(
        _ rects: [UUID: NormalizedRect],
        primary: UUID,
        match: SizeMatch
    ) -> [UUID: NormalizedRect] {
        guard let source = rects[primary] else { return rects }
        var result: [UUID: NormalizedRect] = [:]
        for (id, rect) in rects {
            var next = rect
            switch match {
            case .width:
                next.width = source.width
            case .height:
                next.height = source.height
            case .both:
                next.width = source.width
                next.height = source.height
            }
            result[id] = next.clamped()
        }
        return result
    }

    public static func distributing(
        _ rects: [UUID: NormalizedRect],
        axis: Axis
    ) -> [UUID: NormalizedRect] {
        guard rects.count >= 3 else { return rects }
        let ordered: [(UUID, NormalizedRect)]
        switch axis {
        case .horizontal:
            ordered = rects.sorted { lhs, rhs in
                if lhs.value.midX != rhs.value.midX { return lhs.value.midX < rhs.value.midX }
                return lhs.key.uuidString < rhs.key.uuidString
            }.map { ($0.key, $0.value) }
        case .vertical:
            ordered = rects.sorted { lhs, rhs in
                if lhs.value.midY != rhs.value.midY { return lhs.value.midY < rhs.value.midY }
                return lhs.key.uuidString < rhs.key.uuidString
            }.map { ($0.key, $0.value) }
        }
        guard let first = ordered.first, let last = ordered.last else { return rects }
        let count = Double(ordered.count - 1)
        var result = rects
        switch axis {
        case .horizontal:
            let start = first.1.midX
            let spacing = (last.1.midX - start) / count
            for (index, item) in ordered.enumerated() {
                var next = item.1
                next.x = start + spacing * Double(index) - next.width / 2
                result[item.0] = next.clamped()
            }
        case .vertical:
            let start = first.1.midY
            let spacing = (last.1.midY - start) / count
            for (index, item) in ordered.enumerated() {
                var next = item.1
                next.y = start + spacing * Double(index) - next.height / 2
                result[item.0] = next.clamped()
            }
        }
        return result
    }

    public static func union(of rects: Dictionary<UUID, NormalizedRect>.Values) -> NormalizedRect {
        union(of: Array(rects))
    }

    public static func union(of rects: [NormalizedRect]) -> NormalizedRect {
        guard let first = rects.first else {
            return NormalizedRect(x: 0, y: 0, width: 0, height: 0)
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.maxX
        var maxY = first.maxY
        for rect in rects.dropFirst() {
            minX = min(minX, rect.x)
            minY = min(minY, rect.y)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        return NormalizedRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}
