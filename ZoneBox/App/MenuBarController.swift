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
            button.toolTip = "ZoneBox"
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
        updateTrustAppearance()
        Log.app.info("Status item installed (visible=\(item.isVisible, privacy: .public))")
    }

    func updateTrustAppearance() {
        guard let button = statusItem?.button else { return }
        let warning = runtime.trust.showsMenuBarWarning()
        button.image = Self.statusImage(warning: warning)
        button.contentTintColor = warning ? .systemOrange : nil
        switch runtime.trust.status() {
        case .trusted:
            button.toolTip = "ZoneBox"
        case .runningUnderDebugger:
            button.toolTip = "ZoneBox"
        case .untrusted:
            button.toolTip = "ZoneBox needs Accessibility to snap windows"
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
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        if runtime.trust.showsMenuBarWarning() {
            let enable = NSMenuItem(
                title: "Enable Accessibility to Snap Windows…",
                action: #selector(openAccessibility(_:)),
                keyEquivalent: ""
            )
            enable.target = self
            menu.addItem(enable)
            menu.addItem(.separator())
        }

        let snap = NSMenuItem(title: "Snap Enabled", action: #selector(toggleSnapEnabled(_:)), keyEquivalent: "")
        snap.target = self
        snap.state = runtime.snapEnabled ? .on : .off
        menu.addItem(snap)

        if NSWorkspace.shared.isVoiceOverEnabled {
            let vo = NSMenuItem(title: "Hotkeys paused — VoiceOver on", action: nil, keyEquivalent: "")
            vo.isEnabled = false
            menu.addItem(vo)
        }

        menu.addItem(.separator())

        let editor = NSMenuItem(title: "Open Layout Editor", action: #selector(openEditor(_:)), keyEquivalent: "")
        editor.target = self
        menu.addItem(editor)

        let preview = NSMenuItem(title: "Preview Zones", action: #selector(previewZones(_:)), keyEquivalent: "")
        preview.target = self
        menu.addItem(preview)

        let layouts = NSMenuItem(title: "Layouts", action: nil, keyEquivalent: "")
        layouts.submenu = makeLayoutsMenu()
        menu.addItem(layouts)

        let newCanvas = NSMenuItem(title: "New Canvas Layout…", action: #selector(newCanvas(_:)), keyEquivalent: "")
        newCanvas.target = self
        menu.addItem(newCanvas)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ZoneBox", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func makeLayoutsMenu() -> NSMenu {
        let menu = NSMenu()
        let current = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
            .flatMap { runtime.document.layout(for: $0.display.id) }?.id
        for layout in runtime.document.layouts {
            let item = NSMenuItem(title: layout.name, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.id.uuidString
            item.state = layout.id == current ? .on : .off
            menu.addItem(item)
        }
        return menu
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
