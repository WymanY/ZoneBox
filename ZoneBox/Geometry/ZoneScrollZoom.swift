import CoreGraphics

/// Editor scroll-zoom axis selection from the scroll gesture itself.
///
/// Vertical motion scales height; horizontal motion scales width. Trackpads leak
/// a small orthogonal delta, so the dominant axis has to win by a clear margin
/// instead of treating every non-zero `deltaX` as a width change.
public enum ZoneScrollZoom: Sendable {
    public enum Axes: Equatable, Sendable {
        case height
        case width
    }

    public static func axes(deltaX: CGFloat, deltaY: CGFloat) -> Axes? {
        let x = abs(deltaX)
        let y = abs(deltaY)
        if x < 0.01 && y < 0.01 { return nil }
        if x > y * 1.35 { return .width }
        if y >= x { return .height }
        return nil
    }
}
