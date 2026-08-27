import AppKit
import ZoneBoxCore

@MainActor
final class MenuBarController: NSObject {
    private unowned let runtime: AppRuntime
    private var statusItem: NSStatusItem?

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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
        }
        item.menu = makeMenu()
        statusItem = item
        installApplicationMenu()
        updateTrustAppearance()
        Log.app.info("Status item installed (visible=\(item.isVisible, privacy: .public))")
    }

    func updateTrustAppearance() {
        guard let button = statusItem?.button else { return }
        let warning = runtime.trust.showsMenuBarWarning()
        button.image = Self.statusImage(warning: warning)
        button.contentTintColor = warning ? .systemOrange : nil
        switch runtime.trust.status() {
        case .trusted, .runningUnderDebugger:
            button.toolTip = L10n.text(.statusTooltip)
        case .untrusted:
            button.toolTip = L10n.text(.statusTooltipNeedsAccess)
        }
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
    }

    func reloadMenu() {
        statusItem?.menu = makeMenu()
        installApplicationMenu()
    }

    private func installApplicationMenu() {
        let voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        let appMenu = NSMenu()
        let settings = NSMenuItem(
            title: L10n.text(.menuSettings),
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(settings)

        let shortcuts = NSMenuItem(
            title: L10n.text(.menuKeyboardShortcuts),
            action: #selector(openShortcuts(_:)),
            keyEquivalent: voiceOver ? "" : "/"
        )
        if !voiceOver {
            shortcuts.keyEquivalentModifierMask = [.control, .option]
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

        let snap = NSMenuItem(title: L10n.text(.menuSnapEnabled), action: #selector(toggleSnapEnabled(_:)), keyEquivalent: "")
        snap.target = self
        snap.state = runtime.snapEnabled ? .on : .off
        menu.addItem(snap)

        if NSWorkspace.shared.isVoiceOverEnabled {
            let vo = NSMenuItem(title: L10n.text(.menuHotkeysPausedVO), action: nil, keyEquivalent: "")
            vo.isEnabled = false
            menu.addItem(vo)
        }

        menu.addItem(.separator())

        let editor = NSMenuItem(title: L10n.text(.menuOpenEditor), action: #selector(openEditor(_:)), keyEquivalent: "")
        editor.target = self
        menu.addItem(editor)

        let preview = NSMenuItem(title: L10n.text(.menuPreviewZones), action: #selector(previewZones(_:)), keyEquivalent: "")
        preview.target = self
        menu.addItem(preview)

        let layouts = NSMenuItem(title: L10n.text(.menuLayouts), action: nil, keyEquivalent: "")
        layouts.submenu = makeLayoutsMenu()
        menu.addItem(layouts)

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
            menu.addItem(item)
        }
        return menu
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
    private func toggleSnapEnabled(_ sender: NSMenuItem) {
        runtime.setSnapEnabled(!runtime.snapEnabled)
    }

    @objc
    private func openSettings(_ sender: NSMenuItem) {
        runtime.openSettings()
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
    private func previewZones(_ sender: NSMenuItem) {
        runtime.previewZones()
    }

    @objc
    private func newCanvas(_ sender: NSMenuItem) {
        runtime.newCanvasLayout()
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
    private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
