import CoreGraphics
import Foundation

public enum WindowMutationKind: Equatable, Sendable {
    case applyFrame
    case raise
}

public struct WindowMutationRequest: Equatable, Sendable {
    public var sessionID: UUID
    public var generation: Int
    public var identity: WindowIdentity
    public var kind: WindowMutationKind
    public var frameAX: CGRect?

    public init(
        sessionID: UUID,
        generation: Int,
        identity: WindowIdentity,
        kind: WindowMutationKind,
        frameAX: CGRect? = nil
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.identity = identity
        self.kind = kind
        self.frameAX = frameAX
    }
}

public struct WindowMutationRecord: Equatable, Sendable {
    public var request: WindowMutationRequest
    public var appliedFrameAX: CGRect?
    public var succeeded: Bool

    public init(request: WindowMutationRequest, appliedFrameAX: CGRect?, succeeded: Bool) {
        self.request = request
        self.appliedFrameAX = appliedFrameAX
        self.succeeded = succeeded
    }
}

public protocol WindowMutating: AnyObject {
    func applyFrame(_ frame: CGRect, of identity: WindowIdentity) async -> CGRect?
    func raise(_ identity: WindowIdentity) async -> Bool
}

/// Serial owner of live AX writes. Later generations for the same
/// session+window replace earlier queued frames; cancelled sessions never
/// write; a timeout drops a stalled writer so mouse-up can still land the
/// latest frame.
@MainActor
public final class WindowMutationQueue {
    public struct Configuration: Equatable, Sendable {
        public var timeoutNanoseconds: UInt64

        public init(timeoutNanoseconds: UInt64 = 2_000_000_000) {
            self.timeoutNanoseconds = timeoutNanoseconds
        }
    }

    private struct Lane: Hashable {
        var sessionID: UUID
        var identity: WindowIdentity
    }

    private struct PendingWrite {
        var request: WindowMutationRequest
        var continuation: CheckedContinuation<WindowMutationRecord, Never>
    }

    private let mutator: any WindowMutating
    private let configuration: Configuration
    private var latest: [Lane: WindowMutationRequest] = [:]
    private var cancelled = Set<UUID>()
    private var pending: [Lane: [PendingWrite]] = [:]
    private var pumping = false
    private var inflight: (lane: Lane, generation: Int, task: Task<WindowMutationRecord, Never>)?

    public init(mutator: any WindowMutating, configuration: Configuration = Configuration()) {
        self.mutator = mutator
        self.configuration = configuration
    }

    public func submit(_ request: WindowMutationRequest) async -> WindowMutationRecord {
        let lane = Lane(sessionID: request.sessionID, identity: request.identity)
        if cancelled.contains(request.sessionID) {
            return WindowMutationRecord(request: request, appliedFrameAX: nil, succeeded: false)
        }
        if let current = latest[lane], request.generation < current.generation {
            return WindowMutationRecord(request: request, appliedFrameAX: nil, succeeded: false)
        }
        latest[lane] = request
        if let inflight, inflight.lane == lane, inflight.generation < request.generation {
            inflight.task.cancel()
        }
        return await withCheckedContinuation { continuation in
            pending[lane, default: []].append(PendingWrite(request: request, continuation: continuation))
            guard !pumping else { return }
            pumping = true
            Task { @MainActor in
                await self.pump()
            }
        }
    }

    public func cancel(sessionID: UUID) {
        cancelled.insert(sessionID)
        for lane in Array(latest.keys) where lane.sessionID == sessionID {
            latest[lane] = nil
            failPending(lane: lane)
        }
        if inflight?.lane.sessionID == sessionID {
            inflight?.task.cancel()
            inflight = nil
        }
    }

    public func finish(sessionID: UUID) {
        cancelled.remove(sessionID)
        for lane in Array(latest.keys) where lane.sessionID == sessionID {
            if pending[lane]?.isEmpty != false {
                latest[lane] = nil
            }
        }
    }

    private func pump() async {
        defer { pumping = false }
        while let job = dequeue() {
            if cancelled.contains(job.request.sessionID) {
                failWaiters(job.waiters)
                continue
            }
            let lane = Lane(sessionID: job.request.sessionID, identity: job.request.identity)
            if let current = latest[lane], current.generation != job.request.generation {
                failWaiters(job.waiters, except: current)
                continue
            }
            let result = await perform(job.request, lane: lane)
            for waiter in job.waiters {
                if waiter.request == job.request {
                    waiter.continuation.resume(returning: result)
                } else {
                    waiter.continuation.resume(
                        returning: WindowMutationRecord(request: waiter.request, appliedFrameAX: nil, succeeded: false)
                    )
                }
            }
        }
    }

    private struct Job {
        var request: WindowMutationRequest
        var waiters: [PendingWrite]
    }

    private func dequeue() -> Job? {
        for lane in Array(pending.keys) {
            if cancelled.contains(lane.sessionID) {
                failPending(lane: lane)
                continue
            }
            guard let latestRequest = latest[lane],
                  let waiters = pending.removeValue(forKey: lane),
                  !waiters.isEmpty
            else { continue }
            return Job(request: latestRequest, waiters: waiters)
        }
        return nil
    }

    private func failPending(lane: Lane) {
        failWaiters(pending.removeValue(forKey: lane) ?? [])
    }

    private func failWaiters(_ waiters: [PendingWrite], except latestRequest: WindowMutationRequest? = nil) {
        for waiter in waiters {
            if let latestRequest, waiter.request == latestRequest {
                let lane = Lane(sessionID: latestRequest.sessionID, identity: latestRequest.identity)
                pending[lane, default: []].append(waiter)
                continue
            }
            waiter.continuation.resume(
                returning: WindowMutationRecord(request: waiter.request, appliedFrameAX: nil, succeeded: false)
            )
        }
    }

    private func perform(_ request: WindowMutationRequest, lane: Lane) async -> WindowMutationRecord {
        let timeoutRecord = WindowMutationRecord(request: request, appliedFrameAX: nil, succeeded: false)
        let work = Task { () -> WindowMutationRecord in
            if Task.isCancelled {
                return timeoutRecord
            }
            switch request.kind {
            case .applyFrame:
                guard let frame = request.frameAX else {
                    return timeoutRecord
                }
                let applied = await mutator.applyFrame(frame, of: request.identity)
                if Task.isCancelled {
                    return timeoutRecord
                }
                return WindowMutationRecord(request: request, appliedFrameAX: applied, succeeded: applied != nil)
            case .raise:
                let succeeded = await mutator.raise(request.identity)
                if Task.isCancelled {
                    return timeoutRecord
                }
                return WindowMutationRecord(request: request, appliedFrameAX: request.frameAX, succeeded: succeeded)
            }
        }
        inflight = (lane, request.generation, work)
        let result = await race(work, timeoutRecord: timeoutRecord)
        if inflight?.lane == lane, inflight?.generation == request.generation {
            inflight = nil
        }
        return result
    }

    private func race(
        _ work: Task<WindowMutationRecord, Never>,
        timeoutRecord: WindowMutationRecord
    ) async -> WindowMutationRecord {
        await withCheckedContinuation { continuation in
            var resumed = false
            func finish(_ record: WindowMutationRecord) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: record)
            }
            Task { @MainActor in
                finish(await work.value)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: configuration.timeoutNanoseconds)
                work.cancel()
                finish(timeoutRecord)
            }
        }
    }
}
