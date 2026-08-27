import CoreGraphics

public enum Gutter {
    public static func apply(_ rect: CGRect, gutter: CGFloat, workAreaAX: CGRect) -> CGRect {
        rect.insetBy(dx: gutter, dy: gutter).intersection(workAreaAX)
    }
}
