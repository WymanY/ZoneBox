import AppKit
import ZoneBoxCore

@MainActor
final class WorkspaceConsoleStrip: NSView {
    var onApply: ((WorkspaceProfile.ID) -> Void)?
    var onSave: (() -> Void)?
    var onBeginRename: ((WorkspaceProfile.ID) -> Void)?
    var onUpdate: ((WorkspaceProfile.ID) -> Void)?
    var onRename: ((WorkspaceProfile.ID, String) -> Void)?
    var onDelete: ((WorkspaceProfile) -> Void)?

    private let scroll = NSScrollView()
    private let row = NSStackView()
    private var renamingID: WorkspaceProfile.ID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .allowed
        let clip = NSClipView()
        clip.drawsBackground = false
        scroll.contentView = clip
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = row
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Metrics.height),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reload(
        profiles: [WorkspaceProfile],
        activeID: WorkspaceProfile.ID?,
        layouts: [Layout.ID: Layout],
        connectedDisplayIDs: Set<DisplayIdentity.ID>,
        beginRename: WorkspaceProfile.ID? = nil
    ) {
        if let beginRename {
            renamingID = beginRename
        }
        row.arrangedSubviews.forEach {
            row.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if profiles.isEmpty {
            let empty = WorkspaceConsoleEmptyCard()
            empty.onSave = { [weak self] in self?.onSave?() }
            row.addArrangedSubview(empty)
        } else {
            for (index, profile) in profiles.enumerated() {
                let info = WorkspaceApplicationInfo.info(for: profile.sections.flatMap(\.rules).map(\.bundleID))
                let card = WorkspaceConsoleCard(
                    profile: profile,
                    number: index < 9 ? index + 1 : nil,
                    isCurrent: profile.id == activeID,
                    disconnected: profile.sections.contains { !connectedDisplayIDs.contains($0.space.displayID) },
                    layout: profile.sections.first.flatMap { layouts[$0.layoutID] },
                    applicationInfo: info,
                    isRenaming: renamingID == profile.id
                )
                card.onSelect = { [weak self] in self?.onApply?(profile.id) }
                card.onUpdate = { [weak self] in self?.onUpdate?(profile.id) }
                card.onRenameRequested = { [weak self] in
                    self?.onBeginRename?(profile.id)
                }
                card.onRenameCommit = { [weak self] name in
                    self?.renamingID = nil
                    self?.onRename?(profile.id, name)
                }
                card.onRenameCancel = { [weak self] in
                    self?.renamingID = nil
                }
                card.onDelete = { [weak self] in self?.onDelete?(profile) }
                row.addArrangedSubview(card)
            }
        }
        row.layoutSubtreeIfNeeded()
        row.setFrameSize(NSSize(width: max(row.fittingSize.width, bounds.width), height: Metrics.height))
        if let renamingID, let card = row.arrangedSubviews.compactMap({ $0 as? WorkspaceConsoleCard }).first(where: { $0.profileID == renamingID }) {
            card.focusNameField()
        }
    }

    private enum Metrics {
        static let height: CGFloat = 84
    }
}

private final class WorkspaceConsoleEmptyCard: NSView {
    var onSave: (() -> Void)?
    private let title = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 168, height: 84)))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .controlAccentColor
        title.stringValue = L10n.text(.consoleSaveWorkspace)
        title.translatesAutoresizingMaskIntoConstraints = false
        let detail = NSTextField(labelWithString: L10n.text(.workspaceSwitcherEmptyDetail))
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        addSubview(detail)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 168),
            heightAnchor.constraint(equalToConstant: 84),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            title.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            detail.centerXAnchor.constraint(equalTo: centerXAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        onSave?()
    }
}

final class WorkspaceConsoleCard: NSView, NSTextFieldDelegate {
    let profileID: WorkspaceProfile.ID
    var onSelect: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onRenameRequested: (() -> Void)?
    var onRenameCommit: ((String) -> Void)?
    var onRenameCancel: (() -> Void)?
    var onDelete: (() -> Void)?
    private let nameField = NSTextField(string: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let menuButton = NSButton()
    private var hovering = false

    init(
        profile: WorkspaceProfile,
        number: Int?,
        isCurrent: Bool,
        disconnected: Bool,
        layout: Layout?,
        applicationInfo: [String: (name: String, icon: NSImage?)],
        isRenaming: Bool
    ) {
        self.profileID = profile.id
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 84)))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        alphaValue = disconnected ? 0.55 : 1
        setAccessibilityRole(.button)
        setAccessibilityLabel(
            [number.map(String.init), profile.name, isCurrent ? L10n.text(.workspaceSwitcherCurrent) : nil]
                .compactMap { $0 }
                .joined(separator: ", ")
        )

        let preview = WorkspaceLayoutPreviewView(
            layout: layout,
            rules: profile.sections.first?.rules ?? [],
            applicationInfo: applicationInfo,
            canvasSize: NSSize(width: 84, height: 40)
        )
        preview.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.stringValue = profile.name
        nameLabel.font = .systemFont(ofSize: 10, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        nameField.stringValue = profile.name
        nameField.font = .systemFont(ofSize: 10)
        nameField.delegate = self
        nameField.isHidden = !isRenaming
        nameLabel.isHidden = isRenaming
        nameField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(preview)
        addSubview(nameLabel)
        addSubview(nameField)

        if let number {
            let badge = NSTextField(labelWithString: String(number))
            badge.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                badge.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            ])
        }
        if isCurrent {
            let current = NSTextField(labelWithString: L10n.text(.workspaceSwitcherCurrent))
            current.font = .systemFont(ofSize: 8, weight: .semibold)
            current.textColor = .controlAccentColor
            current.translatesAutoresizingMaskIntoConstraints = false
            addSubview(current)
            NSLayoutConstraint.activate([
                current.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                current.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            ])
        }

        menuButton.bezelStyle = .inline
        menuButton.isBordered = false
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        menuButton.imagePosition = .imageOnly
        menuButton.target = self
        menuButton.action = #selector(showMenu)
        menuButton.isHidden = true
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 100),
            heightAnchor.constraint(equalToConstant: 84),
            preview.centerXAnchor.constraint(equalTo: centerXAnchor),
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            menuButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            menuButton.widthAnchor.constraint(equalToConstant: 16),
            menuButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func focusNameField() {
        window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        menuButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        menuButton.isHidden = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !menuButton.isHidden, menuButton.frame.contains(point) {
            showMenu()
            return
        }
        if !nameField.isHidden { return }
        onSelect?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == HardwareKeyCode.escape, !nameField.isHidden {
            onRenameCancel?()
            return
        }
        super.keyDown(with: event)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !nameField.isHidden else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            onRenameCancel?()
        } else {
            onRenameCommit?(name)
        }
    }

    @objc private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text(.workspaceCardUpdate), action: #selector(updateTapped), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text(.workspaceCardRename), action: #selector(renameTapped), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text(.workspaceCardDelete), action: #selector(deleteTapped), keyEquivalent: "")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: menuButton.frame.minX, y: menuButton.frame.minY), in: self)
    }

    @objc private func updateTapped() { onUpdate?() }
    @objc private func renameTapped() { onRenameRequested?() }
    @objc private func deleteTapped() { onDelete?() }
}
