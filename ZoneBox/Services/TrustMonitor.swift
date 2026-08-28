import ApplicationServices
import AppKit
import Darwin
import ZoneBoxCore

enum TrustStatus: Equatable {
    case trusted
    case untrusted
    /// Debugger attached: TCC switch can be on for ZoneBox, but this process still fails `AXIsProcessTrusted()`.
    case runningUnderDebugger
}

@MainActor
final class TrustMonitor {
    /// Usable for snapping: either the official TCC flag *or* a live AX probe.
    /// Xcode-launched Debug builds often report `AXIsProcessTrusted() == false`
    /// even when the Accessibility switch is already on.
    func isTrusted() -> Bool {
        Self.hasAccessibilityAccess()
    }

    func status() -> TrustStatus {
        if Self.hasAccessibilityAccess() { return .trusted }
        if Self.isDebuggerAttached() { return .runningUnderDebugger }
        return .untrusted
    }

    /// Menu-bar warning triangle only when Accessibility is actually off.
    /// Under Xcode the TCC switch can already be on while `AXIsProcessTrusted()` is false —
    /// that must not keep showing the exclamation.
    func showsMenuBarWarning() -> Bool {
        status() == .untrusted
    }

    nonisolated static func hasAccessibilityAccess() -> Bool {
        if AXIsProcessTrusted() { return true }
        return probeAX()
    }

    /// Reading the focused application alone is no longer a sufficient probe:
    /// macOS can expose that system-wide attribute while returning
    /// `AXError.apiDisabled` for every foreign app/window attribute. The
    /// onboarding window can also make ZoneBox itself focused, and an app can
    /// always read its own AX tree. Probe the frontmost external layer-0 window
    /// so this check crosses the same permission boundary as snapping.
    nonisolated static func probeAX() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let candidatePIDs = info.compactMap { entry -> pid_t? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  (entry[kCGWindowLayer as String] as? Int ?? 0) == 0
            else { return nil }
            return pid
        }
        var seen = Set<pid_t>()
        for pid in candidatePIDs where seen.insert(pid).inserted {
            let app = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(
                app,
                kAXWindowsAttribute as CFString,
                &windowsRef
            )
            if error == .success { return true }
            if error == .apiDisabled { return false }
        }
        return false
    }

    nonisolated static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }

    static var currentBuildPath: String {
        Bundle.main.bundlePath
    }

    /// Opens the Accessibility privacy pane. Do **not** call `kAXTrustedCheckOptionPrompt`
    /// every time — that system sheet looks like “you still haven’t allowed it” even
    /// when the switch is already on.
    @discardableResult
    func openAccessibilitySettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                Log.trust.info("Opened Accessibility settings via \(raw, privacy: .public)")
                return true
            }
        }
        Log.trust.error("Failed to open Accessibility settings")
        return false
    }

    func relaunchApp() {
        let path = Bundle.main.bundlePath
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.7; /usr/bin/open -n \"\(escaped)\""]
        do {
            try task.run()
        } catch {
            Log.trust.error("Relaunch spawn failed: \(error.localizedDescription, privacy: .public)")
        }
        NSApp.terminate(nil)
    }
}
