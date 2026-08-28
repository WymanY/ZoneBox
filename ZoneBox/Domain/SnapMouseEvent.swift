import CoreGraphics

public struct SnapModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let shift = SnapModifiers(rawValue: 1 << 0)
    public static let control = SnapModifiers(rawValue: 1 << 1)
    public static let option = SnapModifiers(rawValue: 1 << 2)
    public static let command = SnapModifiers(rawValue: 1 << 3)
}

public struct SnapMouseEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case leftDown, leftDragged, leftUp
        case rightDown
        case flagsChanged
        case escape
        /// Overlay zone number 1...9. Hardware key, not a character.
        case digit(Int)
    }

    public var kind: Kind
    public var locationAppKit: CGPoint
    public var modifiers: SnapModifiers

    public init(kind: Kind, locationAppKit: CGPoint, modifiers: SnapModifiers) {
        self.kind = kind
        self.locationAppKit = locationAppKit
        self.modifiers = modifiers
    }
}
