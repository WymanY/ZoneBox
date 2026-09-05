import Foundation

/// Snapshot of snappable own-window IDs that AX can read off the main actor.
public final class WindowNumberAllowlist: @unchecked Sendable {
    private let lock = NSLock()
    private var numbers: Set<UInt32> = []

    public init() {}

    public func replace(_ numbers: Set<UInt32>) {
        lock.lock()
        self.numbers = numbers
        lock.unlock()
    }

    public func current() -> Set<UInt32> {
        lock.lock()
        defer { lock.unlock() }
        return numbers
    }

    public func contains(_ number: UInt32) -> Bool {
        current().contains(number)
    }
}
