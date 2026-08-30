import CoreGraphics

public enum Gutter {
    /// Shared-edge gap: neighboring zones each give up `gutter / 2` on the
    /// shared side, so the visible space between windows is `gutter`.
    /// Outer edges and edges with no aligned neighbor stay flush.
    public static func apply(_ rect: CGRect, gutter: CGFloat, workAreaAX: CGRect) -> CGRect {
        apply([rect], gutter: gutter, workAreaAX: workAreaAX).first ?? .null
    }

    public static func apply(_ rects: [CGRect], gutter: CGFloat, workAreaAX: CGRect) -> [CGRect] {
        let clipped = rects.map { $0.standardized.intersection(workAreaAX) }
        guard gutter != 0, clipped.count > 1 else { return clipped }

        let half = gutter / 2
        let epsilon: CGFloat = 0.75
        return clipped.enumerated().map { index, rect in
            var left: CGFloat = 0
            var right: CGFloat = 0
            var top: CGFloat = 0
            var bottom: CGFloat = 0
            for otherIndex in clipped.indices where otherIndex != index {
                let other = clipped[otherIndex]
                if sharesVertical(rect, other, epsilon: epsilon) {
                    if abs(rect.maxX - other.minX) <= epsilon { right = half }
                    if abs(rect.minX - other.maxX) <= epsilon { left = half }
                }
                if sharesHorizontal(rect, other, epsilon: epsilon) {
                    if abs(rect.maxY - other.minY) <= epsilon { bottom = half }
                    if abs(rect.minY - other.maxY) <= epsilon { top = half }
                }
            }
            let insetted = CGRect(
                x: rect.minX + left,
                y: rect.minY + top,
                width: max(0, rect.width - left - right),
                height: max(0, rect.height - top - bottom)
            )
            return insetted.intersection(workAreaAX)
        }
    }

    private static func sharesVertical(_ a: CGRect, _ b: CGRect, epsilon: CGFloat) -> Bool {
        overlap(a.minY, a.maxY, b.minY, b.maxY, epsilon: epsilon)
    }

    private static func sharesHorizontal(_ a: CGRect, _ b: CGRect, epsilon: CGFloat) -> Bool {
        overlap(a.minX, a.maxX, b.minX, b.maxX, epsilon: epsilon)
    }

    private static func overlap(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat, epsilon: CGFloat) -> Bool {
        min(a1, b1) - max(a0, b0) > epsilon
    }
}
