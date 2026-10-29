import AppKit
import ZoneBoxCore

/// Shared by Settings and the keyboard switcher; the sheet owns only confirmation UI.
@MainActor
final class WorkspaceDeleteConfirmation: NSPanel {
    static func present(for parent: NSWindow, name: String, onDelete: @escaping () -> Void) {
        guard parent.attachedSheet == nil else { return }
        let sheet = WorkspaceDeleteConfirmation(name: name)
        parent.beginSheet(sheet) { [sheet] response in
            sheet.orderOut(nil)
            if response == .OK { onDelete() }
        }
    }

    init(name: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = L10n.text(.settingsWorkspaceDeleteTitle)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        isMovable = false
        backgroundColor = .windowBackgroundColor
        animationBehavior = .alertPanel
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let root = NSView()
        contentView = root

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 20, weight: .medium)
        icon.contentTintColor = .systemRed
        icon.setAccessibilityElement(false)

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.textColor = .labelColor

        let header = NSStackView(views: [icon, heading])
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY

        let nameCard = WorkspaceDeleteNameView()
        let nameLabel = NSTextField(wrappingLabelWithString: name)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.maximumNumberOfLines = 2
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.toolTip = name
        nameLabel.setAccessibilityLabel(name)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameCard.addSubview(nameLabel)

        let detail = NSTextField(wrappingLabelWithString: L10n.text(.settingsWorkspaceDeleteDetail))
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.setContentCompressionResistancePriority(.required, for: .vertical)

        let cancel = NSButton(title: L10n.text(.editorCancel), target: self, action: #selector(cancelDeletion))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\r"
        let delete = NSButton(title: L10n.text(.settingsWorkspaceDelete), target: self, action: #selector(confirmDeletion))
        delete.bezelStyle = .rounded
        delete.hasDestructiveAction = true
        delete.attributedTitle = NSAttributedString(string: delete.title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.systemRed,
        ])
        let actions = NSStackView(views: [cancel, delete])
        actions.orientation = .horizontal
        actions.spacing = 8

        for view in [header, nameCard, detail, actions] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 28),
            nameCard.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            nameCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            nameCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            nameLabel.topAnchor.constraint(equalTo: nameCard.topAnchor, constant: 12),
            nameLabel.bottomAnchor.constraint(equalTo: nameCard.bottomAnchor, constant: -12),
            nameLabel.leadingAnchor.constraint(equalTo: nameCard.leadingAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: nameCard.trailingAnchor, constant: -14),
            detail.topAnchor.constraint(equalTo: nameCard.bottomAnchor, constant: 12),
            detail.leadingAnchor.constraint(equalTo: nameCard.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: nameCard.trailingAnchor),
            actions.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 20),
            actions.trailingAnchor.constraint(equalTo: nameCard.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            delete.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
        root.layoutSubtreeIfNeeded()
        setContentSize(NSSize(width: 420, height: root.fittingSize.height))
        initialFirstResponder = cancel
        defaultButtonCell = cancel.cell as? NSButtonCell
    }

    override func cancelOperation(_ sender: Any?) {
        cancelDeletion()
    }

    @objc private func cancelDeletion() {
        sheetParent?.endSheet(self, returnCode: .cancel)
    }

    @objc private func confirmDeletion() {
        sheetParent?.endSheet(self, returnCode: .OK)
    }
}

private final class WorkspaceDeleteNameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.045).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        path.fill()
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        NSColor.separatorColor.withAlphaComponent(contrast ? 1 : 0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
