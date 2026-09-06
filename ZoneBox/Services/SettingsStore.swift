import Foundation

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let root = directory ?? AppIdentity.defaultSupportDirectory
        self.fileURL = root.appendingPathComponent("settings.json")
    }

    public func load() throws -> AppSettings {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            try save(.default)
            return .default
        }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONCoding.decoder().decode(AppSettings.self, from: data)
        } catch {
            // Fall back to defaults so a bad file never blocks launch, but
            // keep the original beside it: the next save would otherwise
            // overwrite the user's only copy without a trace.
            Log.store.error(
                "Settings decode failed; using defaults path=\(self.fileURL.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            JSONCoding.quarantineCorruptFile(at: fileURL)
            try save(.default)
            return .default
        }
    }

    public func save(_ settings: AppSettings) throws {
        let data = try JSONCoding.encoder().encode(settings)
        try JSONCoding.atomicWrite(data, to: fileURL)
    }
}
