import AppKit
import Foundation
import ZoneBoxCore

@MainActor
final class UpdateInstaller: UpdateInstalling {
    var stagingDirectory: URL
    var currentExecutable: () -> URL? = { Bundle.main.executableURL }
    var parentPID: () -> Int32 = { ProcessInfo.processInfo.processIdentifier }
    var terminateApp: () -> Void = { NSApp.terminate(nil) }

    init(stagingDirectory: URL) {
        self.stagingDirectory = stagingDirectory
    }

    func install(fromDMG dmgURL: URL, offer: UpdateOffer, context: UpdateInstallContext) async -> UpdateInstallAttempt {
        switch UpdateInstallPolicy.eligibility(for: context) {
        case .unsupported(let blocker):
            return .unsupported(blocker)
        case .ready(let destination):
            do {
                try ReleaseUpdateSelector.validateDownloadedFile(
                    at: dmgURL,
                    expectedSize: offer.asset.size,
                    expectedSHA256: offer.expectedSHA256
                )
                let staging = stagingDirectory
                let currentVersion = context.version
                let architecture = context.architecture
                let staged = try await Task.detached(priority: .userInitiated) {
                    try UpdateDiskImage.stageVerifiedApp(
                        fromDMG: dmgURL,
                        offer: offer,
                        currentVersion: currentVersion,
                        architecture: architecture,
                        stagingDirectory: staging
                    )
                }.value
                return try launchHelper(
                    source: staged,
                    destination: destination,
                    offer: offer,
                    currentVersion: context.version,
                    architecture: context.architecture
                )
            } catch let error as UpdateStagedBundleError {
                return .failed(Self.message(for: error))
            } catch {
                Log.update.error("Update install failed error=\(error.localizedDescription, privacy: .public)")
                return .failed(L10n.text(.settingsUpdateInstallFailed))
            }
        }
    }

    private func launchHelper(
        source: URL,
        destination: URL,
        offer: UpdateOffer,
        currentVersion: String,
        architecture: UpdateArchitecture
    ) throws -> UpdateInstallAttempt {
        guard let executable = currentExecutable() else {
            return .failed(L10n.text(.settingsUpdateInstallFailed))
        }
        let helperURL = stagingDirectory.appendingPathComponent("ZoneBox-update-helper")
        let fm = FileManager.default
        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: helperURL.path) {
            try fm.removeItem(at: helperURL)
        }
        try fm.copyItem(at: executable, to: helperURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        let request = UpdateHelperLaunch.request(
            parentPID: parentPID(),
            sourceApp: source,
            destinationApp: destination,
            helperURL: helperURL,
            expectedVersion: offer.latestVersion.description,
            currentVersion: currentVersion,
            architecture: architecture,
            errorFile: stagingDirectory.appendingPathComponent("install-error.json")
        )
        let process = Process()
        process.executableURL = helperURL
        process.arguments = UpdateHelperArguments.makeArguments(request)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        terminateApp()
        return .helperStarted
    }

    private static func message(for error: UpdateStagedBundleError) -> String {
        switch error {
        case .missingBundle, .unreadableInfo:
            return L10n.text(.settingsUpdateInstallInvalidBundle)
        case .bundleIDMismatch, .signatureRejected:
            return L10n.text(.settingsUpdateInstallSignature)
        case .versionMismatch, .notNewer:
            return L10n.text(.settingsUpdateInstallVersion)
        case .architectureMismatch:
            return L10n.text(.settingsUpdateInstallArchitecture)
        }
    }
}

enum UpdateDiskImage {
    static func stageVerifiedApp(
        fromDMG dmgURL: URL,
        offer: UpdateOffer,
        currentVersion: String,
        architecture: UpdateArchitecture,
        stagingDirectory: URL
    ) throws -> URL {
        let fm = FileManager.default
        let mountPoint = stagingDirectory.appendingPathComponent("mnt-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer {
            detach(mountPoint)
            try? fm.removeItem(at: mountPoint)
        }
        try attach(dmgURL, mountPoint: mountPoint)
        let mountedApp = mountPoint.appendingPathComponent(OfficialUpdateIdentity.appFileName, isDirectory: true)
        let mounted = try UpdateStagedBundleLoader.load(fromApp: mountedApp)
        if case .failure(let error) = UpdateStagedBundleGate.evaluate(
            staged: mounted,
            offer: offer,
            currentVersion: currentVersion,
            architecture: architecture
        ) {
            throw error
        }
        let stagedRoot = stagingDirectory.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagedRoot, withIntermediateDirectories: true)
        let stagedApp = stagedRoot.appendingPathComponent(OfficialUpdateIdentity.appFileName, isDirectory: true)
        if fm.fileExists(atPath: stagedApp.path) {
            try fm.removeItem(at: stagedApp)
        }
        try fm.copyItem(at: mountedApp, to: stagedApp)
        let staged = try UpdateStagedBundleLoader.load(fromApp: stagedApp)
        if case .failure(let error) = UpdateStagedBundleGate.evaluate(
            staged: staged,
            offer: offer,
            currentVersion: currentVersion,
            architecture: architecture
        ) {
            try? fm.removeItem(at: stagedRoot)
            throw error
        }
        return stagedApp
    }

    private static func attach(_ dmg: URL, mountPoint: URL) throws {
        let status = try runHdiutil([
            "attach", dmg.path,
            "-nobrowse",
            "-readonly",
            "-noverify",
            "-mountpoint", mountPoint.path,
        ])
        guard status == 0 else {
            throw UpdateStagedBundleError.missingBundle
        }
    }

    private static func detach(_ mountPoint: URL) {
        _ = try? runHdiutil(["detach", mountPoint.path, "-quiet", "-force"])
    }

    @discardableResult
    private static func runHdiutil(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
