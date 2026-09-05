import CoreGraphics
import Foundation
@testable import ZoneBoxCore

final class FakeWindowMutator: WindowMutating, @unchecked Sendable {
    struct FrameWrite: Equatable {
        var identity: WindowIdentity
        var frameAX: CGRect
    }

    private let lock = NSLock()
    private var frames: [WindowIdentity: CGRect]
    private(set) var appliedFrames: [FrameWrite] = []
    private(set) var raised: [WindowIdentity] = []
    var delayNanoseconds: UInt64 = 0
    var hangUntilCancelled = false
    var failUntilCount = 0
    private var applyCount = 0

    init(frames: [WindowIdentity: CGRect] = [:]) {
        self.frames = frames
    }

    func frame(of identity: WindowIdentity) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }
        return frames[identity]
    }

    func applyFrame(_ frame: CGRect, of identity: WindowIdentity) async -> CGRect? {
        if hangUntilCancelled {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            return nil
        }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if Task.isCancelled {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        applyCount += 1
        if applyCount <= failUntilCount {
            return nil
        }
        frames[identity] = frame
        appliedFrames.append(FrameWrite(identity: identity, frameAX: frame))
        return frame
    }

    func raise(_ identity: WindowIdentity) async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        raised.append(identity)
        return true
    }
}

/// In-memory stand-in for CGWindowList. Tests that need "live" windows use
/// this instead of AppKit so execution-layer contracts can fail in Core.
struct FakeWindowList: Equatable, Sendable {
    var windows: [WindowIdentity: CGRect]

    init(windows: [WindowIdentity: CGRect] = [:]) {
        self.windows = windows
    }

    mutating func apply(_ frame: CGRect, of identity: WindowIdentity) {
        windows[identity] = frame
    }

    func frame(of identity: WindowIdentity) -> CGRect? {
        windows[identity]
    }
}
