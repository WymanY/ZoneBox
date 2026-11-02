import Foundation
import AppKit
import Network
import ZoneBoxCore

enum LicenseFeature {
    case workspace
    case pin
    case quickSnapper
}

@MainActor
final class LicenseCenter {
    private let store: LicenseStore
    private let client: CreemLicenseClient
    private(set) var record: LicenseRecord
    var onChange: (() -> Void)?
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var refreshRequest: UUID?
    private var generation = 0
    private var lastAttemptAt: Date?
    private var licenseMutationCount = 0
    private let now: () -> Date
    private let pollInterval: TimeInterval

    init(
        store: LicenseStore = LicenseStore(),
        client: CreemLicenseClient = CreemLicenseClient(),
        now: @escaping () -> Date = Date.init,
        pollInterval: TimeInterval = 15 * 60
    ) {
        self.store = store
        self.client = client
        self.now = now
        self.pollInterval = pollInterval
        self.record = (try? store.load()) ?? .freshTrial()
    }

    var snapshot: LicenseSnapshot {
#if DEBUG
        if ProcessInfo.processInfo.environment["ZONEBOX_UNLOCK_PRO"] == "1" {
            return LicenseSnapshot(kind: .licensed, allowsPro: true, trialDaysRemaining: 0)
        }
#endif
        return LicenseAccess.snapshot(record, now: now())
    }

    var allowsPro: Bool { snapshot.allowsPro }

    func start() {
        invalidate()
        persist()
        Task { [weak self] in await self?.refreshAutomatically() }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAutomatically() }
        }
        timer.tolerance = min(60, pollInterval / 10)
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAutomatically() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAutomatically() }
        })
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.refreshAutomatically() }
        }
        monitor.start(queue: DispatchQueue(label: "com.fancyzone.license-network"))
        pathMonitor = monitor
    }

    func invalidate() {
        generation += 1
        refreshRequest = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func persist() {
        do {
            try store.save(record)
        } catch {
            Log.store.error("License save failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CreemLicenseError.invalidKey }
        generation += 1
        licenseMutationCount += 1
        defer { licenseMutationCount -= 1 }
        let operation = generation
        let result = try await client.activate(key: trimmed, instanceName: DeviceIdentity.instanceName())
        guard operation == generation else { return }
        guard result.status == .active, let instanceID = result.instanceID else {
            throw CreemLicenseError.invalidKey
        }
        apply(result, key: trimmed, instanceID: instanceID)
    }

    func deactivate() async throws {
        guard let key = record.licenseKey, let instanceID = record.instanceID else { return }
        generation += 1
        licenseMutationCount += 1
        defer { licenseMutationCount -= 1 }
        let operation = generation
        do {
            _ = try await client.deactivate(key: key, instanceID: instanceID)
        } catch CreemLicenseError.invalidKey {
            // Already released on Creem's side.
        }
        guard operation == generation else { return }
        generation += 1
        record.licenseKey = nil
        record.instanceID = nil
        record.lastValidatedAt = nil
        record.lastValidationStatus = .unknown
        record.cachedExpiresAt = nil
        persist()
        onChange?()
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "zonebox" else { return }
        guard url.host?.lowercased() == "activate" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard let key = items?.first(where: { $0.name == "key" })?.value, !key.isEmpty else { return }
        Task { @MainActor in
            do {
                try await activate(key: key)
            } catch {
                Log.store.error("License URL activate failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func refreshAutomatically() async {
        guard refreshTimer != nil else { return }
        await refreshIfNeeded()
    }

    func refreshIfNeeded() async {
        guard refreshRequest == nil, licenseMutationCount == 0,
              let key = record.licenseKey, let instanceID = record.instanceID else { return }
        let date = now()
        if let last = record.lastValidatedAt,
           (0 ..< 6 * 60 * 60).contains(date.timeIntervalSince(last)) {
            return
        }
        // Wake, activation and network callbacks can arrive together. Retry failed
        // checks within 15 minutes, while limiting bursts to one request per 5 minutes.
        if let last = lastAttemptAt, (0 ..< 5 * 60).contains(date.timeIntervalSince(last)) { return }
        lastAttemptAt = date
        let request = UUID()
        let operation = generation
        refreshRequest = request
        defer { if refreshRequest == request { refreshRequest = nil } }
        do {
            let result = try await client.validate(key: key, instanceID: instanceID)
            guard operation == generation,
                  record.licenseKey == key, record.instanceID == instanceID else { return }
            apply(result, key: key, instanceID: result.instanceID ?? instanceID)
        } catch {
            Log.store.error("License validate failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ result: CreemLicenseResult, key: String, instanceID: String) {
        generation += 1
        record.licenseKey = result.key ?? key
        record.instanceID = instanceID
        record.lastValidatedAt = now()
        record.lastValidationStatus = result.status
        record.cachedExpiresAt = result.expiresAt
        persist()
        onChange?()
    }
}
