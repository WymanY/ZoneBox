import CoreGraphics

public struct WorkArea: Equatable, Sendable {
    public var display: DisplayIdentity
    public var frameAppKit: CGRect
    public var visibleFrameAppKit: CGRect
    public var backingScale: CGFloat

    public init(
        display: DisplayIdentity,
        frameAppKit: CGRect,
        visibleFrameAppKit: CGRect,
        backingScale: CGFloat
    ) {
        self.display = display
        self.frameAppKit = frameAppKit
        self.visibleFrameAppKit = visibleFrameAppKit
        self.backingScale = backingScale
    }

    public func containsAppKitPoint(_ point: CGPoint) -> Bool {
        visibleFrameAppKit.contains(point)
    }
}
