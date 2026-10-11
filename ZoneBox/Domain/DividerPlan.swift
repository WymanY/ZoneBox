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

public struct DividerMinSizeStop: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public var identity: WindowIdentity
        public var limit: CGFloat
        /// True only when the completed AX frame itself shows how far the
        /// window refused to shrink. A learned clamp without that frame is
        /// not an exact intrinsic size.
        public var observed: Bool

        public init(identity: WindowIdentity, limit: CGFloat, observed: Bool = true) {
            self.identity = identity
            self.limit = limit
            self.observed = observed
        }
    }

    public var axis: GridAxis
    public var windows: [Window]

    public init(axis: GridAxis, windows: [Window]) {
        self.axis = axis
        self.windows = windows
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
            guard let zoneID = uniqueFilledZone(for: window.frameAX, in: resolvedFrames) else { continue }
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

    public static func observingMinSize(
        _ minSizes: [UUID: CGSize],
        zoneID: UUID,
        requested: CGRect,
        actual: CGRect,
        axis: GridAxis,
        tolerance: CGFloat = AXFrameMutation.successTolerance
    ) -> [UUID: CGSize] {
        var next = minSizes
        var size = next[zoneID] ?? .zero
        switch axis {
        case .vertical:
            guard actual.width > requested.width + tolerance else { return minSizes }
            size.width = max(size.width, actual.width)
        case .horizontal:
            guard actual.height > requested.height + tolerance else { return minSizes }
            size.height = max(size.height, actual.height)
        }
        next[zoneID] = size
        return next
    }

    /// Explains a stopped divider only when a completed AX write refused to
    /// shrink and that refusal is what held the seam. A missing write, a write
    /// that matched the request, or a pointer that never reached the learned
    /// bound is not evidence of a minimum size.
    ///
    /// `requestedLayout` must be the pointer's raw line, not a layout already
    /// clamped to a learned minimum. `refusals` are completed writes whose
    /// actual frame stayed larger than the frame that write asked for.
    public static func minSizeStop(
        handle: DividerHandleSpec,
        requestedLayout: Layout,
        appliedLayout: Layout,
        requestedFrames: [UUID: CGRect],
        actualFrames: [UUID: CGRect],
        workAreaAX: CGRect,
        gutter: CGFloat,
        tolerance: CGFloat = AXFrameMutation.successTolerance
    ) -> DividerMinSizeStop? {
        let refusals = Dictionary(uniqueKeysWithValues: handle.slots.compactMap { slot -> (UUID, CGSize)? in
            guard let requested = requestedFrames[slot.zoneID],
                  let actual = actualFrames[slot.zoneID]
            else { return nil }
            let observed = observingMinSize(
                [:],
                zoneID: slot.zoneID,
                requested: requested,
                actual: actual,
                axis: handle.axis,
                tolerance: tolerance
            )
            guard let learned = observed[slot.zoneID] else { return nil }
            return (slot.zoneID, learned)
        })
        return minSizeStop(
            handle: handle,
            requestedLayout: requestedLayout,
            appliedLayout: appliedLayout,
            refusals: refusals,
            workAreaAX: workAreaAX,
            gutter: gutter,
            tolerance: tolerance
        )
    }

    public static func minSizeStop(
        handle: DividerHandleSpec,
        requestedLayout: Layout,
        appliedLayout: Layout,
        refusals: [UUID: CGSize],
        workAreaAX: CGRect,
        gutter: CGFloat,
        tolerance: CGFloat = AXFrameMutation.successTolerance
    ) -> DividerMinSizeStop? {
        guard geometryChanged(from: requestedLayout, to: appliedLayout),
              let requestedLine = normalizedLine(of: handle, in: requestedLayout, workAreaAX: workAreaAX),
              let appliedLine = normalizedLine(of: handle, in: appliedLayout, workAreaAX: workAreaAX),
              abs(requestedLine - appliedLine) > 0.000_001
        else { return nil }

        let movingTowardTrailing = requestedLine > appliedLine
        var blocked: [DividerMinSizeStop.Window] = []
        for slot in handle.slots {
            guard let learned = refusals[slot.zoneID] else { continue }
            let shrinking = movingTowardTrailing == slotIsTrailing(slot, handle: handle, layout: appliedLayout)
            let limit: CGFloat
            switch handle.axis {
            case .vertical:
                limit = learned.width
            case .horizontal:
                limit = learned.height
            }
            guard shrinking, limit > tolerance else { continue }
            guard let unconstrained = movedLayout(appliedLayout, handle: handle, toNormalized: requestedLine),
                  !satisfiesMinSizes(
                    unconstrained,
                    handle: handle,
                    workAreaAX: workAreaAX,
                    gutter: gutter,
                    minSizes: [slot.zoneID: learned]
                  )
            else { continue }
            blocked.append(DividerMinSizeStop.Window(identity: slot.identity, limit: limit, observed: true))
        }
        guard !blocked.isEmpty else { return nil }
        return DividerMinSizeStop(axis: handle.axis, windows: blocked)
    }

    /// Keeps a completed shrink refusal only while the pointer is still past
    /// the seam that refusal is holding. Backing away from that seam drops
    /// the evidence so a later release does not explain a stop the user left.
    public static func retainedMinSizeRefusals(
        _ refusals: [UUID: CGSize],
        handle: DividerHandleSpec,
        pointerLayout: Layout?,
        appliedLayout: Layout,
        workAreaAX: CGRect
    ) -> [UUID: CGSize] {
        guard let pointerLayout,
              let pointerLine = normalizedLine(of: handle, in: pointerLayout, workAreaAX: workAreaAX),
              let appliedLine = normalizedLine(of: handle, in: appliedLayout, workAreaAX: workAreaAX),
              abs(pointerLine - appliedLine) > 0.000_001
        else { return [:] }
        let pushingPast = pointerLine > appliedLine
        var kept: [UUID: CGSize] = [:]
        for slot in handle.slots {
            guard let refusal = refusals[slot.zoneID] else { continue }
            let trailing = slotIsTrailing(slot, handle: handle, layout: appliedLayout)
            let stillPushingInto = pushingPast == trailing
            if stillPushingInto {
                kept[slot.zoneID] = refusal
            }
        }
        return kept
    }

    public static func mergingMinSize(
        _ minSizes: [UUID: CGSize],
        zoneID: UUID,
        minSize: CGSize
    ) -> [UUID: CGSize] {
        var next = minSizes
        let current = next[zoneID] ?? .zero
        next[zoneID] = CGSize(
            width: max(current.width, minSize.width),
            height: max(current.height, minSize.height)
        )
        return next
    }

    public static func normalizedLine(
        of handle: DividerHandleSpec,
        in layout: Layout,
        workAreaAX: CGRect
    ) -> Double? {
        if layout.kind == .grid, let spec = layout.grid {
            switch handle.axis {
            case .vertical:
                let marks = prefix(spec.columnWeights)
                guard handle.afterIndex + 1 < marks.count else { return nil }
                return marks[handle.afterIndex + 1]
            case .horizontal:
                let marks = prefix(spec.rowWeights)
                guard handle.afterIndex + 1 < marks.count else { return nil }
                return marks[handle.afterIndex + 1]
            }
        }
        guard handle.slots.count >= 2,
              let first = layout.zones.first(where: { $0.id == handle.slots[0].zoneID })?.canvasRect,
              let second = layout.zones.first(where: { $0.id == handle.slots[1].zoneID })?.canvasRect
        else { return nil }
        switch handle.axis {
        case .vertical:
            let left = first.midX <= second.midX ? first : second
            return left.x + left.width
        case .horizontal:
            let top = first.midY <= second.midY ? first : second
            return top.y + top.height
        }
    }

    public static func clampedMovedLayout(
        _ layout: Layout,
        handle: DividerHandleSpec,
        toNormalized t: Double,
        workAreaAX: CGRect,
        gutter: CGFloat,
        minSizes: [UUID: CGSize]
    ) -> Layout? {
        let requested = movedLayout(layout, handle: handle, toNormalized: t)
        if minSizes.isEmpty { return requested }
        if let requested, satisfiesMinSizes(
            requested,
            handle: handle,
            workAreaAX: workAreaAX,
            gutter: gutter,
            minSizes: minSizes
        ) {
            return requested
        }

        guard let originT = normalizedLine(of: handle, in: layout, workAreaAX: workAreaAX) else {
            return requested
        }
        let originLayout = movedLayout(layout, handle: handle, toNormalized: originT) ?? layout
        if !satisfiesMinSizes(
            originLayout,
            handle: handle,
            workAreaAX: workAreaAX,
            gutter: gutter,
            minSizes: minSizes
        ) {
            return layoutPastInvalidBase(
                layout,
                handle: handle,
                requestedT: t,
                fallback: originLayout,
                workAreaAX: workAreaAX,
                gutter: gutter,
                minSizes: minSizes
            )
        }
        let movingTowardTrailing = t >= originT
        var low = min(originT, t)
        var high = max(originT, t)
        var best = originLayout
        for _ in 0..<40 {
            let mid = (low + high) / 2
            guard let candidate = movedLayout(layout, handle: handle, toNormalized: mid) else {
                if movingTowardTrailing {
                    high = mid
                } else {
                    low = mid
                }
                continue
            }
            if satisfiesMinSizes(
                candidate,
                handle: handle,
                workAreaAX: workAreaAX,
                gutter: gutter,
                minSizes: minSizes
            ) {
                best = candidate
                if movingTowardTrailing {
                    low = mid
                } else {
                    high = mid
                }
            } else if movingTowardTrailing {
                high = mid
            } else {
                low = mid
            }
        }
        return best
    }

    /// The base seam itself misses a learned minimum, so the feasible interval
    /// may sit past that seam. Leading and trailing limits are each monotonic
    /// inside the adjacent track (or canvas pair); their overlap is the only
    /// legal correction. An empty overlap keeps the existing base fallback.
    private static func layoutPastInvalidBase(
        _ layout: Layout,
        handle: DividerHandleSpec,
        requestedT: Double,
        fallback: Layout,
        workAreaAX: CGRect,
        gutter: CGFloat,
        minSizes: [UUID: CGSize]
    ) -> Layout {
        guard let domain = movableSeamDomain(layout, handle: handle) else { return fallback }
        guard let lower = lowestSeam(in: domain, layout: layout, handle: handle, meets: { candidate in
            sideMeetsMinimum(
                candidate,
                handle: handle,
                workAreaAX: workAreaAX,
                gutter: gutter,
                minSizes: minSizes,
                trailing: false
            )
        }),
        let upper = highestSeam(in: domain, layout: layout, handle: handle, meets: { candidate in
            sideMeetsMinimum(
                candidate,
                handle: handle,
                workAreaAX: workAreaAX,
                gutter: gutter,
                minSizes: minSizes,
                trailing: true
            )
        }),
        lower <= upper + 0.000_001
        else { return fallback }

        let target = min(max(requestedT, lower), upper)
        guard let corrected = movedLayout(layout, handle: handle, toNormalized: target),
              satisfiesMinSizes(
                corrected,
                handle: handle,
                workAreaAX: workAreaAX,
                gutter: gutter,
                minSizes: minSizes
              )
        else { return fallback }
        return corrected
    }

    public static func clamping(
        _ pending: Layout,
        toHandle handle: DividerHandleSpec,
        from base: Layout,
        workAreaAX: CGRect,
        gutter: CGFloat,
        minSizes: [UUID: CGSize]
    ) -> Layout {
        guard let t = normalizedLine(of: handle, in: pending, workAreaAX: workAreaAX) else {
            return pending
        }
        return clampedMovedLayout(
            base,
            handle: handle,
            toNormalized: t,
            workAreaAX: workAreaAX,
            gutter: gutter,
            minSizes: minSizes
        ) ?? pending
    }

    public static func layoutMatchingActualFrames(
        _ layout: Layout,
        handle: DividerHandleSpec,
        actualFrames: [UUID: CGRect],
        workAreaAX: CGRect
    ) -> Layout? {
        guard let sides = partitionedActualFrames(
            handle: handle,
            layout: layout,
            actualFrames: actualFrames,
            workAreaAX: workAreaAX
        ) else { return nil }
        let line: CGFloat
        switch handle.axis {
        case .vertical:
            let leftEdge = sides.leading.map(\.maxX).max() ?? 0
            let rightEdge = sides.trailing.map(\.minX).min() ?? 0
            let gap = rightEdge - leftEdge
            guard abs(gap) <= seamGapTolerance else { return nil }
            line = (leftEdge + rightEdge) / 2
        case .horizontal:
            let topEdge = sides.leading.map(\.maxY).max() ?? 0
            let bottomEdge = sides.trailing.map(\.minY).min() ?? 0
            let gap = bottomEdge - topEdge
            guard abs(gap) <= seamGapTolerance else { return nil }
            line = (topEdge + bottomEdge) / 2
        }
        let point: CGPoint
        switch handle.axis {
        case .vertical:
            point = CGPoint(x: line, y: workAreaAX.midY)
        case .horizontal:
            point = CGPoint(x: workAreaAX.midX, y: line)
        }
        guard let t = normalizedPosition(of: point, axis: handle.axis, in: workAreaAX) else {
            return nil
        }
        return movedLayout(layout, handle: handle, toNormalized: t)
    }
}

private extension DividerPlan {
    static func movableSeamDomain(_ layout: Layout, handle: DividerHandleSpec) -> ClosedRange<Double>? {
        if layout.kind == .grid, let spec = layout.grid {
            let weights = handle.axis == .vertical ? spec.columnWeights : spec.rowWeights
            guard handle.afterIndex >= 0, handle.afterIndex + 1 < weights.count else { return nil }
            let start = prefix(weights)[handle.afterIndex]
            let pairSum = weights[handle.afterIndex] + weights[handle.afterIndex + 1]
            let unit = Double(GridEditing.weightTotal)
            let lower = start + Double(GridEditing.minWeight) / unit
            let upper = start + Double(pairSum - GridEditing.minWeight) / unit
            guard upper > lower else { return nil }
            return lower...upper
        }
        guard handle.slots.count >= 2,
              let first = layout.zones.first(where: { $0.id == handle.slots[0].zoneID })?.canvasRect,
              let second = layout.zones.first(where: { $0.id == handle.slots[1].zoneID })?.canvasRect
        else { return nil }
        let minimum = ZoneSplit.minSize
        switch handle.axis {
        case .vertical:
            let left = first.midX <= second.midX ? first : second
            let right = left.midX == first.midX ? second : first
            let lower = Double(left.x) + minimum
            let upper = Double(right.x + right.width) - minimum
            guard upper > lower else { return nil }
            return lower...upper
        case .horizontal:
            let top = first.midY <= second.midY ? first : second
            let bottom = top.midY == first.midY ? second : first
            let lower = Double(top.y) + minimum
            let upper = Double(bottom.y + bottom.height) - minimum
            guard upper > lower else { return nil }
            return lower...upper
        }
    }

    static func sideMeetsMinimum(
        _ layout: Layout,
        handle: DividerHandleSpec,
        workAreaAX: CGRect,
        gutter: CGFloat,
        minSizes: [UUID: CGSize],
        trailing: Bool
    ) -> Bool {
        let resolved = (try? resolveLayout(layout, workAreaAX: workAreaAX, gutter: gutter)) ?? []
        let frames = Dictionary(uniqueKeysWithValues: resolved.map { ($0.zoneID, $0.frameAX) })
        for slot in handle.slots {
            guard slotIsTrailing(slot, handle: handle, layout: layout) == trailing else { continue }
            guard let minSize = minSizes[slot.zoneID], let frame = frames[slot.zoneID] else { continue }
            switch handle.axis {
            case .vertical:
                if minSize.width > 0, frame.width + 0.5 < minSize.width { return false }
            case .horizontal:
                if minSize.height > 0, frame.height + 0.5 < minSize.height { return false }
            }
        }
        return true
    }

    static func lowestSeam(
        in domain: ClosedRange<Double>,
        layout: Layout,
        handle: DividerHandleSpec,
        meets: (Layout) -> Bool
    ) -> Double? {
        func ok(_ seam: Double) -> Bool {
            guard let candidate = movedLayout(layout, handle: handle, toNormalized: seam) else { return false }
            return meets(candidate)
        }
        guard ok(domain.upperBound) else { return nil }
        if ok(domain.lowerBound) { return domain.lowerBound }
        var low = domain.lowerBound
        var high = domain.upperBound
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if ok(mid) {
                high = mid
            } else {
                low = mid
            }
        }
        return high
    }

    static func highestSeam(
        in domain: ClosedRange<Double>,
        layout: Layout,
        handle: DividerHandleSpec,
        meets: (Layout) -> Bool
    ) -> Double? {
        func ok(_ seam: Double) -> Bool {
            guard let candidate = movedLayout(layout, handle: handle, toNormalized: seam) else { return false }
            return meets(candidate)
        }
        guard ok(domain.lowerBound) else { return nil }
        if ok(domain.upperBound) { return domain.upperBound }
        var low = domain.lowerBound
        var high = domain.upperBound
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if ok(mid) {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }

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

    static func partitionedActualFrames(
        handle: DividerHandleSpec,
        layout: Layout,
        actualFrames: [UUID: CGRect],
        workAreaAX: CGRect
    ) -> (leading: [CGRect], trailing: [CGRect])? {
        guard let t = normalizedLine(of: handle, in: layout, workAreaAX: workAreaAX) else {
            return nil
        }
        let seam: CGFloat
        switch handle.axis {
        case .vertical:
            seam = workAreaAX.minX + CGFloat(t) * workAreaAX.width
        case .horizontal:
            seam = workAreaAX.minY + CGFloat(t) * workAreaAX.height
        }
        var leading: [CGRect] = []
        var trailing: [CGRect] = []
        for slot in handle.slots {
            guard let frame = actualFrames[slot.zoneID] else { continue }
            switch handle.axis {
            case .vertical:
                if frame.midX <= seam {
                    leading.append(frame)
                } else {
                    trailing.append(frame)
                }
            case .horizontal:
                if frame.midY <= seam {
                    leading.append(frame)
                } else {
                    trailing.append(frame)
                }
            }
        }
        guard !leading.isEmpty, !trailing.isEmpty else { return nil }
        return (leading, trailing)
    }

    static func satisfiesMinSizes(
        _ layout: Layout,
        handle: DividerHandleSpec,
        workAreaAX: CGRect,
        gutter: CGFloat,
        minSizes: [UUID: CGSize]
    ) -> Bool {
        let resolved = (try? resolveLayout(layout, workAreaAX: workAreaAX, gutter: gutter)) ?? []
        let frames = Dictionary(uniqueKeysWithValues: resolved.map { ($0.zoneID, $0.frameAX) })
        for slot in handle.slots {
            guard let minSize = minSizes[slot.zoneID], let frame = frames[slot.zoneID] else { continue }
            switch handle.axis {
            case .vertical:
                if minSize.width > 0, frame.width + 0.5 < minSize.width {
                    return false
                }
            case .horizontal:
                if minSize.height > 0, frame.height + 0.5 < minSize.height {
                    return false
                }
            }
        }
        return true
    }

    static func slotIsTrailing(
        _ slot: DividerHandleSlot,
        handle: DividerHandleSpec,
        layout: Layout
    ) -> Bool {
        if layout.kind == .grid, let spec = layout.grid,
           let zoneIndex = layout.zones.firstIndex(where: { $0.id == slot.zoneID }) {
            return gridSlotIsTrailing(zoneIndex: zoneIndex, handle: handle, spec: spec)
        }
        guard let rect = layout.zones.first(where: { $0.id == slot.zoneID })?.canvasRect else {
            return false
        }
        let others = handle.slots.compactMap { other -> NormalizedRect? in
            guard other.zoneID != slot.zoneID else { return nil }
            return layout.zones.first(where: { $0.id == other.zoneID })?.canvasRect
        }
        guard !others.isEmpty else { return false }
        switch handle.axis {
        case .vertical:
            let neighbor = others.map(\.midX).reduce(0, +) / CGFloat(others.count)
            return rect.midX > neighbor
        case .horizontal:
            let neighbor = others.map(\.midY).reduce(0, +) / CGFloat(others.count)
            return rect.midY > neighbor
        }
    }

    /// Grid zones have no canvas rect. A slot is trailing only when every cell
    /// of that zone sits strictly past this seam, so a merged zone that also
    /// occupies the leading side is not treated as the window being shrunk.
    static func gridSlotIsTrailing(
        zoneIndex: Int,
        handle: DividerHandleSpec,
        spec: GridSpec
    ) -> Bool {
        var matched = 0
        var pastSeam = 0
        for row in 0..<spec.rows {
            for column in 0..<spec.columns where spec.cellMap[row][column] == zoneIndex {
                matched += 1
                switch handle.axis {
                case .vertical:
                    if column > handle.afterIndex { pastSeam += 1 }
                case .horizontal:
                    if row > handle.afterIndex { pastSeam += 1 }
                }
            }
        }
        return matched > 0 && pastSeam == matched
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
