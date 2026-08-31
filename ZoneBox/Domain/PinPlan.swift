import CoreGraphics

public struct PinWindowSnapshot: Equatable, Sendable {
    public var identity: WindowIdentity
    public var frameAX: CGRect
    public var layer: Int

    public init(identity: WindowIdentity, frameAX: CGRect, layer: Int = 0) {
        self.identity = identity
        self.frameAX = frameAX
        self.layer = layer
    }
}

public struct PinPlan: Equatable, Sendable {
    /// Visible pins in oldest-to-newest order. Ordering mirror panels in this
    /// sequence leaves the most recently pinned window in front.
    public var visible: [WindowIdentity]
    public var dormant: [WindowIdentity]
    public var gone: [WindowIdentity]
    public var visibleFrames: [WindowIdentity: CGRect]

    public init(
        visible: [WindowIdentity] = [],
        dormant: [WindowIdentity] = [],
        gone: [WindowIdentity] = [],
        visibleFrames: [WindowIdentity: CGRect] = [:]
    ) {
        self.visible = visible
        self.dormant = dormant
        self.gone = gone
        self.visibleFrames = visibleFrames
    }
}

public enum PinPlanner {
    /// Classifies one watchdog tick from the WindowServer's front-to-back order.
    /// `pinOrder` is oldest-to-newest and `allWindowIdentities` must include
    /// off-screen/minimized windows so absence can be classified safely. Pass
    /// `nil` when that list was not sampled this tick; absent pins are then
    /// treated as dormant rather than closed.
    public static func plan(
        frontToBack: [PinWindowSnapshot],
        allWindowIdentities: Set<WindowIdentity>?,
        pinOrder: [WindowIdentity]
    ) -> PinPlan {
        let layerZero = frontToBack.filter { $0.layer == 0 }
        let snapshotByIdentity = Dictionary(
            uniqueKeysWithValues: layerZero.map { ($0.identity, $0) }
        )

        var dormant: [WindowIdentity] = []
        var gone: [WindowIdentity] = []
        var frames: [WindowIdentity: CGRect] = [:]
        var visiblePins: [WindowIdentity] = []

        for identity in pinOrder {
            if let snapshot = snapshotByIdentity[identity] {
                visiblePins.append(identity)
                frames[identity] = snapshot.frameAX
            } else if allWindowIdentities?.contains(identity) ?? true {
                dormant.append(identity)
            } else {
                gone.append(identity)
            }
        }

        return PinPlan(
            visible: visiblePins,
            dormant: dormant,
            gone: gone,
            visibleFrames: frames
        )
    }
}
