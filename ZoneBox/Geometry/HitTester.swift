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
    /// clearly entered another zone outside the window. A pointer on the
    /// dragged window itself is not a zone choice. Multi-zone grid spans stay
    /// untouched.
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
              let occupied = Self.occupiedZone(for: windowFrameAX, at: pointAX, in: zones)
        else {
            return cursor
        }
        guard let cursorZone = zone(for: cursor, in: zones) else {
            return cursor == .none ? .zone(occupied) : cursor
        }
        if cursorZone.zoneID == occupied.zoneID {
            return cursor
        }
        if Self.pointerIsOnWindow(pointAX, windowFrameAX: windowFrameAX) {
            return .zone(occupied)
        }
        if ZoneOccupancy.containsInterior(pointAX, zone: cursorZone.frameAX, inset: occupancyStickyInset) {
            return cursor
        }
        return .zone(occupied)
    }

    private static func pointerIsOnWindow(_ pointAX: CGPoint, windowFrameAX: CGRect) -> Bool {
        windowFrameAX.insetBy(dx: -8, dy: -8).contains(pointAX)
    }

    private static func occupiedZone(
        for windowFrameAX: CGRect,
        at pointAX: CGPoint,
        in zones: [ResolvedZone]
    ) -> ResolvedZone? {
        if let filled = ZoneOccupancy.preferredZone(for: windowFrameAX, in: zones) {
            return filled
        }
        guard pointerIsOnWindow(pointAX, windowFrameAX: windowFrameAX) else { return nil }
        return ZoneOccupancy.preferredBelongingZone(for: windowFrameAX, in: zones)
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
