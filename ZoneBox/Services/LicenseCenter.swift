import Foundation
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

    init(store: LicenseStore = LicenseStore(), client: CreemLicenseClient = CreemLicenseClient()) {
        self.store = store
        self.client = client
        self.record = (try? store.load()) ?? .freshTrial()
    }

    var snapshot: LicenseSnapshot {
#if DEBUG
        if ProcessInfo.processInfo.environment["ZONEBOX_UNLOCK_PRO"] == "1" {
            return LicenseSnapshot(kind: .licensed, allowsPro: true, trialDaysRemaining: 0)
        }
#endif
        return LicenseAccess.snapshot(record)
    }

    var allowsPro: Bool { snapshot.allowsPro }

    func start() {
        persist()
        Task { await refreshIfNeeded() }
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
        let result = try await client.activate(key: trimmed, instanceName: DeviceIdentity.instanceName())
        guard result.status == .active, let instanceID = result.instanceID else {
            throw CreemLicenseError.invalidKey
        }
        apply(result, key: trimmed, instanceID: instanceID)
    }

    func deactivate() async throws {
        guard let key = record.licenseKey, let instanceID = record.instanceID else { return }
        do {
            _ = try await client.deactivate(key: key, instanceID: instanceID)
        } catch CreemLicenseError.invalidKey {
            // Already released on Creem's side.
        }
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

    func refreshIfNeeded() async {
        guard let key = record.licenseKey, let instanceID = record.instanceID else { return }
        if let last = record.lastValidatedAt, Date().timeIntervalSince(last) < 6 * 60 * 60 {
            return
        }
        do {
            let result = try await client.validate(key: key, instanceID: instanceID)
            apply(result, key: key, instanceID: result.instanceID ?? instanceID)
        } catch {
            Log.store.error("License validate failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ result: CreemLicenseResult, key: String, instanceID: String) {
        record.licenseKey = result.key ?? key
        record.instanceID = instanceID
        record.lastValidatedAt = Date()
        record.lastValidationStatus = result.status
        record.cachedExpiresAt = result.expiresAt
        persist()
        onChange?()
    }
}
