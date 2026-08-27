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
}
