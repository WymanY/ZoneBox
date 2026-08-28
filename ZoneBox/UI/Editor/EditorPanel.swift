import AppKit
import ZoneBoxCore

final class EditorPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onCycleZones: ((Bool) -> Void)?
    var onSaveCopy: (() -> Void)?

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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if ShortcutCatalog.editorSaveChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        ) {
            onSaveCopy?()
            return true
        }
        return super.performKeyEquivalent(with: event)
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
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
        worksWhenModal = true
        autorecalculatesKeyViewLoop = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        setFrame(screen.visibleFrame, display: true)
    }
}
