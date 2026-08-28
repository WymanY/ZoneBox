import AppKit
import ZoneBoxCore

@MainActor
final class MenuBarConsoleController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var panel: ConsolePanel?
    private var sessionActive = false
    private var displayLabel: NSTextField?
    private var snapSwitch: NSSwitch?
    private var snapLabel: NSTextField?
    private var warningButton: NSButton?
    private var gridView: TileGridView?
    private var gridHeightConstraint: NSLayoutConstraint?
    private var editButton: NSButton?
    private var previewButton: NSButton?
    private var newButton: NSButton?
    private var settingsButton: NSButton?
    private var quitButton: NSButton?
    private var eventMonitor: Any?
    private weak var statusButton: NSStatusBarButton?

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
    }

    var isShown: Bool { panel?.isVisible == true }

    func toggle(from button: NSStatusBarButton) {
        if isShown {
            close()
        } else {
            show(from: button)
        }
    }

    func show(from button: NSStatusBarButton) {
        if isShown {
            reload()
            return
        }
        sessionActive = true
        statusButton = button
        let panel = makePanel()
        self.panel = panel
        applyContent()
        applyPanelFrame(under: button)
        panel.orderFront(nil)
        startDismissMonitors()
    }

    func close() {
        dismiss(handoff: nil)
    }

    func reload() {
        guard isShown else { return }
        applyContent()
        if let statusButton {
            applyPanelFrame(under: statusButton)
        }
    }

    func windowWillClose(_ notification: Notification) {
        stopDismissMonitors()
        panel = nil
        sessionActive = false
        statusButton = nil
    }

    private func dismiss(handoff: (() -> Void)?) {
        sessionActive = false
        statusButton = nil
        stopDismissMonitors()
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            panel.close()
        }
        self.panel = nil
        handoff?()
    }

    private func makePanel() -> ConsolePanel {
        let panel = ConsolePanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let root = makeRoot()
        panel.contentView = root
        return panel
    }

    private func makeRoot() -> NSView {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: 240))
        root.material = .menu
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.detachesHiddenViews = true
        stack.addArrangedSubview(makeHeader())
        stack.addArrangedSubview(makeWarningButton())
        stack.addArrangedSubview(makeGrid())
        stack.addArrangedSubview(makeActions())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeFooter())

        root.translatesAutoresizingMaskIntoConstraints = true
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
        ])
        return root
    }

    private func makeHeader() -> NSView {
        let name = NSTextField(labelWithString: "")
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        displayLabel = name

        let snap = NSTextField(labelWithString: L10n.text(.consoleSnap))
        snap.font = .systemFont(ofSize: 11, weight: .medium)
        snap.textColor = .secondaryLabelColor
        snap.setContentHuggingPriority(.required, for: .horizontal)
        snapLabel = snap

        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = #selector(snapSwitchChanged(_:))
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        snapSwitch = toggle

        let snapRow = NSStackView(views: [snap, toggle])
        snapRow.orientation = .horizontal
        snapRow.alignment = .centerY
        snapRow.spacing = 6

        let header = NSStackView(views: [name, snapRow])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        header.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return header
    }

    private func makeWarningButton() -> NSButton {
        let button = NSButton(
            title: L10n.text(.menuEnableAccessibility),
            target: self,
            action: #selector(enableAccessibility)
        )
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.contentTintColor = .systemOrange
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        warningButton = button
        return button
    }

    private func makeGrid() -> NSView {
        let grid = TileGridView()
        gridView = grid

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.verticalScrollElasticity = .none
        scroll.documentView = grid
        let height = scroll.heightAnchor.constraint(equalToConstant: gridHeight())
        gridHeightConstraint = height
        NSLayoutConstraint.activate([
            height,
        ])
        return scroll
    }

    private func makeActions() -> NSView {
        let edit = actionButton(title: L10n.text(.consoleEdit), action: #selector(editLayout))
        let preview = actionButton(title: L10n.text(.consolePreview), action: #selector(previewCurrent))
        let create = actionButton(title: L10n.text(.consoleNew), action: #selector(newLayout))
        editButton = edit
        previewButton = preview
        newButton = create
        let row = NSStackView(views: [edit, preview, create])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return row
    }

    private func makeFooter() -> NSView {
        let settings = NSButton(title: L10n.text(.menuSettings), target: self, action: #selector(openSettings))
        settings.bezelStyle = .rounded
        settings.controlSize = .small
        settingsButton = settings

        let quit = NSButton(title: L10n.text(.menuQuit), target: self, action: #selector(quit))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        quitButton = quit

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [settings, spacer, quit])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return row
    }

    private func makeSeparator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        return line
    }

    private func actionButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    private func applyContent() {
        let area = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
        displayLabel?.stringValue = area?.display.localizedName ?? L10n.text(.consoleNoDisplay)
        snapLabel?.stringValue = L10n.text(.consoleSnap)
        snapSwitch?.state = runtime.snapEnabled ? .on : .off
        snapSwitch?.toolTip = L10n.text(.menuSnapEnabled)
        snapSwitch?.setAccessibilityLabel(L10n.text(.menuSnapEnabled))

        let warning = runtime.trust.showsMenuBarWarning()
        warningButton?.title = L10n.text(.menuEnableAccessibility)
        warningButton?.isHidden = !warning

        editButton?.title = L10n.text(.consoleEdit)
        previewButton?.title = L10n.text(.consolePreview)
        newButton?.title = L10n.text(.consoleNew)
        settingsButton?.title = L10n.text(.menuSettings)
        quitButton?.title = L10n.text(.menuQuit)

        rebuildTiles(currentID: area.flatMap { runtime.document.layout(for: $0.display.id) }?.id)
        gridHeightConstraint?.constant = gridHeight()
    }

    private func rebuildTiles(currentID: UUID?) {
        guard let gridView else { return }
        let tiles = runtime.document.layouts.map { layout in
            LayoutTileView(
                layout: layout,
                selected: layout.id == currentID,
                width: Metrics.tileWidth,
                thumbnailSize: Metrics.thumbnailSize,
                onSelect: { [weak self] in self?.select(layout) }
            )
        }
        gridView.setTiles(tiles)
    }

    private func contentHeight() -> CGFloat {
        let warning: CGFloat = runtime.trust.showsMenuBarWarning() ? 34 : 0
        return 12 + 24 + warning + 10 + gridHeight() + 10 + 28 + 10 + 1 + 10 + 24 + 12
    }

    private func gridHeight() -> CGFloat {
        let layouts = max(runtime.document.layouts.count, 1)
        let rows = Int(ceil(Double(layouts) / Double(Metrics.columns)))
        let natural = CGFloat(rows) * Metrics.tileHeight + CGFloat(max(rows - 1, 0)) * Metrics.rowSpacing
        return min(Metrics.maxGridHeight, natural)
    }

    private func applyPanelFrame(under button: NSStatusBarButton) {
        guard let panel else { return }
        let size = NSSize(width: Metrics.width, height: contentHeight())
        panel.minSize = size
        panel.maxSize = size
        panel.contentMinSize = size
        panel.contentMaxSize = size
        position(panel, under: button, size: size)
    }

    private func position(_ panel: NSPanel, under button: NSStatusBarButton, size: NSSize) {
        guard let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        var origin = NSPoint(
            x: buttonRect.midX - size.width / 2,
            y: buttonWindow.frame.minY - size.height - 6
        )
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        if origin.y + size.height > visible.maxY {
            origin.y = visible.maxY - size.height - 4
        }
        if origin.y < visible.minY {
            origin.y = visible.minY + 4
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.contentView?.setFrameSize(size)

    }

    private func startDismissMonitors() {}

    private func stopDismissMonitors() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func select(_ layout: Layout) {
        runtime.selectLayout(layout)
        reload()
    }

    @objc
    private func snapSwitchChanged(_ sender: NSSwitch) {
        runtime.setSnapEnabled(sender.state == .on)
    }

    @objc
    private func enableAccessibility() {
        dismiss(handoff: { [runtime] in runtime.openAccessibility() })
    }

    @objc
    private func editLayout() {
        dismiss(handoff: { [runtime] in runtime.openEditor() })
    }

    @objc
    private func previewCurrent() {
        runtime.previewZones()
    }

    @objc
    private func newLayout() {
        dismiss(handoff: { [runtime] in runtime.newCanvasLayout() })
    }

    @objc
    private func openSettings() {
        dismiss(handoff: { [runtime] in runtime.openSettings() })
    }

    @objc
    private func quit() {
        dismiss(handoff: { NSApp.terminate(nil) })
    }
}

private final class ConsolePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private enum Metrics {
    static let width: CGFloat = 300
    static let columns = 2
    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 8
    static let thumbnailSize = NSSize(width: 126, height: 58)
    static let tileWidth: CGFloat = 134
    static let tileHeight: CGFloat = 108
    static let maxGridHeight: CGFloat = 456
}

private final class TileGridView: NSView {
    override var isFlipped: Bool { true }

    func setTiles(_ tiles: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        for tile in tiles {
            tile.translatesAutoresizingMaskIntoConstraints = true
            addSubview(tile)
        }
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let count = max(subviews.count, 1)
        let rows = Int(ceil(Double(count) / Double(Metrics.columns)))
        let height = CGFloat(rows) * Metrics.tileHeight + CGFloat(max(rows - 1, 0)) * Metrics.rowSpacing
        return NSSize(width: Metrics.width - 24, height: height)
    }

    override func layout() {
        super.layout()
        let tileW = Metrics.tileWidth
        let tileH = Metrics.tileHeight
        let colGap = Metrics.columnSpacing
        let rowGap = Metrics.rowSpacing
        for (index, tile) in subviews.enumerated() {
            let row = index / Metrics.columns
            let col = index % Metrics.columns
            tile.frame = NSRect(
                x: CGFloat(col) * (tileW + colGap),
                y: CGFloat(row) * (tileH + rowGap),
                width: tileW,
                height: tileH
            )
        }
        let rows = max(1, Int(ceil(Double(max(subviews.count, 1)) / Double(Metrics.columns))))
        let height = CGFloat(rows) * tileH + CGFloat(max(rows - 1, 0)) * rowGap
        if abs(frame.height - height) > 0.5 || abs(frame.width - (Metrics.width - 24)) > 0.5 {
            setFrameSize(NSSize(width: Metrics.width - 24, height: height))
        }
    }
}

private final class LayoutTileView: NSView {
    private let selected: Bool
    private let onSelect: () -> Void
    private let title: String
    private let thumbnail: NSImage
    private var hovering = false { didSet { needsDisplay = true } }

    init(
        layout: Layout,
        selected: Bool,
        width: CGFloat,
        thumbnailSize: NSSize,
        onSelect: @escaping () -> Void
    ) {
        self.selected = selected
        self.onSelect = onSelect
        self.title = L10n.layoutDisplayName(layout.name)
        let fill = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.55)
            : NSColor.controlAccentColor.withAlphaComponent(0.28)
        let stroke = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.9)
            : NSColor.white.withAlphaComponent(0.35)
        self.thumbnail = LayoutThumbnailRenderer.image(
            for: layout,
            size: thumbnailSize,
            fill: fill,
            stroke: stroke
        )
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Metrics.tileHeight))
        translatesAutoresizingMaskIntoConstraints = true
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        autoresizingMask = []
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Metrics.tileWidth, height: Metrics.tileHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
    }

    override func mouseDown(with event: NSEvent) {
        onSelect()
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill: NSColor
        if selected {
            fill = NSColor.controlAccentColor.withAlphaComponent(dark ? 0.22 : 0.16)
        } else if hovering {
            fill = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.06)
        } else {
            fill = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.04)
        }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        if selected {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            border.lineWidth = 2
            border.stroke()
        }

        let captionHeight: CGFloat = 22
        let thumbRect = NSRect(
            x: ((bounds.width - Metrics.thumbnailSize.width) / 2).rounded(),
            y: bounds.maxY - 8 - Metrics.thumbnailSize.height,
            width: Metrics.thumbnailSize.width,
            height: Metrics.thumbnailSize.height
        )
        thumbnail.draw(in: thumbRect)

        let caption = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: captionHeight)
        let captionFill = dark
            ? NSColor.black.withAlphaComponent(0.72)
            : NSColor.windowBackgroundColor
        captionFill.setFill()
        caption.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: selected ? .semibold : .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(in: caption.insetBy(dx: 6, dy: 3), withAttributes: attrs)
    }
}
