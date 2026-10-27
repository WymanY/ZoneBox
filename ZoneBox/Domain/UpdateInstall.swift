import Foundation
import Security
import Darwin

public enum OfficialUpdateIdentity {
    public static let bundleID = AppIdentity.releaseBundleID
    public static let teamID = "A594W68DE5"
    public static let appFileName = "ZoneBox.app"
}

public enum UpdateInstallBlocker: Equatable, Sendable {
    case debugBuild
    case translocated
    case unwritable
    case unexpectedBundleID
    case unsignedOrAdHocCurrent
    case teamMismatch
    case invalidSignature
}

public struct UpdateCodeSignature: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case developerID
        case appleDevelopment
        case adHoc
        case unsigned
        case other
    }

    public var identifier: String
    public var teamIdentifier: String?
    public var kind: Kind
    public var satisfiesOfficialRequirement: Bool

    public init(identifier: String, teamIdentifier: String?, kind: Kind, satisfiesOfficialRequirement: Bool = false) {
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.kind = kind
        self.satisfiesOfficialRequirement = satisfiesOfficialRequirement
    }
}

public struct UpdateInstallContext: Equatable, Sendable {
    public var bundleURL: URL
    public var bundleID: String
    public var version: String
    public var architecture: UpdateArchitecture
    public var signature: UpdateCodeSignature?
    public var isTranslocated: Bool
    public var isWritable: Bool

    public init(
        bundleURL: URL,
        bundleID: String,
        version: String,
        architecture: UpdateArchitecture,
        signature: UpdateCodeSignature?,
        isTranslocated: Bool,
        isWritable: Bool
    ) {
        self.bundleURL = bundleURL
        self.bundleID = bundleID
        self.version = version
        self.architecture = architecture
        self.signature = signature
        self.isTranslocated = isTranslocated
        self.isWritable = isWritable
    }
}

public enum UpdateInstallEligibility: Equatable, Sendable {
    case ready(destination: URL)
    case unsupported(UpdateInstallBlocker)
}

public enum UpdateInstallPolicy {
    public static func eligibility(for context: UpdateInstallContext) -> UpdateInstallEligibility {
        if context.bundleID == AppIdentity.debugBundleID {
            return .unsupported(.debugBuild)
        }
        if context.bundleID != OfficialUpdateIdentity.bundleID {
            return .unsupported(.unexpectedBundleID)
        }
        if context.isTranslocated {
            return .unsupported(.translocated)
        }
        if !context.isWritable {
            return .unsupported(.unwritable)
        }
        guard let signature = context.signature else {
            return .unsupported(.unsignedOrAdHocCurrent)
        }
        switch signature.kind {
        case .developerID:
            break
        case .adHoc, .unsigned:
            return .unsupported(.unsignedOrAdHocCurrent)
        case .appleDevelopment, .other:
            return .unsupported(.teamMismatch)
        }
        if signature.identifier != OfficialUpdateIdentity.bundleID {
            return .unsupported(.unexpectedBundleID)
        }
        if signature.teamIdentifier != OfficialUpdateIdentity.teamID {
            return .unsupported(.teamMismatch)
        }
        if !signature.satisfiesOfficialRequirement {
            return .unsupported(.invalidSignature)
        }
        return .ready(destination: context.bundleURL)
    }
}

public enum UpdatePayloadGate {
    public static func acceptsOfficial(_ signature: UpdateCodeSignature) -> Bool {
        signature.identifier == OfficialUpdateIdentity.bundleID
            && signature.teamIdentifier == OfficialUpdateIdentity.teamID
            && signature.kind == .developerID
            && signature.satisfiesOfficialRequirement
    }
}

public struct UpdateStagedBundle: Equatable, Sendable {
    public var url: URL
    public var bundleID: String
    public var version: String
    public var architectures: Set<UpdateArchitecture>
    public var signature: UpdateCodeSignature

    public init(
        url: URL,
        bundleID: String,
        version: String,
        architectures: Set<UpdateArchitecture>,
        signature: UpdateCodeSignature
    ) {
        self.url = url
        self.bundleID = bundleID
        self.version = version
        self.architectures = architectures
        self.signature = signature
    }
}

public enum UpdateStagedBundleError: Equatable, Error {
    case missingBundle
    case unreadableInfo
    case bundleIDMismatch
    case versionMismatch
    case notNewer
    case architectureMismatch
    case signatureRejected
}

public enum UpdateStagedBundleGate {
    public static func evaluate(
        staged: UpdateStagedBundle,
        offer: UpdateOffer,
        currentVersion: String,
        architecture: UpdateArchitecture
    ) -> Result<Void, UpdateStagedBundleError> {
        guard staged.bundleID == OfficialUpdateIdentity.bundleID else {
            return .failure(.bundleIDMismatch)
        }
        guard UpdatePayloadGate.acceptsOfficial(staged.signature) else {
            return .failure(.signatureRejected)
        }
        guard let stagedVersion = AppVersion.parse(staged.version), stagedVersion == offer.latestVersion else {
            return .failure(.versionMismatch)
        }
        guard let current = AppVersion.parse(currentVersion), current < stagedVersion else {
            return .failure(.notNewer)
        }
        guard staged.architectures.contains(architecture) else {
            return .failure(.architectureMismatch)
        }
        return .success(())
    }
}

public enum UpdateInstallLocation {
    public static func isTranslocated(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/AppTranslocation/")
    }

    public static func isWritable(_ url: URL) -> Bool {
        let fm = FileManager.default
        let path = url.path
        let parent = url.deletingLastPathComponent().path
        return fm.isWritableFile(atPath: path) && fm.isWritableFile(atPath: parent)
    }
}

public enum UpdateBundleInfo {
    public static func read(fromApp bundleURL: URL) -> (bundleID: String, version: String, executable: URL)? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else { return nil }
        let bundleID = dict["CFBundleIdentifier"] as? String ?? ""
        let version = dict["CFBundleShortVersionString"] as? String ?? ""
        let executableName = dict["CFBundleExecutable"] as? String ?? "ZoneBox"
        guard !bundleID.isEmpty, !version.isEmpty, !executableName.isEmpty, !executableName.contains("/") else {
            return nil
        }
        let executable = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
        return (bundleID, version, executable)
    }
}

public enum UpdateInstallAttempt: Equatable, Sendable {
    case helperStarted
    case unsupported(UpdateInstallBlocker)
    case failed(String)
}

@MainActor
public protocol UpdateInstalling: AnyObject {
    func install(fromDMG dmgURL: URL, offer: UpdateOffer, context: UpdateInstallContext) async -> UpdateInstallAttempt
}

public struct UpdateHelperRequest: Equatable, Sendable {
    public var parentPID: Int32
    public var sourceApp: URL
    public var destinationApp: URL
    public var backupApp: URL
    public var timeout: TimeInterval
    public var relaunch: Bool
    public var selfDelete: URL?
    public var errorFile: URL?
    public var expectedVersion: String
    public var currentVersion: String
    public var architecture: UpdateArchitecture

    public init(
        parentPID: Int32,
        sourceApp: URL,
        destinationApp: URL,
        backupApp: URL,
        timeout: TimeInterval,
        relaunch: Bool,
        selfDelete: URL? = nil,
        errorFile: URL? = nil,
        expectedVersion: String,
        currentVersion: String,
        architecture: UpdateArchitecture
    ) {
        self.parentPID = parentPID
        self.sourceApp = sourceApp
        self.destinationApp = destinationApp
        self.backupApp = backupApp
        self.timeout = timeout
        self.relaunch = relaunch
        self.selfDelete = selfDelete
        self.errorFile = errorFile
        self.expectedVersion = expectedVersion
        self.currentVersion = currentVersion
        self.architecture = architecture
    }
}

public enum UpdateHelperArguments {
    public static let flag = "--zonebox-update-helper"
    public static let errorFlag = "--zonebox-update-error"

    public static func parse(_ arguments: [String]) -> UpdateHelperRequest? {
        guard let start = arguments.firstIndex(of: flag) else { return nil }
        var pid: Int32?
        var source: URL?
        var destination: URL?
        var backup: URL?
        var timeout: TimeInterval = 30
        var relaunch = false
        var selfDelete: URL?
        var errorFile: URL?
        var expectedVersion: String?
        var currentVersion: String?
        var architecture: UpdateArchitecture?
        var index = start + 1
        while index < arguments.count {
            let arg = arguments[index]
            func takeValue() -> String? {
                let next = index + 1
                guard next < arguments.count else { return nil }
                index = next
                return arguments[next]
            }
            switch arg {
            case "--pid":
                if let raw = takeValue(), let value = Int32(raw), value > 0 {
                    pid = value
                }
            case "--source":
                if let raw = takeValue() { source = URL(fileURLWithPath: raw) }
            case "--destination":
                if let raw = takeValue() { destination = URL(fileURLWithPath: raw) }
            case "--backup":
                if let raw = takeValue() { backup = URL(fileURLWithPath: raw) }
            case "--timeout-ms":
                if let raw = takeValue(), let millis = Double(raw), millis > 0 {
                    timeout = millis / 1000
                }
            case "--relaunch":
                relaunch = true
            case "--self-delete":
                if let raw = takeValue() { selfDelete = URL(fileURLWithPath: raw) }
            case "--error-file":
                if let raw = takeValue() { errorFile = URL(fileURLWithPath: raw) }
            case "--expected-version":
                if let raw = takeValue(), !raw.isEmpty { expectedVersion = raw }
            case "--current-version":
                if let raw = takeValue(), !raw.isEmpty { currentVersion = raw }
            case "--arch":
                if let raw = takeValue() { architecture = UpdateArchitecture(rawValue: raw) }
            default:
                break
            }
            index += 1
        }
        guard let pid, let source, let destination, let backup,
              let expectedVersion, let currentVersion, let architecture else { return nil }
        return UpdateHelperRequest(
            parentPID: pid,
            sourceApp: source,
            destinationApp: destination,
            backupApp: backup,
            timeout: timeout,
            relaunch: relaunch,
            selfDelete: selfDelete,
            errorFile: errorFile,
            expectedVersion: expectedVersion,
            currentVersion: currentVersion,
            architecture: architecture
        )
    }

    public static func makeArguments(_ request: UpdateHelperRequest) -> [String] {
        var args = [
            flag,
            "--pid", String(request.parentPID),
            "--source", request.sourceApp.path,
            "--destination", request.destinationApp.path,
            "--backup", request.backupApp.path,
            "--timeout-ms", String(Int((request.timeout * 1000).rounded())),
            "--expected-version", request.expectedVersion,
            "--current-version", request.currentVersion,
            "--arch", request.architecture.rawValue,
        ]
        if request.relaunch {
            args.append("--relaunch")
        }
        if let extra = request.selfDelete {
            args.append(contentsOf: ["--self-delete", extra.path])
        }
        if let extra = request.errorFile {
            args.append(contentsOf: ["--error-file", extra.path])
        }
        return args
    }

    public static func errorFile(from arguments: [String]) -> URL? {
        guard let start = arguments.firstIndex(of: errorFlag) else { return nil }
        let next = start + 1
        guard next < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[next])
    }
}

public enum UpdateCodeSignatureInspector {
    public static let officialRequirement: String = """
anchor apple generic and identifier \"com.fancyzone.app\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"A594W68DE5\"
""".trimmingCharacters(in: .whitespacesAndNewlines)

    public static func inspect(bundleURL: URL) -> UpdateCodeSignature {
        var staticCode: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard created == errSecSuccess, let staticCode else {
            return UpdateCodeSignature(identifier: "", teamIdentifier: nil, kind: .unsigned, satisfiesOfficialRequirement: false)
        }
        var cfInfo: CFDictionary?
        let copied = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &cfInfo)
        guard copied == errSecSuccess, let info = cfInfo as? [String: Any] else {
            return UpdateCodeSignature(identifier: "", teamIdentifier: nil, kind: .unsigned, satisfiesOfficialRequirement: false)
        }
        let identifier = (info[kSecCodeInfoIdentifier as String] as? String) ?? ""
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        let adHoc = (flags & 2) != 0
        let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let kind: UpdateCodeSignature.Kind
        if certs.isEmpty {
            kind = adHoc ? .adHoc : .unsigned
        } else if adHoc {
            kind = .adHoc
        } else if let name = commonName(of: certs[0]), name.contains("Developer ID Application") {
            kind = .developerID
        } else if let name = commonName(of: certs[0]),
                  name.contains("Apple Development") || name.contains("Mac Developer") || name.contains("Apple Developer") {
            kind = .appleDevelopment
        } else {
            kind = .other
        }
        let valid = satisfiesOfficial(staticCode)
        return UpdateCodeSignature(
            identifier: identifier,
            teamIdentifier: team,
            kind: kind,
            satisfiesOfficialRequirement: valid
        )
    }

    public static func satisfiesOfficial(_ staticCode: SecStaticCode) -> Bool {
        var requirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(officialRequirement as CFString, [], &requirement)
        guard reqStatus == errSecSuccess, let requirement else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        return status == errSecSuccess
    }

    private static func commonName(of certificate: SecCertificate) -> String? {
        var name: CFString?
        let status = SecCertificateCopyCommonName(certificate, &name)
        guard status == errSecSuccess else { return nil }
        return name as String?
    }
}

public enum MachOArchitectureReader {
    public static func architectures(at executable: URL) throws -> Set<UpdateArchitecture> {
        let data = try Data(contentsOf: executable, options: [.mappedIfSafe])
        return try architectures(in: data)
    }

    public static func architectures(in data: Data) throws -> Set<UpdateArchitecture> {
        guard data.count >= 8 else { throw UpdateStagedBundleError.unreadableInfo }
        let magic = load32(data, 0)
        switch magic {
        case 0xcafebabe, 0xcafebabf:
            return try fat(data, swap: false)
        case 0xbebafeca, 0xbfbafeca:
            return try fat(data, swap: true)
        case 0xfeedfacf, 0xfeedface:
            return try thin(data, swap: false)
        case 0xcffaedfe, 0xcefaedfe:
            return try thin(data, swap: true)
        default:
            throw UpdateStagedBundleError.unreadableInfo
        }
    }

    private static func fat(_ data: Data, swap: Bool) throws -> Set<UpdateArchitecture> {
        guard data.count >= 8 else { throw UpdateStagedBundleError.unreadableInfo }
        let count = Int(u32(load32(data, 4), swap: swap))
        guard count > 0, count < 16 else { throw UpdateStagedBundleError.unreadableInfo }
        var result: Set<UpdateArchitecture> = []
        for index in 0..<count {
            let offset = 8 + index * 20
            guard data.count >= offset + 4 else { throw UpdateStagedBundleError.unreadableInfo }
            if let arch = architecture(forCPUType: u32(load32(data, offset), swap: swap)) {
                result.insert(arch)
            }
        }
        if result.isEmpty { throw UpdateStagedBundleError.unreadableInfo }
        return result
    }

    private static func thin(_ data: Data, swap: Bool) throws -> Set<UpdateArchitecture> {
        guard data.count >= 8 else { throw UpdateStagedBundleError.unreadableInfo }
        guard let arch = architecture(forCPUType: u32(load32(data, 4), swap: swap)) else {
            throw UpdateStagedBundleError.unreadableInfo
        }
        return [arch]
    }

    private static func architecture(forCPUType type: UInt32) -> UpdateArchitecture? {
        switch Int32(bitPattern: type) {
        case 0x01000007: return .x86_64
        case 0x0100000c: return .arm64
        default: return nil
        }
    }

    private static func load32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
    }

    private static func u32(_ value: UInt32, swap: Bool) -> UInt32 {
        swap ? value.byteSwapped : value
    }
}

public enum UpdateStagedBundleLoader {
    public static func load(fromApp url: URL) throws -> UpdateStagedBundle {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw UpdateStagedBundleError.missingBundle
        }
        guard let info = UpdateBundleInfo.read(fromApp: url) else {
            throw UpdateStagedBundleError.unreadableInfo
        }
        let architectures = try MachOArchitectureReader.architectures(at: info.executable)
        let signature = UpdateCodeSignatureInspector.inspect(bundleURL: url)
        return UpdateStagedBundle(
            url: url,
            bundleID: info.bundleID,
            version: info.version,
            architectures: architectures,
            signature: signature
        )
    }
}

public enum UpdateInstallKind: Equatable, Sendable {
    case inPlace
    case manualFallback
}

public enum UpdateInstallPresentation {
    public static func kind(for eligibility: UpdateInstallEligibility) -> UpdateInstallKind {
        if case .ready = eligibility { return .inPlace }
        return .manualFallback
    }
}

public struct UpdateFileOperations {
    public var fileExists: (URL) -> Bool
    public var removeItem: (URL) throws -> Void
    public var moveItem: (URL, URL) throws -> Void
    public var copyItem: (URL, URL) throws -> Void

    public init(
        fileExists: @escaping (URL) -> Bool,
        removeItem: @escaping (URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        copyItem: @escaping (URL, URL) throws -> Void
    ) {
        self.fileExists = fileExists
        self.removeItem = removeItem
        self.moveItem = moveItem
        self.copyItem = copyItem
    }

    public static let posix = UpdateFileOperations(
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        removeItem: { try FileManager.default.removeItem(at: $0) },
        moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
        copyItem: { try FileManager.default.copyItem(at: $0, to: $1) }
    )
}

public enum UpdateReplacementResult: Equatable, Sendable {
    case replaced
    case rolledBack(String)
    case failed(String)
}

public struct UpdateReplacementReport: Equatable, Sendable {
    public var result: UpdateReplacementResult
    public var backup: URL?
}

public enum UpdateReplacement {
    public static func uniqueBackupURL(beside destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            "." + destination.lastPathComponent + ".zoneboxbackup-" + UUID().uuidString
        )
    }

    public static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let aID = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let bID = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        guard let aID, let bID else { return true }
        return aID.isEqual(bID)
    }

    public static func replace(
        source: URL,
        destination: URL,
        backup requestedBackup: URL,
        files: UpdateFileOperations = .posix
    ) -> UpdateReplacementReport {
        let source = source.standardizedFileURL
        let destination = destination.standardizedFileURL
        guard files.fileExists(source) else {
            return UpdateReplacementReport(result: .failed("missing source"), backup: nil)
        }
        if source.path == destination.path {
            return UpdateReplacementReport(result: .failed("source is destination"), backup: nil)
        }
        var backup = requestedBackup.standardizedFileURL
        while files.fileExists(backup) {
            backup = uniqueBackupURL(beside: destination)
        }
        var staged = source
        var createdStage: URL?
        if !sameVolume(source, destination) {
            let stage = destination.deletingLastPathComponent().appendingPathComponent(
                destination.lastPathComponent + ".zoneboxstage-" + UUID().uuidString
            )
            do {
                try files.copyItem(source, stage)
                staged = stage
                createdStage = stage
            } catch {
                return UpdateReplacementReport(result: .failed(error.localizedDescription), backup: nil)
            }
        }
        let destinationExisted = files.fileExists(destination)
        var movedDestinationToBackup = false
        do {
            if destinationExisted {
                try files.moveItem(destination, backup)
                movedDestinationToBackup = true
            }
            try files.moveItem(staged, destination)
            createdStage = nil
            return UpdateReplacementReport(result: .replaced, backup: movedDestinationToBackup ? backup : nil)
        } catch {
            if files.fileExists(destination), movedDestinationToBackup || !destinationExisted {
                try? files.removeItem(destination)
            }
            if let createdStage, files.fileExists(createdStage) {
                try? files.removeItem(createdStage)
            }
            if movedDestinationToBackup, files.fileExists(backup) {
                do {
                    try files.copyItem(backup, destination)
                    return UpdateReplacementReport(result: .rolledBack(error.localizedDescription), backup: backup)
                } catch {
                    return UpdateReplacementReport(result: .failed(error.localizedDescription), backup: backup)
                }
            }
            return UpdateReplacementReport(result: .failed(error.localizedDescription), backup: movedDestinationToBackup ? backup : nil)
        }
    }

    public static func restoreBackup(
        destination: URL,
        backup: URL,
        files: UpdateFileOperations = .posix
    ) -> Bool {
        if files.fileExists(destination) {
            try? files.removeItem(destination)
        }
        guard files.fileExists(backup) else { return false }
        do {
            try files.copyItem(backup, destination)
            return files.fileExists(destination)
        } catch {
            return false
        }
    }
}

public enum UpdateInstallPath {
    public static func resolvedApp(_ url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        guard standardized.pathExtension == "app" else { return nil }
        if (try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return nil
        }
        let resolved = standardized.resolvingSymlinksInPath()
        guard resolved.pathExtension == "app" else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return resolved
    }

    public static func validateDistinct(source: URL, destination: URL, backup: URL) -> String? {
        guard let source = resolvedApp(source) else { return "invalid source" }
        guard let destination = resolvedApp(destination) else { return "invalid destination" }
        let backup = backup.standardizedFileURL.resolvingSymlinksInPath()
        if backup.pathExtension == "app", resolvedApp(backup) == nil, FileManager.default.fileExists(atPath: backup.path) {
            return "invalid backup"
        }
        let paths = [source.path, destination.path, backup.path]
        if Set(paths).count != 3 { return "overlapping paths" }
        if isNested(source, under: destination) || isNested(backup, under: destination) {
            return "nested paths"
        }
        if isNested(destination, under: source) || isNested(backup, under: source) {
            return "nested paths"
        }
        return nil
    }

    public static func isNested(_ child: URL, under parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        if childPath == parentPath { return true }
        let prefix = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"
        return childPath.hasPrefix(prefix)
    }
}

public struct UpdateInstallFailureRecord: Codable, Equatable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public static func write(_ message: String, to url: URL?) {
        guard let url else { return }
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let record = UpdateInstallFailureRecord(message: message)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(UpdateInstallFailureRecord.self, from: data),
              !record.message.isEmpty else { return nil }
        return record.message
    }
}

public enum UpdateHelperPreflight {
    public static func evaluate(_ request: UpdateHelperRequest) -> String? {
        if let error = UpdateInstallPath.validateDistinct(
            source: request.sourceApp,
            destination: request.destinationApp,
            backup: request.backupApp
        ) {
            return error
        }
        guard let sourceURL = UpdateInstallPath.resolvedApp(request.sourceApp),
              let destinationURL = UpdateInstallPath.resolvedApp(request.destinationApp) else {
            return "invalid app path"
        }
        guard let source = try? UpdateStagedBundleLoader.load(fromApp: sourceURL) else {
            return "unreadable source"
        }
        guard let destination = try? UpdateStagedBundleLoader.load(fromApp: destinationURL) else {
            return "unreadable destination"
        }
        guard UpdatePayloadGate.acceptsOfficial(source.signature) else {
            return "source signature rejected"
        }
        guard UpdatePayloadGate.acceptsOfficial(destination.signature) else {
            return "destination signature rejected"
        }
        guard source.version == request.expectedVersion else {
            return "source version mismatch"
        }
        guard destination.version == request.currentVersion else {
            return "destination version mismatch"
        }
        guard source.architectures.contains(request.architecture),
              destination.architectures.contains(request.architecture) else {
            return "architecture mismatch"
        }
        return nil
    }
}

public enum UpdateParentWait {
    public static func isRunning(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }

    public static func wait(pid: Int32, timeout: TimeInterval, poll: TimeInterval = 0.05) -> Bool {
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        while isRunning(pid) {
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: poll)
        }
        return true
    }
}

public enum UpdateHelperRunner {
    public static func run(_ request: UpdateHelperRequest, files: UpdateFileOperations = .posix) -> Int32 {
        guard UpdateParentWait.wait(pid: request.parentPID, timeout: request.timeout) else {
            UpdateInstallFailureRecord.write("The update helper timed out while ZoneBox was still running.", to: request.errorFile)
            cleanup(request, files: files)
            return 2
        }
        if let message = UpdateHelperPreflight.evaluate(request) {
            return fail(request, message: message, files: files, relaunchOld: true)
        }
        let report = UpdateReplacement.replace(
            source: request.sourceApp,
            destination: request.destinationApp,
            backup: request.backupApp,
            files: files
        )
        switch report.result {
        case .replaced:
            if let dest = UpdateInstallPath.resolvedApp(request.destinationApp),
               let staged = try? UpdateStagedBundleLoader.load(fromApp: dest),
               UpdatePayloadGate.acceptsOfficial(staged.signature),
               staged.version == request.expectedVersion {
                if request.relaunch {
                    if !relaunch(request.destinationApp, errorFile: nil) {
                        _ = UpdateReplacement.restoreBackup(
                            destination: request.destinationApp,
                            backup: report.backup ?? request.backupApp,
                            files: files
                        )
                        return fail(request, message: "Relaunch failed; the previous copy was restored.", files: files, relaunchOld: true)
                    }
                }
                cleanup(request, files: files)
                return 0
            }
            _ = UpdateReplacement.restoreBackup(
                destination: request.destinationApp,
                backup: report.backup ?? request.backupApp,
                files: files
            )
            return fail(request, message: "The replaced app did not pass verification.", files: files, relaunchOld: true)
        case .rolledBack(let message), .failed(let message):
            return fail(request, message: message, files: files, relaunchOld: true)
        }
    }

    private static func fail(
        _ request: UpdateHelperRequest,
        message: String,
        files: UpdateFileOperations,
        relaunchOld: Bool
    ) -> Int32 {
        UpdateInstallFailureRecord.write(message, to: request.errorFile)
        if request.relaunch, relaunchOld, UpdateInstallPath.resolvedApp(request.destinationApp) != nil {
            _ = relaunch(request.destinationApp, errorFile: request.errorFile)
        }
        cleanup(request, files: files)
        return 1
    }

    private static func cleanup(_ request: UpdateHelperRequest, files: UpdateFileOperations) {
        if let extra = request.selfDelete, files.fileExists(extra) {
            try? files.removeItem(extra)
        }
    }

    @discardableResult
    public static func relaunch(_ app: URL, errorFile: URL?) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var arguments = ["-n", app.path]
        if let errorFile {
            arguments.append(contentsOf: ["--args", UpdateHelperArguments.errorFlag, errorFile.path])
        }
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

public enum UpdateHelperLaunch {
    public static func request(
        parentPID: Int32,
        sourceApp: URL,
        destinationApp: URL,
        helperURL: URL,
        timeout: TimeInterval = 45,
        expectedVersion: String,
        currentVersion: String,
        architecture: UpdateArchitecture,
        errorFile: URL?
    ) -> UpdateHelperRequest {
        let backup = UpdateReplacement.uniqueBackupURL(beside: destinationApp)
        return UpdateHelperRequest(
            parentPID: parentPID,
            sourceApp: sourceApp,
            destinationApp: destinationApp,
            backupApp: backup,
            timeout: timeout,
            relaunch: true,
            selfDelete: helperURL,
            errorFile: errorFile,
            expectedVersion: expectedVersion,
            currentVersion: currentVersion,
            architecture: architecture
        )
    }
}
