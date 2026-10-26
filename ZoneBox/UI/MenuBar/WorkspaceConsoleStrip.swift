import AppKit
import ZoneBoxCore

private enum WorkspaceConsoleMetrics {
    static let height: CGFloat = 80
    static let emptyHeight: CGFloat = 48
    static let cardWidth: CGFloat = 128
    static let previewSize = NSSize(width: 108, height: 36)
}

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
    private var heightConstraint: NSLayoutConstraint!
    var occupiedHeight: CGFloat { heightConstraint.constant }

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
        scroll.horizontalScroller = ThinOverlayScroller()
        scroll.horizontalScroller?.controlSize = .mini
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
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
        heightConstraint = heightAnchor.constraint(equalToConstant: WorkspaceConsoleMetrics.height)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint,
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reload(
        profiles: [WorkspaceProfile],
        activeID: WorkspaceProfile.ID?,
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
            empty.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
            heightConstraint.constant = WorkspaceConsoleMetrics.emptyHeight
        } else {
            heightConstraint.constant = WorkspaceConsoleMetrics.height
            for (index, profile) in profiles.enumerated() {
                let info = WorkspaceApplicationInfo.info(for: profile.sections.flatMap(\.rules).map(\.bundleID))
                let card = WorkspaceConsoleCard(
                    profile: profile,
                    number: index < 9 ? index + 1 : nil,
                    isCurrent: profile.id == activeID,
                    disconnected: profile.sections.contains { !connectedDisplayIDs.contains($0.space.displayID) },
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
                    guard let self else { return }
                    self.renamingID = nil
                    self.reload(
                        profiles: profiles,
                        activeID: activeID,
                        connectedDisplayIDs: connectedDisplayIDs
                    )
                }
                card.onDelete = { [weak self] in self?.onDelete?(profile) }
                row.addArrangedSubview(card)
            }
        }
        row.layoutSubtreeIfNeeded()
        row.setFrameSize(NSSize(width: max(row.fittingSize.width, bounds.width), height: heightConstraint.constant))
        let cards = row.arrangedSubviews.compactMap { $0 as? WorkspaceConsoleCard }
        if let renamingID, let card = cards.first(where: { $0.profileID == renamingID }) {
            card.focusNameField()
            card.scrollToVisible(card.bounds)
        } else if let card = cards.first(where: { $0.profileID == activeID }) {
            // The strip may have been scrolled away earlier; the card in use
            // (always first) must not sit hidden off the leading edge.
            card.scrollToVisible(card.bounds)
        }
    }
}

private final class WorkspaceConsoleEmptyCard: NSView {
    var onSave: (() -> Void)?
    private let title = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 320, height: WorkspaceConsoleMetrics.emptyHeight)))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .controlAccentColor
        title.stringValue = L10n.text(.consoleSaveWorkspace)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentHuggingPriority(.required, for: .horizontal)
        let detail = NSTextField(labelWithString: L10n.text(.workspaceSwitcherEmptyDetail))
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(title)
        addSubview(detail)
        setAccessibilityRole(.button)
        setAccessibilityLabel([L10n.text(.consoleSaveWorkspace), L10n.text(.workspaceSwitcherEmptyDetail)].joined(separator: ", "))
        toolTip = L10n.text(.consoleSaveWorkspace)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: WorkspaceConsoleMetrics.emptyHeight),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
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
    private var currentTrailing: NSLayoutConstraint?
    private let isCurrent: Bool

    init(
        profile: WorkspaceProfile,
        number: Int?,
        isCurrent: Bool,
        disconnected: Bool,
        applicationInfo: [String: (name: String, icon: NSImage?)],
        isRenaming: Bool
    ) {
        self.profileID = profile.id
        self.isCurrent = isCurrent
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: WorkspaceConsoleMetrics.cardWidth, height: WorkspaceConsoleMetrics.height)))
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
        toolTip = profile.name

        let preview = WorkspaceLayoutPreviewView(
            rules: profile.sections.first?.rules ?? [],
            applicationInfo: applicationInfo,
            canvasSize: WorkspaceConsoleMetrics.previewSize
        )
        preview.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.stringValue = profile.name
        nameLabel.font = .systemFont(ofSize: 12, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.toolTip = profile.name

        nameField.stringValue = profile.name
        nameField.font = .systemFont(ofSize: 12)
        nameField.delegate = self
        nameField.isHidden = !isRenaming
        nameLabel.isHidden = isRenaming
        nameField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(preview)
        addSubview(nameLabel)
        addSubview(nameField)

        if let number {
            let badge = NSTextField(labelWithString: String(number))
            badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                badge.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            ])
        }
        if isCurrent {
            let current = NSTextField(labelWithString: L10n.text(.workspaceSwitcherCurrent))
            current.font = .systemFont(ofSize: 11, weight: .medium)
            current.textColor = .controlAccentColor
            current.translatesAutoresizingMaskIntoConstraints = false
            addSubview(current)
            current.lineBreakMode = .byTruncatingTail
            current.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let trailing = current.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
            currentTrailing = trailing
            NSLayoutConstraint.activate([
                trailing,
                current.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                current.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 18),
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
            widthAnchor.constraint(equalToConstant: WorkspaceConsoleMetrics.cardWidth),
            heightAnchor.constraint(equalToConstant: WorkspaceConsoleMetrics.height),
            preview.centerXAnchor.constraint(equalTo: centerXAnchor),
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            menuButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            menuButton.widthAnchor.constraint(equalToConstant: 22),
            menuButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func focusNameField() {
        window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill = isCurrent
            ? NSColor.controlAccentColor.withAlphaComponent(dark ? 0.12 : 0.06)
            : hovering
                ? NSColor.labelColor.withAlphaComponent(dark ? 0.06 : 0.04)
                : NSColor.labelColor.withAlphaComponent(dark ? 0.04 : 0.025)
        fill.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        path.fill()
        if isCurrent {
            NSColor.controlAccentColor.withAlphaComponent(dark ? 0.50 : 0.35).setStroke()
            path.lineWidth = 1
        } else {
            NSColor.separatorColor.withAlphaComponent(dark ? 0.50 : 0.35).setStroke()
            path.lineWidth = 0.5
        }
        path.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        menuButton.isHidden = false
        currentTrailing?.constant = -26
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        menuButton.isHidden = true
        currentTrailing?.constant = -6
        needsDisplay = true
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
