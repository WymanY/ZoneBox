/// Editor scroll-zoom axis selection.
///
/// Trackpads leak a horizontal `scrollingDeltaX` on vertical swipes (and the
/// reverse). Axis choice is therefore modifiers-only — never the deltas.
public enum ZoneScrollZoom: Sendable {
    public enum Axes: Equatable, Sendable {
        case height
        case width
        case both
    }

    public static func axes(option: Bool, shift: Bool) -> Axes {
        if option { return .both }
        if shift { return .width }
        return .height
    }
}
