import XCTest
@testable import ZoneBoxCore

final class SettingsStoreTests: XCTestCase {
    func testDefaultDirectoryFollowsAppIdentity() {
        let store = SettingsStore()
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().lastPathComponent, AppIdentity.bundleID)
        XCTAssertEqual(store.fileURL.lastPathComponent, "settings.json")
    }

    func testDecodingPersistedExclusionsAddsMissingAppIdentities() throws {
        let json = """
        {"schemaVersion":1,"excludedBundleIDs":["com.apple.dock","com.fancyzone.app","com.example.keep"]}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertTrue(settings.excludedBundleIDs.contains("com.apple.dock"))
        XCTAssertTrue(settings.excludedBundleIDs.contains("com.example.keep"))
        XCTAssertTrue(settings.excludedBundleIDs.contains(AppIdentity.releaseBundleID))
        XCTAssertTrue(settings.excludedBundleIDs.contains(AppIdentity.debugBundleID))
        XCTAssertEqual(settings.excludedBundleIDs.filter { $0 == AppIdentity.releaseBundleID }.count, 1)
        XCTAssertTrue(settings.hoverPinEnabled)
    }

    func testHoverPinSettingRoundTripsAndLegacyDefaultsOn() throws {
        var settings = AppSettings.default
        settings.hoverPinEnabled = false
        let data = try JSONEncoder().encode(settings)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).hoverPinEnabled)

        let legacy = try JSONDecoder().decode(
            AppSettings.self,
            from: Data("{\"schemaVersion\":1}".utf8)
        )
        XCTAssertTrue(legacy.hoverPinEnabled)
    }

    func testLayoutStripSettingDefaultsOnForLegacyJSON() throws {
        XCTAssertTrue(AppSettings.default.showLayoutStrip)
        var settings = AppSettings.default
        settings.showLayoutStrip = false
        let data = try JSONEncoder().encode(settings)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).showLayoutStrip)

        let legacy = try JSONDecoder().decode(
            AppSettings.self,
            from: Data("{\"schemaVersion\":1}".utf8)
        )
        XCTAssertTrue(legacy.showLayoutStrip)
    }

    func testPreviewLayoutOnSelectDefaultsOnForLegacyJSON() throws {
        XCTAssertTrue(AppSettings.default.previewLayoutOnSelect)
        var settings = AppSettings.default
        settings.previewLayoutOnSelect = false
        let data = try JSONEncoder().encode(settings)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).previewLayoutOnSelect)

        let legacy = try JSONDecoder().decode(
            AppSettings.self,
            from: Data("{\"schemaVersion\":1}".utf8)
        )
        XCTAssertTrue(legacy.previewLayoutOnSelect)
    }

    func testWorkspaceHotkeyRoundTripsAndLegacyDefaultsToControlOptionP() throws {
        var settings = AppSettings.default
        settings.applyWorkspaceHotkey = KeyChord(
            keyCode: HardwareKeyCode.p,
            carbonModifiers: CarbonModifier.command | CarbonModifier.shift
        )
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(
            try JSONDecoder().decode(AppSettings.self, from: data).applyWorkspaceHotkey,
            settings.applyWorkspaceHotkey
        )

        let legacy = try JSONDecoder().decode(
            AppSettings.self,
            from: Data("{\"schemaVersion\":1}".utf8)
        )
        XCTAssertEqual(
            legacy.applyWorkspaceHotkey,
            KeyChord(keyCode: HardwareKeyCode.p, carbonModifiers: CarbonModifier.controlOption)
        )
    }
}
