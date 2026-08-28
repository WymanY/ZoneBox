import XCTest
@testable import ZoneBoxCore

final class ShortcutCatalogTests: XCTestCase {
    func testDefaultCarbonHotkeysAreUniqueAndSequoiaLegal() {
        let pairs = ShortcutCatalog.carbonHotkeys(from: .default)
        XCTAssertEqual(Set(pairs.map(\.id)).count, pairs.count)
        XCTAssertTrue(pairs.contains(where: { $0.id == ShortcutCatalog.editorHotkeyID }))
        XCTAssertTrue(pairs.contains(where: { $0.id == ShortcutCatalog.shortcutsPanelHotkeyID }))
        XCTAssertTrue(pairs.contains(where: { $0.id == ShortcutCatalog.quickSnapperHotkeyID }))
        XCTAssertTrue(pairs.contains(where: { $0.id == 1 }))
        XCTAssertTrue(pairs.contains(where: { $0.id == 9 }))
        for pair in pairs {
            XCTAssertTrue(pair.chord.isSequoiaLegal, "illegal chord id=\(pair.id) caps=\(pair.chord.displayCaps)")
        }
    }

    func testZoneKeyCodesMatchHardwareOneThroughNine() {
        XCTAssertEqual(AppSettings.zoneKeyCodes, [18, 19, 20, 21, 23, 22, 26, 28, 25])
        XCTAssertEqual(KeyChord.glyph(for: 18), "1")
        XCTAssertEqual(KeyChord.glyph(for: 25), "9")
        XCTAssertEqual(KeyChord.glyph(for: HardwareKeyCode.z), "Z")
        XCTAssertEqual(KeyChord.glyph(for: HardwareKeyCode.slash), "/")
    }

    func testControlOptionZMatchesEditorDefault() {
        let chord = AppSettings.default.editorHotkey
        XCTAssertTrue(chord.matches(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.controlOption))
        XCTAssertFalse(chord.matches(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.control))
        XCTAssertFalse(chord.matches(keyCode: HardwareKeyCode.u, carbonModifiers: CarbonModifier.controlOption))
        XCTAssertEqual(chord.displayCaps, ["⌃", "⌥", "Z"])
    }

    func testHotkeyLookupUsesCurrentSettings() {
        let settings = AppSettings.default
        XCTAssertEqual(
            ShortcutCatalog.hotkeyID(
                matching: HardwareKeyCode.z,
                carbonModifiers: CarbonModifier.controlOption,
                settings: settings
            ),
            ShortcutCatalog.editorHotkeyID
        )
        XCTAssertEqual(
            ShortcutCatalog.hotkeyID(
                matching: HardwareKeyCode.slash,
                carbonModifiers: CarbonModifier.controlOption,
                settings: settings
            ),
            ShortcutCatalog.shortcutsPanelHotkeyID
        )
        XCTAssertEqual(
            ShortcutCatalog.hotkeyID(
                matching: HardwareKeyCode.space,
                carbonModifiers: CarbonModifier.controlOption,
                settings: settings
            ),
            ShortcutCatalog.quickSnapperHotkeyID
        )
        XCTAssertEqual(
            ShortcutCatalog.hotkeyID(
                matching: 18,
                carbonModifiers: CarbonModifier.controlOption,
                settings: settings
            ),
            1
        )
        XCTAssertNil(
            ShortcutCatalog.hotkeyID(
                matching: HardwareKeyCode.tab,
                carbonModifiers: 0,
                settings: settings
            )
        )
    }

    func testDisabledZoneHotkeysDropOneThroughNine() {
        var settings = AppSettings.default
        settings.snapZoneHotkeysEnabled = false
        let ids = Set(ShortcutCatalog.carbonHotkeys(from: settings).map(\.id))
        XCTAssertFalse(ids.contains(1))
        XCTAssertFalse(ids.contains(9))
        XCTAssertTrue(ids.contains(ShortcutCatalog.editorHotkeyID))
    }

    func testCatalogCoversEverySurfaceAndHasCopy() {
        let grouped = ShortcutCatalog.grouped(from: .default)
        XCTAssertEqual(grouped.map(\.surface), ShortcutSurface.allCases)
        for group in grouped {
            XCTAssertFalse(group.items.isEmpty, "empty surface \(group.surface)")
            for item in group.items {
                XCTAssertFalse(item.title(language: .english).isEmpty, item.id)
                XCTAssertFalse(item.title(language: .chineseSimplified).isEmpty, item.id)
                XCTAssertNotEqual(
                    item.title(language: .english),
                    item.title(language: .chineseSimplified),
                    item.id
                )
            }
        }
    }

    func testEscapePrefersKeyShortcutsPanelOverEditor() {
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(shortcutsPanelIsKey: true, editorClaimsKeyboard: true, appHasKeyWindow: true)
            ),
            .closeShortcuts
        )
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(shortcutsPanelIsKey: false, editorClaimsKeyboard: true, appHasKeyWindow: true)
            ),
            .cancelEditor
        )
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(shortcutsPanelIsKey: false, editorClaimsKeyboard: false, appHasKeyWindow: false)
            ),
            .cancelSnap
        )
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(
                    shortcutsPanelIsKey: false,
                    editorClaimsKeyboard: false,
                    appHasKeyWindow: true,
                    quickSnapperShowing: true
                )
            ),
            .dismissQuickSnapper
        )
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(shortcutsPanelIsKey: false, editorClaimsKeyboard: false, appHasKeyWindow: true)
            ),
            .ignore
        )
    }

    func testOnlyAdjacentAndCycleHotkeysRepeat() {
        XCTAssertTrue(ShortcutCatalog.allowsKeyRepeat(hotkeyID: ShortcutCatalog.nextZoneHotkeyID))
        XCTAssertTrue(ShortcutCatalog.allowsKeyRepeat(hotkeyID: ShortcutCatalog.cycleForwardHotkeyID))
        XCTAssertFalse(ShortcutCatalog.allowsKeyRepeat(hotkeyID: ShortcutCatalog.shortcutsPanelHotkeyID))
        XCTAssertFalse(ShortcutCatalog.allowsKeyRepeat(hotkeyID: ShortcutCatalog.editorHotkeyID))
        XCTAssertFalse(ShortcutCatalog.allowsKeyRepeat(hotkeyID: 1))
    }

    func testTrustExemptIDsDoNotRequireAccessibility() {
        XCTAssertTrue(ShortcutCatalog.trustExemptIDs.contains(ShortcutCatalog.editorHotkeyID))
        XCTAssertTrue(ShortcutCatalog.trustExemptIDs.contains(ShortcutCatalog.shortcutsPanelHotkeyID))
        XCTAssertFalse(ShortcutCatalog.trustExemptIDs.contains(1))
        XCTAssertFalse(ShortcutCatalog.trustExemptIDs.contains(ShortcutCatalog.unsnapHotkeyID))
    }

    func testCommandCommaAndShiftTabDisplay() {
        let settings = KeyChord(keyCode: HardwareKeyCode.comma, carbonModifiers: CarbonModifier.command)
        XCTAssertEqual(settings.displayCaps, ["⌘", ","])
        let backtab = KeyChord(keyCode: HardwareKeyCode.tab, carbonModifiers: CarbonModifier.shift)
        XCTAssertEqual(backtab.displayCaps, ["⇧", "⇥"])
    }
}
