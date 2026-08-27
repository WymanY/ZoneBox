import CoreGraphics
import Foundation

public struct ResolvedZone: Equatable, Sendable {
    public var zoneID: UUID
    public var number: Int
    public var frameAX: CGRect

    public init(zoneID: UUID, number: Int, frameAX: CGRect) {
        self.zoneID = zoneID
        self.number = number
        self.frameAX = frameAX
    }
}

public enum SnapTarget: Equatable, Sendable {
    case none
    case zone(ResolvedZone)
    /// Axis-aligned union of grid cells covered by a draw-rectangle.
    case span(frameAX: CGRect, zoneIDs: [UUID])

    public var frameAX: CGRect? {
        switch self {
        case .none:
            return nil
        case .zone(let zone):
            return zone.frameAX
        case .span(let frameAX, _):
            return frameAX
        }
    }

    public var unsnapZoneIDs: [UUID] {
        switch self {
        case .none:
            return []
        case .zone(let zone):
            return [zone.zoneID]
        case .span(_, let zoneIDs):
            return zoneIDs
        }
    }
}
