import CoreGraphics
import Foundation

public struct DividerHandleSlot: Equatable, Sendable, Hashable {
    public var zoneID: UUID
    public var identity: WindowIdentity

    public init(zoneID: UUID, identity: WindowIdentity) {
        self.zoneID = zoneID
        self.identity = identity
    }
}

public struct DividerHandleSpec: Equatable, Sendable {
    public var axis: GridAxis
    public var afterIndex: Int
    public var lineAX: CGFloat
    public var spanAX: ClosedRange<CGFloat>
    public var slots: [DividerHandleSlot]

    public init(
        axis: GridAxis,
        afterIndex: Int,
        lineAX: CGFloat,
        spanAX: ClosedRange<CGFloat>,
        slots: [DividerHandleSlot]
    ) {
        self.axis = axis
        self.afterIndex = afterIndex
        self.lineAX = lineAX
        self.spanAX = spanAX
        self.slots = slots
    }

    public var centerAX: CGPoint {
        switch axis {
        case .vertical:
            return CGPoint(x: lineAX, y: (spanAX.lowerBound + spanAX.upperBound) / 2)
        case .horizontal:
            return CGPoint(x: (spanAX.lowerBound + spanAX.upperBound) / 2, y: lineAX)
        }
    }

    public var isVertical: Bool { axis == .vertical }

    public var slotZoneIDs: Set<UUID> {
        Set(slots.map { $0.zoneID })
    }

    public func matches(_ other: DividerHandleSpec) -> Bool {
        axis == other.axis && slotZoneIDs == other.slotZoneIDs
    }
}

public enum DividerPlan {
    public static let inPlaceSizeTolerance: CGFloat = 28
    public static let inPlaceOriginTolerance: CGFloat = 28
    public static let seamGapTolerance: CGFloat = 24
    public static let minSeamOverlap: CGFloat = 36
    public static let verticalHitSize = CGSize(width: 36, height: 48)
    public static let horizontalHitSize = CGSize(width: 48, height: 36)

    public static func handles(
        layout: Layout,
        workAreaAX: CGRect,
        resolvedFrames: [UUID: CGRect],
        snapped: [UUID: [WindowIdentity]]
    ) -> [DividerHandleSpec] {
        guard workAreaAX.width > 0, workAreaAX.height > 0 else {
            return []
        }
        if layout.kind == .canvas {
            return canvasHandles(
                layout: layout,
                resolvedFrames: resolvedFrames,
                snapped: snapped
            )
        }
        guard let spec = layout.grid else { return [] }
        var handles: [DividerHandleSpec] = []
        handles.append(contentsOf: verticalHandles(
            layout: layout,
            spec: spec,
            workAreaAX: workAreaAX,
            resolvedFrames: resolvedFrames,
            snapped: snapped
        ))
        handles.append(contentsOf: horizontalHandles(
            layout: layout,
            spec: spec,
            workAreaAX: workAreaAX,
            resolvedFrames: resolvedFrames,
            snapped: snapped
        ))
        return handles
    }

    /// Bind live window frames onto the current layout's zones.
    /// Catalog membership wins when the window still fills that zone, so an
    /// overlapping Finder/browser window cannot steal the seam.
    public static func occupancy(
        resolvedFrames: [UUID: CGRect],
        windows: [(identity: WindowIdentity, frameAX: CGRect)],
        preferred: [WindowIdentity: UUID] = [:],
        workAreaAX: CGRect? = nil
    ) -> [UUID: [WindowIdentity]] {
        var result: [UUID: [WindowIdentity]] = [:]
        var used = Set<WindowIdentity>()
        let clipped = windows.compactMap { window -> (identity: WindowIdentity, frameAX: CGRect)? in
            let frame = clippedFrame(window.frameAX, to: workAreaAX)
            guard isUsableWindow(frame) else { return nil }
            return (window.identity, frame)
        }

        func assign(_ identity: WindowIdentity, to zoneID: UUID) {
            result[zoneID, default: []].append(identity)
            used.insert(identity)
        }

        for window in clipped {
            guard !used.contains(window.identity) else { continue }
            guard let zoneID = preferred[window.identity],
                  let target = resolvedFrames[zoneID],
                  occupiesPreferred(window.frameAX, target: target)
            else { continue }
            assign(window.identity, to: zoneID)
        }

        for window in clipped {
            guard !used.contains(window.identity) else { continue }
            guard let zoneID = uniqueFilledZone(for: window.frameAX, in: resolvedFrames),
                  result[zoneID] == nil
            else { continue }
            assign(window.identity, to: zoneID)
        }
        return result
    }

    public static func hitRect(for handle: DividerHandleSpec, primaryFlipHeight: CGFloat) -> CGRect {
        let centerAppKit = CoordinateConverter.appKitPoint(
            fromAX: handle.centerAX,
            primaryFlipHeight: primaryFlipHeight
        )
        let size = handle.isVertical ? verticalHitSize : horizontalHitSize
        return CGRect(
            x: centerAppKit.x - size.width / 2,
            y: centerAppKit.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    public static func isInPlace(_ actual: CGRect, target: CGRect) -> Bool {
        WindowOrganize.didApply(
            actual,
            to: target,
            sizeTolerance: inPlaceSizeTolerance,
            originTolerance: inPlaceOriginTolerance
        )
    }

    public static func normalizedPosition(
        of pointAX: CGPoint,
        axis: GridAxis,
        in workAreaAX: CGRect
    ) -> Double? {
        switch axis {
        case .vertical:
            guard workAreaAX.width > 0 else { return nil }
            return Double((pointAX.x - workAreaAX.minX) / workAreaAX.width)
        case .horizontal:
            guard workAreaAX.height > 0 else { return nil }
            return Double((pointAX.y - workAreaAX.minY) / workAreaAX.height)
        }
    }

    public static func movedLayout(
        _ layout: Layout,
        handle: DividerHandleSpec,
        toNormalized t: Double
    ) -> Layout? {
        if layout.kind == .grid {
            return GridEditing.moveLine(
                layout,
                axis: handle.axis,
                afterIndex: handle.afterIndex,
                toNormalized: t
            )
        }
        guard handle.slots.count == 2 else { return nil }
        let firstID = handle.slots[0].zoneID
        let secondID = handle.slots[1].zoneID
        guard let first = layout.zones.first(where: { $0.id == firstID })?.canvasRect,
              let second = layout.zones.first(where: { $0.id == secondID })?.canvasRect
        else { return nil }
        switch handle.axis {
        case .vertical:
            let pair = ZoneSplit.movingVerticalSeam(left: first, right: second, to: t)
            return CanvasEditing.applying(layout, rects: [firstID: pair.left, secondID: pair.right])
        case .horizontal:
            let pair = ZoneSplit.movingHorizontalSeam(top: first, bottom: second, to: t)
            return CanvasEditing.applying(layout, rects: [firstID: pair.top, secondID: pair.bottom])
        }
    }

    public static func geometryChanged(from start: Layout, to end: Layout) -> Bool {
        if start.kind != end.kind || start.grid != end.grid || start.zones.count != end.zones.count {
            return true
        }
        return zip(start.zones, end.zones).contains { lhs, rhs in
            lhs.id != rhs.id || lhs.canvasRect != rhs.canvasRect
        }
    }
}

private extension DividerPlan {
    static func verticalHandles(
        layout: Layout,
        spec: GridSpec,
        workAreaAX: CGRect,
        resolvedFrames: [UUID: CGRect],
        snapped: [UUID: [WindowIdentity]]
    ) -> [DividerHandleSpec] {
        guard spec.columns > 1 else { return [] }
        let colPrefix = prefix(spec.columnWeights)
        return (0..<(spec.columns - 1)).compactMap { afterIndex in
            var zoneIndices = Set<Int>()
            var spanMin = CGFloat.greatestFiniteMagnitude
            var spanMax = -CGFloat.greatestFiniteMagnitude
            for r in 0..<spec.rows {
                let left = spec.cellMap[r][afterIndex]
                let right = spec.cellMap[r][afterIndex + 1]
                guard left != right else { continue }
                zoneIndices.insert(left)
                zoneIndices.insert(right)
                if let overlap = verticalOverlap(
                    left: resolvedFrames[layout.zones[left].id],
                    right: resolvedFrames[layout.zones[right].id]
                ) {
                    spanMin = min(spanMin, overlap.lowerBound)
                    spanMax = max(spanMax, overlap.upperBound)
                } else {
                    let fallback = fallbackSpan(
                        for: [left, right],
                        layout: layout,
                        resolvedFrames: resolvedFrames,
                        axis: .vertical,
                        workAreaAX: workAreaAX
                    )
                    spanMin = min(spanMin, fallback.lowerBound)
                    spanMax = max(spanMax, fallback.upperBound)
                }
            }
            return makeHandle(
                axis: .vertical,
                afterIndex: afterIndex,
                fallbackLineAX: workAreaAX.minX + workAreaAX.width * CGFloat(colPrefix[afterIndex + 1]),
                span: spanMin...spanMax,
                zoneIndices: zoneIndices,
                layout: layout,
                resolvedFrames: resolvedFrames,
                snapped: snapped
            )
        }
    }

    static func horizontalHandles(
        layout: Layout,
        spec: GridSpec,
        workAreaAX: CGRect,
        resolvedFrames: [UUID: CGRect],
        snapped: [UUID: [WindowIdentity]]
    ) -> [DividerHandleSpec] {
        guard spec.rows > 1 else { return [] }
        let rowPrefix = prefix(spec.rowWeights)
        return (0..<(spec.rows - 1)).compactMap { afterIndex in
            var zoneIndices = Set<Int>()
            var spanMin = CGFloat.greatestFiniteMagnitude
            var spanMax = -CGFloat.greatestFiniteMagnitude
            for c in 0..<spec.columns {
                let top = spec.cellMap[afterIndex][c]
                let bottom = spec.cellMap[afterIndex + 1][c]
                guard top != bottom else { continue }
                zoneIndices.insert(top)
                zoneIndices.insert(bottom)
                if let overlap = horizontalOverlap(
                    top: resolvedFrames[layout.zones[top].id],
                    bottom: resolvedFrames[layout.zones[bottom].id]
                ) {
                    spanMin = min(spanMin, overlap.lowerBound)
                    spanMax = max(spanMax, overlap.upperBound)
                } else {
                    let fallback = fallbackSpan(
                        for: [top, bottom],
                        layout: layout,
                        resolvedFrames: resolvedFrames,
                        axis: .horizontal,
                        workAreaAX: workAreaAX
                    )
                    spanMin = min(spanMin, fallback.lowerBound)
                    spanMax = max(spanMax, fallback.upperBound)
                }
            }
            return makeHandle(
                axis: .horizontal,
                afterIndex: afterIndex,
                fallbackLineAX: workAreaAX.minY + workAreaAX.height * CGFloat(rowPrefix[afterIndex + 1]),
                span: spanMin...spanMax,
                zoneIndices: zoneIndices,
                layout: layout,
                resolvedFrames: resolvedFrames,
                snapped: snapped
            )
        }
    }

    static func makeHandle(
        axis: GridAxis,
        afterIndex: Int,
        fallbackLineAX: CGFloat,
        span: ClosedRange<CGFloat>,
        zoneIndices: Set<Int>,
        layout: Layout,
        resolvedFrames: [UUID: CGRect],
        snapped: [UUID: [WindowIdentity]]
    ) -> DividerHandleSpec? {
        guard !zoneIndices.isEmpty,
              span.lowerBound.isFinite,
              span.upperBound.isFinite,
              span.upperBound > span.lowerBound
        else {
            return nil
        }
        var slots: [DividerHandleSlot] = []
        for index in zoneIndices.sorted() {
            guard layout.zones.indices.contains(index) else { return nil }
            let zoneID = layout.zones[index].id
            let windows = snapped[zoneID] ?? []
            guard windows.count == 1, let identity = windows.first else { return nil }
            slots.append(DividerHandleSlot(zoneID: zoneID, identity: identity))
        }
        let lineAX = contactLine(
            axis: axis,
            zoneIndices: zoneIndices,
            layout: layout,
            resolvedFrames: resolvedFrames
        ) ?? fallbackLineAX
        return DividerHandleSpec(
            axis: axis,
            afterIndex: afterIndex,
            lineAX: lineAX,
            spanAX: span,
            slots: slots
        )
    }

    static func canvasHandles(
        layout: Layout,
        resolvedFrames: [UUID: CGRect],
        snapped: [UUID: [WindowIdentity]]
    ) -> [DividerHandleSpec] {
        let items = layout.zones.compactMap { zone -> (zone: Zone, frame: CGRect)? in
            guard let frame = resolvedFrames[zone.id], frame.width > 1, frame.height > 1 else { return nil }
            return (zone, frame)
        }
        var handles: [DividerHandleSpec] = []
        var afterIndex = 0
        for i in items.indices {
            for j in items.indices where i < j {
                if let handle = canvasHandle(
                    first: items[i],
                    second: items[j],
                    axis: .vertical,
                    afterIndex: afterIndex,
                    snapped: snapped
                ) {
                    handles.append(handle)
                    afterIndex += 1
                }
                if let handle = canvasHandle(
                    first: items[i],
                    second: items[j],
                    axis: .horizontal,
                    afterIndex: afterIndex,
                    snapped: snapped
                ) {
                    handles.append(handle)
                    afterIndex += 1
                }
            }
        }
        return handles
    }

    static func canvasHandle(
        first: (zone: Zone, frame: CGRect),
        second: (zone: Zone, frame: CGRect),
        axis: GridAxis,
        afterIndex: Int,
        snapped: [UUID: [WindowIdentity]]
    ) -> DividerHandleSpec? {
        switch axis {
        case .vertical:
            let (left, right) = first.frame.midX <= second.frame.midX
                ? (first, second)
                : (second, first)
            let gap = right.frame.minX - left.frame.maxX
            guard abs(gap) <= seamGapTolerance else { return nil }
            let start = max(left.frame.minY, right.frame.minY)
            let end = min(left.frame.maxY, right.frame.maxY)
            guard end - start >= minSeamOverlap else { return nil }
            guard let leftIdentity = uniqueIdentity(in: snapped[left.zone.id]),
                  let rightIdentity = uniqueIdentity(in: snapped[right.zone.id])
            else { return nil }
            return DividerHandleSpec(
                axis: .vertical,
                afterIndex: afterIndex,
                lineAX: (left.frame.maxX + right.frame.minX) / 2,
                spanAX: start...end,
                slots: [
                    DividerHandleSlot(zoneID: left.zone.id, identity: leftIdentity),
                    DividerHandleSlot(zoneID: right.zone.id, identity: rightIdentity),
                ]
            )
        case .horizontal:
            let (top, bottom) = first.frame.midY <= second.frame.midY
                ? (first, second)
                : (second, first)
            let gap = bottom.frame.minY - top.frame.maxY
            guard abs(gap) <= seamGapTolerance else { return nil }
            let start = max(top.frame.minX, bottom.frame.minX)
            let end = min(top.frame.maxX, bottom.frame.maxX)
            guard end - start >= minSeamOverlap else { return nil }
            guard let topIdentity = uniqueIdentity(in: snapped[top.zone.id]),
                  let bottomIdentity = uniqueIdentity(in: snapped[bottom.zone.id])
            else { return nil }
            return DividerHandleSpec(
                axis: .horizontal,
                afterIndex: afterIndex,
                lineAX: (top.frame.maxY + bottom.frame.minY) / 2,
                spanAX: start...end,
                slots: [
                    DividerHandleSlot(zoneID: top.zone.id, identity: topIdentity),
                    DividerHandleSlot(zoneID: bottom.zone.id, identity: bottomIdentity),
                ]
            )
        }
    }

    static func uniqueIdentity(in windows: [WindowIdentity]?) -> WindowIdentity? {
        guard let windows, windows.count == 1 else { return nil }
        return windows.first
    }

    static func isUsableWindow(_ frame: CGRect) -> Bool {
        frame.width >= 80 && frame.height >= 80
    }

    static func clippedFrame(_ frame: CGRect, to workAreaAX: CGRect?) -> CGRect {
        guard let workAreaAX else { return frame }
        let clipped = frame.intersection(workAreaAX)
        if clipped.isNull || clipped.isInfinite { return .zero }
        return clipped
    }

    /// Catalog-backed occupancy: the window still owns this zone if it covers
    /// most of the zone. Overflow past the zone/screen edge is allowed.
    static func occupiesPreferred(_ actual: CGRect, target: CGRect) -> Bool {
        WindowOrganize.didApply(
            actual,
            to: target,
            sizeTolerance: 64,
            originTolerance: 64
        ) || coversZone(actual, target: target, minimum: 0.62)
    }

    static func coversZone(_ actual: CGRect, target: CGRect, minimum: CGFloat) -> Bool {
        let overlap = actual.intersection(target)
        guard !overlap.isNull, !overlap.isInfinite else { return false }
        let overlapArea = overlap.width * overlap.height
        let zoneArea = max(target.width * target.height, 1)
        return overlapArea / zoneArea >= minimum
    }

    /// Uncatalogued occupancy is stricter: the window must uniquely fill a zone
    /// without spilling too far into a neighbor.
    static func uniqueFilledZone(for frame: CGRect, in resolvedFrames: [UUID: CGRect]) -> UUID? {
        var matches: [UUID] = []
        for (zoneID, target) in resolvedFrames {
            let overlap = frame.intersection(target)
            guard !overlap.isNull, !overlap.isInfinite else { continue }
            let overlapArea = overlap.width * overlap.height
            let windowArea = max(frame.width * frame.height, 1)
            let zoneArea = max(target.width * target.height, 1)
            if overlapArea / windowArea >= 0.78, overlapArea / zoneArea >= 0.70 {
                matches.append(zoneID)
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func contactLine(
        axis: GridAxis,
        zoneIndices: Set<Int>,
        layout: Layout,
        resolvedFrames: [UUID: CGRect]
    ) -> CGFloat? {
        let frames = zoneIndices.compactMap { index -> CGRect? in
            guard layout.zones.indices.contains(index) else { return nil }
            return resolvedFrames[layout.zones[index].id]
        }
        guard frames.count >= 2 else { return nil }
        switch axis {
        case .vertical:
            let left = frames.min(by: { $0.midX < $1.midX })!
            let right = frames.max(by: { $0.midX < $1.midX })!
            let gap = right.minX - left.maxX
            guard abs(gap) <= seamGapTolerance else { return nil }
            return (left.maxX + right.minX) / 2
        case .horizontal:
            let top = frames.min(by: { $0.midY < $1.midY })!
            let bottom = frames.max(by: { $0.midY < $1.midY })!
            let gap = bottom.minY - top.maxY
            guard abs(gap) <= seamGapTolerance else { return nil }
            return (top.maxY + bottom.minY) / 2
        }
    }

    static func verticalOverlap(left: CGRect?, right: CGRect?) -> ClosedRange<CGFloat>? {
        guard let left, let right else { return nil }
        let start = max(left.minY, right.minY)
        let end = min(left.maxY, right.maxY)
        guard end > start else { return nil }
        return start...end
    }

    static func horizontalOverlap(top: CGRect?, bottom: CGRect?) -> ClosedRange<CGFloat>? {
        guard let top, let bottom else { return nil }
        let start = max(top.minX, bottom.minX)
        let end = min(top.maxX, bottom.maxX)
        guard end > start else { return nil }
        return start...end
    }

    static func fallbackSpan(
        for indices: [Int],
        layout: Layout,
        resolvedFrames: [UUID: CGRect],
        axis: GridAxis,
        workAreaAX: CGRect
    ) -> ClosedRange<CGFloat> {
        var start = CGFloat.greatestFiniteMagnitude
        var end = -CGFloat.greatestFiniteMagnitude
        for index in indices where layout.zones.indices.contains(index) {
            guard let frame = resolvedFrames[layout.zones[index].id] else { continue }
            switch axis {
            case .vertical:
                start = min(start, frame.minY)
                end = max(end, frame.maxY)
            case .horizontal:
                start = min(start, frame.minX)
                end = max(end, frame.maxX)
            }
        }
        if start.isFinite, end.isFinite, end > start {
            return start...end
        }
        switch axis {
        case .vertical:
            return workAreaAX.minY...workAreaAX.maxY
        case .horizontal:
            return workAreaAX.minX...workAreaAX.maxX
        }
    }

    static func prefix(_ weights: [Int]) -> [Double] {
        var out = [0.0]
        out.reserveCapacity(weights.count + 1)
        var sum = 0
        for weight in weights {
            sum += weight
            out.append(Double(sum) / Double(GridEditing.weightTotal))
        }
        return out
    }
}
