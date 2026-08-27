import CoreGraphics

public enum RectMath {
    public static func chebyshev(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        max(abs(a.x - b.x), abs(a.y - b.y))
    }

    public static func chebyshevSize(_ a: CGSize, _ b: CGSize) -> CGFloat {
        max(abs(a.width - b.width), abs(a.height - b.height))
    }
}
