import AppKit

final class EditorPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onCycleZones: ((Bool) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func selectNextKeyView(_ sender: Any?) {
        if let onCycleZones {
            onCycleZones(true)
        } else {
            super.selectNextKeyView(sender)
        }
    }

    override func selectPreviousKeyView(_ sender: Any?) {
        if let onCycleZones {
            onCycleZones(false)
        } else {
            super.selectPreviousKeyView(sender)
        }
    }

    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.visibleFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.18)
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        autorecalculatesKeyViewLoop = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .transient]
        setFrame(screen.visibleFrame, display: true)
    }
}
