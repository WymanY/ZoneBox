import CoreGraphics

public enum Gutter {
    /// Shared-edge gap: neighboring zones each give up `gutter / 2` on the
    /// shared side, so the visible space between windows is `gutter`.
    /// Outer edges that already sit on the work-area boundary stay flush.
    public static func apply(_ rect: CGRect, gutter: CGFloat, workAreaAX: CGRect) -> CGRect {
        apply([rect], gutter: gutter, workAreaAX: workAreaAX).first ?? .null
    }

    public static func apply(_ rects: [CGRect], gutter: CGFloat, workAreaAX: CGRect) -> [CGRect] {
        guard gutter != 0, !rects.isEmpty else {
            return rects.map { $0.intersection(workAreaAX) }
        }

        let half = gutter / 2
        let epsilon: CGFloat = 0.75
        return rects.map { raw in
            let rect = raw.standardized
            let left = abs(rect.minX - workAreaAX.minX) <= epsilon ? 0 : half
            let right = abs(rect.maxX - workAreaAX.maxX) <= epsilon ? 0 : half
            let top = abs(rect.minY - workAreaAX.minY) <= epsilon ? 0 : half
            let bottom = abs(rect.maxY - workAreaAX.maxY) <= epsilon ? 0 : half
            let insetted = CGRect(
                x: rect.minX + left,
                y: rect.minY + top,
                width: max(0, rect.width - left - right),
                height: max(0, rect.height - top - bottom)
            )
            return insetted.intersection(workAreaAX)
        }
    }
}
