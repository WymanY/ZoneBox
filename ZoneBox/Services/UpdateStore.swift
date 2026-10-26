import Foundation

public struct UpdateRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var lastCheckAt: Date?
    public var lastSuccessfulCheckAt: Date?
    public var lastKnownLatestVersion: String?
    public var downloadedInstallerPath: String?
    public var downloadedInstaller: DownloadedInstallerRecord?

    public init(
        schemaVersion: Int = 1,
        lastCheckAt: Date? = nil,
        lastSuccessfulCheckAt: Date? = nil,
        lastKnownLatestVersion: String? = nil,
        downloadedInstallerPath: String? = nil,
        downloadedInstaller: DownloadedInstallerRecord? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.lastCheckAt = lastCheckAt
        self.lastSuccessfulCheckAt = lastSuccessfulCheckAt
        self.lastKnownLatestVersion = lastKnownLatestVersion
        self.downloadedInstallerPath = downloadedInstallerPath
        self.downloadedInstaller = downloadedInstaller
    }

    public static let empty = UpdateRecord()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        lastCheckAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckAt)
        lastSuccessfulCheckAt = try c.decodeIfPresent(Date.self, forKey: .lastSuccessfulCheckAt)
        lastKnownLatestVersion = try c.decodeIfPresent(String.self, forKey: .lastKnownLatestVersion)
        downloadedInstallerPath = try c.decodeIfPresent(String.self, forKey: .downloadedInstallerPath)
        downloadedInstaller = try c.decodeIfPresent(DownloadedInstallerRecord.self, forKey: .downloadedInstaller)
    }
}

public struct DownloadedInstallerRecord: Codable, Equatable, Sendable {
    public var version: String
    public var tagName: String
    public var assetName: String
    public var size: Int
    public var sha256: String
    public var downloadURL: String
    public var path: String

    public init(
        version: String,
        tagName: String,
        assetName: String,
        size: Int,
        sha256: String,
        downloadURL: String,
        path: String
    ) {
        self.version = version
        self.tagName = tagName
        self.assetName = assetName
        self.size = size
        self.sha256 = sha256
        self.downloadURL = downloadURL
        self.path = path
    }
}

public enum UpdateDownloadURL {
    public static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        let host = (url.host ?? "").lowercased()
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host.hasSuffix(".githubusercontent.com")
    }
}

public enum DownloadedInstallerRestore {
    public static func makeOffer(from record: UpdateRecord, currentVersion rawCurrent: String) -> (offer: UpdateOffer, fileURL: URL)? {
        guard let installer = record.downloadedInstaller else { return nil }
        guard let current = AppVersion.parse(rawCurrent) else { return nil }
        guard let latest = AppVersion.parse(installer.version) ?? AppVersion.parse(installer.tagName), current < latest else {
            return nil
        }
        guard let url = URL(string: installer.downloadURL), UpdateDownloadURL.isTrusted(url) else { return nil }
        guard installer.size > 0, let digest = UpdateDigest.parse(installer.sha256) else { return nil }
        let name = URL(fileURLWithPath: installer.assetName).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
        let fileURL = URL(fileURLWithPath: installer.path)
        let offer = UpdateOffer(
            currentVersion: current,
            latestVersion: latest,
            tagName: installer.tagName.isEmpty ? installer.version : installer.tagName,
            asset: GitHubReleaseAsset(
                name: name,
                size: installer.size,
                browserDownloadURL: url,
                digest: "sha256:" + digest
            ),
            expectedSHA256: digest
        )
        return (offer, fileURL)
    }
}

public enum UpdateFilePlacement {
    public static func place(from source: URL, intoDirectory directory: URL, named name: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        let staged = directory.appendingPathComponent("." + name + ".staging-" + UUID().uuidString)
        do {
            try fm.copyItem(at: source, to: staged)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: destination)
            }
            return destination
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
    }
}

public struct UpdateStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let root = directory ?? AppIdentity.defaultSupportDirectory
        self.fileURL = root.appendingPathComponent("updates.json")
    }

    public func load() throws -> UpdateRecord {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            try save(.empty)
            return .empty
        }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONCoding.decoder().decode(UpdateRecord.self, from: data)
        } catch {
            Log.store.error(
                "Update record decode failed; starting empty path=\(self.fileURL.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            JSONCoding.quarantineCorruptFile(at: fileURL)
            try save(.empty)
            return .empty
        }
    }

    public func save(_ record: UpdateRecord) throws {
        let data = try JSONCoding.encoder().encode(record)
        try JSONCoding.atomicWrite(data, to: fileURL)
    }
}
