import AppKit
import ZoneBoxCore

struct OrganizeFeedback {
    enum Tone {
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
        panel?.orderOut(nil)

        let panel = OrganizeFeedbackPanel(feedback: feedback)
        panel.onDismiss = { [weak self] in self?.dismiss() }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.maxY - panel.frame.height - 28
            )
        )
        panel.orderFrontRegardless()
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
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class OrganizeFeedbackPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(feedback: OrganizeFeedback) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 104),
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

        let effect = NSVisualEffectView(frame: .zero)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: feedback.tone == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        icon.contentTintColor = feedback.tone == .error ? .systemRed : .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: feedback.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail

        let detail = NSTextField(wrappingLabelWithString: feedback.detail)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 3
        detail.setContentCompressionResistancePriority(.required, for: .vertical)

        let text = NSStackView(views: [title, detail])
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

        let closeTitle = L10n.text(.organizeClose)
        let close = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: closeTitle) ?? NSImage(),
            target: self,
            action: #selector(closeFeedback)
        )
        close.bezelStyle = .inline
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.translatesAutoresizingMaskIntoConstraints = false
        close.toolTip = closeTitle
        close.setAccessibilityLabel(closeTitle)

        effect.addSubview(icon)
        effect.addSubview(text)
        effect.addSubview(actionRow)
        effect.addSubview(close)
        contentView = effect

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            icon.topAnchor.constraint(equalTo: effect.topAnchor, constant: 15),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            close.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            close.topAnchor.constraint(equalTo: effect.topAnchor, constant: 10),
            close.widthAnchor.constraint(equalToConstant: 20),
            close.heightAnchor.constraint(equalToConstant: 20),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            text.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            actionRow.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            actionRow.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -12),
            actionRow.topAnchor.constraint(equalTo: text.bottomAnchor, constant: actions.isEmpty ? 0 : 8),
            actionRow.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: actions.isEmpty ? -12 : -10),
            actionRow.heightAnchor.constraint(equalToConstant: actions.isEmpty ? 0 : 24),
        ])

        let textWidth: CGFloat = 430 - 72
        title.preferredMaxLayoutWidth = textWidth
        detail.preferredMaxLayoutWidth = textWidth
        let textHeight = ceil(title.intrinsicContentSize.height + 3 + detail.intrinsicContentSize.height)
        let actionsHeight: CGFloat = actions.isEmpty ? 0 : 32
        let height = max(88, 12 + textHeight + (actions.isEmpty ? 12 : 8) + actionsHeight)
        setContentSize(NSSize(width: 430, height: height))
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
