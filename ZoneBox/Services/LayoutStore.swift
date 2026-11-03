import Foundation

public struct LayoutStore: Sendable {
    public enum LoadError: Error {
        case unsupportedSchema
    }

    public struct LoadResult: Sendable {
        public let document: StoreDocument
        public let recovery: Recovery?
    }

    public struct Recovery: Sendable {
        public let restoredBackup: Bool
        public let originalFile: URL
    }

    public let fileURL: URL
    public var backupURL: URL { fileURL.appendingPathExtension("backup") }

    public init(directory: URL? = nil) {
        let root = directory ?? AppIdentity.defaultSupportDirectory
        self.fileURL = root.appendingPathComponent("store.json")
    }

    public func load() throws -> StoreDocument {
        try loadWithRecovery().document
    }

    public func loadWithRecovery() throws -> LoadResult {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            // A backup can survive an interrupted write or a missing primary file.
            if fm.fileExists(atPath: backupURL.path) {
                let data = try Data(contentsOf: backupURL)
                let document: StoreDocument
                do {
                    document = try decode(data)
                } catch LoadError.unsupportedSchema {
                    throw LoadError.unsupportedSchema
                } catch {
                    guard let original = JSONCoding.quarantineCorruptFile(at: backupURL) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    let document = StoreDocument()
                    try JSONCoding.atomicWrite(try JSONCoding.encoder().encode(document), to: fileURL)
                    return LoadResult(document: document, recovery: Recovery(restoredBackup: false, originalFile: original))
                }
                try JSONCoding.atomicWrite(data, to: fileURL)
                return LoadResult(document: document, recovery: Recovery(restoredBackup: true, originalFile: backupURL))
            }
            let document = StoreDocument()
            try save(document)
            return LoadResult(document: document, recovery: nil)
        }
        let data = try Data(contentsOf: fileURL)
        do {
            return LoadResult(document: try decode(data), recovery: nil)
        } catch LoadError.unsupportedSchema {
            // A newer schema is not corruption. Never replace it when downgrading.
            throw LoadError.unsupportedSchema
        } catch {
            Log.store.error("Store decode failed; attempting backup recovery error=\(error.localizedDescription, privacy: .public)")
            let backup: StoreDocument?
            if fm.fileExists(atPath: backupURL.path) {
                do {
                    backup = try decode(Data(contentsOf: backupURL))
                } catch LoadError.unsupportedSchema {
                    throw LoadError.unsupportedSchema
                } catch {
                    backup = nil
                }
            } else {
                backup = nil
            }
            guard let original = JSONCoding.quarantineCorruptFile(at: fileURL) else {
                // Preserve the only original if it cannot be safely moved aside.
                throw CocoaError(.fileWriteUnknown)
            }
            let document = backup ?? StoreDocument()
            // Do not replace a retained backup with fallback defaults during recovery.
            try JSONCoding.atomicWrite(try JSONCoding.encoder().encode(document), to: fileURL)
            return LoadResult(document: document, recovery: Recovery(restoredBackup: backup != nil, originalFile: original))
        }
    }

    private func decode(_ data: Data) throws -> StoreDocument {
        // Inspect the version before decoding fields that a future format may change.
        if let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = header["schemaVersion"] as? Int, version > 1 {
            throw LoadError.unsupportedSchema
        }
        let document = try JSONCoding.decoder().decode(StoreDocument.self, from: data)
        guard document.schemaVersion <= 1 else { throw LoadError.unsupportedSchema }
        return document
    }

    public func save(_ document: StoreDocument) throws {
        let data = try JSONCoding.encoder().encode(document)
        try JSONCoding.atomicWrite(data, to: fileURL)
        do {
            try JSONCoding.atomicWrite(data, to: backupURL)
        } catch {
            // The primary save succeeded. Retain the previous backup if this write fails.
            Log.store.error("Layout backup save failed error=\(error.localizedDescription, privacy: .public)")
        }
    }
}
