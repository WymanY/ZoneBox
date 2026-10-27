import CryptoKit
import Foundation

public enum UpdateArchitecture: String, Sendable, Equatable {
    case arm64
    case x86_64
}

public struct GitHubReleaseAsset: Equatable, Sendable {
    public var name: String
    public var size: Int
    public var browserDownloadURL: URL
    public var digest: String?

    public init(name: String, size: Int, browserDownloadURL: URL, digest: String? = nil) {
        self.name = name
        self.size = size
        self.browserDownloadURL = browserDownloadURL
        self.digest = digest
    }
}

public struct GitHubRelease: Equatable, Sendable {
    public var tagName: String
    public var name: String?
    public var draft: Bool
    public var prerelease: Bool
    public var assets: [GitHubReleaseAsset]

    public init(tagName: String, name: String? = nil, draft: Bool, prerelease: Bool, assets: [GitHubReleaseAsset]) {
        self.tagName = tagName
        self.name = name
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }
}

public struct UpdateOffer: Equatable, Sendable {
    public var currentVersion: AppVersion
    public var latestVersion: AppVersion
    public var tagName: String
    public var asset: GitHubReleaseAsset
    public var expectedSHA256: String

    public init(
        currentVersion: AppVersion,
        latestVersion: AppVersion,
        tagName: String,
        asset: GitHubReleaseAsset,
        expectedSHA256: String
    ) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.tagName = tagName
        self.asset = asset
        self.expectedSHA256 = expectedSHA256
    }
}

public enum UpdateRejection: Equatable, Sendable {
    case unreadableCurrentVersion
    case unreadableReleaseVersion
    case draft
    case prerelease
    case notNewer(current: AppVersion, latest: AppVersion)
    case noMacInstaller
    case missingDigest
    case invalidAssetSize
}

public enum ReleaseEvaluation: Equatable, Sendable {
    case upToDate(current: AppVersion, latest: AppVersion)
    case available(UpdateOffer)
    case rejected(UpdateRejection)
}

public enum ReleaseParseError: Error, Equatable {
    case invalidJSON
}

public enum UpdateValidationError: Error, Equatable {
    case missingFile
    case unreadable
    case sizeMismatch(expected: Int, actual: Int)
    case digestMismatch
}

public enum UpdateDigest {
    public static func parse(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let hex: String
        if trimmed.hasPrefix("sha256:") {
            hex = String(trimmed.dropFirst(7))
        } else {
            hex = trimmed
        }
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return hex
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(ofFile url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw UpdateValidationError.unreadable
        }
        return sha256Hex(of: data)
    }
}

public enum UpdateCheckFrequency: String, Codable, Sendable, Equatable, CaseIterable {
    case onLaunch
    case daily
    case weekly
    case manual
}

public enum HomeUpdateLiveState: Equatable, Sendable {
    case none
    case checking
    case upToDate
    case available(version: String)
    case downloading(version: String, percent: Int)
    case downloaded(version: String)
    case checkFailed
    case downloadFailed(version: String)
    case installing(version: String)
    case installFailed(version: String)
}

public enum HomeUpdateNotice: Equatable, Sendable {
    case available(version: String)
    case downloading(version: String, percent: Int)
    case downloaded(version: String)
    case downloadFailed(version: String)
    case installing(version: String)
    case installFailed(version: String)
    case knownNewer(version: String)

    public var version: String {
        switch self {
        case .available(let version),
             .downloading(let version, _),
             .downloaded(let version),
             .downloadFailed(let version),
             .installing(let version),
             .installFailed(let version),
             .knownNewer(let version):
            return version
        }
    }

    public var needsOfferRefresh: Bool {
        if case .knownNewer = self { return true }
        return false
    }

    public static func make(
        currentVersion: String,
        lastKnownLatestVersion: String?,
        live: HomeUpdateLiveState
    ) -> HomeUpdateNotice? {
        switch live {
        case .upToDate:
            return nil
        case .available(let version):
            return .available(version: version)
        case .downloading(let version, let percent):
            return .downloading(version: version, percent: min(max(percent, 0), 100))
        case .downloaded(let version):
            return .downloaded(version: version)
        case .downloadFailed(let version):
            return .downloadFailed(version: version)
        case .installing(let version):
            return .installing(version: version)
        case .installFailed(let version):
            return .installFailed(version: version)
        case .none, .checking, .checkFailed:
            guard let cached = cachedNewerVersion(
                currentVersion: currentVersion,
                lastKnownLatestVersion: lastKnownLatestVersion
            ) else {
                return nil
            }
            return .knownNewer(version: cached)
        }
    }

    public static func cachedNewerVersion(
        currentVersion: String,
        lastKnownLatestVersion: String?
    ) -> String? {
        guard let raw = lastKnownLatestVersion?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        guard let current = AppVersion.parse(currentVersion), let latest = AppVersion.parse(raw) else {
            return nil
        }
        guard current < latest else { return nil }
        return latest.description
    }
}

public enum UpdateSchedule {
    public static let dailyInterval: TimeInterval = 24 * 60 * 60
    public static let weeklyInterval: TimeInterval = 7 * 24 * 60 * 60
    public static let minimumRetryInterval: TimeInterval = 15 * 60

    public static func shouldSkipAutomaticCheck(unresolvedInstallFailure: Bool) -> Bool {
        unresolvedInstallFailure
    }

    public static func shouldAutomaticallyCheck(
        frequency: UpdateCheckFrequency,
        lastCheckAt: Date?,
        lastSuccessfulCheckAt: Date?,
        now: Date,
        launchCheckSatisfied: Bool
    ) -> Bool {
        switch frequency {
        case .manual:
            return false
        case .onLaunch:
            return !launchCheckSatisfied
        case .daily:
            guard backoffElapsed(lastCheckAt, now: now) else { return false }
            return intervalElapsed(lastSuccessfulCheckAt, interval: dailyInterval, now: now)
        case .weekly:
            guard backoffElapsed(lastCheckAt, now: now) else { return false }
            return intervalElapsed(lastSuccessfulCheckAt, interval: weeklyInterval, now: now)
        }
    }

    private static func backoffElapsed(_ lastCheckAt: Date?, now: Date) -> Bool {
        guard let last = lastCheckAt else { return true }
        return now.timeIntervalSince(last) >= minimumRetryInterval
    }

    private static func intervalElapsed(_ lastSuccessfulCheckAt: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let success = lastSuccessfulCheckAt else { return true }
        return now.timeIntervalSince(success) >= interval
    }
}

public enum ReleaseUpdateSelector {
    public static func parseRelease(from data: Data) throws -> GitHubRelease {
        let decoder = JSONDecoder()
        do {
            let dto = try decoder.decode(GitHubReleaseDTO.self, from: data)
            return dto.makeRelease()
        } catch {
            throw ReleaseParseError.invalidJSON
        }
    }

    public static func evaluate(
        release: GitHubRelease,
        currentVersion rawCurrent: String,
        architecture: UpdateArchitecture
    ) -> ReleaseEvaluation {
        guard let current = AppVersion.parse(rawCurrent) else {
            return .rejected(.unreadableCurrentVersion)
        }
        if release.draft { return .rejected(.draft) }
        if release.prerelease { return .rejected(.prerelease) }
        guard let latest = AppVersion.parse(release.tagName) ?? release.name.flatMap(AppVersion.parse) else {
            return .rejected(.unreadableReleaseVersion)
        }
        guard latest.isStable else { return .rejected(.prerelease) }
        if latest == current {
            return .upToDate(current: current, latest: latest)
        }
        guard current < latest else {
            return .rejected(.notNewer(current: current, latest: latest))
        }
        guard let asset = selectAsset(from: release.assets, version: latest, architecture: architecture) else {
            return .rejected(.noMacInstaller)
        }
        guard asset.size > 0 else { return .rejected(.invalidAssetSize) }
        guard let digest = UpdateDigest.parse(asset.digest) else { return .rejected(.missingDigest) }
        return .available(
            UpdateOffer(
                currentVersion: current,
                latestVersion: latest,
                tagName: release.tagName,
                asset: asset,
                expectedSHA256: digest
            )
        )
    }

    public static func evaluate(
        json: Data,
        currentVersion: String,
        architecture: UpdateArchitecture
    ) throws -> ReleaseEvaluation {
        evaluate(release: try parseRelease(from: json), currentVersion: currentVersion, architecture: architecture)
    }

    public static func selectAsset(
        from assets: [GitHubReleaseAsset],
        version: AppVersion,
        architecture: UpdateArchitecture
    ) -> GitHubReleaseAsset? {
        let installers = assets.filter(isMacInstaller)
        guard !installers.isEmpty else { return nil }
        let archSpecific = installers.filter { assetArchitecture($0) == architecture }
        if let chosen = preferredInstaller(archSpecific, version: version) {
            return chosen
        }
        let universal = installers.filter { assetArchitecture($0) == nil }
        return preferredInstaller(universal, version: version)
    }

    public static func validateDownloadedFile(
        at url: URL,
        expectedSize: Int,
        expectedSHA256: String
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw UpdateValidationError.missingFile
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let actual = values.fileSize ?? 0
        guard actual == expectedSize else {
            throw UpdateValidationError.sizeMismatch(expected: expectedSize, actual: actual)
        }
        let hex = try UpdateDigest.sha256Hex(ofFile: url)
        guard hex == expectedSHA256.lowercased() else {
            throw UpdateValidationError.digestMismatch
        }
    }

    public static func isMacInstaller(_ asset: GitHubReleaseAsset) -> Bool {
        let name = asset.name.lowercased()
        guard !name.isEmpty, !name.hasPrefix(".") else { return false }
        if name.contains("source") { return false }
        if name.contains("sha256") || name.contains("checksum") { return false }
        if name.hasSuffix(".txt") || name.hasSuffix("sums") { return false }
        if name.hasSuffix(".zip") || name.hasSuffix(".tar") || name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            return false
        }
        return name.hasSuffix(".dmg")
    }

    private static func preferredInstaller(_ assets: [GitHubReleaseAsset], version: AppVersion) -> GitHubReleaseAsset? {
        guard !assets.isEmpty else { return nil }
        let versionToken = version.description.lowercased()
        let matchingVersion = assets.filter { $0.name.lowercased().contains(versionToken) }
        let pool = matchingVersion.isEmpty ? assets : matchingVersion
        let named = pool.filter { $0.name.lowercased().hasPrefix("zonebox") }
        return (named.isEmpty ? pool : named).max { lhs, rhs in
            if lhs.size != rhs.size { return lhs.size < rhs.size }
            return lhs.name < rhs.name
        }
    }

    private static func assetArchitecture(_ asset: GitHubReleaseAsset) -> UpdateArchitecture? {
        let name = asset.name.lowercased()
        let arm = name.contains("arm64") || name.contains("apple-silicon") || name.contains("applesilicon")
        let intel = name.contains("x86_64") || name.contains("intel")
        if arm && !intel { return .arm64 }
        if intel && !arm { return .x86_64 }
        return nil
    }
}

private struct GitHubReleaseDTO: Decodable {
    var tagName: String
    var name: String?
    var draft: Bool?
    var prerelease: Bool?
    var assets: [Asset]?

    enum CodingKeys: String, CodingKey {
        case name, draft, prerelease, assets
        case tagName = "tag_name"
    }

    struct Asset: Decodable {
        var name: String
        var size: Int
        var browserDownloadURL: URL
        var digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    func makeRelease() -> GitHubRelease {
        GitHubRelease(
            tagName: tagName,
            name: name,
            draft: draft ?? false,
            prerelease: prerelease ?? false,
            assets: (assets ?? []).map {
                GitHubReleaseAsset(
                    name: $0.name,
                    size: $0.size,
                    browserDownloadURL: $0.browserDownloadURL,
                    digest: $0.digest
                )
            }
        )
    }
}
