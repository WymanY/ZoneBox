import AppKit

/// Explicit hover help also works in nonactivating menu-bar panels.
@MainActor
final class HoverHelpButton: NSButton {
    var helpText = "" {
        didSet {
            setAccessibilityLabel(helpText)
            setAccessibilityHelp(helpText)
            if helpText != oldValue { hideHint() }
        }
    }
    private var hoverArea: NSTrackingArea?
    private var pendingHint: DispatchWorkItem?
    private var hintPanel: NSPanel?
    private var closeObserver: NSObjectProtocol?
    private var pointerInside = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryChange)
        isBordered = false
        title = ""
        image = nil
        imagePosition = .noImage
        focusRingType = .none
        if let buttonCell = cell as? NSButtonCell {
            buttonCell.highlightsBy = []
            buttonCell.showsStateBy = []
        }
        target = self
        action = #selector(toggleHint)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        needsDisplay = true
        pendingHint?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showHint() }
        pendingHint = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        needsDisplay = true
        hideHint()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        hideHint()
        super.viewWillMove(toWindow: newWindow)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { hideHint() }
        return result
    }

    override func cancelOperation(_ sender: Any?) { hideHint() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let emphasized = pointerInside || isHighlighted || hintPanel != nil
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let badgeSide: CGFloat = 14
        let badge = NSRect(
            x: (bounds.midX - badgeSide / 2).rounded(),
            y: (bounds.midY - badgeSide / 2).rounded(),
            width: badgeSide,
            height: badgeSide
        )
        let fill: NSColor = emphasized
            ? NSColor.controlAccentColor.withAlphaComponent(dark ? 0.28 : 0.16)
            : NSColor.labelColor.withAlphaComponent(dark ? 0.12 : 0.07)
        fill.setFill()
        NSBezierPath(ovalIn: badge).fill()

        let accent = dark
            ? NSColor.controlAccentColor.blended(withFraction: 0.45, of: .white) ?? .controlAccentColor
            : .controlAccentColor
        let color: NSColor = emphasized ? accent : .secondaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let glyph = NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = glyph.size
        let rect = NSRect(
            x: badge.midX - size.width / 2,
            y: badge.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        glyph.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    @objc private func toggleHint() {
        if hintPanel == nil { showHint() } else { hideHint() }
    }

    private func showHint() {
        pendingHint?.cancel()
        pendingHint = nil
        guard hintPanel == nil, let parent = window, parent.isVisible, !helpText.isEmpty else { return }
        let label = NSTextField(wrappingLabelWithString: helpText)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = 244
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = HelpSurfaceView()
        content.addSubview(label)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 268),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let panel = HelpPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.appearance = effectiveAppearance
        panel.contentView = content
        let anchor = parent.convertToScreen(convert(bounds, to: nil))
        let visible = parent.screen?.visibleFrame ?? parent.frame
        let x = min(max(anchor.minX, visible.minX + 8), visible.maxX - size.width - 8)
        var y = anchor.maxY + 6
        if y + size.height > visible.maxY - 8 { y = anchor.minY - size.height - 6 }
        panel.setFrameOrigin(NSPoint(x: x, y: max(visible.minY + 8, y)))
        hintPanel = panel
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideHint() }
        }
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
        needsDisplay = true
    }

    private func hideHint() {
        pendingHint?.cancel()
        pendingHint = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        guard let panel = hintPanel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.close()
        hintPanel = nil
        needsDisplay = true
    }
}

private final class HelpPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Same opaque tint as the menu panel, so the hint does not sit on a system window color.
private final class HelpSurfaceView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill = dark
            ? NSColor(srgbRed: 0.17, green: 0.172, blue: 0.183, alpha: 1)
            : NSColor(srgbRed: 0.955, green: 0.958, blue: 0.966, alpha: 1)
        let border = dark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.08)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        fill.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
