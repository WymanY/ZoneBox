import CoreGraphics
import Foundation

/// Testable owner of live-runtime writes. Production services submit through
/// this instead of calling AX directly, so generation, latest-write, cancel,
/// and mouse-up flush can fail in Core tests.
@MainActor
public final class WindowMutationEngine {
    public let queue: WindowMutationQueue
    private var gate: RuntimeModeGate

    public init(mutator: any WindowMutating, timeoutNanoseconds: UInt64 = 2_000_000_000) {
        self.queue = WindowMutationQueue(
            mutator: mutator,
            configuration: WindowMutationQueue.Configuration(timeoutNanoseconds: timeoutNanoseconds)
        )
        self.gate = RuntimeModeGate()
    }

    public var mode: RuntimeMode {
        gate.mode
    }

    public func allows(_ capability: RuntimeCapability) -> Bool {
        gate.allows(capability)
    }

    public func begin(_ request: RuntimeModeRequest) -> Bool {
        gate.begin(request)
    }

    public func end(_ request: RuntimeModeRequest) {
        gate.end(request)
    }

    public func force(_ mode: RuntimeMode) {
        gate.force(mode)
    }

    public func applyFrame(
        _ frame: CGRect,
        of identity: WindowIdentity,
        sessionID: UUID,
        generation: Int
    ) async -> CGRect? {
        guard gate.allows(.mutateWindows) else { return nil }
        let record = await queue.submit(
            WindowMutationRequest(
                sessionID: sessionID,
                generation: generation,
                identity: identity,
                kind: .applyFrame,
                frameAX: frame
            )
        )
        return record.appliedFrameAX
    }

    public func raise(
        _ identity: WindowIdentity,
        sessionID: UUID,
        generation: Int,
        frameAX: CGRect? = nil
    ) async -> Bool {
        guard gate.allows(.raisePinnedWindows) || gate.allows(.mutateWindows) else { return false }
        let record = await queue.submit(
            WindowMutationRequest(
                sessionID: sessionID,
                generation: generation,
                identity: identity,
                kind: .raise,
                frameAX: frameAX
            )
        )
        return record.succeeded
    }

    public func cancel(sessionID: UUID) {
        queue.cancel(sessionID: sessionID)
    }

    public func finish(sessionID: UUID) {
        queue.finish(sessionID: sessionID)
    }
}
