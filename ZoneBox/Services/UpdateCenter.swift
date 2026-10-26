import AppKit
import Foundation
import ZoneBoxCore

@MainActor
final class UpdateCenter {
    enum Retry: Equatable {
        case check
        case download(UpdateOffer)
    }

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(current: String, latest: String)
        case available(UpdateOffer)
        case downloading(UpdateOffer, received: Int64, expected: Int64)
        case downloaded(UpdateOffer, fileURL: URL)
        case failed(message: String, retry: Retry)
    }

    private let client: GitHubReleaseClient
    private let store: UpdateStore
    private let directory: URL
    private var downloadSession: UpdateDownloadSession?
    private var checkTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var checkGeneration = 0
    private(set) var record: UpdateRecord
    private(set) var phase: Phase = .idle
    var onChange: (() -> Void)?
    var automaticUpdatesEnabled: () -> Bool = { true }
    var currentVersion: () -> String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    var architecture: UpdateArchitecture = {
#if arch(arm64)
        .arm64
#else
        .x86_64
#endif
    }()

    init(store: UpdateStore = UpdateStore(), client: GitHubReleaseClient = GitHubReleaseClient()) {
        self.store = store
        self.client = client
        self.directory = store.fileURL.deletingLastPathComponent().appendingPathComponent("Updates", isDirectory: true)
        self.record = (try? store.load()) ?? .empty
    }

    var currentVersionText: String { currentVersion() }

    func start() {
        restoreDownloadedIfNeeded()
        checkTask?.cancel()
        checkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.checkIfDue()
        }
        startPolling()
    }

    func invalidate() {
        checkTask?.cancel()
        checkTask = nil
        checkGeneration += 1
        stopPolling()
        abandonDownloadSession()
    }

    func checkIfDue() async {
        let due = UpdateSchedule.shouldAutomaticallyCheck(
            enabled: automaticUpdatesEnabled(),
            lastCheckAt: record.lastCheckAt,
            lastSuccessfulCheckAt: record.lastSuccessfulCheckAt,
            now: Date()
        )
        guard due else { return }
        await checkNow()
    }

    func checkNow() async {
        switch phase {
        case .checking, .downloading:
            return
        default:
            break
        }
        checkGeneration += 1
        let generation = checkGeneration
        phase = .checking
        notify()
        record.lastCheckAt = Date()
        persist()
        do {
            let data = try await client.fetchLatest()
            guard generation == checkGeneration else { return }
            if case .downloading = phase { return }
            let evaluation = try ReleaseUpdateSelector.evaluate(
                json: data,
                currentVersion: currentVersion(),
                architecture: architecture
            )
            apply(evaluation)
        } catch {
            guard generation == checkGeneration else { return }
            if case .downloading = phase { return }
            phase = .failed(message: message(for: error), retry: .check)
            Log.update.error("Update check failed error=\(error.localizedDescription, privacy: .public)")
        }
        persist()
        notify()
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: UpdateSchedule.minimumRetryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkIfDue()
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.checkIfDue()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.checkIfDue()
            }
        })
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func download(_ offer: UpdateOffer) async {
        switch phase {
        case .checking, .downloading:
            return
        default:
            break
        }
        checkGeneration += 1
        let generation = checkGeneration
        phase = .downloading(offer, received: 0, expected: Int64(offer.asset.size))
        notify()
        let session = UpdateDownloadSession(userAgent: GitHubReleaseClient.defaultUserAgent())
        abandonDownloadSession()
        downloadSession = session
        session.onProgress = { [weak self] received, expected in
            Task { @MainActor in
                guard let self else { return }
                guard self.checkGeneration == generation, self.downloadSession === session else { return }
                if case .downloading(let current, _, _) = self.phase, current.tagName == offer.tagName {
                    self.phase = .downloading(offer, received: received, expected: expected)
                    self.notify()
                }
            }
        }
        do {
            let temp = try await session.download(offer.asset.browserDownloadURL)
            defer { try? FileManager.default.removeItem(at: temp) }
            guard generation == checkGeneration, downloadSession === session else { return }
            try ReleaseUpdateSelector.validateDownloadedFile(
                at: temp,
                expectedSize: offer.asset.size,
                expectedSHA256: offer.expectedSHA256
            )
            let destination = try moveIntoUpdatesFolder(temp, name: offer.asset.name)
            guard generation == checkGeneration, downloadSession === session else { return }
            try ReleaseUpdateSelector.validateDownloadedFile(
                at: destination,
                expectedSize: offer.asset.size,
                expectedSHA256: offer.expectedSHA256
            )
            remember(offer, at: destination)
            persist()
            phase = .downloaded(offer, fileURL: destination)
        } catch is CancellationError {
            guard generation == checkGeneration, downloadSession === session else { return }
            phase = .available(offer)
        } catch let error as URLError where error.code == .cancelled {
            guard generation == checkGeneration, downloadSession === session else { return }
            phase = .available(offer)
        } catch {
            guard generation == checkGeneration, downloadSession === session else { return }
            Log.update.error("Update download failed error=\(error.localizedDescription, privacy: .public)")
            phase = .failed(message: message(for: error), retry: .download(offer))
        }
        if downloadSession === session {
            abandonDownloadSession()
        }
        notify()
    }

    func cancelDownload() {
        downloadSession?.onProgress = nil
        downloadSession?.cancel()
    }

    func retry() {
        switch phase {
        case .failed(_, .check), .idle:
            Task { await checkNow() }
        case .failed(_, .download(let offer)), .available(let offer):
            Task { await download(offer) }
        default:
            break
        }
    }

    func revealInstaller() {
        guard case .downloaded(_, let url) = phase else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInstaller() {
        guard case .downloaded(_, let url) = phase else { return }
        NSWorkspace.shared.open(url)
    }

    private func apply(_ evaluation: ReleaseEvaluation) {
        record.lastSuccessfulCheckAt = Date()
        switch evaluation {
        case .upToDate(let current, let latest):
            record.lastKnownLatestVersion = latest.description
            clearDownloadedInstaller()
            phase = .upToDate(current: current.description, latest: latest.description)
        case .available(let offer):
            record.lastKnownLatestVersion = offer.latestVersion.description
            if let existing = existingValidDownload(for: offer) {
                remember(offer, at: existing)
                phase = .downloaded(offer, fileURL: existing)
            } else {
                phase = .available(offer)
            }
        case .rejected(.notNewer(let current, let latest)):
            record.lastKnownLatestVersion = latest.description
            clearDownloadedInstaller()
            phase = .upToDate(current: current.description, latest: latest.description)
        case .rejected(.noMacInstaller):
            phase = .failed(message: L10n.text(.settingsUpdateNoInstaller), retry: .check)
        case .rejected(.prerelease), .rejected(.draft):
            phase = .failed(message: L10n.text(.settingsUpdatePrerelease), retry: .check)
        case .rejected(.missingDigest), .rejected(.invalidAssetSize), .rejected(.unreadableReleaseVersion):
            phase = .failed(message: L10n.text(.settingsUpdateErrorInvalid), retry: .check)
        case .rejected(.unreadableCurrentVersion):
            phase = .failed(message: L10n.text(.settingsUpdateErrorGeneric), retry: .check)
        }
    }

    private func restoreDownloadedIfNeeded() {
        guard let restored = DownloadedInstallerRestore.makeOffer(from: record, currentVersion: currentVersion()) else {
            if record.downloadedInstaller != nil {
                let path = record.downloadedInstaller?.path ?? record.downloadedInstallerPath
                if let path, !FileManager.default.fileExists(atPath: path) {
                    clearDownloadedInstaller()
                    persist()
                }
            }
            return
        }
        do {
            try ReleaseUpdateSelector.validateDownloadedFile(
                at: restored.fileURL,
                expectedSize: restored.offer.asset.size,
                expectedSHA256: restored.offer.expectedSHA256
            )
            phase = .downloaded(restored.offer, fileURL: restored.fileURL)
        } catch {
            clearDownloadedInstaller()
            persist()
        }
    }

    private func existingValidDownload(for offer: UpdateOffer) -> URL? {
        let candidates = [
            record.downloadedInstallerPath.map(URL.init(fileURLWithPath:)),
            try? updatesFolder().appendingPathComponent(sanitizedFileName(offer.asset.name)),
        ].compactMap { $0 }
        for url in candidates {
            if (try? ReleaseUpdateSelector.validateDownloadedFile(
                at: url,
                expectedSize: offer.asset.size,
                expectedSHA256: offer.expectedSHA256
            )) != nil {
                return url
            }
        }
        return nil
    }

    private func moveIntoUpdatesFolder(_ temp: URL, name: String) throws -> URL {
        let folder = try updatesFolder()
        return try UpdateFilePlacement.place(from: temp, intoDirectory: folder, named: sanitizedFileName(name))
    }

    private func updatesFolder() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func sanitizedFileName(_ raw: String) -> String {
        let name = URL(fileURLWithPath: raw).lastPathComponent
        if name.isEmpty || name == "." || name == ".." || name.contains("/") { return "ZoneBox-update.dmg" }
        return name
    }

    private func persist() {
        do {
            try store.save(record)
        } catch {
            Log.update.error("Update record save failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func remember(_ offer: UpdateOffer, at url: URL) {
        record.lastKnownLatestVersion = offer.latestVersion.description
        record.downloadedInstallerPath = url.path
        record.downloadedInstaller = DownloadedInstallerRecord(
            version: offer.latestVersion.description,
            tagName: offer.tagName,
            assetName: offer.asset.name,
            size: offer.asset.size,
            sha256: offer.expectedSHA256,
            downloadURL: offer.asset.browserDownloadURL.absoluteString,
            path: url.path
        )
    }

    private func clearDownloadedInstaller() {
        record.downloadedInstaller = nil
        record.downloadedInstallerPath = nil
    }

    private func abandonDownloadSession() {
        downloadSession?.onProgress = nil
        downloadSession?.cancel()
        downloadSession?.invalidate()
        downloadSession = nil
    }

    private func notify() {
        onChange?()
    }

    private func message(for error: Error) -> String {
        if let client = error as? GitHubReleaseClientError {
            switch client {
            case .network, .invalidResponse:
                return L10n.text(.settingsUpdateErrorNetwork)
            case .http(let code):
                return String(format: L10n.text(.settingsUpdateErrorHTTP), locale: LanguageCenter.language.locale, code)
            }
        }
        if let parse = error as? ReleaseParseError, parse == .invalidJSON {
            return L10n.text(.settingsUpdateErrorInvalid)
        }
        if let validation = error as? UpdateValidationError {
            switch validation {
            case .digestMismatch:
                return L10n.text(.settingsUpdateErrorDigest)
            case .sizeMismatch:
                return L10n.text(.settingsUpdateErrorSize)
            case .missingFile, .unreadable:
                return L10n.text(.settingsUpdateErrorGeneric)
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled:
                return L10n.text(.settingsUpdateCancelled)
            default:
                return L10n.text(.settingsUpdateErrorNetwork)
            }
        }
        return L10n.text(.settingsUpdateErrorGeneric)
    }
}

final class UpdateDownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    var onProgress: ((Int64, Int64) -> Void)?

    init(userAgent: String) {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 15 * 60
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            continuation = cont
            lock.unlock()
            var request = URLRequest(url: url)
            request.setValue(GitHubReleaseClient.defaultUserAgent(), forHTTPHeaderField: "User-Agent")
            task = session.downloadTask(with: request)
            task?.resume()
        }
    }

    func cancel() {
        onProgress = nil
        task?.cancel()
    }

    func invalidate() {
        onProgress = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            resume(.failure(GitHubReleaseClientError.http(code)))
            return
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("zonebox-update-\(UUID().uuidString)")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: location, to: dest)
            resume(.success(dest))
        } catch {
            resume(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        resume(.failure(error))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    private func resume(_ result: Result<URL, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }
}
