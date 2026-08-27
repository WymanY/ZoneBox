import AppKit

@MainActor
final class MenuBarController: NSObject {
    private unowned let runtime: AppRuntime
    private var statusItem: NSStatusItem?

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "ZoneBox")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ZoneBox"
        }
        item.menu = makeMenu()
        statusItem = item
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

        let snap = NSMenuItem(
            title: "Snap Enabled",
            action: #selector(toggleSnapEnabled(_:)),
            keyEquivalent: ""
        )
        snap.target = self
        snap.state = runtime.snapEnabled ? .on : .off
        menu.addItem(snap)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit ZoneBox",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

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
    private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
