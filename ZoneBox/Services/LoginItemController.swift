import AppKit
import ServiceManagement
import ZoneBoxCore

@MainActor
enum LoginItemController {
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(enabled: Bool, runtime: AppRuntime) {
        runtime.settings.launchAtLogin = enabled
        runtime.persistSettings()
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item failed: \(error.localizedDescription, privacy: .public)")
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        runtime.settingsWindowDidChangeLoginItem()
    }
}

