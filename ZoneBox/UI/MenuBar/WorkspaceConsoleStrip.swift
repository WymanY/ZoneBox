import AppKit
import ZoneBoxCore

private enum WorkspaceConsoleMetrics {
    static let rowHeight: CGFloat = 50
    static let emptyHeight: CGFloat = 46
    static let maxVisibleRows: CGFloat = 4
    static let maxVisibleHeight: CGFloat = rowHeight * maxVisibleRows
    static let previewSize = NSSize(width: 64, height: 40)
    static let cornerRadius: CGFloat = 10
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
    private let column = WorkspaceColumnView()
    private let fade = ConsoleScrollFade(color: { ConsoleChrome.opaqueSurface(dark: $0) })
    private let outline = WorkspaceOutlineView()
    private var heightConstraint: NSLayoutConstraint!
    var occupiedHeight: CGFloat { heightConstraint.constant }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = WorkspaceConsoleMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScroller = ThinOverlayScroller()
        scroll.verticalScroller?.controlSize = .mini
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.verticalScrollElasticity = .allowed
        scroll.horizontalScrollElasticity = .none
        let clip = ScrollAwareClipView()
        clip.drawsBackground = false
        clip.onBoundsChange = { [weak self] in self?.scrollPositionChanged() }
        scroll.contentView = clip
        scroll.documentView = column
        addSubview(scroll)
        addSubview(fade)
        addSubview(outline)

        heightConstraint = heightAnchor.constraint(equalToConstant: WorkspaceConsoleMetrics.rowHeight)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            fade.leadingAnchor.constraint(equalTo: leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: trailingAnchor),
            fade.bottomAnchor.constraint(equalTo: bottomAnchor),
            fade.heightAnchor.constraint(equalToConstant: 16),
            outline.topAnchor.constraint(equalTo: topAnchor),
            outline.leadingAnchor.constraint(equalTo: leadingAnchor),
            outline.trailingAnchor.constraint(equalTo: trailingAnchor),
            outline.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint,
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard bounds.width > 1 else { return }
        column.reflow(width: bounds.width)
        updateFade()
    }

    override func draw(_ dirtyRect: NSRect) {
        ConsoleChrome.surface(dark: ConsoleChrome.isDark(effectiveAppearance)).setFill()
        bounds.fill()
    }

    func reload(
        profiles: [WorkspaceProfile],
        activeID: WorkspaceProfile.ID?,
        connectedDisplayIDs: Set<DisplayIdentity.ID>,
        beginRename: WorkspaceProfile.ID? = nil
    ) {
        let width = bounds.width > 1 ? bounds.width : ConsoleChrome.contentWidth
        if profiles.isEmpty {
            let empty = WorkspaceConsoleEmptyRow()
            empty.onSave = { [weak self] in self?.onSave?() }
            column.setRows([empty], width: width)
            heightConstraint.constant = WorkspaceConsoleMetrics.emptyHeight
            updateFade()
            return
        }

        var rows: [NSView] = []
        var renamingRow: WorkspaceConsoleRow?
        var activeRow: WorkspaceConsoleRow?
        for (index, profile) in profiles.enumerated() {
            let bundleIDs = Self.orderedBundleIDs(in: profile)
            let info = WorkspaceApplicationInfo.info(for: bundleIDs)
            let row = WorkspaceConsoleRow(
                profile: profile,
                bundleIDs: bundleIDs,
                isCurrent: profile.id == activeID,
                disconnected: profile.sections.contains { !connectedDisplayIDs.contains($0.space.displayID) },
                applicationInfo: info,
                isRenaming: beginRename == profile.id,
                showsSeparator: index < profiles.count - 1
            )
            row.onSelect = { [weak self] in self?.onApply?(profile.id) }
            row.onUpdate = { [weak self] in self?.onUpdate?(profile.id) }
            row.onRenameRequested = { [weak self] in self?.onBeginRename?(profile.id) }
            row.onRenameCommit = { [weak self] name in self?.onRename?(profile.id, name) }
            row.onRenameCancel = { [weak self] in
                self?.reload(profiles: profiles, activeID: activeID, connectedDisplayIDs: connectedDisplayIDs)
            }
            row.onDelete = { [weak self] in self?.onDelete?(profile) }
            if beginRename == profile.id { renamingRow = row }
            if profile.id == activeID { activeRow = row }
            rows.append(row)
        }
        column.setRows(rows, width: width)
        heightConstraint.constant = min(WorkspaceConsoleMetrics.maxVisibleHeight, max(column.frame.height, WorkspaceConsoleMetrics.rowHeight))
        updateFade()
        guard let focus = renamingRow ?? activeRow else { return }
        let shouldRename = renamingRow != nil
        Task { @MainActor [weak focus, weak self] in
            guard let focus else { return }
            if shouldRename { focus.focusNameField() }
            focus.scrollToVisible(focus.bounds)
            self?.updateFade()
        }
    }

    private func scrollPositionChanged() {
        updateFade()
        for case let row as ConsoleInteractiveView in column.subviews {
            row.reconcileHoverState()
        }
    }

    private func updateFade() {
        fade.isHidden = !ConsoleScrollFade.shouldShow(for: scroll)
    }

    private static func orderedBundleIDs(in profile: WorkspaceProfile) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        for rule in profile.sections.flatMap(\.rules) {
            if seen.insert(rule.bundleID).inserted {
                ids.append(rule.bundleID)
            }
        }
        return ids
    }
}

private final class WorkspaceOutlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let radius = WorkspaceConsoleMetrics.cornerRadius
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        ConsoleChrome.surfaceBorder(dark: ConsoleChrome.isDark(effectiveAppearance)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class WorkspaceColumnView: NSView {
    override var isFlipped: Bool { true }
    private var rows: [NSView] = []

    func setRows(_ rows: [NSView], width: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        self.rows = rows
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = true
            addSubview(row)
        }
        reflow(width: width)
    }

    func reflow(width: CGFloat) {
        let resolved = max(width, 1)
        var y: CGFloat = 0
        for row in rows {
            let height = (row as? WorkspaceRowSizing)?.preferredHeight ?? WorkspaceConsoleMetrics.rowHeight
            row.frame = NSRect(x: 0, y: y, width: resolved, height: height)
            y += height
        }
        if abs(frame.width - resolved) > 0.5 || abs(frame.height - y) > 0.5 {
            setFrameSize(NSSize(width: resolved, height: y))
        }
    }
}

private protocol WorkspaceRowSizing: AnyObject {
    var preferredHeight: CGFloat { get }
}

private final class WorkspaceConsoleEmptyRow: ConsoleInteractiveView, WorkspaceRowSizing {
    var onSave: (() -> Void)?
    var preferredHeight: CGFloat { WorkspaceConsoleMetrics.emptyHeight }
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: L10n.text(.consoleSaveWorkspace))

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 320, height: WorkspaceConsoleMetrics.emptyHeight)))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityElement(false)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        let detail = NSTextField(labelWithString: L10n.text(.workspaceSwitcherEmptyDetail))
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(icon)
        addSubview(title)
        addSubview(detail)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel([L10n.text(.consoleSaveWorkspace), L10n.text(.workspaceSwitcherEmptyDetail)].joined(separator: ", "))
        toolTip = L10n.text(.workspaceSwitcherEmptyDetail)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
        applyChrome()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyChrome()
    }

    private func applyChrome() {
        let blue = ConsoleChrome.brandBlue(dark: ConsoleChrome.isDark(effectiveAppearance))
        title.textColor = blue
        icon.image = ConsoleChrome.symbol("plus.circle.fill", size: 15, weight: .semibold, color: blue)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        if isPressed {
            ConsoleChrome.pressedWash(dark: dark).setFill()
            bounds.fill()
        } else if isHovering {
            ConsoleChrome.hoverWash(dark: dark).setFill()
            bounds.fill()
        }
    }

    override func performPrimaryAction() {
        onSave?()
    }
}

private final class WorkspaceConsoleRow: ConsoleInteractiveView, NSTextFieldDelegate, WorkspaceRowSizing {
    let profileID: WorkspaceProfile.ID
    var preferredHeight: CGFloat { WorkspaceConsoleMetrics.rowHeight }
    var onSelect: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onRenameRequested: (() -> Void)?
    var onRenameCommit: ((String) -> Void)?
    var onRenameCancel: (() -> Void)?
    var onDelete: (() -> Void)?

    private let nameField = NSTextField(string: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let preview: WorkspaceMiniPreview
    private let moreButton: ConsoleButton
    private let currentBadge = NSTextField(labelWithString: L10n.text(.workspaceSwitcherCurrent))
    private let currentIcon = NSImageView()
    private let warningIcon = NSImageView()
    private let content = NSView()
    private let isCurrent: Bool
    private let disconnected: Bool
    private let showsSeparator: Bool
    private var isRenaming: Bool

    init(
        profile: WorkspaceProfile,
        bundleIDs: [String],
        isCurrent: Bool,
        disconnected: Bool,
        applicationInfo: [String: (name: String, icon: NSImage?)],
        isRenaming: Bool,
        showsSeparator: Bool
    ) {
        self.profileID = profile.id
        self.isCurrent = isCurrent
        self.disconnected = disconnected
        self.showsSeparator = showsSeparator
        self.isRenaming = isRenaming
        let moreTitle = L10n.text(.consoleMore)
        moreButton = ConsoleButton(role: .plain, symbol: "ellipsis")
        moreButton.controlHeight = 24
        moreButton.toolTip = moreTitle
        moreButton.setAccessibilityLabel(moreTitle)
        preview = WorkspaceMiniPreview(
            rules: profile.sections.first?.rules ?? [],
            icons: applicationInfo.compactMapValues { $0.icon },
            highlighted: isCurrent
        )
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 360, height: WorkspaceConsoleMetrics.rowHeight)))
        moreButton.target = self
        moreButton.action = #selector(showMenu)

        let names = bundleIDs.compactMap { applicationInfo[$0]?.name }
        let summary = names.joined(separator: ", ")
        let accessibility = [
            profile.name,
            summary.isEmpty ? nil : summary,
            isCurrent ? L10n.text(.workspaceSwitcherCurrent) : nil,
            disconnected ? L10n.text(.workspaceSwitcherDisconnected) : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibility)
        toolTip = [profile.name, summary.isEmpty ? nil : summary, disconnected ? L10n.text(.workspaceSwitcherDisconnected) : nil]
            .compactMap { $0 }
            .joined(separator: "\n")

        content.translatesAutoresizingMaskIntoConstraints = false
        content.alphaValue = disconnected ? 0.5 : 1
        addSubview(content)

        // Auto-generated names already list the apps; only repeat them for renamed workspaces.
        let nameListsApps = !names.isEmpty && names.allSatisfy { profile.name.localizedCaseInsensitiveContains($0) }
        summaryLabel.stringValue = names.joined(separator: " · ")
        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1
        summaryLabel.cell?.truncatesLastVisibleLine = true
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        summaryLabel.setAccessibilityElement(false)
        summaryLabel.isHidden = names.isEmpty || nameListsApps || isRenaming

        nameLabel.stringValue = profile.name
        nameLabel.font = .systemFont(ofSize: 13, weight: isCurrent ? .semibold : .regular)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setAccessibilityElement(false)
        nameLabel.isHidden = isRenaming

        nameField.stringValue = profile.name
        nameField.font = .systemFont(ofSize: 13)
        nameField.bezelStyle = .roundedBezel
        nameField.focusRingType = .exterior
        nameField.delegate = self
        nameField.isHidden = !isRenaming
        nameField.translatesAutoresizingMaskIntoConstraints = false

        currentBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        currentBadge.translatesAutoresizingMaskIntoConstraints = false
        currentBadge.setContentHuggingPriority(.required, for: .horizontal)
        currentBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        currentBadge.setAccessibilityElement(false)
        currentBadge.isHidden = !isCurrent
        currentIcon.translatesAutoresizingMaskIntoConstraints = false
        currentIcon.setAccessibilityElement(false)
        currentIcon.isHidden = !isCurrent

        warningIcon.translatesAutoresizingMaskIntoConstraints = false
        warningIcon.toolTip = L10n.text(.workspaceSwitcherDisconnected)
        warningIcon.setAccessibilityElement(false)
        warningIcon.isHidden = !disconnected

        let textColumn = NSStackView(views: [nameLabel, summaryLabel])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 1
        textColumn.detachesHiddenViews = true
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        textColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textColumn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        content.addSubview(preview)
        content.addSubview(textColumn)
        content.addSubview(currentIcon)
        content.addSubview(currentBadge)
        addSubview(nameField)
        addSubview(warningIcon)
        addSubview(moreButton)

        let statusLeading: NSLayoutXAxisAnchor = isCurrent ? currentIcon.leadingAnchor : content.trailingAnchor
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.trailingAnchor.constraint(equalTo: (disconnected ? warningIcon.leadingAnchor : moreButton.leadingAnchor), constant: -4),

            preview.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            preview.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            textColumn.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 10),
            textColumn.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            textColumn.trailingAnchor.constraint(lessThanOrEqualTo: statusLeading, constant: -8),

            currentBadge.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            currentBadge.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            currentIcon.trailingAnchor.constraint(equalTo: currentBadge.leadingAnchor, constant: -3),
            currentIcon.centerYAnchor.constraint(equalTo: content.centerYAnchor),

            nameField.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 7),
            nameField.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -6),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),

            warningIcon.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -4),
            warningIcon.centerYAnchor.constraint(equalTo: centerYAnchor),

            moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            moreButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyChrome()
        interactionStateDidChange()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func focusNameField() {
        window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyChrome()
    }

    private func applyChrome() {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let blue = ConsoleChrome.brandBlue(dark: dark)
        currentBadge.textColor = blue
        currentIcon.image = ConsoleChrome.symbol("checkmark.circle.fill", size: 12, weight: .semibold, color: blue)
        warningIcon.image = ConsoleChrome.symbol(
            "exclamationmark.triangle.fill",
            size: 12,
            weight: .semibold,
            color: ConsoleChrome.warning(dark: dark)
        )
    }

    override func interactionStateDidChange() {
        super.interactionStateDidChange()
        moreButton.isHidden = !(isHovering || isRenaming)
        preview.highlighted = isCurrent || isHovering || isPressed
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        if isPressed {
            ConsoleChrome.pressedWash(dark: dark).setFill()
            bounds.fill()
        } else if isHovering {
            ConsoleChrome.hoverWash(dark: dark).setFill()
            bounds.fill()
        } else if isCurrent {
            ConsoleChrome.brandBlue(dark: dark).withAlphaComponent(dark ? 0.08 : 0.04).setFill()
            bounds.fill()
        }
        if isCurrent {
            ConsoleChrome.brandBlue(dark: dark).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 0, y: 9, width: 3, height: bounds.height - 18),
                xRadius: 1.5,
                yRadius: 1.5
            ).fill()
        }
        if showsSeparator {
            NSColor.separatorColor.withAlphaComponent(dark ? 0.6 : 0.5).setFill()
            let inset = 10 + WorkspaceConsoleMetrics.previewSize.width + 10
            NSRect(x: inset, y: 0, width: bounds.width - inset, height: 1 / max(1, window?.backingScaleFactor ?? 2)).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isRenaming { return }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isRenaming { return }
        super.mouseUp(with: event)
    }

    override func performPrimaryAction() {
        guard !isRenaming else { return }
        onSelect?()
    }

    override func showContextMenu(with event: NSEvent) {
        guard !isRenaming else { return }
        let menu = makeMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isRenaming else { return }
        isRenaming = false
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            onRenameCancel?()
        } else {
            onRenameCommit?(name)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            isRenaming = false
            onRenameCancel?()
            return true
        }
        return false
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text(.workspaceCardUpdate), action: #selector(updateTapped), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text(.workspaceCardRename), action: #selector(renameTapped), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text(.workspaceCardDelete), action: #selector(deleteTapped), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func showMenu() {
        makeMenu().popUp(positioning: nil, at: NSPoint(x: moreButton.frame.minX, y: moreButton.frame.minY), in: self)
    }

    @objc private func updateTapped() { onUpdate?() }
    @objc private func renameTapped() { onRenameRequested?() }
    @objc private func deleteTapped() { onDelete?() }
}

/// Small restore schematic for a workspace row: each window where restore puts it, with the
/// app icon when the window is large enough to carry one.
private final class WorkspaceMiniPreview: NSView {
    private static let placementCanvas = CGSize(width: 160, height: 100)
    private let snapshot: WorkspaceLayoutPreview.Snapshot
    private let icons: [String: NSImage]
    var highlighted: Bool {
        didSet { if oldValue != highlighted { needsDisplay = true } }
    }

    init(rules: [AppPlacementRule], icons: [String: NSImage], highlighted: Bool) {
        self.snapshot = WorkspaceLayoutPreview.snapshot(rules: rules, canvasSize: Self.placementCanvas)
        self.icons = icons
        self.highlighted = highlighted
        super.init(frame: NSRect(origin: .zero, size: WorkspaceConsoleMetrics.previewSize))
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: WorkspaceConsoleMetrics.previewSize.width),
            heightAnchor.constraint(equalToConstant: WorkspaceConsoleMetrics.previewSize.height),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        ConsoleChrome.screenPlate(dark: dark).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

        let canvas = bounds.insetBy(dx: 3, dy: 3)
        let tone = highlighted ? ConsoleChrome.zoneActive(dark: dark) : ConsoleChrome.zoneIdle(dark: dark)
        let base = ConsoleChrome.opaqueSurface(dark: dark)
        var frames: [CGRect] = []
        for pane in snapshot.panes {
            let frame = rect(pane.rect, in: canvas).insetBy(dx: 0.5, dy: 0.5)
            frames.append(frame)
            guard let path = WorkspaceLayoutPreviewDrawing.roundedPath(
                for: frame,
                maxRadius: 3,
                factor: 0.2
            ) else { continue }
            base.setFill()
            path.fill()
            tone.withAlphaComponent(highlighted ? (dark ? 0.42 : 0.30) : (dark ? 0.40 : 0.28)).setFill()
            path.fill()
        }
        let outline = tone.withAlphaComponent(0.9)
        WorkspaceLayoutPreviewDrawing.strokeOutlines(
            panes: snapshot.panes,
            frames: frames,
            maxRadius: 3,
            factor: 0.2,
            solid: outline,
            dashed: outline,
            solidWidth: 1,
            dashedWidth: 1
        )

        for (index, pane) in snapshot.panes.enumerated() where pane.showsIcon {
            guard let icon = icons[pane.bundleID] else { continue }
            let frame = frames[index]
            let side = min(16, frame.width - 4, frame.height - 4)
            guard side >= 8 else { continue }
            let covered = frames[(index + 1)...].contains { $0.intersects(frame) }
            let anchor = covered ? rect(pane.labelRect, in: canvas) : frame
            var iconRect = CGRect(x: anchor.midX - side / 2, y: anchor.midY - side / 2, width: side, height: side)
            iconRect.origin.x = min(max(iconRect.minX, frame.minX + 2), frame.maxX - 2 - side)
            iconRect.origin.y = min(max(iconRect.minY, frame.minY + 2), frame.maxY - 2 - side)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    private func rect(_ normalized: NormalizedRect, in canvas: CGRect) -> CGRect {
        CGRect(
            x: canvas.minX + CGFloat(normalized.x) * canvas.width,
            y: canvas.minY + CGFloat(normalized.y) * canvas.height,
            width: CGFloat(normalized.width) * canvas.width,
            height: CGFloat(normalized.height) * canvas.height
        )
    }
}
