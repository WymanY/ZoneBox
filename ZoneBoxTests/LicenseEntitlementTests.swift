import XCTest
@testable import ZoneBoxCore

final class LicenseEntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshTrialAllowsProForFourteenDays() {
        let record = LicenseRecord.freshTrial(now: now)
        let snap = LicenseAccess.snapshot(record, now: now)
        XCTAssertEqual(snap.kind, .trial)
        XCTAssertTrue(snap.allowsPro)
        XCTAssertEqual(snap.trialDaysRemaining, 14)
    }

    func testTrialExpiresAfterFourteenDays() {
        let record = LicenseRecord.freshTrial(now: now)
        let later = now.addingTimeInterval(LicenseAccess.trialLength)
        let snap = LicenseAccess.snapshot(record, now: later)
        XCTAssertEqual(snap.kind, .expired)
        XCTAssertFalse(snap.allowsPro)
        XCTAssertEqual(snap.trialDaysRemaining, 0)
    }

    func testActiveLicenseWithinGraceAllowsPro() {
        let record = LicenseRecord(
            trialStartedAt: now.addingTimeInterval(-LicenseAccess.trialLength * 2),
            licenseKey: "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY",
            instanceID: "inst_1",
            lastValidatedAt: now.addingTimeInterval(-3600),
            lastValidationStatus: .active
        )
        let snap = LicenseAccess.snapshot(record, now: now)
        XCTAssertEqual(snap.kind, .licensed)
        XCTAssertTrue(snap.allowsPro)
        XCTAssertEqual(snap.maskedKey, "•••••UVWXY")
    }

    func testActiveLicenseOlderThanSevenDaysIsOfflineGrace() {
        let record = LicenseRecord(
            trialStartedAt: now.addingTimeInterval(-LicenseAccess.trialLength * 2),
            licenseKey: "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY",
            instanceID: "inst_1",
            lastValidatedAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
            lastValidationStatus: .active
        )
        let snap = LicenseAccess.snapshot(record, now: now)
        XCTAssertEqual(snap.kind, .offlineGrace)
        XCTAssertTrue(snap.allowsPro)
    }

    func testActiveLicensePastThirtyDayGraceExpires() {
        let record = LicenseRecord(
            trialStartedAt: now.addingTimeInterval(-LicenseAccess.trialLength * 2),
            licenseKey: "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY",
            instanceID: "inst_1",
            lastValidatedAt: now.addingTimeInterval(-31 * 24 * 60 * 60),
            lastValidationStatus: .active
        )
        let snap = LicenseAccess.snapshot(record, now: now)
        XCTAssertEqual(snap.kind, .expired)
        XCTAssertFalse(snap.allowsPro)
    }

    func testDisabledLicenseDoesNotFallBackToTrial() {
        let record = LicenseRecord(
            trialStartedAt: now,
            licenseKey: "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY",
            instanceID: "inst_1",
            lastValidatedAt: now,
            lastValidationStatus: .disabled
        )
        let snap = LicenseAccess.snapshot(record, now: now)
        XCTAssertEqual(snap.kind, .expired)
        XCTAssertFalse(snap.allowsPro)
    }

    func testCachedExpiryInThePastExpiresEvenIfStatusIsActive() {
        let record = LicenseRecord(
            trialStartedAt: now.addingTimeInterval(-LicenseAccess.trialLength * 2),
            licenseKey: "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY",
            instanceID: "inst_1",
            lastValidatedAt: now,
            lastValidationStatus: .active,
            cachedExpiresAt: now.addingTimeInterval(-1)
        )
        let snap = LicenseAccess.snapshot(record, now: now)
        XCTAssertEqual(snap.kind, .expired)
        XCTAssertFalse(snap.allowsPro)
    }

    func testStoreCreatesTrialFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZoneBoxLicense-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LicenseStore(directory: dir)
        let loaded = try store.load(now: now)
        XCTAssertEqual(loaded.trialStartedAt, now)
        XCTAssertNil(loaded.licenseKey)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        var updated = loaded
        updated.licenseKey = "KEY-12345"
        updated.instanceID = "inst_2"
        updated.lastValidationStatus = .active
        updated.lastValidatedAt = now
        try store.save(updated)
        let reloaded = try store.load(now: now)
        XCTAssertEqual(reloaded.licenseKey, "KEY-12345")
        XCTAssertEqual(reloaded.instanceID, "inst_2")
    }

    func testPayloadParsesInstanceObjectAndFractionalDate() {
        let json: [String: Any] = [
            "status": "active",
            "key": "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY",
            "expires_at": "2026-09-07T03:52:22.164Z",
            "instance": [
                "id": "inst_1",
                "status": "active",
            ],
        ]
        let payload = CreemLicensePayload.parse(json)
        XCTAssertEqual(payload.status, .active)
        XCTAssertEqual(payload.key, "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY")
        XCTAssertEqual(payload.instanceID, "inst_1")
        XCTAssertNotNil(payload.expiresAt)
    }

    func testPayloadPrefersActiveInstanceFromArray() {
        let json: [String: Any] = [
            "status": "active",
            "key": "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY",
            "expires_at": NSNull(),
            "instance": [
                ["id": "inst_old", "status": "deactivated"],
                ["id": "inst_live", "status": "active"],
            ],
        ]
        let payload = CreemLicensePayload.parse(json)
        XCTAssertEqual(payload.instanceID, "inst_live")
        XCTAssertNil(payload.expiresAt)
    }

    func testPayloadTreatsNullExpiryAndUnknownStatus() {
        let json: [String: Any] = [
            "status": "mystery",
            "key": "KEY-1",
            "instance_id": "inst_fallback",
            "expires_at": "null",
        ]
        let payload = CreemLicensePayload.parse(json)
        XCTAssertEqual(payload.status, .unknown)
        XCTAssertEqual(payload.instanceID, "inst_fallback")
        XCTAssertNil(payload.expiresAt)
    }
}
