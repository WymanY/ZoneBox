import AppKit
import ZoneBoxCore

@MainActor
final class MenuBarConsoleController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var panel: ConsolePanel?
    private var sessionActive = false
    private var currentDisplayLabel: NSTextField?
    private var displayLabel: NSTextField?
    private weak var headerTitleStack: NSStackView?
    private var warningButton: NSButton?
    private var featuredLayoutHost: NSView?
    private var otherLayoutsHeader: NSView?
    private var otherLayoutsLabel: NSTextField?
    private var otherLayoutsScrollView: NSScrollView?
    private var gridView: LayoutGridView?
    private var gridHeightConstraint: NSLayoutConstraint?
    private var otherLayoutCount = 0
    private var organizeButton: NSButton?
    private var workspaceHeader: NSView?
    private var workspaceLabel: NSTextField?
    private var saveWorkspaceButton: NSButton?
    private var manageWorkspaceButton: NSButton?
    private var workspaceStrip: WorkspaceConsoleStrip?
    private var switcherHintLabel: NSTextField?
    private var settingsButton: NSButton?
    private var newButton: NSButton?
    private var quitButton: NSButton?
    private var appliedNewButtonTitle: String?
    private var eventMonitors: [Any] = []
    private var activationObservers: [NSObjectProtocol] = []
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
            raisePanel()
            return
        }
        sessionActive = true
        statusButton = button
        let panel = makePanel()
        self.panel = panel
        applyContent()
        applyPanelFrame(under: button)
        panel.orderFront(nil)
        panel.makeKey()
        raisePanel()
        startDismissMonitors()
        startActivationObservers()
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
        stopActivationObservers()
        panel = nil
        sessionActive = false
        statusButton = nil
    }

    private func dismiss(handoff: (() -> Void)?) {
        sessionActive = false
        statusButton = nil
        stopDismissMonitors()
        stopActivationObservers()
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
        let root = ConsoleMaterialView(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: 240))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = Metrics.stackSpacing
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = Metrics.panelInsets
        stack.detachesHiddenViews = true
        stack.addArrangedSubview(makeHeader())
        stack.addArrangedSubview(makeWarningButton())
        stack.addArrangedSubview(makeFeaturedLayoutHost())
        stack.addArrangedSubview(makeOtherLayoutsHeader())
        stack.addArrangedSubview(makeOtherLayoutsGrid())
        stack.addArrangedSubview(makeWorkspaceHeader())
        stack.addArrangedSubview(makeWorkspaceStrip())
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
        let eyebrow = makeTruncatingLabel(
            font: .systemFont(ofSize: 9, weight: .medium),
            color: .secondaryLabelColor
        )
        currentDisplayLabel = eyebrow

        let name = makeTruncatingLabel(
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: .labelColor
        )
        displayLabel = name

        let titleStack = NSStackView(views: [eyebrow, name])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.distribution = .fill
        titleStack.spacing = 1
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleStack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titleStack.setHuggingPriority(.defaultLow, for: .horizontal)
        titleStack.setClippingResistancePriority(.defaultHigh, for: .horizontal)
        headerTitleStack = titleStack

        let create = NSButton(title: L10n.text(.consoleNew), target: self, action: #selector(newLayout))
        create.bezelStyle = .rounded
        create.controlSize = .small
        create.refusesFirstResponder = true
        create.setContentHuggingPriority(.required, for: .horizontal)
        create.setContentCompressionResistancePriority(.required, for: .horizontal)
        create.translatesAutoresizingMaskIntoConstraints = false
        newButton = create
        appliedNewButtonTitle = nil

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleStack)
        header.addSubview(create)
        header.setContentHuggingPriority(.required, for: .vertical)
        header.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),
            titleStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: create.leadingAnchor, constant: -8),
            create.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            create.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            create.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor),
            create.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor),
        ])
        applyNewLayoutButtonTitle(L10n.text(.consoleNew))
        return header
    }

    private func makeTruncatingLabel(font: NSFont, color: NSColor) -> NSTextField {
        let field = ConsoleSingleLineLabel(labelWithString: "")
        field.font = font
        field.textColor = color
        field.alignment = .left
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = false
        field.preferredMaxLayoutWidth = 0
        field.cell?.truncatesLastVisibleLine = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    private func makeFeaturedLayoutHost() -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.heightAnchor.constraint(equalToConstant: Metrics.featuredHeight).isActive = true
        featuredLayoutHost = host
        return host
    }

    private func makeOtherLayoutsHeader() -> NSView {
        let label = NSTextField(labelWithString: L10n.text(.consoleOtherLayouts))
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        otherLayoutsLabel = label

        let separator = NSBox()
        separator.boxType = .separator
        separator.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, separator])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Metrics.sectionHeaderHeight).isActive = true
        otherLayoutsHeader = row
        return row
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

    private func makeOtherLayoutsGrid() -> NSView {
        let grid = LayoutGridView()
        gridView = grid

        let scroll = NSScrollView()
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
        let clipView = ScrollAwareClipView()
        clipView.drawsBackground = false
        clipView.onBoundsChange = { [weak grid] in
            grid?.reconcileHoverState()
        }
        scroll.contentView = clipView
        scroll.documentView = grid
        let height = scroll.heightAnchor.constraint(equalToConstant: gridHeight())
        gridHeightConstraint = height
        otherLayoutsScrollView = scroll
        NSLayoutConstraint.activate([
            height,
        ])
        return scroll
    }

    private func makeWorkspaceHeader() -> NSView {
        let label = NSTextField(labelWithString: L10n.text(.consoleWorkspaces))
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        workspaceLabel = label

        let save = NSButton(title: L10n.text(.consoleSaveWorkspace), target: self, action: #selector(saveCurrentWorkspace))
        save.bezelStyle = .inline
        save.isBordered = false
        save.font = .systemFont(ofSize: 11, weight: .medium)
        save.contentTintColor = .controlAccentColor
        save.setContentHuggingPriority(.required, for: .horizontal)
        saveWorkspaceButton = save

        let manage = NSButton(title: L10n.text(.consoleManageWorkspaces), target: self, action: #selector(manageConsoleWorkspaces(_:)))
        manage.bezelStyle = .inline
        manage.isBordered = false
        manage.font = .systemFont(ofSize: 11, weight: .medium)
        manage.setContentHuggingPriority(.required, for: .horizontal)
        manageWorkspaceButton = manage

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, save, manage])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Metrics.sectionHeaderHeight).isActive = true
        workspaceHeader = row
        return row
    }

    private func makeWorkspaceStrip() -> NSView {
        let strip = WorkspaceConsoleStrip()
        strip.onApply = { [weak self] id in
            self?.dismiss(handoff: { [weak self] in self?.runtime.workspace.apply(profileID: id) })
        }
        strip.onSave = { [weak self] in self?.saveCurrentWorkspace() }
        strip.onBeginRename = { [weak self] id in self?.reloadWorkspaceStrip(beginRename: id) }
        strip.onUpdate = { [weak self] id in
            self?.runtime.workspace.updateProfileFromCurrent(id: id)
            self?.reloadWorkspaceStrip()
        }
        strip.onRename = { [weak self] id, name in
            guard var profile = self?.runtime.document.profiles.first(where: { $0.id == id }) else { return }
            profile.name = LayoutEditTransaction.uniqueName(
                base: name,
                existingNames: self?.runtime.document.profiles.filter { $0.id != id }.map(\.name) ?? []
            )
            self?.runtime.workspace.updateProfile(profile)
            self?.reloadWorkspaceStrip()
        }
        strip.onDelete = { [weak self] profile in self?.confirmAndDeleteWorkspace(profile) }
        workspaceStrip = strip
        return strip
    }

    private func makeFooter() -> NSView {
        let settings = NSButton(title: L10n.text(.menuSettings), target: self, action: #selector(openSettings))
        settings.bezelStyle = .rounded
        settings.controlSize = .small
        settingsButton = settings

        let hint = NSTextField(labelWithString: "")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        switcherHintLabel = hint

        let quit = NSButton(title: L10n.text(.menuQuit), target: self, action: #selector(quit))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        quitButton = quit

        let row = NSStackView(views: [settings, hint, quit])
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

    private func applyContent() {
        let area = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
        currentDisplayLabel?.stringValue = L10n.text(.consoleCurrentDisplay)
        displayLabel?.stringValue = displayTitle(for: area)
        currentDisplayLabel?.invalidateIntrinsicContentSize()
        displayLabel?.invalidateIntrinsicContentSize()
        headerTitleStack?.invalidateIntrinsicContentSize()
        otherLayoutsLabel?.stringValue = L10n.text(.consoleOtherLayouts)
        let warning = runtime.trust.showsMenuBarWarning()
        warningButton?.title = L10n.text(.menuEnableAccessibility)
        warningButton?.isHidden = !warning

        organizeButton?.title = L10n.text(.consoleOrganize)
        organizeButton?.isEnabled = !runtime.isOrganizingWindows
        workspaceLabel?.stringValue = L10n.text(.consoleWorkspaces)
        saveWorkspaceButton?.title = L10n.text(.consoleSaveWorkspace)
        manageWorkspaceButton?.title = L10n.text(.consoleManageWorkspaces)
        settingsButton?.title = L10n.text(.menuSettings)
        applyNewLayoutButtonTitle(L10n.text(.consoleNew))
        quitButton?.title = L10n.text(.menuQuit)
        let chord = runtime.settings.applyWorkspaceHotkey.displayCaps.joined()
        switcherHintLabel?.stringValue = String(format: L10n.text(.consoleSwitcherHint), chord)

        rebuildLayoutViews(currentID: area.flatMap { runtime.document.layout(for: $0.display.id) }?.id)
        reloadWorkspaceStrip()
        gridHeightConstraint?.constant = gridHeight()
    }

    private func displayTitle(for area: WorkArea?) -> String {
        let stored = area?.display.localizedName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty { return stored }
        return L10n.text(.consoleNoDisplay)
    }

    private func applyNewLayoutButtonTitle(_ title: String) {
        guard let newButton else { return }
        newButton.toolTip = title
        newButton.setAccessibilityLabel(title)
        guard appliedNewButtonTitle != title else { return }
        appliedNewButtonTitle = title
        newButton.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.controlAccentColor,
            ]
        )
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: title)
        newButton.imagePosition = .imageLeading
        newButton.imageScaling = .scaleProportionallyDown
        newButton.imageHugsTitle = true
        newButton.contentTintColor = .controlAccentColor
        newButton.invalidateIntrinsicContentSize()
    }

    private func rebuildLayoutViews(currentID: UUID?) {
        guard let featuredLayoutHost, let gridView else { return }
        let layouts = runtime.document.layouts
        guard let featured = layouts.first(where: { $0.id == currentID }) ?? layouts.first else {
            featuredLayoutHost.subviews.forEach { $0.removeFromSuperview() }
            gridView.setTiles([])
            otherLayoutCount = 0
            otherLayoutsHeader?.isHidden = true
            otherLayoutsScrollView?.isHidden = true
            return
        }

        featuredLayoutHost.subviews.forEach { $0.removeFromSuperview() }
        let featuredCard = LayoutCardView(
            layout: featured,
            mode: .featured,
            selected: featured.id == currentID,
            canDelete: layouts.count > 1,
            gutterPoints: CGFloat(runtime.settings.gutterPoints),
            showNumbers: runtime.settings.showZoneNumbers,
            onSelect: { [weak self] in self?.select(featured) },
            onEdit: { [weak self] in self?.edit(featured) },
            onDelete: { [weak self] in self?.confirmAndDelete(featured) }
        )
        featuredCard.frame = featuredLayoutHost.bounds
        featuredCard.autoresizingMask = [.width, .height]
        featuredLayoutHost.addSubview(featuredCard)

        let otherLayouts = layouts.filter { $0.id != featured.id }
        let tiles: [NSView] = otherLayouts.map { layout in
            LayoutCardView(
                layout: layout,
                mode: .compact,
                selected: false,
                canDelete: layouts.count > 1,
                gutterPoints: CGFloat(runtime.settings.gutterPoints),
                showNumbers: runtime.settings.showZoneNumbers,
                onSelect: { [weak self] in self?.select(layout) },
                onEdit: { [weak self] in self?.edit(layout) },
                onDelete: { [weak self] in self?.confirmAndDelete(layout) }
            )
        }
        gridView.setTiles(tiles)
        otherLayoutCount = otherLayouts.count
        let hidesOthers = otherLayouts.isEmpty
        otherLayoutsHeader?.isHidden = hidesOthers
        otherLayoutsScrollView?.isHidden = hidesOthers
    }

    private func contentHeight() -> CGFloat {
        var visibleHeights: [CGFloat] = [
            Metrics.headerHeight,
            Metrics.featuredHeight,
            Metrics.sectionHeaderHeight,
            Metrics.workspaceStripHeight,
            1,
            Metrics.footerHeight,
        ]
        if runtime.trust.showsMenuBarWarning() {
            visibleHeights.insert(Metrics.warningHeight, at: 1)
        }
        if otherLayoutCount > 0 {
            visibleHeights.insert(contentsOf: [Metrics.sectionHeaderHeight, gridHeight()], at: 2)
        }
        let gaps = CGFloat(max(visibleHeights.count - 1, 0)) * Metrics.stackSpacing
        return Metrics.panelInsets.top + visibleHeights.reduce(0, +) + gaps + Metrics.panelInsets.bottom
    }

    private func gridHeight() -> CGFloat {
        guard otherLayoutCount > 0 else { return 0 }
        let rows = Int(ceil(Double(otherLayoutCount) / Double(Metrics.columns)))
        let natural = CGFloat(rows) * Metrics.compactHeight + CGFloat(max(rows - 1, 0)) * Metrics.rowSpacing
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
        panel.invalidateShadow()

    }

    private func startActivationObservers() {
        stopActivationObservers()
        let resign = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.close() }
        }
        let switchApp = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let controller = self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in controller.handleOtherAppActivated(app) }
        }
        activationObservers = [resign, switchApp]
    }

    private func stopActivationObservers() {
        for observer in activationObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        activationObservers.removeAll()
    }

    private func handleOtherAppActivated(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        close()
    }

    private func raisePanel() {
        guard let panel else { return }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.orderFrontRegardless()
        if NSApp.isActive {
            panel.makeKey()
        }
    }

    private func startDismissMonitors() {
        stopDismissMonitors()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            Task { @MainActor in self?.handleOutsideClick(event) }
        }) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            Task { @MainActor in self?.handleOutsideClick(event) }
            return event
        }) {
            eventMonitors.append(local)
        }
    }

    private func stopDismissMonitors() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard sessionActive, let panel, panel.isVisible else { return }
        let location = NSEvent.mouseLocation
        if panel.frame.contains(location) { return }
        if let sheet = panel.attachedSheet, sheet.frame.contains(location) { return }
        if let button = statusButton, let window = button.window {
            let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonRect.contains(location) { return }
        }
        close()
    }

    private func select(_ layout: Layout) {
        runtime.selectLayout(layout)
        if runtime.settings.previewLayoutOnSelect {
            close()
        } else {
            reload()
        }
    }

    @objc
    private func enableAccessibility() {
        dismiss(handoff: { [runtime] in runtime.openAccessibility() })
    }

    private func edit(_ layout: Layout) {
        dismiss(handoff: { [runtime] in runtime.openEditor(for: layout) })
    }

    @objc
    private func organizeWindows() {
        dismiss(handoff: { [runtime] in runtime.organizeWindowsFromPointer() })
    }

    private func confirmAndDelete(_ layout: Layout) {
        guard runtime.document.layouts.count > 1 else {
            NSSound.beep()
            return
        }
        let name = L10n.layoutDisplayName(layout.name)
        let alert = NSAlert()
        alert.messageText = String(format: L10n.text(.menuDeleteLayoutTitle), name)
        alert.informativeText = L10n.text(.menuDeleteLayoutMessage)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text(.menuDeleteLayoutConfirm))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        alert.buttons.first?.hasDestructiveAction = true
        if let panel {
            alert.beginSheetModal(for: panel) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn else { return }
                if !self.runtime.deleteLayout(layout) {
                    NSSound.beep()
                    return
                }
                self.reload()
            }
        } else {
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            if !runtime.deleteLayout(layout) {
                NSSound.beep()
                return
            }
            reload()
        }
    }

    @objc
    private func newLayout() {
        dismiss(handoff: { [runtime] in runtime.newGridLayout() })
    }

    private func reloadWorkspaceStrip(beginRename: WorkspaceProfile.ID? = nil) {
        workspaceStrip?.reload(
            profiles: runtime.document.orderedProfilesForSettings(),
            activeID: runtime.document.activeProfileID,
            connectedDisplayIDs: Set(runtime.displays.workAreas.map(\.display.id)),
            beginRename: beginRename
        )
    }

    @objc
    private func saveCurrentWorkspace() {
        runtime.workspace.captureImmediately { [weak self] id in
            self?.reloadWorkspaceStrip(beginRename: id)
        }
    }

    private func confirmAndDeleteWorkspace(_ profile: WorkspaceProfile) {
        let alert = NSAlert()
        alert.messageText = String(format: L10n.text(.settingsWorkspaceDeleteTitle), profile.name)
        alert.addButton(withTitle: L10n.text(.settingsWorkspaceDelete))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        alert.buttons.first?.hasDestructiveAction = true
        if let panel {
            alert.beginSheetModal(for: panel) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn else { return }
                self.runtime.workspace.deleteProfile(id: profile.id)
                self.reloadWorkspaceStrip()
            }
        }
    }

    @objc
    private func manageConsoleWorkspaces(_ sender: Any? = nil) {
        dismiss(handoff: { [runtime] in runtime.openWorkspaceSettings() })
    }

    @objc
    private func openSettings() {
        dismiss(handoff: { [runtime] in runtime.openSettings() })
    }

    fileprivate func handleSettingsKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        let chord = runtime.settings.settingsHotkey
        guard chord.matches(keyCode: event.keyCode, carbonModifiers: modifiers) else { return false }
        if ShortcutVoiceOverPolicy.shouldPause(
            chord: chord,
            voiceOverEnabled: NSWorkspace.shared.isVoiceOverEnabled
        ) {
            return false
        }
        openSettings()
        return true
    }

    @objc
    private func quit() {
        dismiss(handoff: { NSApp.terminate(nil) })
    }
}

private final class ConsoleSingleLineLabel: NSTextField {
    override var intrinsicContentSize: NSSize {
        let vertical = super.intrinsicContentSize.height
        guard !stringValue.isEmpty else {
            return NSSize(width: NSView.noIntrinsicMetric, height: vertical)
        }
        let textWidth = ceil(attributedStringValue.size().width) + 2
        return NSSize(width: textWidth, height: vertical)
    }
}

private final class ConsolePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? MenuBarConsoleController)?.close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if (delegate as? MenuBarConsoleController)?.handleSettingsKeyEquivalent(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        invalidateShadow()
    }
}

private final class ConsoleMaterialView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .menu
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Metrics.panelCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        autoresizingMask = [.width, .height]
        maskImage = Self.roundedMaskImage(cornerRadius: Metrics.panelCornerRadius)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        window?.invalidateShadow()
    }

    private static func roundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let cap = ceil(cornerRadius)
        let size = NSSize(width: cap * 2 + 1, height: cap * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cap, yRadius: cap).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
        image.resizingMode = .stretch
        return image
    }
}

/// 8pt overlay scroller with no slot, shared by the console's layout grid and
/// workspace strip so both scroll indicators look alike.
final class ThinOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        8
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

private final class ScrollAwareClipView: NSClipView {
    var onBoundsChange: (() -> Void)?
    private var reportedBoundsOrigin: NSPoint?

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(newOrigin)
        reportBoundsOriginChange()
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: newOrigin)
        reportBoundsOriginChange()
    }

    private func reportBoundsOriginChange() {
        let origin = bounds.origin
        guard reportedBoundsOrigin != origin else { return }
        reportedBoundsOrigin = origin
        onBoundsChange?()
    }
}

private enum Metrics {
    static let width: CGFloat = 360
    static let panelCornerRadius: CGFloat = 12
    static let panelInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
    static let stackSpacing: CGFloat = 10
    static let headerHeight: CGFloat = 42
    static let warningHeight: CGFloat = 24
    static let featuredHeight: CGFloat = 120
    static let sectionHeaderHeight: CGFloat = 18
    static let footerHeight: CGFloat = 24
    static let columns = 2
    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 10
    static let contentWidth = width - panelInsets.left - panelInsets.right
    static let compactWidth = (contentWidth - columnSpacing) / 2
    static let compactHeight: CGFloat = 88
    static let compactPreviewSize = NSSize(width: compactWidth - 16, height: 52)
    static let compactThumbnailSize = NSSize(width: compactPreviewSize.width - 6, height: compactPreviewSize.height - 6)
    /// The featured card frames its thumbnail in a "screen" like the compact
    /// cards do, so the zones read as sitting inside the display.
    static let featuredPreviewSize = NSSize(width: 188, height: 94)
    static let featuredPreviewInset: CGFloat = 4
    static let featuredThumbnailSize = NSSize(
        width: featuredPreviewSize.width - featuredPreviewInset * 2,
        height: featuredPreviewSize.height - featuredPreviewInset * 2
    )
    static let maxGridHeight: CGFloat = compactHeight * 2 + rowSpacing
    static let workspaceStripHeight: CGFloat = 84
}

private final class LayoutGridView: NSView {
    override var isFlipped: Bool { true }

    func setTiles(_ tiles: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        for tile in tiles {
            tile.translatesAutoresizingMaskIntoConstraints = true
            addSubview(tile)
        }
        needsLayout = true
        invalidateIntrinsicContentSize()
        setFrameSize(intrinsicContentSize)
    }

    func reconcileHoverState() {
        for case let tile as LayoutCardView in subviews {
            tile.reconcileHoverState()
        }
    }

    override var intrinsicContentSize: NSSize {
        let count = subviews.count
        guard count > 0 else { return NSSize(width: Metrics.contentWidth, height: 0) }
        let rows = Int(ceil(Double(count) / Double(Metrics.columns)))
        let height = CGFloat(rows) * Metrics.compactHeight + CGFloat(max(rows - 1, 0)) * Metrics.rowSpacing
        return NSSize(width: Metrics.contentWidth, height: height)
    }

    override func layout() {
        super.layout()
        let tileW = Metrics.compactWidth
        let tileH = Metrics.compactHeight
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
        let rows = Int(ceil(Double(subviews.count) / Double(Metrics.columns)))
        let height = CGFloat(rows) * tileH + CGFloat(max(rows - 1, 0)) * rowGap
        if abs(frame.height - height) > 0.5 || abs(frame.width - Metrics.contentWidth) > 0.5 {
            setFrameSize(NSSize(width: Metrics.contentWidth, height: height))
        }
        reconcileHoverState()
    }
}

private final class LayoutCardView: NSView {
    enum Mode {
        case featured
        case compact
    }

    private let mode: Mode
    private let selected: Bool
    private let canDelete: Bool
    private let onSelect: () -> Void
    private let onEdit: () -> Void
    private let onDelete: () -> Void
    private let title: String
    private let thumbnail: NSImage
    private let gutterPoints: CGFloat
    private let showNumbers: Bool
    private var hovering = false {
        didSet {
            guard oldValue != hovering else { return }
            updateActionVisibility()
            needsDisplay = true
        }
    }
    private let editButton = NSButton()
    private let deleteButton = NSButton()
    private let checkImageView = NSImageView()

    init(
        layout: Layout,
        mode: Mode,
        selected: Bool,
        canDelete: Bool,
        gutterPoints: CGFloat,
        showNumbers: Bool,
        onSelect: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.mode = mode
        self.selected = selected
        self.canDelete = canDelete
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.title = L10n.layoutDisplayName(layout.name)
        self.gutterPoints = gutterPoints
        self.showNumbers = showNumbers
        let thumbnailSize = mode == .featured
            ? Metrics.featuredThumbnailSize
            : Metrics.compactThumbnailSize
        let fill = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.36)
            : NSColor.controlAccentColor.withAlphaComponent(0.28)
        let stroke = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.76)
            : NSColor.white.withAlphaComponent(0.38)
        self.thumbnail = LayoutThumbnailRenderer.image(
            for: layout,
            size: thumbnailSize,
            fill: fill,
            stroke: stroke,
            gutterPoints: gutterPoints,
            showNumbers: showNumbers
        )
        let size = mode == .featured
            ? NSSize(width: Metrics.contentWidth, height: Metrics.featuredHeight)
            : NSSize(width: Metrics.compactWidth, height: Metrics.compactHeight)
        super.init(frame: NSRect(origin: .zero, size: size))
        translatesAutoresizingMaskIntoConstraints = true
        wantsLayer = true
        layer?.cornerRadius = mode == .featured ? 10 : 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilitySelected(selected)
        autoresizingMask = []
        configureCheckmark()
        configureActionButtons()
    }

    private func configureCheckmark() {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        checkImageView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        checkImageView.contentTintColor = .controlAccentColor
        checkImageView.imageScaling = .scaleProportionallyDown
        checkImageView.isHidden = !selected || mode != .featured
        addSubview(checkImageView)
    }

    private func configureActionButtons() {
        configureChromeButton(
            editButton,
            symbol: "pencil",
            title: L10n.text(.consoleEdit),
            role: .edit,
            action: #selector(editTapped)
        )
        configureChromeButton(
            deleteButton,
            symbol: "trash",
            title: L10n.text(.editorDelete),
            role: .delete,
            action: #selector(deleteTapped)
        )
        addSubview(editButton)
        addSubview(deleteButton)
        updateActionVisibility()
        layoutActionButtons()
    }

    private func configureChromeButton(
        _ button: NSButton,
        symbol: String,
        title: String,
        role: ActionRole,
        action: Selector
    ) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.refusesFirstResponder = true
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.target = self
        button.action = action
        button.wantsLayer = true
        button.layer?.cornerRadius = mode == .featured ? 6 : 5
        button.layer?.cornerCurve = .continuous
        button.layer?.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = true
        applyActionChrome(button, role: role)
    }

    private func updateActionVisibility() {
        let showsActions = mode == .featured || hovering
        editButton.isHidden = !showsActions
        deleteButton.isHidden = !showsActions || !canDelete
    }

    @objc private func deleteTapped() {
        onDelete()
    }

    @objc private func editTapped() {
        onEdit()
    }

    private func layoutActionButtons() {
        let size: CGFloat = mode == .featured ? 22 : 20
        let inset: CGFloat = mode == .featured ? 8 : 6
        let gap: CGFloat = 6
        deleteButton.frame = NSRect(
            x: bounds.maxX - inset - size,
            y: bounds.maxY - inset - size,
            width: size,
            height: size
        )
        editButton.frame = NSRect(
            x: deleteButton.frame.minX - gap - size,
            y: deleteButton.frame.minY,
            width: size,
            height: size
        )
        if mode == .featured {
            checkImageView.frame = NSRect(x: bounds.maxX - 32, y: 18, width: 20, height: 20)
        } else {
            checkImageView.frame = .zero
        }
        updateActionVisibility()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        mode == .featured
            ? NSSize(width: Metrics.contentWidth, height: Metrics.featuredHeight)
            : NSSize(width: Metrics.compactWidth, height: Metrics.compactHeight)
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
        if let grid = superview as? LayoutGridView {
            grid.reconcileHoverState()
        } else {
            reconcileHoverState()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
    }

    func reconcileHoverState() {
        guard mode == .compact, let window else {
            hovering = false
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        hovering = bounds.contains(point) && visibleRect.contains(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !editButton.isHidden, editButton.frame.contains(point) {
            onEdit()
            return
        }
        if !deleteButton.isHidden, deleteButton.frame.contains(point) {
            onDelete()
            return
        }
        onSelect()
    }

    override func layout() {
        super.layout()
        layoutActionButtons()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyActionChrome(editButton, role: .edit)
        applyActionChrome(deleteButton, role: .delete)
        needsDisplay = true
    }

    private enum ActionRole {
        case edit
        case delete
    }

    private func applyActionChrome(_ button: NSButton, role: ActionRole) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tint: NSColor
        let fill: NSColor
        let border: NSColor
        switch role {
        case .edit:
            tint = .controlAccentColor
            fill = NSColor.controlAccentColor.withAlphaComponent(dark ? 0.28 : 0.16)
            border = NSColor.controlAccentColor.withAlphaComponent(dark ? 0.46 : 0.28)
        case .delete:
            tint = .systemRed
            fill = NSColor.systemRed.withAlphaComponent(dark ? 0.28 : 0.14)
            border = NSColor.systemRed.withAlphaComponent(dark ? 0.46 : 0.26)
        }
        button.contentTintColor = tint
        effectiveAppearance.performAsCurrentDrawingAppearance {
            button.layer?.backgroundColor = fill.cgColor
            button.layer?.borderColor = border.cgColor
            button.layer?.borderWidth = 1
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill: NSColor
        switch mode {
        case .featured:
            fill = selected
                ? NSColor.controlAccentColor.withAlphaComponent(dark ? 0.20 : 0.10)
                : (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.045)
        case .compact:
            fill = hovering
                ? NSColor.controlAccentColor.withAlphaComponent(dark ? 0.14 : 0.08)
                : NSColor.controlBackgroundColor.withAlphaComponent(dark ? 0.20 : 0.56)
        }
        fill.setFill()
        let radius: CGFloat = mode == .featured ? 10 : 8
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let border = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: radius,
            yRadius: radius
        )
        if mode == .featured, selected {
            NSColor.controlAccentColor.withAlphaComponent(0.88).setStroke()
            border.lineWidth = 1.5
        } else if mode == .compact {
            let compactBorder = hovering
                ? NSColor.controlAccentColor.withAlphaComponent(0.72)
                : NSColor.separatorColor.withAlphaComponent(0.48)
            compactBorder.setStroke()
            border.lineWidth = 1
        } else {
            NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
            border.lineWidth = 1
        }
        border.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let thumbRect: NSRect
        let titleRect: NSRect
        let font: NSFont
        switch mode {
        case .featured:
            let previewRect = NSRect(
                x: 12,
                y: ((bounds.height - Metrics.featuredPreviewSize.height) / 2).rounded(),
                width: Metrics.featuredPreviewSize.width,
                height: Metrics.featuredPreviewSize.height
            )
            drawScreenFrame(previewRect, radius: 6, lineWidth: 1, strokeAlpha: 0.42, dark: dark)
            thumbRect = previewRect.insetBy(
                dx: Metrics.featuredPreviewInset,
                dy: Metrics.featuredPreviewInset
            )
            titleRect = NSRect(
                x: previewRect.maxX + 14,
                y: 42,
                width: max(0, bounds.maxX - previewRect.maxX - 54),
                height: 22
            )
            font = .systemFont(ofSize: 13, weight: .semibold)
            paragraph.alignment = .left
        case .compact:
            let previewRect = NSRect(
                x: ((bounds.width - Metrics.compactPreviewSize.width) / 2).rounded(),
                y: bounds.maxY - 8 - Metrics.compactPreviewSize.height,
                width: Metrics.compactPreviewSize.width,
                height: Metrics.compactPreviewSize.height
            )
            drawScreenFrame(previewRect, radius: 5, lineWidth: 0.5, strokeAlpha: 0.28, dark: dark)
            thumbRect = NSRect(
                x: previewRect.minX + 3,
                y: previewRect.minY + 3,
                width: Metrics.compactThumbnailSize.width,
                height: Metrics.compactThumbnailSize.height
            )
            titleRect = NSRect(x: 8, y: 4, width: bounds.width - 16, height: 18)
            font = .systemFont(ofSize: 11, weight: .medium)
            paragraph.alignment = .center
        }
        thumbnail.draw(in: thumbRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(in: titleRect, withAttributes: attrs)
    }

    /// The display the zones live in: a faint bezel-like plate behind the
    /// thumbnail, drawn the same way on featured and compact cards.
    private func drawScreenFrame(
        _ rect: NSRect,
        radius: CGFloat,
        lineWidth: CGFloat,
        strokeAlpha: CGFloat,
        dark: Bool
    ) {
        let path = NSBezierPath(
            roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
            xRadius: radius,
            yRadius: radius
        )
        NSColor.labelColor.withAlphaComponent(dark ? 0.055 : 0.035).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(strokeAlpha).setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}
