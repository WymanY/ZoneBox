import XCTest
@testable import ZoneBoxCore

final class UpdateInstallTests: XCTestCase {
    private let fixtureApp = URL(fileURLWithPath: "/tmp/zonebox-update-audit-20261027/mount/ZoneBox.app")
    private let scratchRoot = URL(fileURLWithPath: "/tmp/zonebox update tests " + UUID().uuidString)

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratchRoot)
        super.tearDown()
    }

    func testDebugBuildIsManualFallback() {
        let context = UpdateInstallContext(
            bundleURL: URL(fileURLWithPath: "/Applications/ZoneBox.app"),
            bundleID: AppIdentity.debugBundleID,
            version: "0.5.0",
            architecture: .arm64,
            signature: UpdateCodeSignature(
                identifier: OfficialUpdateIdentity.bundleID,
                teamIdentifier: OfficialUpdateIdentity.teamID,
                kind: .developerID,
                satisfiesOfficialRequirement: true
            ),
            isTranslocated: false,
            isWritable: true
        )
        XCTAssertEqual(UpdateInstallPolicy.eligibility(for: context), .unsupported(.debugBuild))
        XCTAssertEqual(UpdateInstallPresentation.kind(for: .unsupported(.debugBuild)), .manualFallback)
    }

    func testOfficialWritableBundleIsReady() {
        let destination = URL(fileURLWithPath: "/Applications/ZoneBox.app")
        let context = UpdateInstallContext(
            bundleURL: destination,
            bundleID: OfficialUpdateIdentity.bundleID,
            version: "0.5.0",
            architecture: .arm64,
            signature: UpdateCodeSignature(
                identifier: OfficialUpdateIdentity.bundleID,
                teamIdentifier: OfficialUpdateIdentity.teamID,
                kind: .developerID,
                satisfiesOfficialRequirement: true
            ),
            isTranslocated: false,
            isWritable: true
        )
        XCTAssertEqual(UpdateInstallPolicy.eligibility(for: context), .ready(destination: destination))
    }

    func testOfficialWritableBundleRejectsUnverifiedDeveloperIDMetadata() {
        let destination = URL(fileURLWithPath: "/Applications/ZoneBox.app")
        let context = UpdateInstallContext(
            bundleURL: destination,
            bundleID: OfficialUpdateIdentity.bundleID,
            version: "0.5.0",
            architecture: .arm64,
            signature: UpdateCodeSignature(
                identifier: OfficialUpdateIdentity.bundleID,
                teamIdentifier: OfficialUpdateIdentity.teamID,
                kind: .developerID,
                satisfiesOfficialRequirement: false
            ),
            isTranslocated: false,
            isWritable: true
        )
        XCTAssertEqual(UpdateInstallPolicy.eligibility(for: context), .unsupported(.invalidSignature))
        XCTAssertFalse(
            UpdatePayloadGate.acceptsOfficial(
                UpdateCodeSignature(
                    identifier: OfficialUpdateIdentity.bundleID,
                    teamIdentifier: OfficialUpdateIdentity.teamID,
                    kind: .developerID,
                    satisfiesOfficialRequirement: false
                )
            )
        )
    }

    func testOfficialFixtureSignatureVersionAndArchitecture() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixtureApp.path), "signed fixture missing")
        let staged = try UpdateStagedBundleLoader.load(fromApp: fixtureApp)
        XCTAssertEqual(staged.bundleID, OfficialUpdateIdentity.bundleID)
        XCTAssertEqual(staged.version, "0.5.1")
        XCTAssertEqual(staged.architectures, [.arm64, .x86_64])
        XCTAssertTrue(staged.signature.satisfiesOfficialRequirement)
        XCTAssertTrue(UpdatePayloadGate.acceptsOfficial(staged.signature))
    }

    func testTamperedOfficialFixtureFailsClosed() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixtureApp.path), "signed fixture missing")
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let copy = scratchRoot.appendingPathComponent("Tampered.app", isDirectory: true)
        try FileManager.default.copyItem(at: fixtureApp, to: copy)
        let executable = copy.appendingPathComponent("Contents/MacOS/ZoneBox")
        var data = try Data(contentsOf: executable)
        XCTAssertGreaterThan(data.count, 32)
        data[data.count / 2] ^= 0xFF
        try data.write(to: executable)
        let staged = try UpdateStagedBundleLoader.load(fromApp: copy)
        XCTAssertFalse(staged.signature.satisfiesOfficialRequirement)
        XCTAssertFalse(UpdatePayloadGate.acceptsOfficial(staged.signature))
    }

    func testHelperArgumentsRoundTripPathsWithSpaces() {
        let request = UpdateHelperLaunch.request(
            parentPID: 4242,
            sourceApp: URL(fileURLWithPath: "/tmp/zonebox update/source/ZoneBox.app"),
            destinationApp: URL(fileURLWithPath: "/tmp/zonebox update/My Dest.app"),
            helperURL: URL(fileURLWithPath: "/tmp/zonebox update/ZoneBox-update-helper"),
            timeout: 12.5,
            expectedVersion: "0.5.1",
            currentVersion: "0.5.0",
            architecture: .arm64,
            errorFile: URL(fileURLWithPath: "/tmp/zonebox update/install-error.json")
        )
        let parsed = UpdateHelperArguments.parse(["ZoneBox"] + UpdateHelperArguments.makeArguments(request))
        XCTAssertEqual(parsed?.parentPID, 4242)
        XCTAssertEqual(parsed?.sourceApp.path, request.sourceApp.path)
        XCTAssertEqual(parsed?.destinationApp.path, request.destinationApp.path)
        XCTAssertEqual(parsed?.expectedVersion, "0.5.1")
        XCTAssertEqual(parsed?.currentVersion, "0.5.0")
        XCTAssertEqual(parsed?.architecture, .arm64)
        XCTAssertEqual(parsed?.errorFile?.path, request.errorFile?.path)
        XCTAssertTrue(request.backupApp.lastPathComponent.contains("zoneboxbackup-"))
        XCTAssertTrue(request.backupApp.lastPathComponent.hasPrefix("."))
        XCTAssertEqual(UpdateHelperArguments.errorFile(from: ["app", "--zonebox-update-error", "/tmp/err.json"])?.path, "/tmp/err.json")
    }

    func testFat64ReportsBothArchitecturesInBothEndians() throws {
        let cpuTypes: [UInt32] = [0x01000007, 0x0100000c]
        let native = fatBinary(magic: 0xcafebabf, nfatArch: 2, recordSize: 32, cpuTypes: cpuTypes, swapFields: false)
        let swapped = fatBinary(magic: 0xbfbafeca, nfatArch: 2, recordSize: 32, cpuTypes: cpuTypes, swapFields: true)
        XCTAssertEqual(try MachOArchitectureReader.architectures(in: native), [.x86_64, .arm64])
        XCTAssertEqual(try MachOArchitectureReader.architectures(in: swapped), [.x86_64, .arm64])
    }

    func testFat32AndThinArchitecturesDoNotRegress() throws {
        let cpuTypes: [UInt32] = [0x01000007, 0x0100000c]
        let nativeFat32 = fatBinary(magic: 0xcafebabe, nfatArch: 2, recordSize: 20, cpuTypes: cpuTypes, swapFields: false)
        let swappedFat32 = fatBinary(magic: 0xbebafeca, nfatArch: 2, recordSize: 20, cpuTypes: cpuTypes, swapFields: true)
        XCTAssertEqual(try MachOArchitectureReader.architectures(in: nativeFat32), [.x86_64, .arm64])
        XCTAssertEqual(try MachOArchitectureReader.architectures(in: swappedFat32), [.x86_64, .arm64])

        XCTAssertEqual(
            try MachOArchitectureReader.architectures(in: thinBinary(magic: 0xfeedfacf, cpuType: 0x0100000c)),
            [.arm64]
        )
        XCTAssertEqual(
            try MachOArchitectureReader.architectures(in: thinBinary(magic: 0xcffaedfe, cpuType: UInt32(0x0100000c).byteSwapped)),
            [.arm64]
        )
        XCTAssertEqual(
            try MachOArchitectureReader.architectures(in: thinBinary(magic: 0xfeedface, cpuType: 0x01000007)),
            [.x86_64]
        )
        XCTAssertEqual(
            try MachOArchitectureReader.architectures(in: thinBinary(magic: 0xcefaedfe, cpuType: UInt32(0x01000007).byteSwapped)),
            [.x86_64]
        )
    }

    func testTruncatedFat64RecordFailsClosed() {
        let cpuTypes: [UInt32] = [0x01000007, 0x0100000c]
        let full = fatBinary(magic: 0xcafebabf, nfatArch: 2, recordSize: 32, cpuTypes: cpuTypes, swapFields: false)
        let truncated = Data(full.prefix(8 + 32))
        XCTAssertThrowsError(try MachOArchitectureReader.architectures(in: truncated))
    }

    func testHelperVersionGatesAcceptEquivalentForms() {
        XCTAssertNil(
            UpdateHelperPreflight.versionMismatch(
                source: "1.2",
                destination: "1.1",
                expected: "1.2.0",
                current: "1.1.0"
            )
        )
        XCTAssertNil(
            UpdateHelperPreflight.versionMismatch(
                source: "v0.5.1",
                destination: "0.5",
                expected: "0.5.1",
                current: "0.5.0"
            )
        )
        XCTAssertTrue(UpdateHelperPreflight.versionsMatch("1.2", "1.2.0"))
        XCTAssertTrue(UpdateHelperPreflight.versionsMatch("1.2.0", "1.2"))
    }

    func testHelperVersionGatesRejectMismatchesAndInvalids() {
        XCTAssertEqual(
            UpdateHelperPreflight.versionMismatch(
                source: "1.3.0",
                destination: "1.2.0",
                expected: "1.2.0",
                current: "1.2.0"
            ),
            "source version mismatch"
        )
        XCTAssertEqual(
            UpdateHelperPreflight.versionMismatch(
                source: "1.3.0",
                destination: "1.3.0",
                expected: "1.3.0",
                current: "1.2.0"
            ),
            "destination version mismatch"
        )
        XCTAssertEqual(
            UpdateHelperPreflight.versionMismatch(
                source: "not-a-version",
                destination: "also-invalid",
                expected: "not-a-version",
                current: "also-invalid"
            ),
            "source version mismatch"
        )
        XCTAssertEqual(
            UpdateHelperPreflight.versionMismatch(
                source: "1.2.0",
                destination: "",
                expected: "1.2.0",
                current: ""
            ),
            "destination version mismatch"
        )
        XCTAssertFalse(UpdateHelperPreflight.versionsMatch("1.2.0", "1.2.1"))
        XCTAssertFalse(UpdateHelperPreflight.versionsMatch("1.2.0-beta.1", "1.2.0-beta.1"))
        XCTAssertFalse(UpdateHelperPreflight.versionsMatch("", ""))
    }

    func testReplacementKeepsExistingBackupAndRestoresPartialDestination() {
        let source = URL(fileURLWithPath: "/tmp/source.app")
        let destination = URL(fileURLWithPath: "/tmp/dest.app")
        let requestedBackup = URL(fileURLWithPath: "/tmp/dest.app.zoneboxbackup")
        var store: [String: String] = [
            "source.app": "NEW",
            "dest.app": "OLD",
            "dest.app.zoneboxbackup": "KEEP",
        ]
        var copyCalls = 0
        let files = UpdateFileOperations(
            fileExists: { store[$0.lastPathComponent] != nil },
            removeItem: { store.removeValue(forKey: $0.lastPathComponent) },
            moveItem: { from, to in
                if from.lastPathComponent == "source.app" {
                    store[to.lastPathComponent] = "PARTIAL"
                    throw NSError(domain: "test", code: 1)
                }
                guard let value = store.removeValue(forKey: from.lastPathComponent) else {
                    throw NSError(domain: "test", code: 2)
                }
                store[to.lastPathComponent] = value
            },
            copyItem: { from, to in
                copyCalls += 1
                guard let value = store[from.lastPathComponent] else {
                    throw NSError(domain: "test", code: 3)
                }
                store[to.lastPathComponent] = value
            }
        )
        let report = UpdateReplacement.replace(source: source, destination: destination, backup: requestedBackup, files: files)
        guard case .rolledBack = report.result else {
            return XCTFail("expected rollback, got " + String(describing: report.result))
        }
        XCTAssertEqual(store["dest.app"], "OLD")
        XCTAssertEqual(store["dest.app.zoneboxbackup"], "KEEP")
        XCTAssertNotEqual(report.backup?.lastPathComponent, "dest.app.zoneboxbackup")
        XCTAssertEqual(store[report.backup!.lastPathComponent], "OLD")
        XCTAssertGreaterThanOrEqual(copyCalls, 1)
        XCTAssertNil(store["PARTIAL"])
        XCTAssertNotEqual(store["dest.app"], "PARTIAL")
    }

    func testReplacementSucceedsWithPathsContainingSpacesAndRetainsBackup() throws {
        let fm = FileManager.default
        let parent = scratchRoot.appendingPathComponent("Apps", isDirectory: true)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let source = parent.appendingPathComponent("New Copy.app", isDirectory: true)
        let destination = parent.appendingPathComponent("My Dest.app", isDirectory: true)
        let backup = parent.appendingPathComponent("My Dest.app.zoneboxbackup", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: source.appendingPathComponent("marker"))
        try Data("old".utf8).write(to: destination.appendingPathComponent("marker"))
        let report = UpdateReplacement.replace(source: source, destination: destination, backup: backup)
        XCTAssertEqual(report.result, .replaced)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8), "new")
        XCTAssertNotNil(report.backup)
        XCTAssertTrue(fm.fileExists(atPath: report.backup!.path))
        XCTAssertEqual(try String(contentsOf: report.backup!.appendingPathComponent("marker"), encoding: .utf8), "old")
    }

    func testReplacementDoesNotDeleteOriginalWhenBackupMoveFails() {
        let source = URL(fileURLWithPath: "/tmp/source.app")
        let destination = URL(fileURLWithPath: "/tmp/dest.app")
        let backup = URL(fileURLWithPath: "/tmp/dest.app.zoneboxbackup-new")
        var store = ["source.app": "NEW", "dest.app": "OLD"]
        var removed: [String] = []
        let files = UpdateFileOperations(
            fileExists: { store[$0.lastPathComponent] != nil },
            removeItem: {
                removed.append($0.lastPathComponent)
                store.removeValue(forKey: $0.lastPathComponent)
            },
            moveItem: { from, to in
                if from.lastPathComponent == "dest.app" {
                    throw NSError(domain: "test", code: 9)
                }
                guard let value = store.removeValue(forKey: from.lastPathComponent) else {
                    throw NSError(domain: "test", code: 2)
                }
                store[to.lastPathComponent] = value
            },
            copyItem: { from, to in
                guard let value = store[from.lastPathComponent] else {
                    throw NSError(domain: "test", code: 3)
                }
                store[to.lastPathComponent] = value
            }
        )
        let report = UpdateReplacement.replace(source: source, destination: destination, backup: backup, files: files)
        guard case .failed = report.result else {
            return XCTFail("expected failed, got " + String(describing: report.result))
        }
        XCTAssertEqual(store["dest.app"], "OLD")
        XCTAssertEqual(store["source.app"], "NEW")
        XCTAssertEqual(removed, [])
        XCTAssertNil(report.backup)
    }

    func testNestedBackupUnderDestinationIsRejected() throws {
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let destination = try makeScratchApp(named: "Nest Dest.app")
        let source = try makeScratchApp(named: "Nest Source.app")
        let backup = destination.appendingPathComponent("inside.zoneboxbackup")
        let request = helperRequest(
            source: source,
            destination: destination,
            pid: 1,
            timeout: 1,
            errorFile: scratchRoot.appendingPathComponent("nested-error.json"),
            relaunch: false,
            expectedVersion: "0.5.1",
            currentVersion: "0.5.1"
        )
        let nested = UpdateHelperRequest(
            parentPID: request.parentPID,
            sourceApp: request.sourceApp,
            destinationApp: request.destinationApp,
            backupApp: backup,
            timeout: request.timeout,
            relaunch: false,
            errorFile: request.errorFile,
            expectedVersion: "0.5.1",
            currentVersion: "0.5.1",
            architecture: .arm64
        )
        XCTAssertEqual(UpdateHelperPreflight.evaluate(nested), "nested paths")
    }

    func testTmpSymlinkAncestorResolvesOfficialApp() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixtureApp.path), "signed fixture missing")
        let tmpURL = URL(fileURLWithPath: "/tmp/zonebox-update-audit-20261027/mount/ZoneBox.app")
        let resolved = UpdateInstallPath.resolvedApp(tmpURL)
        XCTAssertEqual(resolved?.path, fixtureApp.resolvingSymlinksInPath().path)
        XCTAssertEqual(try UpdateStagedBundleLoader.load(fromApp: resolved!).version, "0.5.1")
    }

    func testHelperReplacesOfficial03With051AfterParentExit() throws {
        let oldFixture = URL(fileURLWithPath: "/tmp/zonebox-update-audit-20261027/old-mount/ZoneBox.app").resolvingSymlinksInPath()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: oldFixture.path), "0.3 fixture missing")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixtureApp.path), "0.5.1 fixture missing")
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let source = scratchRoot.appendingPathComponent("New 0.5.1.app", isDirectory: true)
        let dest = scratchRoot.appendingPathComponent("Old 0.3.app", isDirectory: true)
        try FileManager.default.copyItem(at: fixtureApp.resolvingSymlinksInPath(), to: source)
        try FileManager.default.copyItem(at: oldFixture, to: dest)
        XCTAssertEqual(try UpdateStagedBundleLoader.load(fromApp: dest).version, "0.3.0")
        let errorFile = scratchRoot.appendingPathComponent("upgrade-error.json")
        let code = try runAgainstSleepingParent(
            source: source,
            destination: dest,
            errorFile: errorFile,
            sleep: 0.2,
            timeout: 5,
            expectedVersion: "0.5.1",
            currentVersion: "0.3.0"
        )
        XCTAssertEqual(code, 0)
        let staged = try UpdateStagedBundleLoader.load(fromApp: dest)
        XCTAssertEqual(staged.version, "0.5.1")
        XCTAssertTrue(staged.signature.satisfiesOfficialRequirement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: errorFile.path))
    }

    func testHelperTimesOutWithoutTouchingDestinationOrRelaunching() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixtureApp.path), "signed fixture missing")
        let dest = try copyFixture(named: "Live Dest.app")
        let source = try copyFixture(named: "New Copy.app")
        let errorFile = scratchRoot.appendingPathComponent("timeout-error.json")
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["8"]
        try sleeper.run()
        let request = helperRequest(
            source: source,
            destination: dest,
            pid: sleeper.processIdentifier,
            timeout: 0.25,
            errorFile: errorFile,
            relaunch: true
        )
        let code = UpdateHelperRunner.run(request)
        XCTAssertTrue(sleeper.isRunning)
        sleeper.terminate()
        sleeper.waitUntilExit()
        XCTAssertEqual(code, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertTrue(try UpdateStagedBundleLoader.load(fromApp: dest).signature.satisfiesOfficialRequirement)
        XCTAssertNotNil(UpdateInstallFailureRecord.read(from: errorFile))
    }

    func testHelperRejectsMarkerDestinationAfterParentExit() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixtureApp.path), "signed fixture missing")
        let source = try copyFixture(named: "New Copy.app")
        let dest = scratchRoot.appendingPathComponent("My Dest.app", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: dest.appendingPathComponent("marker"))
        let errorFile = scratchRoot.appendingPathComponent("marker-error.json")
        let code = try runAgainstSleepingParent(source: source, destination: dest, errorFile: errorFile, sleep: 0.2, timeout: 5)
        XCTAssertEqual(code, 1)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("marker"), encoding: .utf8), "old")
        XCTAssertNotNil(UpdateInstallFailureRecord.read(from: errorFile))
    }

    func testHelperRejectsTamperedSourceAfterParentExit() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixtureApp.path), "signed fixture missing")
        let source = try copyFixture(named: "Tampered Source.app")
        let executable = source.appendingPathComponent("Contents/MacOS/ZoneBox")
        var data = try Data(contentsOf: executable)
        data[data.count / 2] ^= 0xFF
        try data.write(to: executable)
        let dest = try copyFixture(named: "Official Dest.app")
        let errorFile = scratchRoot.appendingPathComponent("tamper-error.json")
        let code = try runAgainstSleepingParent(source: source, destination: dest, errorFile: errorFile, sleep: 0.2, timeout: 5)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(try UpdateStagedBundleLoader.load(fromApp: dest).signature.satisfiesOfficialRequirement)
        XCTAssertNotNil(UpdateInstallFailureRecord.read(from: errorFile))
    }

    func testHelperReplacesMatchingOfficialCopiesAfterParentExit() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixtureApp.path), "signed fixture missing")
        let source = try copyFixture(named: "New Official.app")
        let dest = try copyFixture(named: "Old Official.app")
        let errorFile = scratchRoot.appendingPathComponent("success-error.json")
        let code = try runAgainstSleepingParent(source: source, destination: dest, errorFile: errorFile, sleep: 0.2, timeout: 5)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(try UpdateStagedBundleLoader.load(fromApp: dest).signature.satisfiesOfficialRequirement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: errorFile.path))
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: dest.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains("zoneboxbackup-") }
        XCTAssertFalse(leftovers.isEmpty)
    }

    private func makeScratchApp(named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let url = scratchRoot.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func copyFixture(named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let url = scratchRoot.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.copyItem(at: fixtureApp, to: url)
        return url
    }

    private func helperRequest(
        source: URL,
        destination: URL,
        pid: Int32,
        timeout: TimeInterval,
        errorFile: URL,
        relaunch: Bool,
        expectedVersion: String = "0.5.1",
        currentVersion: String = "0.5.1"
    ) -> UpdateHelperRequest {
        UpdateHelperRequest(
            parentPID: pid,
            sourceApp: source,
            destinationApp: destination,
            backupApp: UpdateReplacement.uniqueBackupURL(beside: destination),
            timeout: timeout,
            relaunch: relaunch,
            selfDelete: nil,
            errorFile: errorFile,
            expectedVersion: expectedVersion,
            currentVersion: currentVersion,
            architecture: .arm64
        )
    }

    private func runAgainstSleepingParent(
        source: URL,
        destination: URL,
        errorFile: URL,
        sleep: TimeInterval,
        timeout: TimeInterval,
        expectedVersion: String = "0.5.1",
        currentVersion: String = "0.5.1"
    ) throws -> Int32 {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = [String(sleep)]
        try sleeper.run()
        let request = helperRequest(
            source: source,
            destination: destination,
            pid: sleeper.processIdentifier,
            timeout: timeout,
            errorFile: errorFile,
            relaunch: false,
            expectedVersion: expectedVersion,
            currentVersion: currentVersion
        )
        let code = UpdateHelperRunner.run(request)
        if sleeper.isRunning {
            sleeper.terminate()
            sleeper.waitUntilExit()
        }
        return code
    }
    private func fatBinary(
        magic: UInt32,
        nfatArch: UInt32,
        recordSize: Int,
        cpuTypes: [UInt32],
        swapFields: Bool
    ) -> Data {
        var data = Data()
        appendUInt32(magic, to: &data)
        appendUInt32(swapFields ? nfatArch.byteSwapped : nfatArch, to: &data)
        for cpuType in cpuTypes {
            appendUInt32(swapFields ? cpuType.byteSwapped : cpuType, to: &data)
            data.append(Data(count: recordSize - 4))
        }
        return data
    }

    private func thinBinary(magic: UInt32, cpuType: UInt32) -> Data {
        var data = Data()
        appendUInt32(magic, to: &data)
        appendUInt32(cpuType, to: &data)
        return data
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        data.append(Data(bytes: &littleEndian, count: 4))
    }
}
