import AppKit
import CoreGraphics
import ZoneBoxCore

@MainActor
enum ScreenRecordingAccess {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @discardableResult
    static func openSettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                Log.pin.info("Opened Screen Recording settings via \(raw, privacy: .public)")
                return true
            }
        }
        Log.pin.error("Failed to open Screen Recording settings")
        return false
    }
}
