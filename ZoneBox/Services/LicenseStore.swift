import Foundation
import Security

public struct LicenseStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let root = directory ?? AppIdentity.defaultSupportDirectory
        self.fileURL = root.appendingPathComponent("license.json")
    }

    public func load(now: Date = Date()) throws -> LicenseRecord {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            let fresh = LicenseRecord(trialStartedAt: trialAnchor(now: now))
            try save(fresh)
            return fresh
        }
        let data = try Data(contentsOf: fileURL)
        var record: LicenseRecord
        do {
            record = try JSONCoding.decoder().decode(LicenseRecord.self, from: data)
        } catch {
            Log.store.error(
                "License decode failed; starting a new trial path=\(self.fileURL.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            JSONCoding.quarantineCorruptFile(at: fileURL)
            let fresh = LicenseRecord(trialStartedAt: trialAnchor(now: now))
            try save(fresh)
            return fresh
        }
        let anchor = trialAnchor(now: record.trialStartedAt)
        if record.trialStartedAt > anchor {
            record.trialStartedAt = anchor
            do {
                try save(record)
            } catch {
                // The record is valid. Keep its entitlement even if migration
                // cannot be persisted; retry the clamp on the next load.
                Log.store.error("License trial migration save failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
        return record
    }

    public func save(_ record: LicenseRecord) throws {
        let data = try JSONCoding.encoder().encode(record)
        try JSONCoding.atomicWrite(data, to: fileURL)
        _ = saveTrialAnchor(record.trialStartedAt)
    }

    private var trialAccount: String { "\(AppIdentity.bundleID).trial.\(fileURL.path)" }

    private func trialAnchor(now: Date) -> Date {
        if let stored = readTrialAnchor() { return min(stored, now) }
        _ = saveTrialAnchor(now)
        return now
    }

    @discardableResult
    private func saveTrialAnchor(_ date: Date) -> Bool {
        var seconds = date.timeIntervalSince1970
        let data = Data(bytes: &seconds, count: MemoryLayout<Double>.size)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppIdentity.bundleID,
            kSecAttrAccount as String: trialAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecDuplicateItem
    }

    private func readTrialAnchor() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppIdentity.bundleID,
            kSecAttrAccount as String: trialAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              data.count == MemoryLayout<Double>.size else { return nil }
        return data.withUnsafeBytes { Date(timeIntervalSince1970: $0.load(as: Double.self)) }
    }
}
