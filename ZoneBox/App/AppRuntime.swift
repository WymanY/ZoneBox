import AppKit
import ZoneBoxCore

@MainActor
final class AppRuntime {
    /// PR 8 sets true while the layout editor is front; PR 6 `DragMonitor` no-ops when true.
    var isEditorOpen = false
    var snapEnabled = true

    let uiSession = UISession()

    private var menuBar: MenuBarController?
    private var settings: SettingsWindowController?

    func start() {
        isEditorOpen = false
        menuBar = MenuBarController(runtime: self)
        menuBar?.install()
        Log.app.info("ZoneBox started")
    }

    func hideAllOverlays() {
        // Overlays are created in PR 4.
    }

    func teardown() {
        settings?.close()
        settings = nil
        menuBar?.remove()
        menuBar = nil
        isEditorOpen = false
        Log.app.info("ZoneBox stopped")
    }

    func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(runtime: self)
        }
        uiSession.enterRegular()
        settings?.showWindow()
    }

    func settingsDidClose() {
        settings = nil
        uiSession.leaveRegular()
    }

    func setSnapEnabled(_ enabled: Bool) {
        snapEnabled = enabled
        menuBar?.reloadMenu()
        Log.app.info("Snap Enabled = \(enabled, privacy: .public)")
    }
}
