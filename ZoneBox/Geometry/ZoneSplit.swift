/// Shared-edge resize, like the system Split View divider.
public enum ZoneSplit {
    public static let minSize: Double = 0.05

    /// Move the vertical seam between a left zone and a right zone. Outer edges stay put.
    public static func movingVerticalSeam(
        left: NormalizedRect,
        right: NormalizedRect,
        to seamX: Double,
        minWidth: Double = minSize
    ) -> (left: NormalizedRect, right: NormalizedRect) {
        let rightMax = right.x + right.width
        let x = min(max(seamX, left.x + minWidth), rightMax - minWidth)
        var nextLeft = left
        nextLeft.width = x - left.x
        var nextRight = right
        nextRight.x = x
        nextRight.width = rightMax - x
        return (nextLeft, nextRight)
    }

    /// Move the horizontal seam between a top zone and a bottom zone (`y` grows downward).
    public static func movingHorizontalSeam(
        top: NormalizedRect,
        bottom: NormalizedRect,
        to seamY: Double,
        minHeight: Double = minSize
    ) -> (top: NormalizedRect, bottom: NormalizedRect) {
        let bottomMax = bottom.y + bottom.height
        let y = min(max(seamY, top.y + minHeight), bottomMax - minHeight)
        var nextTop = top
        nextTop.height = y - top.y
        var nextBottom = bottom
        nextBottom.y = y
        nextBottom.height = bottomMax - y
        return (nextTop, nextBottom)
    }
}
