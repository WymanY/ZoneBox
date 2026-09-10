import CoreGraphics

public struct HitTester: Sendable {
    public var policy: OverlapPolicy

    public init(policy: OverlapPolicy = .smallestArea) {
        self.policy = policy
    }

    public func target(at pointAX: CGPoint, zones: [ResolvedZone]) -> SnapTarget {
        target(at: pointAX, zones: zones, windowFrameAX: nil)
    }

    public func target(
        at pointAX: CGPoint,
        zones: [ResolvedZone],
        windowFrameAX: CGRect?,
        occupancyStickyInset: CGFloat = ZoneOccupancy.seamInset
    ) -> SnapTarget {
        preferringOccupancy(
            cursorTarget(at: pointAX, zones: zones),
            at: pointAX,
            windowFrameAX: windowFrameAX,
            zones: zones,
            occupancyStickyInset: occupancyStickyInset
        )
    }

    /// Keep a window that already occupies a zone unless the pointer has
    /// clearly entered another zone away from the window. A pointer on or just
    /// above the dragged window is not a zone choice; the overlay follows
    /// where most of the window sits. Multi-zone grid spans stay untouched.
    public func preferringOccupancy(
        _ cursor: SnapTarget,
        at pointAX: CGPoint,
        windowFrameAX: CGRect?,
        zones: [ResolvedZone],
        occupancyStickyInset: CGFloat = ZoneOccupancy.seamInset
    ) -> SnapTarget {
        if case .span(_, let ids) = cursor, Set(ids).count > 1 {
            return cursor
        }
        guard let windowFrameAX,
              let occupied = occupiedZone(for: windowFrameAX, at: pointAX, in: zones)
        else {
            return cursor
        }
        guard let cursorZone = zone(for: cursor, in: zones) else {
            return cursor == .none ? .zone(occupied) : cursor
        }
        if cursorZone.zoneID == occupied.zoneID {
            return cursor
        }
        if Self.pointerIsNearWindow(pointAX, windowFrameAX: windowFrameAX) {
            return .zone(occupied)
        }
        if ZoneOccupancy.containsInterior(pointAX, zone: cursorZone.frameAX, inset: occupancyStickyInset) {
            return cursor
        }
        return .zone(occupied)
    }

    private static let windowInfluenceOutset: CGFloat = 72

    private static func pointerIsNearWindow(_ pointAX: CGPoint, windowFrameAX: CGRect) -> Bool {
        windowFrameAX.insetBy(dx: -windowInfluenceOutset, dy: -windowInfluenceOutset).contains(pointAX)
    }

    private func occupiedZone(
        for windowFrameAX: CGRect,
        at pointAX: CGPoint,
        in zones: [ResolvedZone]
    ) -> ResolvedZone? {
        let nearWindow = Self.pointerIsNearWindow(pointAX, windowFrameAX: windowFrameAX)
        // Containment of the window beats how much of a zone the window covers.
        // A small window can sit entirely in pane 2 while covering little of
        // pane 2 and a large fraction of a neighboring pane.
        if nearWindow, let belonging = ZoneOccupancy.preferredBelongingZone(
            for: windowFrameAX,
            in: zones,
            policy: policy,
            pointAX: pointAX
        ) {
            return belonging
        }
        if let filled = ZoneOccupancy.preferredZone(for: windowFrameAX, in: zones) {
            return filled
        }
        return nil
    }

    private func zone(for target: SnapTarget, in zones: [ResolvedZone]) -> ResolvedZone? {
        switch target {
        case .none:
            return nil
        case .zone(let zone):
            return zones.first(where: { $0.zoneID == zone.zoneID }) ?? zone
        case .span(_, let ids):
            guard ids.count == 1, let id = ids.first else { return nil }
            return zones.first(where: { $0.zoneID == id })
        }
    }

    private func cursorTarget(at pointAX: CGPoint, zones: [ResolvedZone]) -> SnapTarget {
        let hits = zones.filter { $0.frameAX.contains(pointAX) }
        let chosen: ResolvedZone?
        switch policy {
        case .smallestArea:
            chosen = hits.min(by: { area($0) < area($1) })
        case .largestArea:
            chosen = hits.max(by: { area($0) < area($1) })
        case .closestCenterToCursor:
            chosen = hits.min(by: { centerDistance($0, to: pointAX) < centerDistance($1, to: pointAX) })
        }
        guard let chosen else { return .none }
        return .zone(chosen)
    }

    private func area(_ zone: ResolvedZone) -> CGFloat {
        zone.frameAX.width * zone.frameAX.height
    }

    private func centerDistance(_ zone: ResolvedZone, to pointAX: CGPoint) -> CGFloat {
        hypot(zone.frameAX.midX - pointAX.x, zone.frameAX.midY - pointAX.y)
    }
}
