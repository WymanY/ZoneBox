import CoreGraphics

public enum CoordinateConverter {
    /// AppKit `frame.maxY` of the origin-zero screen. Never `NSScreen.main`, never max of all maxY.
    public static func primaryFlipHeight(screenFramesAppKit: [CGRect]) -> CGFloat {
        screenFramesAppKit.first(where: { $0.origin == .zero })?.maxY
            ?? screenFramesAppKit.first?.maxY
            ?? 0
    }

    public static func axPoint(fromAppKit p: CGPoint, primaryFlipHeight h: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: h - p.y)
    }

    public static func axRect(fromAppKit r: CGRect, primaryFlipHeight h: CGFloat) -> CGRect {
        CGRect(x: r.origin.x, y: h - r.origin.y - r.height, width: r.width, height: r.height)
    }

    public static func appKitPoint(fromAX p: CGPoint, primaryFlipHeight h: CGFloat) -> CGPoint {
        axPoint(fromAppKit: p, primaryFlipHeight: h)
    }

    public static func appKitRect(fromAX r: CGRect, primaryFlipHeight h: CGFloat) -> CGRect {
        axRect(fromAppKit: r, primaryFlipHeight: h)
    }
}
