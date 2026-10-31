import AppKit
import ZoneBoxCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        applyStacking(.liveSnap)
        setFrame(screen.frame, display: false)
        orderOut(nil)
    }

    /// Live snap uses draggingWindow+1; previews stay at screensaver to cover
    /// the console and welcome window. Skip redundant level assignments
    /// during pointer updates.
    func applyStacking(_ kind: OverlayStackingKind) {
        let next = NSWindow.Level(rawValue: Int(OverlayStackingPolicy.windowLevel(kind)))
        if level != next {
            level = next
        }
    }
}
