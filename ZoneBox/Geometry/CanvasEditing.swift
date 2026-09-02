import CoreGraphics
import Foundation

public enum CanvasEditing {
    public static let creatingSentinel = "__creating"

    /// Default click-to-create size, matching the previous canvas editor.
    public static func defaultRect(
        centeredAt point: (x: Double, y: Double),
        canvasSize: CGSize
    ) -> NormalizedRect {
        let width = min(280, max(140, canvasSize.width * 0.28))
        let height = min(200, max(110, canvasSize.height * 0.24))
        var rect = CGRect(
            x: CGFloat(point.x) * canvasSize.width - width / 2,
            y: (1 - CGFloat(point.y)) * canvasSize.height - height / 2,
            width: width,
            height: height
        )
        rect.origin.x = min(max(0, rect.origin.x), max(0, canvasSize.width - rect.width))
        rect.origin.y = min(max(0, rect.origin.y), max(0, canvasSize.height - rect.height))
        let w = max(canvasSize.width, 1)
        let h = max(canvasSize.height, 1)
        return NormalizedRect(
            x: Double(rect.minX / w),
            y: Double((h - rect.maxY) / h),
            width: Double(rect.width / w),
            height: Double(rect.height / h)
        ).clamped()
    }

    public static func inserting(_ layout: Layout, rect: NormalizedRect) -> (layout: Layout, newID: UUID)? {
        guard layout.kind != .grid else { return nil }
        var next = sanitized(layout)
        next.kind = .canvas
        next.grid = nil
        let zone = Zone(
            number: (next.zones.map(\.number).max() ?? 0) + 1,
            canvasRect: rect.clamped()
        )
        next.zones.append(zone)
        return (next.packedNumbers(), zone.id)
    }

    public static func duplicating(
        _ layout: Layout,
        ids: Set<UUID>,
        offset: (x: Double, y: Double)
    ) -> (layout: Layout, newIDs: [UUID])? {
        guard layout.kind != .grid else { return nil }
        let sources = sanitized(layout).zones.filter { ids.contains($0.id) && $0.canvasRect != nil }
        guard !sources.isEmpty else { return nil }

        var next = sanitized(layout)
        next.kind = .canvas
        next.grid = nil
        var newIDs: [UUID] = []
        var number = (next.zones.map(\.number).max() ?? 0) + 1
        for source in sources.sorted(by: { $0.number < $1.number }) {
            guard let rect = source.canvasRect else { continue }
            let placed = placement(for: rect, offset: offset)
            let copy = Zone(number: number, canvasRect: placed)
            next.zones.append(copy)
            newIDs.append(copy.id)
            number += 1
        }
        return (next.packedNumbers(), newIDs)
    }

    public static func splitting(
        _ layout: Layout,
        id: UUID,
        axis: GridAxis,
        at fraction: Double = 0.5
    ) -> (layout: Layout, newID: UUID)? {
        guard layout.kind != .grid else { return nil }
        var next = sanitized(layout)
        next.kind = .canvas
        next.grid = nil
        guard let index = next.zones.firstIndex(where: { $0.id == id }),
              var rect = next.zones[index].canvasRect
        else { return nil }

        let t = min(max(fraction, 0), 1)
        switch axis {
        case .vertical:
            let leftWidth = rect.width * t
            let rightWidth = rect.width - leftWidth
            guard leftWidth >= ZoneSplit.minSize, rightWidth >= ZoneSplit.minSize else { return nil }
            var left = rect
            left.width = leftWidth
            var right = rect
            right.x = rect.x + leftWidth
            right.width = rightWidth
            next.zones[index].canvasRect = left
            rect = right
        case .horizontal:
            let topHeight = rect.height * t
            let bottomHeight = rect.height - topHeight
            guard topHeight >= ZoneSplit.minSize, bottomHeight >= ZoneSplit.minSize else { return nil }
            var top = rect
            top.height = topHeight
            var bottom = rect
            bottom.y = rect.y + topHeight
            bottom.height = bottomHeight
            next.zones[index].canvasRect = top
            rect = bottom
        }

        let zone = Zone(number: (next.zones.map(\.number).max() ?? 0) + 1, canvasRect: rect)
        next.zones.append(zone)
        return (next.packedNumbers(), zone.id)
    }

    public static func deleting(_ layout: Layout, ids: Set<UUID>) -> Layout {
        var next = sanitized(layout)
        next.zones.removeAll { ids.contains($0.id) }
        return next.packedNumbers()
    }

    public static func assigningNumber(_ layout: Layout, id: UUID, number: Int) -> Layout? {
        guard (1...9).contains(number) else { return nil }
        var next = sanitized(layout)
        guard let index = next.zones.firstIndex(where: { $0.id == id }) else { return nil }
        if let occupant = next.zones.firstIndex(where: { $0.id != id && $0.number == number }) {
            next.zones[occupant].number = next.zones[index].number
        }
        next.zones[index].number = number
        return next.packedNumbers()
    }

    public static func applying(
        _ layout: Layout,
        rects: [UUID: NormalizedRect]
    ) -> Layout {
        var next = sanitized(layout)
        next.kind = .canvas
        next.grid = nil
        for index in next.zones.indices {
            if let rect = rects[next.zones[index].id] {
                next.zones[index].canvasRect = rect.clamped()
            }
        }
        return next
    }

    public static func halfWorkArea(_ edge: CanvasAlignment.Edge) -> NormalizedRect {
        switch edge {
        case .left:
            return NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right:
            return NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .top:
            return NormalizedRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottom:
            return NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .centerX, .centerY:
            return NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        }
    }

    public static func centered(_ rect: NormalizedRect) -> NormalizedRect {
        var next = rect.clamped()
        next.x = max(0, min(0.5 - next.width / 2, 1 - next.width))
        next.y = max(0, min(0.5 - next.height / 2, 1 - next.height))
        return next
    }

    public static func offsetPoints(
        _ points: CGFloat,
        workAreaAX: CGRect
    ) -> (x: Double, y: Double) {
        (
            workAreaAX.width > 0 ? Double(points / workAreaAX.width) : 0,
            workAreaAX.height > 0 ? Double(points / workAreaAX.height) : 0
        )
    }

    public static func nudge(
        _ rect: NormalizedRect,
        dxPoints: CGFloat,
        dyPoints: CGFloat,
        resize: Bool,
        workAreaAX: CGRect
    ) -> NormalizedRect {
        guard workAreaAX.width > 0, workAreaAX.height > 0 else { return rect }
        let dx = Double(dxPoints / workAreaAX.width)
        let dy = Double(dyPoints / workAreaAX.height)
        var next = rect
        if resize {
            next.width += dx
            next.height += dy
        } else {
            next.x += dx
            next.y += dy
        }
        return next.clamped()
    }

    public static func sanitized(_ layout: Layout) -> Layout {
        var next = layout
        next.zones.removeAll { $0.name == creatingSentinel }
        return next
    }

    private static func placement(
        for rect: NormalizedRect,
        offset: (x: Double, y: Double)
    ) -> NormalizedRect {
        let preferred = NormalizedRect(
            x: rect.x + offset.x,
            y: rect.y + offset.y,
            width: rect.width,
            height: rect.height
        )
        if fits(preferred) { return preferred.clamped() }

        let right = NormalizedRect(
            x: rect.maxX,
            y: rect.y,
            width: rect.width,
            height: rect.height
        )
        if fits(right) { return right.clamped() }

        let below = NormalizedRect(
            x: rect.x,
            y: rect.maxY,
            width: rect.width,
            height: rect.height
        )
        if fits(below) { return below.clamped() }

        return rect.clamped()
    }

    private static func fits(_ rect: NormalizedRect) -> Bool {
        rect.x >= 0
            && rect.y >= 0
            && rect.maxX <= 1 + 1e-9
            && rect.maxY <= 1 + 1e-9
    }
}
