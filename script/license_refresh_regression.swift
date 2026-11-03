import AppKit
import Foundation
import ZoneBoxCore

private final class Clock {
    var date = Date()
}

private final class LicenseStub: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var calls = 0
    static var offline = false
    static var delay: TimeInterval = 0

    static func reset() {
        lock.lock()
        calls = 0
        offline = false
        delay = 0
        lock.unlock()
    }

    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.calls += 1
        let offline = Self.offline
        let delay = Self.delay
        Self.lock.unlock()
        let reply: @Sendable () -> Void = { [self] in
            if offline {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"status\":\"active\",\"instance_id\":\"test-instance\"}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        if delay == 0 { reply() }
        else { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: reply) }
    }
    override func stopLoading() {}
}

@main
private enum LicenseRefreshRegression {
    struct Failure: Error { var message: String }

    @MainActor
    static func expect(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(message: message) }
    }

    @MainActor
    static func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try expect(condition(), "timed out waiting for refresh")
    }

    @MainActor
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zonebox-license-refresh-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LicenseStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = CreemLicenseClient(endpoint: URL(string: "https://license.test/validate")!, session: session)

        func make(_ clock: Clock, interval: TimeInterval = 3600) throws -> LicenseCenter {
            let store = LicenseStore(directory: root.appendingPathComponent(UUID().uuidString))
            try store.save(LicenseRecord(
                trialStartedAt: clock.date.addingTimeInterval(-60 * 86400),
                licenseKey: "test-key", instanceID: "test-instance",
                lastValidatedAt: clock.date.addingTimeInterval(-7 * 3600), lastValidationStatus: .active
            ))
            return LicenseCenter(store: store, client: client, now: { clock.date }, pollInterval: interval)
        }

        LicenseStub.reset()
        let clock = Clock()
        let center = try make(clock)
        await center.refreshIfNeeded()
        try expect(LicenseStub.count == 1, "due license must validate")
        await center.refreshIfNeeded()
        try expect(LicenseStub.count == 1, "fresh license must not validate again")
        clock.date.addTimeInterval(31 * 86400)
        try expect(!center.allowsPro, "fixture must have expired offline")
        await center.refreshIfNeeded()
        try expect(center.allowsPro && LicenseStub.count == 2, "long-running license must recover without restart")
        print("CASE_OK due-fresh-and-long-running-refresh")

        LicenseStub.reset()
        let offlineClock = Clock()
        let offline = try make(offlineClock)
        let original = offline.record
        LicenseStub.offline = true
        await offline.refreshIfNeeded()
        await offline.refreshIfNeeded()
        try expect(LicenseStub.count == 1 && offline.record == original, "network failure must preserve entitlement and throttle retries")
        offlineClock.date.addTimeInterval(5 * 60)
        LicenseStub.offline = false
        await offline.refreshIfNeeded()
        try expect(LicenseStub.count == 2 && offline.record.lastValidatedAt == offlineClock.date, "failed validation must retry")
        print("CASE_OK offline-preserves-license-and-retries")

        LicenseStub.reset()
        let concurrent = try make(Clock())
        LicenseStub.delay = 0.15
        let first = Task { await concurrent.refreshIfNeeded() }
        try await waitFor { LicenseStub.count == 1 }
        await concurrent.refreshIfNeeded()
        await first.value
        try expect(LicenseStub.count == 1, "simultaneous events must share one refresh")
        print("CASE_OK simultaneous-events-coalesced")

        LicenseStub.reset()
        let stopped = try make(Clock())
        let beforeStop = stopped.record
        LicenseStub.delay = 0.15
        let pending = Task { await stopped.refreshIfNeeded() }
        try await waitFor { LicenseStub.count == 1 }
        stopped.invalidate()
        await pending.value
        try expect(stopped.record == beforeStop, "stopped refresh must not apply a late response")
        print("CASE_OK late-response-after-stop-ignored")

        LicenseStub.reset()
        let periodicClock = Clock()
        let periodic = try make(periodicClock, interval: 0.05)
        periodic.start()
        try await waitFor { periodic.record.lastValidatedAt == periodicClock.date }
        periodicClock.date.addTimeInterval(7 * 3600)
        try await waitFor { periodic.record.lastValidatedAt == periodicClock.date }
        try expect(LicenseStub.count == 2, "timer must refresh without activation or restart")
        periodic.invalidate()
        print("CASE_OK timer-refreshes-running-app")

        LicenseStub.reset()
        let wakeClock = Clock()
        let wake = try make(wakeClock)
        wake.start()
        try await waitFor { wake.record.lastValidatedAt == wakeClock.date }
        wakeClock.date.addTimeInterval(7 * 3600)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await waitFor { wake.record.lastValidatedAt == wakeClock.date }
        wakeClock.date.addTimeInterval(7 * 3600)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await waitFor { wake.record.lastValidatedAt == wakeClock.date }
        try expect(LicenseStub.count == 3, "wake and activation must trigger due validation")
        wake.invalidate()
        wakeClock.date.addTimeInterval(7 * 3600)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        try expect(LicenseStub.count == 3, "invalidate must remove observers")
        print("CASE_OK wake-activation-and-observer-cleanup")
    }

    static func main() async {
        do {
            try await run()
            print("LICENSE_REFRESH_REGRESSION_OK")
        } catch {
            fputs("LICENSE_REFRESH_REGRESSION_FAIL \(error)\n", stderr)
            exit(1)
        }
    }
}
