import Foundation
import os

/// Snapshot of snappable own-window IDs that AX can read off the main actor.
public final class WindowNumberAllowlist: Sendable {
    private let numbers = OSAllocatedUnfairLock(initialState: Set<UInt32>())

    public init() {}

    public func replace(_ numbers: Set<UInt32>) {
        self.numbers.withLock { $0 = numbers }
    }

    public func current() -> Set<UInt32> {
        numbers.withLock { $0 }
    }

    public func contains(_ number: UInt32) -> Bool {
        numbers.withLock { $0.contains(number) }
    }
}
