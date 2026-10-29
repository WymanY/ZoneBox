import AppKit
import ZoneBoxCore

struct OrganizeFeedback {
    enum Tone {
        case success
        case warning
        case error
    }

    var tone: Tone
    var title: String
    var detail: String
    var restoreTitle: String?
    var ignoreTitle: String?
    var onRestore: (() -> Void)?
    var onIgnore: (() -> Void)?
    var displayDuration: TimeInterval? = nil
    var detailLineLimit: Int = 3
}

@MainActor
final class OrganizeFeedbackController: NSObject {
    private var panel: OrganizeFeedbackPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(_ feedback: OrganizeFeedback, on screen: NSScreen) {
        hideWorkItem?.cancel()
        if let existing = panel {
            existing.orderOut(nil)
            panel = nil
        }

        let panel = OrganizeFeedbackPanel(feedback: feedback)
        panel.onDismiss = { [weak self] in self?.dismiss() }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.maxY - panel.frame.height - 28
            )
        )
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        let announcement = feedback.detail.isEmpty
            ? feedback.title
            : "\(feedback.title). \(feedback.detail)"
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )

        let delay = feedback.displayDuration ?? (feedback.onRestore == nil && feedback.onIgnore == nil ? 3.2 : 7)
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func dismiss() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}

private final class OrganizeFeedbackPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(feedback: OrganizeFeedback) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false

        let chrome = FeedbackChromeView(frame: .zero)

        let iconWell = NSView()
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = Metrics.iconWell / 2
        iconWell.layer?.cornerCurve = .continuous
        iconWell.translatesAutoresizingMaskIntoConstraints = false

        let palette = TonePalette(feedback.tone)
        chrome.applyTone = { iconWell.layer?.backgroundColor = palette.well.cgColor }

        let icon = NSImageView()
        let symbol = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        icon.image = NSImage(systemSymbolName: palette.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbol)
        icon.contentTintColor = palette.icon
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityElement(false)

        iconWell.addSubview(icon)

        let title = NSTextField(wrappingLabelWithString: feedback.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.maximumNumberOfLines = 2
        title.cell?.truncatesLastVisibleLine = true
        title.toolTip = feedback.title
        title.setContentCompressionResistancePriority(.required, for: .vertical)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let detail = NSTextField(wrappingLabelWithString: feedback.detail)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = feedback.detailLineLimit
        detail.cell?.truncatesLastVisibleLine = true
        detail.toolTip = feedback.detail
        detail.isHidden = feedback.detail.isEmpty
        detail.setContentCompressionResistancePriority(.required, for: .vertical)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: feedback.detail.isEmpty ? [title] : [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.translatesAutoresizingMaskIntoConstraints = false

        var actions: [NSView] = []
        if let restoreTitle = feedback.restoreTitle, let onRestore = feedback.onRestore {
            actions.append(actionButton(title: restoreTitle) { [weak self] in
                self?.onDismiss?()
                onRestore()
            })
        }
        if let ignoreTitle = feedback.ignoreTitle, let onIgnore = feedback.onIgnore {
            actions.append(actionButton(title: ignoreTitle) { [weak self] in
                self?.onDismiss?()
                onIgnore()
            })
        }
        let actionRow = NSStackView(views: actions)
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.isHidden = actions.isEmpty

        let body = NSStackView(views: actions.isEmpty ? [text] : [text, actionRow])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = actions.isEmpty ? 0 : 12
        body.translatesAutoresizingMaskIntoConstraints = false

        let closeTitle = L10n.text(.organizeClose)
        let close = FeedbackActionButton(title: "", action: { [weak self] in self?.onDismiss?() })
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: closeTitle)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        close.imagePosition = .imageOnly
        close.imageScaling = .scaleProportionallyDown
        close.contentTintColor = .secondaryLabelColor
        close.toolTip = closeTitle
        close.setAccessibilityLabel(closeTitle)

        chrome.addSubview(iconWell)
        chrome.addSubview(body)
        chrome.addSubview(close)
        contentView = chrome

        let titleWidth = ceil(title.attributedStringValue.size().width)
        let detailWidth = feedback.detail.isEmpty ? 0 : ceil(detail.attributedStringValue.size().width)
        let actionWidth = actionRow.fittingSize.width
        let textWidth = min(Metrics.maxTextWidth, max(Metrics.minTextWidth, titleWidth, detailWidth, actionWidth))
        if actionWidth > textWidth {
            actionRow.orientation = .vertical
            actionRow.alignment = .leading
        }
        title.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        detail.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        for button in actions {
            button.widthAnchor.constraint(lessThanOrEqualToConstant: textWidth).isActive = true
        }
        title.preferredMaxLayoutWidth = textWidth
        detail.preferredMaxLayoutWidth = textWidth

        NSLayoutConstraint.activate([
            iconWell.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: Metrics.inset),
            feedback.detail.isEmpty
                ? iconWell.centerYAnchor.constraint(equalTo: text.centerYAnchor)
                : iconWell.topAnchor.constraint(equalTo: body.topAnchor),
            iconWell.widthAnchor.constraint(equalToConstant: Metrics.iconWell),
            iconWell.heightAnchor.constraint(equalToConstant: Metrics.iconWell),
            icon.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            body.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 12),
            body.topAnchor.constraint(greaterThanOrEqualTo: chrome.topAnchor, constant: Metrics.inset),
            body.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),
            body.bottomAnchor.constraint(lessThanOrEqualTo: chrome.bottomAnchor, constant: -Metrics.inset),
            body.widthAnchor.constraint(equalToConstant: textWidth),
            close.leadingAnchor.constraint(equalTo: body.trailingAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -12),
            close.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 24),
            close.heightAnchor.constraint(equalToConstant: 24),
        ])

        chrome.layoutSubtreeIfNeeded()
        let height = max(Metrics.minHeight, ceil(body.fittingSize.height) + Metrics.inset * 2)
        let width = Metrics.inset + Metrics.iconWell + 12 + textWidth + 8 + 24 + 12
        setContentSize(NSSize(width: width, height: height))
        chrome.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        chrome.autoresizingMask = [.width, .height]
        chrome.layoutSubtreeIfNeeded()
        chrome.refreshAppearance()
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> NSButton {
        let button = FeedbackActionButton(title: title, action: action)
        return button
    }

    private enum Metrics {
        static let inset: CGFloat = 16
        static let iconWell: CGFloat = 32
        static let minHeight: CGFloat = 72
        static let minTextWidth: CGFloat = 168
        static let maxTextWidth: CGFloat = 280
    }
}

private struct TonePalette {
    var symbol: String
    var icon: NSColor
    var well: NSColor

    init(_ tone: OrganizeFeedback.Tone) {
        switch tone {
        case .success:
            symbol = "checkmark"
            icon = .systemGreen
            well = NSColor.systemGreen.withAlphaComponent(0.10)
        case .warning:
            symbol = "exclamationmark.triangle"
            icon = .systemOrange
            well = NSColor.systemOrange.withAlphaComponent(0.10)
        case .error:
            symbol = "xmark"
            icon = .systemRed
            well = NSColor.systemRed.withAlphaComponent(0.10)
        }
    }
}

// A single painted surface avoids the extra bezel applied to HUD materials.
private final class FeedbackChromeView: NSView {
    var applyTone: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance { applyTone?() }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSColor(white: dark ? 0.15 : 0.985, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 15.5, yRadius: 15.5)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        NSColor.labelColor.withAlphaComponent(contrast ? 0.45 : (dark ? 0.14 : 0.08)).setStroke()
        border.lineWidth = 1
        border.stroke()
    }
}

private final class FeedbackActionButton: NSButton {
    private let handler: () -> Void
    private var hovering = false
    private var hoverArea: NSTrackingArea?

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        font = .systemFont(ofSize: 11, weight: .medium)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        lineBreakMode = .byTruncatingTail
        toolTip = title.isEmpty ? nil : title
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        self.action = #selector(invoke)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        if imagePosition == .imageOnly { return NSSize(width: 24, height: 24) }
        let width = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 11)]).width
        return NSSize(width: ceil(width) + 20, height: 26)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let opacity: CGFloat = isHighlighted ? 0.14 : (hovering ? 0.09 : (imagePosition == .imageOnly ? 0 : 0.05))
        NSColor.labelColor.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        if imagePosition == .imageOnly {
            super.draw(dirtyRect)
        } else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let text = NSAttributedString(string: title, attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
            let height = ceil(text.size().height)
            text.draw(in: NSRect(x: 10, y: (bounds.height - height) / 2, width: max(0, bounds.width - 20), height: height))
        }
    }

    @objc
    private func invoke() {
        handler()
    }
}
