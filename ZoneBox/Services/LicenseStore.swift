import Foundation

public struct LicenseStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let root = directory ?? AppIdentity.defaultSupportDirectory
        self.fileURL = root.appendingPathComponent("license.json")
    }

    public func load(now: Date = Date()) throws -> LicenseRecord {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            let fresh = LicenseRecord.freshTrial(now: now)
            try save(fresh)
            return fresh
        }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONCoding.decoder().decode(LicenseRecord.self, from: data)
        } catch {
            Log.store.error(
                "License decode failed; starting a new trial path=\(self.fileURL.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            JSONCoding.quarantineCorruptFile(at: fileURL)
            let fresh = LicenseRecord.freshTrial(now: now)
            try save(fresh)
            return fresh
        }
    }

    public func save(_ record: LicenseRecord) throws {
        let data = try JSONCoding.encoder().encode(record)
        try JSONCoding.atomicWrite(data, to: fileURL)
    }
}
