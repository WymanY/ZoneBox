import Foundation

enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func atomicWrite(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let tmp = directory.appendingPathComponent(url.lastPathComponent + ".tmp")
        try data.write(to: tmp, options: .atomic)
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }

    /// Moves an undecodable file aside as `<name>.corrupt-<unix time>` so the
    /// replacement written on the next save does not destroy the user's data.
    /// Best effort: a failed move is logged, never thrown, because the caller
    /// is already on the fallback path.
    @discardableResult
    static func quarantineCorruptFile(at url: URL) -> URL? {
        let quarantined = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".corrupt-\(Int(Date().timeIntervalSince1970))")
        do {
            try FileManager.default.moveItem(at: url, to: quarantined)
            Log.store.error(
                "Quarantined corrupt file path=\(url.lastPathComponent, privacy: .public) as=\(quarantined.lastPathComponent, privacy: .public)"
            )
            return quarantined
        } catch {
            Log.store.error(
                "Failed to quarantine corrupt file path=\(url.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
