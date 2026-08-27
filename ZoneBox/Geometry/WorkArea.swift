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

/// Resolves the display that owns a focused window without consulting pointer state.
///
/// A spanning window belongs to the display containing the greatest portion of its
/// frame. Equal intersections are intentionally ambiguous so keyboard commands fail
/// closed instead of choosing an unrelated display by array order.
public enum DisplayTargetResolver {
    public static func workArea(
        containingWindowFrameAX windowFrameAX: CGRect,
        from workAreas: [WorkArea],
        primaryFlipHeight: CGFloat
    ) -> WorkArea? {
        guard windowFrameAX.width > 0, windowFrameAX.height > 0 else { return nil }

        let candidates = workAreas.compactMap { area -> (area: WorkArea, intersectionArea: CGFloat)? in
            let displayFrameAX = CoordinateConverter.axRect(
                fromAppKit: area.frameAppKit,
                primaryFlipHeight: primaryFlipHeight
            )
            let intersection = windowFrameAX.intersection(displayFrameAX)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
            return (area, intersection.width * intersection.height)
        }
        guard let maximum = candidates.map(\.intersectionArea).max() else { return nil }

        let winners = candidates.filter { abs($0.intersectionArea - maximum) <= 0.5 }
        return winners.count == 1 ? winners[0].area : nil
    }
}
