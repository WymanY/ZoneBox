import AppKit

/// Refcounts Editor + Settings + Onboarding. Restores `.accessory` when the count hits 0
/// so ZoneBox does not keep a Dock icon.
@MainActor
final class UISession {
    private var retainCount = 0

    func enterRegular() {
        retainCount += 1
        if retainCount == 1 {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func leaveRegular() {
        retainCount = max(0, retainCount - 1)
        if retainCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
