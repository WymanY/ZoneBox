import XCTest
@testable import ZoneBoxCore

final class ReleaseUpdateTests: XCTestCase {
    func testParsesStableTagsAndRejectsMalformedOrPrerelease() {
        XCTAssertEqual(AppVersion.parse("v0.5.1"), AppVersion(major: 0, minor: 5, patch: 1))
        XCTAssertEqual(AppVersion.parse("0.5.1"), AppVersion(major: 0, minor: 5, patch: 1))
        XCTAssertEqual(AppVersion.parse("0.5"), AppVersion(major: 0, minor: 5, patch: 0))
        XCTAssertEqual(AppVersion.parse("1.2.3+build.4"), AppVersion(major: 1, minor: 2, patch: 3))
        XCTAssertNil(AppVersion.parse("1..2"))
        XCTAssertNil(AppVersion.parse("1.2."))
        XCTAssertNil(AppVersion.parse(".1.2"))
        XCTAssertNil(AppVersion.parse("1.0.0-"))
        XCTAssertNil(AppVersion.parse("1.0.0-beta.1"))
        XCTAssertNil(AppVersion.parse("01.2.3"))
        XCTAssertNil(AppVersion.parse(""))
        XCTAssertNil(AppVersion.parse("v"))
    }

    func testVersionOrderingAvoidsDowngrade() {
        let older = AppVersion.parse("0.5.0")!
        let newer = AppVersion.parse("0.5.1")!
        XCTAssertTrue(older < newer)
        XCTAssertFalse(newer < older)
        XCTAssertEqual(AppVersion.parse("v0.5.1"), AppVersion.parse("0.5.1"))
        XCTAssertFalse(AppVersion.parse("0.5.1")! < AppVersion.parse("0.5.0")!)
    }

    func testLiveLikeReleaseSelectsUniversalDMGAndSkipsArchives() throws {
        let json = """
        {
          "tag_name": "0.5.1",
          "name": "0.5.1",
          "draft": false,
          "prerelease": false,
          "assets": [
            {
              "name": "SHA256SUMS",
              "size": 98,
              "browser_download_url": "https://github.com/WymanY/ZoneBox/releases/download/0.5.1/SHA256SUMS"
            },
            {
              "name": "ZoneBox-0.5.1.dmg",
              "size": 6155209,
              "browser_download_url": "https://github.com/WymanY/ZoneBox/releases/download/0.5.1/ZoneBox-0.5.1.dmg",
              "digest": "sha256:7d3a44030ecbca0398d4039c4f54684a628695e5ec3626e76a6b749141d16c94"
            },
            {
              "name": "source.zip",
              "size": 123,
              "browser_download_url": "https://github.com/WymanY/ZoneBox/archive/refs/tags/0.5.1.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        let available = try ReleaseUpdateSelector.evaluate(json: json, currentVersion: "0.5.0", architecture: .arm64)
        guard case .available(let offer) = available else {
            return XCTFail("expected available, got \(available)")
        }
        XCTAssertEqual(offer.latestVersion.description, "0.5.1")
        XCTAssertEqual(offer.asset.name, "ZoneBox-0.5.1.dmg")
        XCTAssertEqual(offer.asset.size, 6155209)
        XCTAssertEqual(offer.expectedSHA256, "7d3a44030ecbca0398d4039c4f54684a628695e5ec3626e76a6b749141d16c94")

        let current = try ReleaseUpdateSelector.evaluate(json: json, currentVersion: "0.5.1", architecture: .x86_64)
        guard case .upToDate(_, let latest) = current else {
            return XCTFail("expected up to date, got \(current)")
        }
        XCTAssertEqual(latest.description, "0.5.1")

        let newer = try ReleaseUpdateSelector.evaluate(json: json, currentVersion: "0.6.0", architecture: .arm64)
        guard case .rejected(.notNewer(let installed, _)) = newer else {
            return XCTFail("expected not newer, got \(newer)")
        }
        XCTAssertEqual(installed.description, "0.6.0")
    }

    func testPrefersMatchingArchitectureAndRejectsWrongArchOnlySet() {
        let arm = asset("ZoneBox-0.5.1-arm64.dmg", size: 10, digest: validDigest)
        let intel = asset("ZoneBox-0.5.1-x86_64.dmg", size: 11, digest: validDigest)
        let source = asset("ZoneBox-0.5.1-source.zip", size: 12, digest: validDigest)
        let chosen = ReleaseUpdateSelector.selectAsset(
            from: [source, intel, arm],
            version: AppVersion(major: 0, minor: 5, patch: 1),
            architecture: .arm64
        )
        XCTAssertEqual(chosen?.name, "ZoneBox-0.5.1-arm64.dmg")

        let intelOnly = ReleaseUpdateSelector.selectAsset(
            from: [intel, source],
            version: AppVersion(major: 0, minor: 5, patch: 1),
            architecture: .arm64
        )
        XCTAssertNil(intelOnly)
    }

    func testSkipsDraftPrereleaseMissingDigestAndNonDMG() {
        let dmg = asset("ZoneBox-0.6.0.dmg", size: 20, digest: validDigest)
        let draft = GitHubRelease(tagName: "0.6.0", draft: true, prerelease: false, assets: [dmg])
        XCTAssertEqual(
            ReleaseUpdateSelector.evaluate(release: draft, currentVersion: "0.5.0", architecture: .arm64),
            .rejected(.draft)
        )

        let pre = GitHubRelease(tagName: "0.6.0", draft: false, prerelease: true, assets: [dmg])
        XCTAssertEqual(
            ReleaseUpdateSelector.evaluate(release: pre, currentVersion: "0.5.0", architecture: .arm64),
            .rejected(.prerelease)
        )

        let zipOnly = GitHubRelease(
            tagName: "0.6.0",
            draft: false,
            prerelease: false,
            assets: [asset("ZoneBox-0.6.0.zip", size: 20, digest: validDigest)]
        )
        XCTAssertEqual(
            ReleaseUpdateSelector.evaluate(release: zipOnly, currentVersion: "0.5.0", architecture: .arm64),
            .rejected(.noMacInstaller)
        )

        let noDigest = GitHubRelease(
            tagName: "0.6.0",
            draft: false,
            prerelease: false,
            assets: [asset("ZoneBox-0.6.0.dmg", size: 20, digest: nil)]
        )
        XCTAssertEqual(
            ReleaseUpdateSelector.evaluate(release: noDigest, currentVersion: "0.5.0", architecture: .arm64),
            .rejected(.missingDigest)
        )
    }

    func testDownloadedPayloadSizeAndDigest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("ZoneBox-test.dmg")
        let payload = Data("zonebox-update-payload".utf8)
        try payload.write(to: file)
        let digest = UpdateDigest.sha256Hex(of: payload)

        XCTAssertNoThrow(
            try ReleaseUpdateSelector.validateDownloadedFile(at: file, expectedSize: payload.count, expectedSHA256: digest)
        )

        XCTAssertThrowsError(
            try ReleaseUpdateSelector.validateDownloadedFile(at: file, expectedSize: payload.count + 1, expectedSHA256: digest)
        ) { error in
            XCTAssertEqual(error as? UpdateValidationError, .sizeMismatch(expected: payload.count + 1, actual: payload.count))
        }

        XCTAssertThrowsError(
            try ReleaseUpdateSelector.validateDownloadedFile(at: file, expectedSize: payload.count, expectedSHA256: String(repeating: "0", count: 64))
        ) { error in
            XCTAssertEqual(error as? UpdateValidationError, .digestMismatch)
        }

        XCTAssertThrowsError(
            try ReleaseUpdateSelector.validateDownloadedFile(
                at: dir.appendingPathComponent("missing.dmg"),
                expectedSize: payload.count,
                expectedSHA256: digest
            )
        ) { error in
            XCTAssertEqual(error as? UpdateValidationError, .missingFile)
        }
    }

    func testAutomaticCheckCadence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(
            UpdateSchedule.shouldAutomaticallyCheck(enabled: false, lastCheckAt: nil, lastSuccessfulCheckAt: nil, now: now)
        )
        XCTAssertTrue(
            UpdateSchedule.shouldAutomaticallyCheck(enabled: true, lastCheckAt: nil, lastSuccessfulCheckAt: nil, now: now)
        )
        XCTAssertFalse(
            UpdateSchedule.shouldAutomaticallyCheck(
                enabled: true,
                lastCheckAt: now.addingTimeInterval(-60),
                lastSuccessfulCheckAt: nil,
                now: now
            )
        )
        XCTAssertFalse(
            UpdateSchedule.shouldAutomaticallyCheck(
                enabled: true,
                lastCheckAt: now.addingTimeInterval(-UpdateSchedule.successfulInterval),
                lastSuccessfulCheckAt: now.addingTimeInterval(-60 * 60),
                now: now
            )
        )
        XCTAssertTrue(
            UpdateSchedule.shouldAutomaticallyCheck(
                enabled: true,
                lastCheckAt: now.addingTimeInterval(-UpdateSchedule.successfulInterval),
                lastSuccessfulCheckAt: now.addingTimeInterval(-UpdateSchedule.successfulInterval),
                now: now
            )
        )
    }

    func testUpdateStoreRoundTripAndCorruptFallback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UpdateStore(directory: dir)
        var record = UpdateRecord.empty
        record.lastKnownLatestVersion = "0.5.1"
        record.lastCheckAt = Date(timeIntervalSince1970: 10)
        try store.save(record)
        XCTAssertEqual(try store.load().lastKnownLatestVersion, "0.5.1")

        try Data("{nope".utf8).write(to: store.fileURL)
        XCTAssertEqual(try store.load(), .empty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("updates.json.corrupt-") })
    }

    func testAutomaticUpdatesDefaultOnForLegacySettings() throws {
        XCTAssertTrue(AppSettings.default.automaticUpdatesEnabled)
        var settings = AppSettings.default
        settings.automaticUpdatesEnabled = false
        let data = try JSONEncoder().encode(settings)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).automaticUpdatesEnabled)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{\"schemaVersion\":1}".utf8))
        XCTAssertTrue(legacy.automaticUpdatesEnabled)
    }

    func testDownloadedInstallerRecordRoundTripsAndLegacyOmitsIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UpdateStore(directory: dir)
        var record = UpdateRecord.empty
        record.lastKnownLatestVersion = "0.5.1"
        record.downloadedInstallerPath = "/tmp/ZoneBox-0.5.1.dmg"
        record.downloadedInstaller = DownloadedInstallerRecord(
            version: "0.5.1",
            tagName: "0.5.1",
            assetName: "ZoneBox-0.5.1.dmg",
            size: 10,
            sha256: String(repeating: "ab", count: 32),
            downloadURL: "https://github.com/WymanY/ZoneBox/releases/download/0.5.1/ZoneBox-0.5.1.dmg",
            path: "/tmp/ZoneBox-0.5.1.dmg"
        )
        try store.save(record)
        let loaded = try store.load()
        XCTAssertEqual(loaded.downloadedInstaller?.version, "0.5.1")
        XCTAssertEqual(loaded.downloadedInstaller?.size, 10)
        XCTAssertEqual(loaded.downloadedInstallerPath, "/tmp/ZoneBox-0.5.1.dmg")

        let legacy = try JSONCoding.decoder().decode(
            UpdateRecord.self,
            from: Data("{\"schemaVersion\":1,\"downloadedInstallerPath\":\"/old.dmg\"}".utf8)
        )
        XCTAssertEqual(legacy.downloadedInstallerPath, "/old.dmg")
        XCTAssertNil(legacy.downloadedInstaller)
        XCTAssertNil(DownloadedInstallerRestore.makeOffer(from: legacy, currentVersion: "0.5.0"))
    }

    func testRestoreOfferRequiresTrustedHTTPSAndNewerVersion() throws {
        let payload = Data("installer".utf8)
        let digest = UpdateDigest.sha256Hex(of: payload)
        var record = UpdateRecord.empty
        record.downloadedInstaller = DownloadedInstallerRecord(
            version: "0.5.1",
            tagName: "0.5.1",
            assetName: "ZoneBox-0.5.1.dmg",
            size: payload.count,
            sha256: digest,
            downloadURL: "https://github.com/WymanY/ZoneBox/releases/download/0.5.1/ZoneBox-0.5.1.dmg",
            path: "/tmp/ZoneBox-0.5.1.dmg"
        )
        XCTAssertNotNil(DownloadedInstallerRestore.makeOffer(from: record, currentVersion: "0.5.0"))
        XCTAssertNil(DownloadedInstallerRestore.makeOffer(from: record, currentVersion: "0.5.1"))
        record.downloadedInstaller?.downloadURL = "http://example.com/ZoneBox-0.5.1.dmg"
        XCTAssertNil(DownloadedInstallerRestore.makeOffer(from: record, currentVersion: "0.5.0"))
    }

    func testPlacementKeepsExistingFileIfCopyFails() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let existing = dir.appendingPathComponent("ZoneBox-0.5.1.dmg")
        try Data("keep-me".utf8).write(to: existing)
        XCTAssertThrowsError(
            try UpdateFilePlacement.place(
                from: dir.appendingPathComponent("missing.bin"),
                intoDirectory: dir,
                named: "ZoneBox-0.5.1.dmg"
            )
        )
        XCTAssertEqual(try String(contentsOf: existing), "keep-me")

        let source = dir.appendingPathComponent("new.bin")
        try Data("replaced".utf8).write(to: source)
        let placed = try UpdateFilePlacement.place(from: source, intoDirectory: dir, named: "ZoneBox-0.5.1.dmg")
        XCTAssertEqual(placed.lastPathComponent, "ZoneBox-0.5.1.dmg")
        XCTAssertEqual(try String(contentsOf: placed), "replaced")
    }

    private var validDigest: String {
        "sha256:" + String(repeating: "ab", count: 32)
    }

    private func asset(_ name: String, size: Int, digest: String?) -> GitHubReleaseAsset {
        GitHubReleaseAsset(
            name: name,
            size: size,
            browserDownloadURL: URL(string: "https://example.com/\(name)")!,
            digest: digest
        )
    }
}
