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

        let delay: TimeInterval = feedback.onRestore == nil && feedback.onIgnore == nil ? 3.2 : 7
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
        chrome.translatesAutoresizingMaskIntoConstraints = false

        let iconWell = NSView()
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 8
        iconWell.layer?.cornerCurve = .continuous
        iconWell.translatesAutoresizingMaskIntoConstraints = false

        let palette = TonePalette(feedback.tone)
        iconWell.layer?.backgroundColor = palette.well.cgColor

        let icon = NSImageView()
        let symbol = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        icon.image = NSImage(systemSymbolName: palette.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbol)
        icon.contentTintColor = palette.icon
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        iconWell.addSubview(icon)

        let title = NSTextField(labelWithString: feedback.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let detail = NSTextField(wrappingLabelWithString: feedback.detail)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 3
        detail.isHidden = feedback.detail.isEmpty
        detail.setContentCompressionResistancePriority(.required, for: .vertical)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: feedback.detail.isEmpty ? [title] : [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.translatesAutoresizingMaskIntoConstraints = false

        var actions: [NSView] = []
        if let restoreTitle = feedback.restoreTitle, let onRestore = feedback.onRestore {
            actions.append(actionButton(title: restoreTitle) { [weak self] in
                onRestore()
                self?.onDismiss?()
            })
        }
        if let ignoreTitle = feedback.ignoreTitle, let onIgnore = feedback.onIgnore {
            actions.append(actionButton(title: ignoreTitle) { [weak self] in
                onIgnore()
                self?.onDismiss?()
            })
        }
        let actionRow = NSStackView(views: actions)
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 6
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.isHidden = actions.isEmpty

        let body = NSStackView(views: actions.isEmpty ? [text] : [text, actionRow])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = actions.isEmpty ? 0 : 8
        body.translatesAutoresizingMaskIntoConstraints = false

        let closeTitle = L10n.text(.organizeClose)
        let close = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: closeTitle) ?? NSImage(),
            target: self,
            action: #selector(closeFeedback)
        )
        close.bezelStyle = .inline
        close.isBordered = false
        close.imagePosition = .imageOnly
        close.imageScaling = .scaleProportionallyDown
        close.contentTintColor = .tertiaryLabelColor
        close.translatesAutoresizingMaskIntoConstraints = false
        close.toolTip = closeTitle
        close.setAccessibilityLabel(closeTitle)

        chrome.addSubview(iconWell)
        chrome.addSubview(body)
        chrome.addSubview(close)
        contentView = chrome

        let titleWidth = ceil(title.attributedStringValue.size().width)
        let detailWidth = feedback.detail.isEmpty ? 0 : ceil(detail.attributedStringValue.size().width)
        let textWidth = min(Metrics.maxTextWidth, max(Metrics.minTextWidth, titleWidth, detailWidth))
        title.preferredMaxLayoutWidth = textWidth
        detail.preferredMaxLayoutWidth = textWidth

        NSLayoutConstraint.activate([
            iconWell.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: Metrics.inset),
            iconWell.topAnchor.constraint(equalTo: chrome.topAnchor, constant: Metrics.inset),
            iconWell.widthAnchor.constraint(equalToConstant: Metrics.iconWell),
            iconWell.heightAnchor.constraint(equalToConstant: Metrics.iconWell),
            icon.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            body.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 10),
            body.topAnchor.constraint(equalTo: chrome.topAnchor, constant: Metrics.inset),
            body.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -Metrics.inset),
            body.widthAnchor.constraint(equalToConstant: textWidth),
            close.leadingAnchor.constraint(equalTo: body.trailingAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -10),
            close.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 10),
            close.widthAnchor.constraint(equalToConstant: 18),
            close.heightAnchor.constraint(equalToConstant: 18),
            actionRow.heightAnchor.constraint(equalToConstant: actions.isEmpty ? 0 : 24),
        ])

        chrome.layoutSubtreeIfNeeded()
        let height = max(Metrics.minHeight, chrome.fittingSize.height)
        let width = Metrics.inset + Metrics.iconWell + 10 + textWidth + 8 + 18 + 10
        setContentSize(NSSize(width: width, height: height))
        chrome.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        chrome.autoresizingMask = [.width, .height]
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> NSButton {
        let button = FeedbackActionButton(title: title, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    @objc
    private func closeFeedback() {
        onDismiss?()
    }

    private enum Metrics {
        static let inset: CGFloat = 14
        static let iconWell: CGFloat = 28
        static let minHeight: CGFloat = 56
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
            symbol = "checkmark.circle.fill"
            icon = .systemGreen
            well = NSColor.systemGreen.withAlphaComponent(0.14)
        case .warning:
            symbol = "exclamationmark.triangle.fill"
            icon = .systemOrange
            well = NSColor.systemOrange.withAlphaComponent(0.14)
        case .error:
            symbol = "exclamationmark.octagon.fill"
            icon = .systemRed
            well = NSColor.systemRed.withAlphaComponent(0.14)
        }
    }
}

private final class FeedbackChromeView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }
}

private final class FeedbackActionButton: NSButton {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(invoke)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc
    private func invoke() {
        handler()
    }
}
