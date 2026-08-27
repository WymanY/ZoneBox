import CoreGraphics

public struct HitTester: Sendable {
    public var policy: OverlapPolicy

    public init(policy: OverlapPolicy = .smallestArea) {
        self.policy = policy
    }

    public func target(at pointAX: CGPoint, zones: [ResolvedZone]) -> SnapTarget {
        let hits = zones.filter { $0.frameAX.contains(pointAX) }
        guard !hits.isEmpty else { return .none }
        switch policy {
        case .smallestArea:
            return .zone(hits.min(by: { $0.frameAX.width * $0.frameAX.height < $1.frameAX.width * $1.frameAX.height })!)
        case .largestArea:
            return .zone(hits.max(by: { $0.frameAX.width * $0.frameAX.height < $1.frameAX.width * $1.frameAX.height })!)
        case .closestCenterToCursor:
            return .zone(hits.min(by: {
                let da = hypot($0.frameAX.midX - pointAX.x, $0.frameAX.midY - pointAX.y)
                let db = hypot($1.frameAX.midX - pointAX.x, $1.frameAX.midY - pointAX.y)
                return da < db
            })!)
        }
    }
}
