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

    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onSelectAll: (() -> Void)?
    var onSplitVertical: (() -> Void)?
    var onSplitHorizontal: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        if ShortcutCatalog.editorSaveChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            onSaveCopy?()
            return true
        }
        if ShortcutCatalog.isEditorUndoChord(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            onUndo?()
            return true
        }
        if ShortcutCatalog.isEditorRedoChord(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            onRedo?()
            return true
        }
        if ShortcutCatalog.editorDuplicateChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            onDuplicate?()
            return true
        }
        if ShortcutCatalog.editorSelectAllChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            onSelectAll?()
            return true
        }
        if ShortcutCatalog.editorSplitVerticalChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            onSplitVertical?()
            return true
        }
        if ShortcutCatalog.editorSplitHorizontalChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            onSplitHorizontal?()
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
