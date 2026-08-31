import Foundation

public struct WindowIdentity: Hashable, Sendable {
    public var pid: pid_t
    public var windowNumber: UInt32
    public var bundleID: String?

    public init(pid: pid_t, windowNumber: UInt32, bundleID: String? = nil) {
        self.pid = pid
        self.windowNumber = windowNumber
        self.bundleID = bundleID
    }

    public static func == (lhs: WindowIdentity, rhs: WindowIdentity) -> Bool {
        lhs.pid == rhs.pid && lhs.windowNumber == rhs.windowNumber
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(windowNumber)
    }
}
