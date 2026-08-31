import CoreGraphics

public enum PinBadgeSlot {
    public static let titleBarHeight: CGFloat = 36
    public static let minimumHoverWindowWidth: CGFloat = 120
    /// Sit just below the title-bar controls so Share / toolbar actions stay clickable.
    public static let belowControlsGap: CGFloat = 4

    public static func rect(
        windowFrameAX: CGRect,
        size: CGFloat,
        inset: CGFloat = 8
    ) -> CGRect {
        let bandHeight = min(titleBarHeight, max(windowFrameAX.height, 0))
        let preferredY = windowFrameAX.minY + bandHeight + belowControlsGap
        let maxY = max(windowFrameAX.maxY - size, windowFrameAX.minY)
        return CGRect(
            x: windowFrameAX.maxX - inset - size,
            y: min(preferredY, maxY),
            width: size,
            height: size
        )
    }

    public static func hoverButtonRect(
        windowFrameAX: CGRect,
        size: CGFloat = 24,
        inset: CGFloat = 8
    ) -> CGRect? {
        guard windowFrameAX.width >= minimumHoverWindowWidth else { return nil }
        return rect(windowFrameAX: windowFrameAX, size: size, inset: inset)
    }
}
