import AppKit
import ZoneBoxCore

/// Read-only AppKit schematic of the windows a workspace section restores.
/// Does not restore windows.
final class WorkspaceLayoutPreviewView: NSView {
    private let rules: [AppPlacementRule]
    private let icons: [String: NSImage]
    private let names: [String: String]

    private let canvasSize: NSSize

    init(
        rules: [AppPlacementRule],
        applicationInfo: [String: (name: String, icon: NSImage?)],
        canvasSize: NSSize = WorkspaceLayoutPreview.suggestedSize
    ) {
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
        WorkspaceLayoutPreview.snapshot(rules: rules, canvasSize: bounds.size)
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
        if snapshot.panes.isEmpty {
            let text = L10n.text(.settingsWorkspaceLayoutPreview) as NSString
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
        // Panes arrive back-to-front; a window in front covers the one behind,
        // just as it will on the restored desk.
        var frames: [CGRect] = []
        frames.reserveCapacity(snapshot.panes.count)
        for pane in snapshot.panes {
            let frame = pixelRect(pane.rect, in: inner).insetBy(dx: 0.6, dy: 0.6)
            frames.append(frame)
            guard let path = WorkspaceLayoutPreviewDrawing.roundedPath(
                for: frame,
                maxRadius: 5,
                factor: 0.18
            ) else { continue }
            NSColor.controlBackgroundColor.withAlphaComponent(increaseContrast ? 0.96 : 0.9).setFill()
            path.fill()
            fillColor(increaseContrast: increaseContrast).setFill()
            path.fill()
        }
        let lineWidth = increaseContrast ? 1.2 : 0.8
        WorkspaceLayoutPreviewDrawing.strokeOutlines(
            panes: snapshot.panes,
            frames: frames,
            maxRadius: 5,
            factor: 0.18,
            solid: strokeColor(increaseContrast: increaseContrast),
            dashed: strokeColor(increaseContrast: increaseContrast),
            solidWidth: lineWidth,
            dashedWidth: max(1.0, lineWidth)
        )

        for pane in snapshot.panes {
            drawContents(pane, in: inner)
        }
    }

    private func drawContents(_ pane: WorkspaceLayoutPreview.Pane, in canvas: CGRect) {
        guard pane.showsIcon, let icon = icons[pane.bundleID] else { return }
        let labelFrame = pixelRect(pane.labelRect, in: canvas)
        guard labelFrame.width > 1, labelFrame.height > 1 else { return }
        let iconSide = min(16, min(labelFrame.height, labelFrame.width))
        let iconRect = CGRect(
            x: labelFrame.midX - iconSide / 2,
            y: labelFrame.midY - iconSide / 2,
            width: iconSide,
            height: iconSide
        )
        icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func fillColor(increaseContrast: Bool) -> NSColor {
        NSColor.controlAccentColor.withAlphaComponent(increaseContrast ? 0.42 : 0.26)
    }

    private func strokeColor(increaseContrast: Bool) -> NSColor {
        NSColor.controlAccentColor.withAlphaComponent(increaseContrast ? 0.9 : 0.55)
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
        setAccessibilityLabel(L10n.text(.settingsWorkspaceLayoutPreview))
        let summary = AppPlacementRule.readingOrder(rules)
            .map { names[$0.bundleID] ?? $0.bundleID }
            .joined(separator: "; ")
        setAccessibilityValue(summary.isEmpty ? L10n.text(.settingsWorkspaceLayoutPreview) : summary)
    }
}

/// Shared fill-then-outline pass for menu, settings, and switcher schematics.
enum WorkspaceLayoutPreviewDrawing {
    static func roundedPath(for frame: CGRect, maxRadius: CGFloat, factor: CGFloat) -> NSBezierPath? {
        guard frame.width > 0.8, frame.height > 0.8 else { return nil }
        let radius = min(maxRadius, min(frame.width, frame.height) * factor)
        return NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    }

    static func strokeOutlines(
        panes: [WorkspaceLayoutPreview.Pane],
        frames: [CGRect],
        maxRadius: CGFloat,
        factor: CGFloat,
        solid: NSColor,
        dashed: NSColor,
        solidWidth: CGFloat,
        dashedWidth: CGFloat
    ) {
        for (pane, frame) in zip(panes, frames) where !pane.isOccluded {
            guard let path = roundedPath(for: frame, maxRadius: maxRadius, factor: factor) else { continue }
            solid.setStroke()
            path.lineWidth = solidWidth
            path.lineJoinStyle = .round
            path.stroke()
        }
        // Rear windows: fill stays on the real frame, outline is dashed and
        // inset so the full range reads through a front window instead of
        // coinciding with that window's solid edge.
        for (pane, frame) in zip(panes, frames) where pane.isOccluded {
            let inset = dashedInset(for: frame)
            let inner = frame.insetBy(dx: inset, dy: inset)
            guard let path = roundedPath(for: inner, maxRadius: maxRadius, factor: factor) else { continue }
            dashed.setStroke()
            path.lineWidth = dashedWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .butt
            let on = max(2.0, dashedWidth * 2.4)
            let off = max(1.2, dashedWidth * 1.45)
            var pattern: [CGFloat] = [on, off]
            path.setLineDash(&pattern, count: 2, phase: 0)
            path.stroke()
        }
    }

    /// 1.5–2pt inset of the dashed stroke only. Tiny panes clamp so the path
    /// remains drawable; window frames and fills stay put.
    static func dashedInset(for frame: CGRect) -> CGFloat {
        let shortest = min(frame.width, frame.height)
        let requested: CGFloat = shortest >= 28 ? 2.0 : 1.5
        let maxInset = max(0.6, (shortest - 2.4) / 2)
        return min(requested, maxInset)
    }
}
