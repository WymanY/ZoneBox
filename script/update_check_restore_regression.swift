import Foundation
import ZoneBoxCore

// Repeatable runner from repo root:
//   ./script/run_update_check_restore_regression.sh
// Needs Debug ZoneBoxCore at .build/VerificationDerivedData/Build/Products/Debug/libZoneBoxCore.a
// from make build or make test. Compiles GitHubReleaseClient.swift, UpdateCenter.swift,
// and UpdateInstaller.swift against that library with a URLProtocol fixture.
// A no-op UpdateInstalling stub is injected so this harness never stages or replaces an app.
// No internet, NSWorkspace, or app prefs.

@main
enum UpdateCheckRestoreRegression {
    static func main() async {
        do {
            try await Task { @MainActor in
                try await run()
            }.value
            fputs("RESTORE_REGRESSION_OK\n", stderr)
        } catch {
            fputs("RESTORE_REGRESSION_FAIL \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    static func run() async throws {
        try await validInstallerSurvivesOfflineCheckAndRestart()
        try await missingFileStaysFailed()
        try await sizeMismatchStaysFailed()
        try await hashMismatchStaysFailed()
        try await noDownloadStaysFailed()
        try await parseFailureRestoresValidInstaller()
        try await rejectedReleaseRestoresValidInstaller()
        try await sameVersionDoesNotExposeOldInstaller()
    }

    @MainActor
    static func validInstallerSurvivesOfflineCheckAndRestart() async throws {
        let env = try makeEnv(payload: Data("zonebox-valid-installer".utf8))
        defer { env.cleanup() }
        StubURLProtocol.failWith(URLError(.notConnectedToInternet))

        let first = makeCenter(store: env.store)
        await first.checkNow()
        try expectDownloaded(first.phase, file: env.file, context: "same-run offline check")
        try expectInstallerRetained(env.store, file: env.file)
        guard first.record.lastCheckAt != nil else {
            throw Failure("offline check should stamp lastCheckAt")
        }
        guard first.record.lastSuccessfulCheckAt == env.seededSuccess else {
            throw Failure("offline check must not rewrite lastSuccessfulCheckAt")
        }
        first.invalidate()

        let restarted = makeCenter(store: env.store)
        restarted.start()
        try expectDownloaded(restarted.phase, file: env.file, context: "restart restore")
        await restarted.checkNow()
        try expectDownloaded(restarted.phase, file: env.file, context: "restart offline check")
        try expectInstallerRetained(env.store, file: env.file)
        restarted.invalidate()
        fputs("CASE_OK valid-offline-and-restart\n", stderr)
    }

    @MainActor
    static func missingFileStaysFailed() async throws {
        let env = try makeEnv(payload: Data("zonebox-missing".utf8))
        defer { env.cleanup() }
        try FileManager.default.removeItem(at: env.file)
        StubURLProtocol.failWith(URLError(.notConnectedToInternet))
        let center = makeCenter(store: env.store)
        await center.checkNow()
        try expectFailedCheck(center.phase, context: "missing file")
        try expectInstallerCleared(env.store)
        center.invalidate()
        fputs("CASE_OK missing-file\n", stderr)
    }

    @MainActor
    static func sizeMismatchStaysFailed() async throws {
        let env = try makeEnv(payload: Data("zonebox-size".utf8))
        defer { env.cleanup() }
        try Data("zonebox-size-too-long".utf8).write(to: env.file)
        StubURLProtocol.failWith(URLError(.notConnectedToInternet))
        let center = makeCenter(store: env.store)
        await center.checkNow()
        try expectFailedCheck(center.phase, context: "size mismatch")
        try expectInstallerCleared(env.store)
        center.invalidate()
        fputs("CASE_OK size-mismatch\n", stderr)
    }

    @MainActor
    static func hashMismatchStaysFailed() async throws {
        let env = try makeEnv(payload: Data("zonebox-hash".utf8))
        defer { env.cleanup() }
        try Data("zonebox-hack".utf8).write(to: env.file)
        StubURLProtocol.failWith(URLError(.notConnectedToInternet))
        let center = makeCenter(store: env.store)
        await center.checkNow()
        try expectFailedCheck(center.phase, context: "hash mismatch")
        try expectInstallerCleared(env.store)
        center.invalidate()
        fputs("CASE_OK hash-mismatch\n", stderr)
    }

    @MainActor
    static func noDownloadStaysFailed() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("zonebox-restore-none-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let store = UpdateStore(directory: work)
        try store.save(.empty)
        StubURLProtocol.failWith(URLError(.notConnectedToInternet))
        let center = makeCenter(store: store)
        await center.checkNow()
        try expectFailedCheck(center.phase, context: "no download")
        let loaded = try store.load()
        guard loaded.downloadedInstaller == nil, loaded.downloadedInstallerPath == nil else {
            throw Failure("no-download check exposed an installer record")
        }
        guard loaded.lastCheckAt != nil else {
            throw Failure("no-download check should stamp lastCheckAt")
        }
        center.invalidate()
        fputs("CASE_OK no-download\n", stderr)
    }

    @MainActor
    static func parseFailureRestoresValidInstaller() async throws {
        let env = try makeEnv(payload: Data("zonebox-parse".utf8))
        defer { env.cleanup() }
        StubURLProtocol.respond(status: 200, body: Data("{".utf8))
        let center = makeCenter(store: env.store)
        await center.checkNow()
        try expectDownloaded(center.phase, file: env.file, context: "invalid JSON check")
        try expectInstallerRetained(env.store, file: env.file)
        center.invalidate()
        fputs("CASE_OK parse-failure-restore\n", stderr)
    }

    @MainActor
    static func rejectedReleaseRestoresValidInstaller() async throws {
        let env = try makeEnv(payload: Data("zonebox-rejected".utf8))
        defer { env.cleanup() }
        let json = """
        {
          "tag_name": "0.9.0",
          "draft": false,
          "prerelease": true,
          "assets": [
            {
              "name": "ZoneBox-0.9.0.dmg",
              "size": 12,
              "browser_download_url": "https://github.com/WymanY/ZoneBox/releases/download/0.9.0/ZoneBox-0.9.0.dmg",
              "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            }
          ]
        }
        """
        StubURLProtocol.respond(status: 200, body: Data(json.utf8))
        let center = makeCenter(store: env.store)
        await center.checkNow()
        try expectDownloaded(center.phase, file: env.file, context: "rejected prerelease check")
        try expectInstallerRetained(env.store, file: env.file)
        center.invalidate()
        fputs("CASE_OK rejected-restore\n", stderr)
    }

    @MainActor
    static func sameVersionDoesNotExposeOldInstaller() async throws {
        let env = try makeEnv(payload: Data("zonebox-same-version".utf8))
        defer { env.cleanup() }
        StubURLProtocol.failWith(URLError(.notConnectedToInternet))
        let center = makeCenter(store: env.store, currentVersion: "0.5.1")
        await center.checkNow()
        try expectFailedCheck(center.phase, context: "same version 0.5.1 offline check")
        if case .downloaded = center.phase {
            throw Failure("same version 0.5.1 exposed the stored installer")
        }
        center.invalidate()
        fputs("CASE_OK same-version-hidden\n", stderr)
    }

    @MainActor
    static func makeCenter(store: UpdateStore, currentVersion: String = "0.5.0") -> UpdateCenter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        let client = GitHubReleaseClient(
            endpoint: URL(string: "https://api.github.com/repos/WymanY/ZoneBox/releases/latest")!,
            session: URLSession(configuration: config),
            userAgent: "ZoneBoxRestoreRegression/1"
        )
        let center = UpdateCenter(store: store, client: client, installer: RegressionInstaller())
        center.currentVersion = { currentVersion }
        center.updateCheckFrequency = { .manual }
        return center
    }

    static func makeEnv(payload: Data) throws -> Env {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("zonebox-restore-" + UUID().uuidString, isDirectory: true)
        let updates = work.appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updates, withIntermediateDirectories: true)
        let file = updates.appendingPathComponent("ZoneBox-0.5.1.dmg")
        try payload.write(to: file)
        let digest = UpdateDigest.sha256Hex(of: payload)
        let store = UpdateStore(directory: work)
        let seededSuccess = Date(timeIntervalSince1970: 1_700_000_000)
        var record = UpdateRecord.empty
        record.lastSuccessfulCheckAt = seededSuccess
        record.lastKnownLatestVersion = "0.5.1"
        record.downloadedInstallerPath = file.path
        record.downloadedInstaller = DownloadedInstallerRecord(
            version: "0.5.1",
            tagName: "0.5.1",
            assetName: "ZoneBox-0.5.1.dmg",
            size: payload.count,
            sha256: digest,
            downloadURL: "https://github.com/WymanY/ZoneBox/releases/download/0.5.1/ZoneBox-0.5.1.dmg",
            path: file.path
        )
        try store.save(record)
        return Env(work: work, store: store, file: file, seededSuccess: seededSuccess)
    }

    static func expectDownloaded(_ phase: UpdateCenter.Phase, file: URL, context: String) throws {
        guard case .downloaded(_, let url) = phase else {
            throw Failure("\(context): expected downloaded, got \(phase)")
        }
        guard url.path == file.path else {
            throw Failure("\(context): restored path \(url.path) != \(file.path)")
        }
    }

    static func expectFailedCheck(_ phase: UpdateCenter.Phase, context: String) throws {
        guard case .failed(_, .check) = phase else {
            throw Failure("\(context): expected failed(.check), got \(phase)")
        }
    }

    static func expectInstallerRetained(_ store: UpdateStore, file: URL) throws {
        let loaded = try store.load()
        guard loaded.downloadedInstaller?.path == file.path else {
            throw Failure("installer record was not kept for \(file.path)")
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw Failure("installer file missing at \(file.path)")
        }
    }

    static func expectInstallerCleared(_ store: UpdateStore) throws {
        let loaded = try store.load()
        guard loaded.downloadedInstaller == nil, loaded.downloadedInstallerPath == nil else {
            throw Failure("invalid installer remained in the store")
        }
    }

    struct Env {
        let work: URL
        let store: UpdateStore
        let file: URL
        let seededSuccess: Date
        func cleanup() {
            try? FileManager.default.removeItem(at: work)
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}

@MainActor
final class RegressionInstaller: UpdateInstalling {
    func install(fromDMG dmgURL: URL, offer: UpdateOffer, context: UpdateInstallContext) async -> UpdateInstallAttempt {
        .unsupported(.debugBuild)
    }
}

final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var boxedHandler: (@Sendable (URLRequest) throws -> (Int, Data))?

    static func failWith(_ error: Error) {
        lock.lock()
        boxedHandler = { _ in throw error }
        lock.unlock()
    }

    static func respond(status: Int, body: Data) {
        lock.lock()
        boxedHandler = { _ in (status, body) }
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler: (@Sendable (URLRequest) throws -> (Int, Data))?
        Self.lock.lock()
        handler = Self.boxedHandler
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.notConnectedToInternet) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.github.com/")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
