import AppKit
import ZoneBoxCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private unowned let runtime: AppRuntime
    private var statusItem: NSStatusItem?
    private var console: MenuBarConsoleController?
    private var fallbackMenu: NSMenu?

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "ZoneBoxStatusItem"
        item.isVisible = true
        if let button = item.button {
            button.toolTip = L10n.text(.statusTooltip)
            button.imagePosition = .imageOnly
            if let image = Self.statusImage(warning: runtime.trust.showsMenuBarWarning()) {
                button.image = image
            } else {
                button.title = "ZB"
                button.imagePosition = .noImage
            }
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }
        console = MenuBarConsoleController(runtime: runtime)
        fallbackMenu = makeMenu()
        if usesFallbackMenu {
            item.menu = fallbackMenu
        }
        statusItem = item
        installApplicationMenu()
        updateTrustAppearance()
        Log.app.info("Status item installed (visible=\(item.isVisible, privacy: .public))")
    }

    func updateTrustAppearance() {
        guard let button = statusItem?.button else { return }
        let warning = runtime.trust.showsMenuBarWarning()
        button.image = Self.statusImage(warning: warning)
        button.alphaValue = 1
        button.contentTintColor = warning ? .systemOrange : nil
        button.toolTip = L10n.text(warning ? .statusTooltipNeedsAccess : .statusTooltip)
    }

    private static func statusImage(warning: Bool) -> NSImage? {
        if warning {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "ZoneBox")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            return image
        }

        let image = (NSImage(named: "MenuBarIcon")?.copy() as? NSImage)
            ?? NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "ZoneBox")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }

    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        console?.close()
        console = nil
        fallbackMenu = nil
    }

    func closeConsole() {
        console?.close()
    }

    var isConsoleVisible: Bool { console?.isShown == true }

    func reloadMenu() {
        fallbackMenu = makeMenu()
        if usesFallbackMenu {
            statusItem?.menu = fallbackMenu
        } else {
            statusItem?.menu = nil
        }
        console?.reload()
        updateTrustAppearance()
        installApplicationMenu()
    }

    private var usesFallbackMenu: Bool {
        NSWorkspace.shared.isVoiceOverEnabled
    }

    private static func menuKeyEquivalent(for chord: KeyChord) -> String? {
        let glyph = KeyChord.glyph(for: chord.keyCode)
        if glyph == "•" { return nil }
        if glyph == "space" { return " " }
        if glyph.count == 1 { return glyph.lowercased() }
        return nil
    }

    private static func menuModifierMask(for chord: KeyChord) -> NSEvent.ModifierFlags? {
        let mods = chord.carbonModifiers & KeyChord.modifierMask
        var flags: NSEvent.ModifierFlags = []
        if mods & CarbonModifier.command != 0 { flags.insert(.command) }
        if mods & CarbonModifier.shift != 0 { flags.insert(.shift) }
        if mods & CarbonModifier.option != 0 { flags.insert(.option) }
        if mods & CarbonModifier.control != 0 { flags.insert(.control) }
        return flags.isEmpty ? nil : flags
    }

    private func applySettingsMenuShortcut(to item: NSMenuItem) {
        let chord = runtime.settings.settingsHotkey
        if ShortcutVoiceOverPolicy.shouldPause(
            chord: chord,
            voiceOverEnabled: NSWorkspace.shared.isVoiceOverEnabled
        ) {
            item.keyEquivalent = ""
            return
        }
        item.keyEquivalent = Self.menuKeyEquivalent(for: chord) ?? ""
        if let mask = Self.menuModifierMask(for: chord) {
            item.keyEquivalentModifierMask = mask
        }
    }

    @objc
    private func statusItemClicked(_ sender: Any?) {
        guard let item = statusItem, let button = item.button else { return }
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            console?.close()
            showFallbackMenu(from: button)
            return
        }
        if usesFallbackMenu {
            // VoiceOver keeps the system menu on the status item; don't also pop a console.
            return
        }
        console?.toggle(from: button)
    }

    private func showFallbackMenu(from button: NSStatusBarButton) {
        let menu = fallbackMenu ?? makeMenu()
        fallbackMenu = menu
        let location = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: location, in: button)
    }

    private func installApplicationMenu() {
        let voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        let appMenu = NSMenu()
        let settings = NSMenuItem(
            title: L10n.text(.menuSettings),
            action: #selector(openSettings(_:)),
            keyEquivalent: ""
        )
        settings.target = self
        appMenu.addItem(settings)

        let shortcuts = NSMenuItem(
            title: L10n.text(.menuKeyboardShortcuts),
            action: #selector(openShortcuts(_:)),
            keyEquivalent: Self.menuKeyEquivalent(for: runtime.settings.shortcutsPanelHotkey) ?? ""
        )
        let paused = ShortcutVoiceOverPolicy.shouldPause(
            chord: runtime.settings.shortcutsPanelHotkey,
            voiceOverEnabled: voiceOver
        )
        if paused {
            shortcuts.keyEquivalent = ""
        } else if let mask = Self.menuModifierMask(for: runtime.settings.shortcutsPanelHotkey) {
            shortcuts.keyEquivalentModifierMask = mask
        }
        shortcuts.target = self
        appMenu.addItem(shortcuts)

        appMenu.addItem(.separator())

        let quit = NSMenuItem(
            title: L10n.text(.menuQuit),
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        appMenu.addItem(quit)

        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let main = NSMenu()
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        if runtime.trust.showsMenuBarWarning() {
            let enable = NSMenuItem(
                title: L10n.text(.menuEnableAccessibility),
                action: #selector(openAccessibility(_:)),
                keyEquivalent: ""
            )
            enable.target = self
            menu.addItem(enable)
            menu.addItem(.separator())
        }

        if NSWorkspace.shared.isVoiceOverEnabled {
            let vo = NSMenuItem(title: L10n.text(.menuHotkeysPausedVO), action: nil, keyEquivalent: "")
            vo.isEnabled = false
            menu.addItem(vo)
        }

        if runtime.pins.hasPins {
            let unpinAll = NSMenuItem(
                title: L10n.unpinAll(runtime.pins.count),
                action: #selector(unpinAllWindows(_:)),
                keyEquivalent: ""
            )
            unpinAll.target = self
            menu.addItem(unpinAll)
        }

        menu.addItem(.separator())

        if WindowOrganize.isPubliclyAvailable {
            let organize = NSMenuItem(title: L10n.text(.menuOrganizeWindows), action: #selector(organizeWindows(_:)), keyEquivalent: "")
            organize.target = self
            organize.isEnabled = !runtime.isOrganizingWindows
            menu.addItem(organize)
        }

        let editor = NSMenuItem(title: L10n.text(.menuOpenEditor), action: #selector(openEditor(_:)), keyEquivalent: "")
        editor.target = self
        menu.addItem(editor)

        let preview = NSMenuItem(title: L10n.text(.menuPreviewZones), action: #selector(previewZones(_:)), keyEquivalent: "")
        preview.target = self
        menu.addItem(preview)

        let layouts = NSMenuItem(title: L10n.text(.menuLayouts), action: nil, keyEquivalent: "")
        layouts.submenu = makeLayoutsMenu()
        menu.addItem(layouts)

        let workspaces = NSMenuItem(title: L10n.text(.menuWorkspaces), action: nil, keyEquivalent: "")
        workspaces.submenu = makeWorkspacesMenu()
        menu.addItem(workspaces)

        let newGrid = NSMenuItem(title: L10n.text(.menuNewGrid), action: #selector(newGrid(_:)), keyEquivalent: "")
        newGrid.target = self
        menu.addItem(newGrid)

        let newCanvas = NSMenuItem(title: L10n.text(.menuNewCanvas), action: #selector(newCanvas(_:)), keyEquivalent: "")
        newCanvas.target = self
        menu.addItem(newCanvas)

        menu.addItem(.separator())

        let language = NSMenuItem(title: L10n.text(.settingsLanguage), action: nil, keyEquivalent: "")
        language.submenu = makeLanguageMenu()
        menu.addItem(language)

        let settings = NSMenuItem(title: L10n.text(.menuSettings), action: #selector(openSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let shortcuts = NSMenuItem(
            title: L10n.text(.menuKeyboardShortcuts),
            action: #selector(openShortcuts(_:)),
            keyEquivalent: ""
        )
        shortcuts.target = self
        menu.addItem(shortcuts)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.text(.menuQuit), action: #selector(quit(_:)), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func makeLayoutsMenu() -> NSMenu {
        let menu = NSMenu()
        let current = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
            .flatMap { runtime.document.layout(for: $0.display.id) }?.id
        for layout in runtime.document.layouts {
            let item = NSMenuItem(title: L10n.layoutDisplayName(layout.name), action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.id.uuidString
            item.state = layout.id == current ? .on : .off
            if !LayoutTemplates.thumbnailGeometry(for: layout).isEmpty {
                item.image = LayoutThumbnailRenderer.menuImage(
                    for: layout,
                    gutterPoints: CGFloat(runtime.settings.gutterPoints)
                )
            }
            menu.addItem(item)
        }
        if runtime.document.layouts.count > 1 {
            let currentLayoutExists = current != nil
            menu.addItem(.separator())
            let delete = NSMenuItem(
                title: L10n.text(.menuDeleteLayout),
                action: #selector(deleteLayout(_:)),
                keyEquivalent: ""
            )
            delete.target = self
            delete.isEnabled = currentLayoutExists
            menu.addItem(delete)
        }
        return menu
    }

    private func makeWorkspacesMenu() -> NSMenu {
        let menu = NSMenu()
        for profile in runtime.document.profiles.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let title = profile.name.count > 30 ? String(profile.name.prefix(29)) + "…" : profile.name
            let item = NSMenuItem(title: title, action: #selector(applyWorkspace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id.uuidString
            item.state = profile.id == runtime.document.activeProfileID ? .on : .off
            item.isEnabled = !runtime.isOrganizingWindows
            menu.addItem(item)
        }
        if !runtime.document.profiles.isEmpty { menu.addItem(.separator()) }

        let capture = NSMenuItem(
            title: L10n.text(.menuCaptureWorkspace),
            action: #selector(captureWorkspace(_:)),
            keyEquivalent: ""
        )
        capture.target = self
        capture.isEnabled = !runtime.isOrganizingWindows
        menu.addItem(capture)

        if let activeID = runtime.document.activeProfileID,
           let active = runtime.document.profiles.first(where: { $0.id == activeID })
        {
            let update = NSMenuItem(
                title: L10n.text(.menuUpdateActiveWorkspace),
                action: #selector(updateActiveWorkspace(_:)),
                keyEquivalent: ""
            )
            update.target = self
            update.representedObject = active.id.uuidString
            update.isEnabled = !runtime.isOrganizingWindows
            menu.addItem(update)

        }

        menu.addItem(.separator())
        let manage = NSMenuItem(
            title: L10n.text(.menuManageWorkspaces),
            action: #selector(openWorkspaceSettings(_:)),
            keyEquivalent: ""
        )
        manage.target = self
        menu.addItem(manage)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        applySettingsShortcut(in: menu, enabled: true)
    }

    func menuDidClose(_ menu: NSMenu) {
        applySettingsShortcut(in: menu, enabled: false)
    }

    private func applySettingsShortcut(in menu: NSMenu, enabled: Bool) {
        for item in menu.items where item.action == #selector(openSettings(_:)) {
            if enabled {
                applySettingsMenuShortcut(to: item)
            } else {
                item.keyEquivalent = ""
            }
        }
    }

    private func makeLanguageMenu() -> NSMenu {
        let menu = NSMenu()
        let current = runtime.settings.uiLanguage
        let items: [(AppLanguagePreference, L10nKey)] = [
            (.system, .settingsLanguageSystem),
            (.english, .settingsLanguageEnglish),
            (.chineseSimplified, .settingsLanguageChinese),
        ]
        for (preference, key) in items {
            let item = NSMenuItem(title: L10n.text(key), action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preference.rawValue
            item.state = preference == current ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc
    private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preference = AppLanguagePreference(rawValue: raw)
        else { return }
        runtime.setUILanguage(preference)
    }

    @objc
    private func openSettings(_ sender: NSMenuItem) {
        runtime.openSettings()
    }

    @objc
    private func openWorkspaceSettings(_ sender: NSMenuItem) {
        runtime.openWorkspaceSettings()
    }

    @objc
    private func openShortcuts(_ sender: NSMenuItem) {
        runtime.openShortcutPanel()
    }

    @objc
    private func openEditor(_ sender: NSMenuItem) {
        runtime.openEditor()
    }

    @objc
    private func organizeWindows(_ sender: NSMenuItem) {
        runtime.organizeWindowsFromPointer()
    }

    @objc
    private func unpinAllWindows(_ sender: NSMenuItem) {
        runtime.pins.unpinAll()
    }

    @objc
    private func previewZones(_ sender: NSMenuItem) {
        runtime.previewZones()
    }

    @objc
    private func newCanvas(_ sender: NSMenuItem) {
        runtime.newCanvasLayout()
    }

    @objc
    private func newGrid(_ sender: NSMenuItem) {
        runtime.newGridLayout()
    }

    @objc
    private func openAccessibility(_ sender: NSMenuItem) {
        runtime.openAccessibility()
    }

    @objc
    private func selectLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw),
              let layout = runtime.document.layouts.first(where: { $0.id == id })
        else { return }
        runtime.selectLayout(layout)
    }

    @objc
    private func applyWorkspace(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        runtime.workspace.apply(profileID: id)
    }

    @objc
    private func captureWorkspace(_ sender: NSMenuItem) {
        guard let name = promptWorkspaceName(initial: runtime.workspace.suggestedCaptureName()) else { return }
        runtime.workspace.capture(name: name)
    }

    @objc
    private func updateActiveWorkspace(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw),
              let profile = runtime.document.profiles.first(where: { $0.id == id })
        else { return }
        runtime.workspace.capture(name: profile.name, replacing: profile.id)
    }

    private func promptWorkspaceName(initial: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = L10n.text(.workspaceNameTitle)
        alert.informativeText = L10n.text(.workspaceNameMessage)
        let field = NSTextField(string: initial)
        field.placeholderString = L10n.text(.workspaceNamePlaceholder)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text(.workspaceSave))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        alert.window.initialFirstResponder = field
        if !initial.isEmpty {
            field.selectText(nil)
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    @objc
    private func deleteLayout(_ sender: NSMenuItem) {
        let current = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
            .flatMap { runtime.document.layout(for: $0.display.id) }
        guard let current else { return }
        confirmAndDelete(current)
    }

    private func confirmAndDelete(_ layout: Layout) {
        let name = L10n.layoutDisplayName(layout.name)
        let alert = NSAlert()
        alert.messageText = String(format: L10n.text(.menuDeleteLayoutTitle), name)
        let affected = runtime.document.profiles.filter { profile in
            profile.sections.contains(where: { $0.layoutID == layout.id })
        }.count
        alert.informativeText = affected == 0
            ? L10n.text(.menuDeleteLayoutMessage)
            : L10n.text(.menuDeleteLayoutMessage) + " "
                + String(format: L10n.text(.workspaceLayoutDeleteImpact), affected)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text(.menuDeleteLayoutConfirm))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        alert.buttons.first?.hasDestructiveAction = true
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        if !runtime.deleteLayout(layout) {
            NSSound.beep()
        }
    }

    @objc
    private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
