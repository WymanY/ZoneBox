import CoreGraphics

/// Placeholder work-area used by geometry tests (PR 2).
public struct FakeScreen: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var backingScale: CGFloat
    public var originIsZero: Bool

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        backingScale: CGFloat,
        originIsZero: Bool
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScale = backingScale
        self.originIsZero = originIsZero
    }
}
