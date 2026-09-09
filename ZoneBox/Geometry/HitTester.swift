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
        let cursor = cursorTarget(at: pointAX, zones: zones)
        guard let windowFrameAX,
              let occupied = ZoneOccupancy.preferredZone(for: windowFrameAX, in: zones)
        else {
            return cursor
        }
        switch cursor {
        case .none:
            return .zone(occupied)
        case .zone(let zone) where zone.zoneID == occupied.zoneID:
            return .zone(occupied)
        case .zone(let zone):
            if ZoneOccupancy.containsInterior(pointAX, zone: zone.frameAX, inset: occupancyStickyInset) {
                return .zone(zone)
            }
            return .zone(occupied)
        case .span:
            return cursor
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
