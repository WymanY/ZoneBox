import XCTest
@testable import ZoneBoxCore

final class ShortcutCatalogTests: XCTestCase {
    func testDefaultCarbonHotkeysAreUniqueAndSequoiaLegal() {
        let pairs = ShortcutCatalog.carbonHotkeys(from: .default)
        XCTAssertEqual(Set(pairs.map(\.id)).count, pairs.count)
        XCTAssertTrue(pairs.contains(where: { $0.id == ShortcutCatalog.editorHotkeyID }))
        XCTAssertTrue(pairs.contains(where: { $0.id == ShortcutCatalog.shortcutsPanelHotkeyID }))
        XCTAssertTrue(pairs.contains(where: { $0.id == ShortcutCatalog.quickSnapperHotkeyID }))
        XCTAssertTrue(pairs.contains(where: { $0.id == ShortcutCatalog.applyWorkspaceHotkeyID }))
        XCTAssertEqual(WindowOrganize.isPubliclyAvailable, false)
        XCTAssertFalse(pairs.contains(where: { $0.id == ShortcutCatalog.organizeHotkeyID }))
        XCTAssertFalse(pairs.contains(where: { $0.id == ShortcutCatalog.settingsHotkeyID }))
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
        XCTAssertEqual(HardwareKeyCode.a, 0)
        XCTAssertEqual(HardwareKeyCode.s, 1)
        XCTAssertEqual(HardwareKeyCode.d, 2)
        XCTAssertEqual(HardwareKeyCode.w, 13)
        XCTAssertEqual(KeyChord.glyph(for: HardwareKeyCode.w), "W")
        XCTAssertEqual(KeyChord.glyph(for: HardwareKeyCode.a), "A")
        XCTAssertEqual(KeyChord.glyph(for: HardwareKeyCode.s), "S")
        XCTAssertEqual(KeyChord.glyph(for: HardwareKeyCode.d), "D")
        XCTAssertEqual(HardwareKeyCode.o, 31)
        XCTAssertEqual(KeyChord.glyph(for: HardwareKeyCode.o), "O")
        XCTAssertEqual(KeyChord.glyph(for: HardwareKeyCode.p), "P")
        XCTAssertTrue(HardwareKeyCode.isEditorPaneNavigation(HardwareKeyCode.d))
        XCTAssertTrue(HardwareKeyCode.isEditorPaneNavigation(HardwareKeyCode.w))
        XCTAssertFalse(HardwareKeyCode.isEditorPaneNavigation(HardwareKeyCode.tab))
        XCTAssertEqual(KeyChord.glyph(for: 14), "E")
        XCTAssertEqual(KeyChord.glyph(for: 122), "F1")
        XCTAssertTrue(HardwareKeyCode.isModifierKey(HardwareKeyCode.command))
        XCTAssertFalse(HardwareKeyCode.isModifierKey(HardwareKeyCode.z))
    }

    func testControlOptionZMatchesEditorDefault() {
        let chord = AppSettings.default.editorHotkey
        XCTAssertTrue(chord.matches(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.controlOption))
        XCTAssertFalse(chord.matches(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.control))
        XCTAssertFalse(chord.matches(keyCode: HardwareKeyCode.u, carbonModifiers: CarbonModifier.controlOption))
        XCTAssertEqual(chord.displayCaps, ["⌃", "⌥", "Z"])
    }

    func testWorkspaceShortcutCanBeCustomizedAndReset() {
        let custom = KeyChord(
            keyCode: HardwareKeyCode.p,
            carbonModifiers: CarbonModifier.command | CarbonModifier.shift
        )
        let changed = ShortcutCatalog.applying(custom, to: .applyWorkspace, in: .default)
        XCTAssertEqual(changed.applyWorkspaceHotkey, custom)
        XCTAssertEqual(
            ShortcutCatalog.resetting(.applyWorkspace, in: changed).applyWorkspaceHotkey,
            AppSettings.default.applyWorkspaceHotkey
        )
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
                matching: HardwareKeyCode.p,
                carbonModifiers: CarbonModifier.controlOption,
                settings: settings
            ),
            ShortcutCatalog.applyWorkspaceHotkeyID
        )
        XCTAssertEqual(
            ShortcutCatalog.hotkeyID(
                matching: HardwareKeyCode.o,
                carbonModifiers: CarbonModifier.controlOption,
                settings: settings
            ),
            nil
        )
        XCTAssertNil(
            ShortcutCatalog.hotkeyID(
                matching: HardwareKeyCode.comma,
                carbonModifiers: CarbonModifier.command,
                settings: settings
            )
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

    func testOverlayDigitShortcutIsASnapGesture() throws {
        let item = try XCTUnwrap(
            ShortcutCatalog.items(from: .default).first(where: { $0.id == "overlayDigit" })
        )
        XCTAssertEqual(item.surface, .snap)
        XCTAssertEqual(
            item.title(language: .english),
            "Snap to a numbered zone while the overlay is showing"
        )
        XCTAssertEqual(item.title(language: .chineseSimplified), "覆盖层显示时按分区编号吸附")
        guard case .gesture(let key) = item.binding else {
            return XCTFail("overlayDigit must be a snap gesture")
        }
        XCTAssertEqual(L10n.text(key, language: .english), "1–9")
    }

    func testCycleLayoutShortcutIsASnapGesture() throws {
        let item = try XCTUnwrap(
            ShortcutCatalog.items(from: .default).first(where: { $0.id == "cycleLayout" })
        )
        XCTAssertEqual(item.surface, .snap)
        XCTAssertEqual(
            item.title(language: .english),
            "Switch to the next layout while the overlay is showing"
        )
        guard case .gesture(let key) = item.binding else {
            return XCTFail("cycleLayout must be a snap gesture")
        }
        XCTAssertEqual(L10n.text(key, language: .english), "Scroll or ⇥")
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
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(
                    shortcutsPanelIsKey: false,
                    editorClaimsKeyboard: false,
                    appHasKeyWindow: true,
                    isRecordingHotkey: true,
                    settingsIsKey: true
                )
            ),
            .cancelHotkeyRecording
        )
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(
                    shortcutsPanelIsKey: false,
                    editorClaimsKeyboard: false,
                    appHasKeyWindow: true,
                    settingsIsKey: true
                )
            ),
            .closeSettings
        )
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(
                    shortcutsPanelIsKey: false,
                    editorClaimsKeyboard: false,
                    appHasKeyWindow: true,
                    onboardingIsKey: true
                )
            ),
            .closeOnboarding
        )
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(
                    shortcutsPanelIsKey: false,
                    editorClaimsKeyboard: false,
                    appHasKeyWindow: true,
                    consoleIsVisible: true
                )
            ),
            .closeConsole
        )
        XCTAssertEqual(
            ShortcutRouteContext.escapeAction(
                ShortcutRouteContext(
                    shortcutsPanelIsKey: false,
                    editorClaimsKeyboard: false,
                    appHasKeyWindow: true,
                    dividerDragging: true
                )
            ),
            .cancelDivider
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
        XCTAssertTrue(ShortcutCatalog.trustExemptIDs.contains(ShortcutCatalog.organizeHotkeyID))
        XCTAssertFalse(ShortcutCatalog.trustExemptIDs.contains(ShortcutCatalog.settingsHotkeyID))
        XCTAssertFalse(ShortcutCatalog.trustExemptIDs.contains(1))
        XCTAssertFalse(ShortcutCatalog.trustExemptIDs.contains(ShortcutCatalog.unsnapHotkeyID))
    }

    func testCommandCommaAndShiftTabDisplay() {
        let settings = KeyChord(keyCode: HardwareKeyCode.comma, carbonModifiers: CarbonModifier.command)
        XCTAssertEqual(settings.displayCaps, ["⌘", ","])
        let backtab = KeyChord(keyCode: HardwareKeyCode.tab, carbonModifiers: CarbonModifier.shift)
        XCTAssertEqual(backtab.displayCaps, ["⇧", "⇥"])
    }

    func testEditorSaveUsesCommandS() throws {
        let save = try XCTUnwrap(
            ShortcutCatalog.items(from: .default).first(where: { $0.id == "editorSave" })
        )
        guard case .chord(let chord) = save.binding else {
            return XCTFail("editorSave must be a keyboard chord")
        }

        XCTAssertTrue(
            chord.matches(
                keyCode: HardwareKeyCode.s,
                carbonModifiers: CarbonModifier.command
            )
        )
        XCTAssertFalse(chord.matches(keyCode: HardwareKeyCode.s, carbonModifiers: 0))
        XCTAssertEqual(chord.displayCaps, ["⌘", "S"])
        XCTAssertEqual(save.title(language: .english), "Save layout or copy")
        XCTAssertEqual(save.title(language: .chineseSimplified), "保存布局或另存副本")
    }

    func testEditorUndoUsesControlZ() throws {
        let undo = try XCTUnwrap(
            ShortcutCatalog.items(from: .default).first(where: { $0.id == "editorUndo" })
        )
        guard case .chord(let chord) = undo.binding else {
            return XCTFail("editorUndo must be a keyboard chord")
        }

        XCTAssertTrue(
            chord.matches(
                keyCode: HardwareKeyCode.z,
                carbonModifiers: CarbonModifier.command
            )
        )
        XCTAssertTrue(
            ShortcutCatalog.isEditorUndoChord(
                keyCode: HardwareKeyCode.z,
                carbonModifiers: CarbonModifier.control
            )
        )
        XCTAssertEqual(chord.displayCaps, ["⌘", "Z"])
        XCTAssertEqual(undo.title(language: .english), "Undo last edit")
        XCTAssertEqual(undo.title(language: .chineseSimplified), "撤销上一步")
    }

    func testOrganizeUsesControlOptionO() throws {
        XCTAssertFalse(WindowOrganize.isPubliclyAvailable)
        XCTAssertNil(ShortcutCatalog.items(from: .default).first(where: { $0.id == "organizeWindows" }))
        XCTAssertFalse(ShortcutCatalog.customizableBindings(from: .default).contains(where: { $0.id == .organizeWindows }))
        XCTAssertEqual(AppSettings.default.organizeHotkey.displayCaps, ["⌃", "⌥", "O"])
    }

    func testSettingsUsesCommandComma() throws {
        let item = try XCTUnwrap(
            ShortcutCatalog.items(from: .default).first(where: { $0.id == "openSettings" })
        )
        guard case .chord(let chord) = item.binding else {
            return XCTFail("openSettings must be a keyboard chord")
        }
        XCTAssertEqual(item.surface, .application)
        XCTAssertNil(item.hotkeyID)
        XCTAssertTrue(chord.matches(keyCode: HardwareKeyCode.comma, carbonModifiers: CarbonModifier.command))
        XCTAssertEqual(chord.displayCaps, ["⌘", ","])
        XCTAssertTrue(ShortcutCatalog.customizableBindings(from: .default).contains(where: { $0.id == .openSettings }))
    }

    func testIndependentHotkeysDoNotShareEditorModifiers() {
        var settings = AppSettings.default
        settings.editorHotkey = KeyChord(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.control | CarbonModifier.shift)
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
    }

    func testRebindingRejectsDuplicatesAndSequoiaIllegalChords() {
        var settings = AppSettings.default
        XCTAssertEqual(
            ShortcutCatalog.validate(
                KeyChord(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.option),
                replacing: .openEditor,
                in: settings
            ),
            .sequoiaIllegal
        )
        XCTAssertEqual(
            ShortcutCatalog.validate(
                settings.unsnapHotkey,
                replacing: .openEditor,
                in: settings
            ),
            .duplicate(.unsnap)
        )

        settings = ShortcutCatalog.applying(
            KeyChord(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.command),
            to: .openEditor,
            in: settings
        )
        XCTAssertEqual(settings.editorHotkey.keyCode, HardwareKeyCode.z)
        XCTAssertEqual(settings.shortcutsPanelHotkey.keyCode, HardwareKeyCode.slash)
        XCTAssertEqual(
            ShortcutCatalog.hotkeyID(
                matching: HardwareKeyCode.z,
                carbonModifiers: CarbonModifier.command,
                settings: settings
            ),
            ShortcutCatalog.editorHotkeyID
        )
    }

    func testLegacySettingsInheritEditorModifiers() throws {
        let json = """
        {"schemaVersion":1,"editorHotkey":{"keyCode":6,"carbonModifiers":4608}}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.editorHotkey.carbonModifiers, CarbonModifier.control | CarbonModifier.shift)
        XCTAssertEqual(settings.shortcutsPanelHotkey.carbonModifiers, settings.editorHotkey.carbonModifiers)
        XCTAssertEqual(settings.quickSnapperHotkey.carbonModifiers, settings.editorHotkey.carbonModifiers)
        XCTAssertEqual(settings.zoneHotkeyModifiers, settings.editorHotkey.carbonModifiers)
        XCTAssertEqual(settings.shortcutsPanelHotkey.keyCode, HardwareKeyCode.slash)
        XCTAssertEqual(settings.quickSnapperHotkey.keyCode, HardwareKeyCode.space)
    }

    func testCustomHotkeysSurviveJSONRoundTrip() throws {
        var settings = AppSettings.default
        settings.editorHotkey = KeyChord(keyCode: HardwareKeyCode.e, carbonModifiers: CarbonModifier.command | CarbonModifier.shift)
        settings.shortcutsPanelHotkey = KeyChord(keyCode: HardwareKeyCode.slash, carbonModifiers: CarbonModifier.control | CarbonModifier.shift)
        settings.zoneHotkeyModifiers = CarbonModifier.control | CarbonModifier.shift
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.editorHotkey, settings.editorHotkey)
        XCTAssertEqual(decoded.shortcutsPanelHotkey, settings.shortcutsPanelHotkey)
        XCTAssertEqual(decoded.zoneHotkeyModifiers, settings.zoneHotkeyModifiers)
        XCTAssertEqual(
            ShortcutCatalog.hotkeyID(
                matching: HardwareKeyCode.e,
                carbonModifiers: CarbonModifier.command | CarbonModifier.shift,
                settings: decoded
            ),
            ShortcutCatalog.editorHotkeyID
        )
        XCTAssertEqual(
            ShortcutCatalog.hotkeyID(
                matching: 18,
                carbonModifiers: CarbonModifier.control | CarbonModifier.shift,
                settings: decoded
            ),
            1
        )
    }

    func testVoiceOverOnlyPausesControlOptionChords() {
        let controlOption = AppSettings.default.editorHotkey
        let command = KeyChord(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.command)
        XCTAssertTrue(ShortcutVoiceOverPolicy.shouldPause(chord: controlOption, voiceOverEnabled: true))
        XCTAssertFalse(ShortcutVoiceOverPolicy.shouldPause(chord: command, voiceOverEnabled: true))
        XCTAssertFalse(ShortcutVoiceOverPolicy.shouldPause(chord: controlOption, voiceOverEnabled: false))
    }

    func testReservedSystemChordsAreRejected() {
        XCTAssertEqual(
            ShortcutCatalog.validate(
                KeyChord(keyCode: HardwareKeyCode.space, carbonModifiers: CarbonModifier.command),
                replacing: .quickSnapper,
                in: .default
            ),
            .reservedSystem("Spotlight")
        )
        XCTAssertEqual(
            ShortcutCatalog.validate(
                KeyChord(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.command),
                replacing: .openEditor,
                in: .default
            ),
            .reservedSystem("Undo")
        )
    }

    func testZoneModifierConflictUsesTheOtherAction() {
        var settings = AppSettings.default
        settings.unsnapHotkey = KeyChord(keyCode: 18, carbonModifiers: CarbonModifier.control | CarbonModifier.shift)
        XCTAssertEqual(
            ShortcutCatalog.validate(
                KeyChord(keyCode: 18, carbonModifiers: CarbonModifier.control | CarbonModifier.shift),
                replacing: .snapZones,
                in: settings
            ),
            .duplicate(.unsnap)
        )
    }

    func testResettingAShortcutStillRejectsACollision() {
        var settings = AppSettings.default
        settings.unsnapHotkey = AppSettings.default.editorHotkey
        XCTAssertEqual(
            ShortcutCatalog.validate(
                AppSettings.default.editorHotkey,
                replacing: .openEditor,
                in: settings
            ),
            .duplicate(.unsnap)
        )
    }

    func testEditorCanvasChordsAreUniqueAndDocumented() throws {
        let items = ShortcutCatalog.items(from: .default)
        let duplicate = try XCTUnwrap(items.first(where: { $0.id == "editorDuplicate" }))
        let redo = try XCTUnwrap(items.first(where: { $0.id == "editorRedo" }))
        let splitV = try XCTUnwrap(items.first(where: { $0.id == "editorSplitVertical" }))
        let splitH = try XCTUnwrap(items.first(where: { $0.id == "editorSplitHorizontal" }))
        XCTAssertEqual(duplicate.title(language: .english), "Duplicate pane")
        XCTAssertEqual(redo.title(language: .chineseSimplified), "重做上一步")
        guard case .chord(let duplicateChord) = duplicate.binding else {
            return XCTFail("duplicate must be a chord")
        }
        XCTAssertTrue(duplicateChord.matches(keyCode: HardwareKeyCode.d, carbonModifiers: CarbonModifier.command))
        XCTAssertTrue(ShortcutCatalog.isEditorRedoChord(keyCode: HardwareKeyCode.z, carbonModifiers: CarbonModifier.command | CarbonModifier.shift))
        XCTAssertTrue(HardwareKeyCode.isEditorNudge(HardwareKeyCode.left))
        XCTAssertTrue(HardwareKeyCode.isEditorNudge(HardwareKeyCode.right))
        XCTAssertTrue(HardwareKeyCode.isEditorNudge(HardwareKeyCode.up))
        XCTAssertTrue(HardwareKeyCode.isEditorNudge(HardwareKeyCode.down))
        guard case .chord(let vertical) = splitV.binding, case .chord(let horizontal) = splitH.binding else {
            return XCTFail("split commands must be chords")
        }
        XCTAssertTrue(vertical.matches(keyCode: HardwareKeyCode.backslash, carbonModifiers: CarbonModifier.command | CarbonModifier.shift))
        XCTAssertTrue(horizontal.matches(keyCode: HardwareKeyCode.minus, carbonModifiers: CarbonModifier.command))
    }

}
