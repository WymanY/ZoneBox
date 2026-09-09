import CoreGraphics

/// Geometry used to decide whether a window currently lives in a zone, and
/// whether a pointer has committed to a different zone strongly enough to
/// leave that occupancy.
public enum ZoneOccupancy {
    public static let fillRatio: CGFloat = 0.62
    public static let seamInset: CGFloat = 24
    public static let applyTolerance: CGFloat = 28

    public static func coverage(_ frame: CGRect, zone: CGRect) -> CGFloat {
        let intersection = frame.intersection(zone)
        guard !intersection.isNull, !intersection.isInfinite else { return 0 }
        let overlap = max(intersection.width, 0) * max(intersection.height, 0)
        let zoneArea = max(zone.width * zone.height, 1)
        return overlap / zoneArea
    }

    /// A window fills a zone when it still covers most of that zone.
    public static func fills(_ frame: CGRect, zone: CGRect) -> Bool {
        coverage(frame, zone: zone) >= fillRatio
    }

    public static func isApplied(_ actual: CGRect, to target: CGRect) -> Bool {
        abs(actual.width - target.width) <= applyTolerance
            && abs(actual.height - target.height) <= applyTolerance
            && abs(actual.minX - target.minX) <= applyTolerance
            && abs(actual.minY - target.minY) <= applyTolerance
    }

    /// Whether a window currently counts as living in a zone: either snapped
    /// there within tolerance or covering most of it.
    public static func occupies(_ frame: CGRect, zone: CGRect) -> Bool {
        fills(frame, zone: zone) || isApplied(frame, to: zone)
    }

    public static func preferredZone(for frame: CGRect, in zones: [ResolvedZone]) -> ResolvedZone? {
        let occupied = zones.compactMap { zone -> (zone: ResolvedZone, coverage: CGFloat, applied: Bool)? in
            guard occupies(frame, zone: zone.frameAX) else { return nil }
            return (
                zone,
                coverage(frame, zone: zone.frameAX),
                isApplied(frame, to: zone.frameAX)
            )
        }
        return occupied.max { lhs, rhs in
            if lhs.applied != rhs.applied { return !lhs.applied && rhs.applied }
            if abs(lhs.coverage - rhs.coverage) > 0.000_001 { return lhs.coverage < rhs.coverage }
            return lhs.zone.number > rhs.zone.number
        }?.zone
    }

    public static func containsInterior(_ point: CGPoint, zone: CGRect, inset: CGFloat = seamInset) -> Bool {
        let dx = min(max(inset, 0), max(zone.width / 4, 0))
        let dy = min(max(inset, 0), max(zone.height / 4, 0))
        return zone.insetBy(dx: dx, dy: dy).contains(point)
    }
}
