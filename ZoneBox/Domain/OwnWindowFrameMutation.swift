import CoreGraphics

public enum OwnWindowFrameMutation: Sendable {
    public static func usesMainThreadAppKit(pid: pid_t, ownPID: pid_t) -> Bool {
        pid == ownPID
    }

    public static func cgWindowID(fromAppKitWindowNumber number: Int) -> UInt32? {
        guard number >= 0, number <= Int(UInt32.max) else { return nil }
        return UInt32(number)
    }

    public static func appKitFrame(
        fromAX frame: CGRect,
        primaryFlipHeight: CGFloat
    ) -> CGRect {
        CoordinateConverter.appKitRect(fromAX: frame, primaryFlipHeight: primaryFlipHeight)
    }

    public static func sizeLimits(
        applied: CGSize,
        previousMin: CGSize,
        previousMax: CGSize
    ) -> (min: CGSize, max: CGSize) {
        if previousMin == previousMax {
            return (applied, applied)
        }
        return (previousMin, previousMax)
    }
}
