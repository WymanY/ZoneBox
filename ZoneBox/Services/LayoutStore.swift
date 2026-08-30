import Foundation

public struct LayoutStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let root = directory ?? AppIdentity.defaultSupportDirectory
        self.fileURL = root.appendingPathComponent("store.json")
    }

    public func load() throws -> StoreDocument {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            let document = StoreDocument()
            try save(document)
            return document
        }
        let data = try Data(contentsOf: fileURL)
        do {
            let document = try JSONCoding.decoder().decode(StoreDocument.self, from: data)
            if document.schemaVersion > 1 {
                throw CocoaError(.fileReadCorruptFile)
            }
            return document
        } catch {
            let corrupt = fileURL.deletingLastPathComponent()
                .appendingPathComponent("store.json.corrupt-\(Int(Date().timeIntervalSince1970))")
            try? fm.moveItem(at: fileURL, to: corrupt)
            let document = StoreDocument()
            try save(document)
            return document
        }
    }

    public func save(_ document: StoreDocument) throws {
        let data = try JSONCoding.encoder().encode(document)
        try JSONCoding.atomicWrite(data, to: fileURL)
    }
}
