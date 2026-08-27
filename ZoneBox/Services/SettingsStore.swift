import Foundation

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.fancyzone.app", isDirectory: true)
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
            return .default
        }
    }

    public func save(_ settings: AppSettings) throws {
        let data = try JSONCoding.encoder().encode(settings)
        try JSONCoding.atomicWrite(data, to: fileURL)
    }
}
