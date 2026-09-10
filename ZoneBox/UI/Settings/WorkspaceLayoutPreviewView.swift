import AppKit
import ZoneBoxCore

/// Read-only AppKit schematic for a workspace section. Does not restore windows.
final class WorkspaceLayoutPreviewView: NSView {
    private let previewLayout: Layout?
    private let rules: [AppPlacementRule]
    private let icons: [String: NSImage]
    private let names: [String: String]

    private let canvasSize: NSSize

    init(
        layout: Layout?,
        rules: [AppPlacementRule],
        applicationInfo: [String: (name: String, icon: NSImage?)],
        canvasSize: NSSize = WorkspaceLayoutPreview.suggestedSize
    ) {
        self.previewLayout = layout
        self.rules = rules
        self.icons = applicationInfo.compactMapValues { $0.icon }
        self.names = applicationInfo.mapValues { $0.name }
        self.canvasSize = canvasSize
        super.init(frame: NSRect(origin: .zero, size: canvasSize))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        widthAnchor.constraint(equalToConstant: canvasSize.width).isActive = true
        heightAnchor.constraint(equalToConstant: canvasSize.height).isActive = true
        toolTip = L10n.text(.settingsWorkspaceLayoutPreview)
        setAccessibilityRole(.image)
        setAccessibilityElement(true)
        refreshAccessibility()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize { canvasSize }
    override var acceptsFirstResponder: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        refreshAccessibility()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            drawSchematic()
        }
    }

    private var currentSnapshot: WorkspaceLayoutPreview.Snapshot {
        WorkspaceLayoutPreview.snapshot(layout: previewLayout, rules: rules, canvasSize: bounds.size)
    }

    private func drawSchematic() {
        let canvas = bounds.insetBy(dx: 1, dy: 1)
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        NSColor.controlBackgroundColor.withAlphaComponent(increaseContrast ? 0.96 : 0.78).setFill()
        let background = NSBezierPath(roundedRect: canvas, xRadius: 6, yRadius: 6)
        background.fill()
        NSColor.separatorColor.withAlphaComponent(increaseContrast ? 0.85 : 0.45).setStroke()
        background.lineWidth = increaseContrast ? 1.2 : 0.7
        background.stroke()

        let snapshot = currentSnapshot
        if snapshot.isUnavailable || snapshot.panes.isEmpty {
            let text = (
                snapshot.isUnavailable
                    ? L10n.text(.settingsWorkspaceUnavailableLayout)
                    : L10n.text(.settingsWorkspaceLayoutPreview)
            ) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2),
                withAttributes: attrs
            )
            return
        }

        let inner = canvas.insetBy(dx: 6, dy: 6)
        guard inner.width > 1, inner.height > 1 else { return }
        for pane in snapshot.panes {
            let frame = pixelRect(pane.rect, in: inner).insetBy(dx: 0.6, dy: 0.6)
            guard frame.width > 0.8, frame.height > 0.8 else { continue }
            let path = NSBezierPath(roundedRect: frame, xRadius: min(5, min(frame.width, frame.height) * 0.18), yRadius: min(5, min(frame.width, frame.height) * 0.18))
            fillColor(bound: pane.bundleID != nil, increaseContrast: increaseContrast).setFill()
            path.fill()
            strokeColor(bound: pane.bundleID != nil, increaseContrast: increaseContrast).setStroke()
            path.lineWidth = increaseContrast ? 1.2 : 0.8
            path.stroke()
        }

        for pane in snapshot.panes {
            drawContents(pane, in: inner)
        }
    }

    private func drawContents(_ pane: WorkspaceLayoutPreview.Pane, in canvas: CGRect) {
        let labelFrame = pixelRect(pane.labelRect, in: canvas)
        guard labelFrame.width > 1, labelFrame.height > 1 else { return }
        let number = String(pane.number) as NSString
        let fontSize = max(8, min(12, min(labelFrame.height * 0.72, labelFrame.width * 0.42)))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let numberSize = number.size(withAttributes: attrs)
        if pane.showsIcon, let bundleID = pane.bundleID, let icon = icons[bundleID] {
            let iconSide = min(14, min(labelFrame.height - 2, labelFrame.width * 0.45))
            let spacing: CGFloat = 3
            let totalWidth = iconSide + spacing + numberSize.width
            var originX = labelFrame.midX - totalWidth / 2
            if originX < labelFrame.minX { originX = labelFrame.minX }
            let iconRect = CGRect(
                x: originX,
                y: labelFrame.midY - iconSide / 2,
                width: iconSide,
                height: iconSide
            )
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            number.draw(
                at: CGPoint(
                    x: iconRect.maxX + spacing,
                    y: labelFrame.midY - numberSize.height / 2
                ),
                withAttributes: attrs
            )
            return
        }
        number.draw(
            at: CGPoint(
                x: labelFrame.midX - numberSize.width / 2,
                y: labelFrame.midY - numberSize.height / 2
            ),
            withAttributes: attrs
        )
    }

    private func fillColor(bound: Bool, increaseContrast: Bool) -> NSColor {
        if bound {
            return NSColor.controlAccentColor.withAlphaComponent(increaseContrast ? 0.42 : 0.26)
        }
        return NSColor.quaternaryLabelColor.withAlphaComponent(increaseContrast ? 0.28 : 0.16)
    }

    private func strokeColor(bound: Bool, increaseContrast: Bool) -> NSColor {
        if bound {
            return NSColor.controlAccentColor.withAlphaComponent(increaseContrast ? 0.9 : 0.55)
        }
        return NSColor.separatorColor.withAlphaComponent(increaseContrast ? 0.8 : 0.45)
    }

    private func pixelRect(_ rect: NormalizedRect, in canvas: CGRect) -> CGRect {
        CGRect(
            x: canvas.minX + CGFloat(rect.x) * canvas.width,
            y: canvas.minY + CGFloat(rect.y) * canvas.height,
            width: CGFloat(rect.width) * canvas.width,
            height: CGFloat(rect.height) * canvas.height
        )
    }

    private func refreshAccessibility() {
        let snapshot = currentSnapshot
        setAccessibilityLabel(L10n.text(.settingsWorkspaceLayoutPreview))
        if snapshot.isUnavailable {
            setAccessibilityValue(L10n.text(.settingsWorkspaceUnavailableLayout))
            return
        }
        let summary = snapshot.panes.map { pane in
            let zone = String(format: L10n.text(.settingsWorkspaceZone), pane.number)
            guard let bundleID = pane.bundleID else { return zone }
            return zone + ", " + (names[bundleID] ?? bundleID)
        }.joined(separator: "; ")
        setAccessibilityValue(summary.isEmpty ? L10n.text(.settingsWorkspaceLayoutPreview) : summary)
    }
}
