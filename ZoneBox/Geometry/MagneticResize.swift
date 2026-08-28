import CoreGraphics

/// Snaps dragged window edges to nearby zone edges while a window is resized.
public enum MagneticResize {
    public static let defaultThreshold: CGFloat = 12
    public static let edgeEpsilon: CGFloat = 2
    public static let minimumSize: CGFloat = 40

    public static func snap(
        original: CGRect,
        current: CGRect,
        zoneFramesAX: [CGRect],
        threshold: CGFloat = defaultThreshold,
        workAreaAX: CGRect? = nil
    ) -> CGRect {
        var result = current
        let vertical = zoneFramesAX.flatMap { [$0.minX, $0.maxX] }
        let horizontal = zoneFramesAX.flatMap { [$0.minY, $0.maxY] }

        if abs(current.minX - original.minX) > edgeEpsilon,
           let snapped = nearest(current.minX, candidates: vertical, threshold: threshold)
        {
            let maxX = result.maxX
            if maxX - snapped >= minimumSize {
                result.origin.x = snapped
                result.size.width = maxX - snapped
            }
        }
        if abs(current.maxX - original.maxX) > edgeEpsilon,
           let snapped = nearest(current.maxX, candidates: vertical, threshold: threshold)
        {
            if snapped - result.minX >= minimumSize {
                result.size.width = snapped - result.minX
            }
        }
        if abs(current.minY - original.minY) > edgeEpsilon,
           let snapped = nearest(current.minY, candidates: horizontal, threshold: threshold)
        {
            let maxY = result.maxY
            if maxY - snapped >= minimumSize {
                result.origin.y = snapped
                result.size.height = maxY - snapped
            }
        }
        if abs(current.maxY - original.maxY) > edgeEpsilon,
           let snapped = nearest(current.maxY, candidates: horizontal, threshold: threshold)
        {
            if snapped - result.minY >= minimumSize {
                result.size.height = snapped - result.minY
            }
        }

        if let work = workAreaAX, !work.isNull, work.width > 0, work.height > 0 {
            result = result.intersection(work)
        }
        return result
    }

    private static func nearest(_ value: CGFloat, candidates: [CGFloat], threshold: CGFloat) -> CGFloat? {
        guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }) else { return nil }
        return abs(best - value) <= threshold ? best : nil
    }
}
