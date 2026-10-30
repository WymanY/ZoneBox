import AppKit
import ZoneBoxCore

@MainActor
final class MenuBarConsoleController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var panel: ConsolePanel?
    private var sessionActive = false
    private var rootStack: NSStackView?
    private var displayButton: ConsoleButton?
    private var selectedDisplayID: DisplayIdentity.ID?
    private var warningButton: ConsoleButton?
    private var warningRow: NSView?
    private var featuredLayoutHost: NSView?
    private var otherLayoutsHeader: NSView?
    private var otherLayoutsLabel: NSTextField?
    private var layoutCountLabel: NSTextField?
    private var otherLayoutsScrollView: NSScrollView?
    private var otherLayoutsFade: ConsoleScrollFade?
    private var gridView: LayoutGridView?
    private var gridHeightConstraint: NSLayoutConstraint?
    private var otherLayoutCount = 0
    private var workspaceLabel: NSTextField?
    private var workspaceCaptureOption: WorkspaceCaptureOptionView?
    private var saveWorkspaceButton: ConsoleButton?
    private var manageWorkspaceButton: ConsoleButton?
    private var workspaceStrip: WorkspaceConsoleStrip?
    private var switcherButton: ConsoleButton?
    private var settingsButton: ConsoleButton?
    private var updateNoticeButton: ConsoleButton?
    private var newButton: ConsoleButton?
    private var quitButton: ConsoleButton?
    private var layoutRenderSignature = ""
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
        selectedDisplayID = nil
        layoutRenderSignature = ""
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
        let responder = panel?.firstResponder
        applyContent()
        if let statusButton {
            applyPanelFrame(under: statusButton)
        }
        if let panel, let view = responder as? NSView, view.window === panel {
            panel.makeFirstResponder(view)
        }
    }

    func refreshWorkspaceCaptureSetting() {
        workspaceCaptureOption?.refresh(isOn: runtime.settings.captureFullyOccludedWindows)
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
        selectedDisplayID = nil
        stopDismissMonitors()
        stopActivationObservers()
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            panel.close()
        }
        self.panel = nil
        handoff?()
    }

    // MARK: - Construction

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
        panel.contentView = makeRoot()
        return panel
    }

    private func makeRoot() -> NSView {
        let root = ConsoleMaterialView(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: 240))

        let header = makeHeader()
        let display = makeDisplayRow()
        let warning = makeWarningButton()
        let featured = makeFeaturedLayoutHost()
        let layoutsHeader = makeOtherLayoutsHeader()
        let grid = makeOtherLayoutsGrid()
        let workspaceHeader = makeWorkspaceHeader()
        let captureOption = WorkspaceCaptureOptionView(isOn: runtime.settings.captureFullyOccludedWindows)
        captureOption.onChange = { [weak self] enabled in
            self?.runtime.setCaptureFullyOccludedWindows(enabled)
        }
        workspaceCaptureOption = captureOption
        let strip = makeWorkspaceStrip()
        let separator = makeSeparator()
        let footer = makeFooter()

        let stack = NSStackView(views: [
            header, display, warning, featured, layoutsHeader, grid, workspaceHeader, captureOption, strip, separator, footer,
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = Metrics.panelInsets
        stack.detachesHiddenViews = true
        stack.setCustomSpacing(2, after: header)
        stack.setCustomSpacing(8, after: display)
        stack.setCustomSpacing(8, after: warning)
        stack.setCustomSpacing(Metrics.sectionGap, after: featured)
        stack.setCustomSpacing(Metrics.sectionGap, after: grid)
        stack.setCustomSpacing(10, after: strip)
        stack.setCustomSpacing(2, after: separator)
        rootStack = stack

        root.translatesAutoresizingMaskIntoConstraints = true
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: Metrics.width),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
        ])
        return root
    }

    private func makeHeader() -> NSView {
        let mark = ConsoleBrandMark()
        let title = NSTextField(labelWithString: "ZoneBox")
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.textColor = .labelColor
        title.setContentHuggingPriority(.required, for: .horizontal)
        let brand = NSStackView(views: [mark, title])
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 7
        brand.translatesAutoresizingMaskIntoConstraints = false

        let create = ConsoleButton(role: .primary, title: L10n.text(.consoleNew), symbol: "plus", target: self, action: #selector(newLayout))
        create.controlHeight = 28
        create.fontSize = 13
        create.fontWeight = .semibold
        create.horizontalPadding = 12
        newButton = create

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(brand)
        header.addSubview(create)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),
            brand.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            brand.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            brand.trailingAnchor.constraint(lessThanOrEqualTo: create.leadingAnchor, constant: -8),
            create.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            create.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        return header
    }

    private func makeDisplayRow() -> NSView {
        let button = ConsoleButton(role: .plain, symbol: "display", target: self, action: #selector(chooseDisplay(_:)))
        button.fontSize = 13
        button.fontWeight = .semibold
        button.horizontalPadding = 6
        button.contentAlignment = .left
        button.titleColorOverride = .labelColor
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityLabel(L10n.text(.consoleCurrentDisplay))
        displayButton = button

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(button)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Metrics.displayRowHeight),
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: -6),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
        ])
        return row
    }

    private func makeWarningButton() -> NSView {
        let button = ConsoleButton(
            role: .warning,
            title: L10n.text(.menuEnableAccessibility),
            symbol: "exclamationmark.triangle.fill",
            target: self,
            action: #selector(enableAccessibility)
        )
        button.controlHeight = 28
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        warningButton = button
        let row = NSView.wrapping(button, leading: 0, trailing: 0)
        warningRow = row
        return row
    }

    private func makeFeaturedLayoutHost() -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.heightAnchor.constraint(equalToConstant: Metrics.featuredHeight).isActive = true
        featuredLayoutHost = host
        return host
    }

    private func makeOtherLayoutsHeader() -> NSView {
        let label = Self.sectionLabel(L10n.text(.consoleSwitchLayouts))
        otherLayoutsLabel = label

        let count = NSTextField(labelWithString: "")
        count.font = .systemFont(ofSize: 12, weight: .regular)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        layoutCountLabel = count

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, count])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Metrics.sectionHeaderHeight).isActive = true
        otherLayoutsHeader = row
        return row
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
        clipView.onBoundsChange = { [weak self, weak grid] in
            grid?.reconcileHoverState()
            self?.updateGridFade()
        }
        scroll.contentView = clipView
        scroll.documentView = grid

        let fade = ConsoleScrollFade(color: { ConsoleChrome.opaquePanel(dark: $0) })
        scroll.addSubview(fade)
        otherLayoutsFade = fade

        let height = scroll.heightAnchor.constraint(equalToConstant: gridHeight())
        gridHeightConstraint = height
        otherLayoutsScrollView = scroll
        NSLayoutConstraint.activate([
            height,
            fade.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            fade.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            fade.heightAnchor.constraint(equalToConstant: 22),
        ])
        return scroll
    }

    private func makeWorkspaceHeader() -> NSView {
        let label = Self.sectionLabel(L10n.text(.consoleWorkspaces))
        workspaceLabel = label

        let switcher = ConsoleButton(role: .keycap, target: self, action: #selector(openWorkspaceSwitcher))
        switcher.controlHeight = 18
        switcher.fontSize = 11
        switcher.horizontalPadding = 5
        switcherButton = switcher

        let save = ConsoleButton(role: .accent, title: L10n.text(.consoleSaveWorkspace), symbol: "plus", target: self, action: #selector(saveCurrentWorkspace))
        save.horizontalPadding = 7
        saveWorkspaceButton = save

        let manage = ConsoleButton(role: .plain, title: L10n.text(.consoleManage), target: self, action: #selector(manageConsoleWorkspaces(_:)))
        manage.horizontalPadding = 7
        manageWorkspaceButton = manage

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, switcher, spacer, save, manage])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 2
        row.setCustomSpacing(8, after: label)
        row.detachesHiddenViews = true
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Metrics.sectionHeaderHeight).isActive = true
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
        let settings = ConsoleButton(role: .plain, title: L10n.text(.consoleSettings), symbol: "gearshape", target: self, action: #selector(openSettings))
        settings.controlHeight = 26
        settingsButton = settings

        let update = ConsoleButton(role: .tinted, target: self, action: #selector(openUpdateNotice))
        update.horizontalPadding = 9
        update.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        update.isHidden = true
        updateNoticeButton = update

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let quit = ConsoleButton(role: .plain, title: L10n.text(.consoleQuit), symbol: "power", target: self, action: #selector(quit))
        quit.controlHeight = 26
        quitButton = quit

        let row = NSStackView(views: [settings, update, spacer, quit])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.detachesHiddenViews = true
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Metrics.footerHeight).isActive = true
        return NSView.wrapping(row, leading: -6, trailing: 6)
    }

    private func makeSeparator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        return line
    }

    private static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    // MARK: - Content

    private func applyContent() {
        let area = resolvedArea()
        applyDisplayButton(for: area)
        otherLayoutsLabel?.stringValue = L10n.text(.consoleSwitchLayouts)
        warningButton?.title = L10n.text(.menuEnableAccessibility)
        warningRow?.isHidden = !runtime.trust.showsMenuBarWarning()

        workspaceLabel?.stringValue = L10n.text(.consoleWorkspaces)
        workspaceCaptureOption?.refresh(isOn: runtime.settings.captureFullyOccludedWindows)
        let chord = runtime.settings.applyWorkspaceHotkey.displayCaps.joined()
        let switcherTitle = String(format: L10n.text(.consoleSwitcherAction), chord)
        switcherButton?.title = chord
        switcherButton?.toolTip = switcherTitle
        switcherButton?.setAccessibilityLabel(switcherTitle)
        saveWorkspaceButton?.title = L10n.text(.consoleSaveWorkspace)
        manageWorkspaceButton?.title = L10n.text(.consoleManage)
        manageWorkspaceButton?.toolTip = L10n.text(.consoleManageWorkspaces)
        settingsButton?.title = L10n.text(.consoleSettings)
        newButton?.title = L10n.text(.consoleNew)
        quitButton?.title = L10n.text(.consoleQuit)

        applyUpdateNotice()
        let currentID = area.flatMap { runtime.document.layout(for: $0.display.id) }?.id
        rebuildLayoutViewsIfNeeded(currentID: currentID)
        layoutCountLabel?.stringValue = String(
            format: L10n.text(.consoleLayoutCount),
            locale: LanguageCenter.language.locale,
            runtime.document.layouts.count
        )
        reloadWorkspaceStrip()
        gridHeightConstraint?.constant = gridHeight()
        updateGridFade()
    }

    private func resolvedArea() -> WorkArea? {
        if let id = selectedDisplayID,
           let area = runtime.displays.workAreas.first(where: { $0.display.id == id }) {
            return area
        }
        selectedDisplayID = nil
        return runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
            ?? runtime.displays.workAreas.first
    }

    private func applyDisplayButton(for area: WorkArea?) {
        guard let displayButton else { return }
        let title = displayTitle(for: area)
        let choosable = runtime.displays.workAreas.count > 1
        displayButton.title = title
        displayButton.trailingSymbolName = choosable ? "chevron.down" : nil
        displayButton.isInteractive = choosable
        displayButton.toolTip = title
        displayButton.setAccessibilityValue(title)
    }

    private func displayTitle(for area: WorkArea?) -> String {
        let stored = area?.display.localizedName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty { return stored }
        return L10n.text(.consoleNoDisplay)
    }

    private func rebuildLayoutViewsIfNeeded(currentID: UUID?) {
        let layouts = runtime.document.layouts
        let names = runtime.document.presentationNames()
        let signature = [
            LanguageCenter.language.rawValue,
            currentID?.uuidString ?? "",
            layouts.map { "\($0.id.uuidString):\($0.name):\($0.zones.count):\(names[$0.id] ?? "")" }.joined(separator: ","),
        ].joined(separator: "|")
        if signature == layoutRenderSignature, featuredLayoutHost?.subviews.isEmpty == false {
            return
        }
        layoutRenderSignature = signature
        rebuildLayoutViews(currentID: currentID)
    }

    private func rebuildLayoutViews(currentID: UUID?) {
        guard let featuredLayoutHost, let gridView else { return }
        let layouts = runtime.document.layouts
        featuredLayoutHost.subviews.forEach { $0.removeFromSuperview() }
        guard let featured = layouts.first(where: { $0.id == currentID }) ?? layouts.first else {
            gridView.setTiles([])
            otherLayoutCount = 0
            otherLayoutsHeader?.isHidden = true
            otherLayoutsScrollView?.isHidden = true
            return
        }

        let featuredCard = makeCard(for: featured, mode: .featured, selected: featured.id == currentID, canDelete: layouts.count > 1)
        featuredCard.frame = featuredLayoutHost.bounds
        featuredCard.autoresizingMask = [.width, .height]
        featuredLayoutHost.addSubview(featuredCard)

        let otherLayouts = layouts.filter { $0.id != featured.id }
        gridView.setTiles(otherLayouts.map {
            makeCard(for: $0, mode: .compact, selected: false, canDelete: layouts.count > 1)
        })
        otherLayoutCount = otherLayouts.count
        let hidesOthers = otherLayouts.isEmpty
        otherLayoutsHeader?.isHidden = hidesOthers
        otherLayoutsScrollView?.isHidden = hidesOthers
        otherLayoutsScrollView?.contentView.scroll(to: .zero)
    }

    private func makeCard(for layout: Layout, mode: LayoutCardView.Mode, selected: Bool, canDelete: Bool) -> LayoutCardView {
        LayoutCardView(
            layout: layout,
            displayTitle: runtime.document.presentationName(for: layout.id),
            mode: mode,
            selected: selected,
            canDelete: canDelete,
            onSelect: { [weak self] in self?.select(layout) },
            onEdit: { [weak self] in self?.edit(layout) },
            onDelete: { [weak self] in self?.confirmAndDelete(layout) }
        )
    }

    private func gridHeight() -> CGFloat {
        guard otherLayoutCount > 0 else { return 0 }
        return min(Metrics.maxGridHeight, LayoutGridView.height(forTileCount: otherLayoutCount))
    }

    private func updateGridFade() {
        guard let scroll = otherLayoutsScrollView else { return }
        otherLayoutsFade?.isHidden = !ConsoleScrollFade.shouldShow(for: scroll)
    }

    private func applyPanelFrame(under button: NSStatusBarButton) {
        guard let panel, let rootStack else { return }
        rootStack.layoutSubtreeIfNeeded()
        let size = NSSize(width: Metrics.width, height: ceil(rootStack.fittingSize.height))
        panel.minSize = size
        panel.maxSize = size
        panel.contentMinSize = size
        panel.contentMaxSize = size
        position(panel, under: button, size: size)
        updateGridFade()
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

    // MARK: - Dismissal

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

    // MARK: - Actions

    private func select(_ layout: Layout) {
        if let id = resolvedArea()?.display.id {
            runtime.selectLayout(layout, on: id)
        } else {
            runtime.selectLayout(layout)
        }
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

    private func confirmAndDelete(_ layout: Layout) {
        guard runtime.document.layouts.count > 1 else {
            NSSound.beep()
            return
        }
        let name = runtime.document.presentationName(for: layout.id)
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
        let profiles = runtime.document.orderedProfilesForSettings()
        saveWorkspaceButton?.isHidden = profiles.isEmpty
        workspaceStrip?.reload(
            profiles: profiles,
            activeID: runtime.document.activeProfileID,
            connectedDisplayIDs: Set(runtime.displays.workAreas.map(\.display.id)),
            beginRename: beginRename
        )
        if isShown, let statusButton {
            applyPanelFrame(under: statusButton)
        }
    }

    @objc
    private func saveCurrentWorkspace() {
        runtime.workspace.captureImmediately { [weak self] id in
            self?.reloadWorkspaceStrip(beginRename: id)
        }
    }

    private func confirmAndDeleteWorkspace(_ profile: WorkspaceProfile) {
        guard let panel else { return }
        WorkspaceDeleteConfirmation.present(for: panel, name: profile.name) { [weak self] in
            guard let self else { return }
            self.runtime.workspace.deleteProfile(id: profile.id)
            self.reloadWorkspaceStrip()
        }
    }

    @objc
    private func manageConsoleWorkspaces(_ sender: Any? = nil) {
        dismiss(handoff: { [runtime] in runtime.openWorkspaceSettings() })
    }

    @objc
    private func openWorkspaceSwitcher() {
        dismiss(handoff: { [runtime] in runtime.handleWorkspaceSwitcher(.invoke) })
    }

    @objc
    private func chooseDisplay(_ sender: NSButton) {
        let areas = runtime.displays.workAreas
        guard areas.count > 1 else { return }
        let menu = NSMenu()
        let current = resolvedArea()?.display.id
        for area in areas {
            let item = NSMenuItem(
                title: displayTitle(for: area),
                action: #selector(displayChosen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = area.display.id.uuidString
            item.state = area.display.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: menu.items.first, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
    }

    @objc
    private func displayChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        selectedDisplayID = id
        layoutRenderSignature = ""
        reload()
    }

    @objc
    private func openSettings() {
        dismiss(handoff: { [runtime] in runtime.openSettings() })
    }

    @objc
    private func openUpdateNotice() {
        runtime.updates.startUserRequestedUpdate()
    }

    private func applyUpdateNotice() {
        guard let button = updateNoticeButton else { return }
        guard let notice = runtime.updates.homeNotice else {
            button.isHidden = true
            return
        }
        let locale = LanguageCenter.language.locale
        let text: String
        switch notice {
        case .available(let version), .knownNewer(let version):
            text = String(format: L10n.text(.consoleUpdateFooterAvailable), locale: locale, version)
            button.role = .tinted
            button.symbolName = "arrow.down.circle.fill"
        case .downloading(let version, let percent):
            text = String(format: L10n.text(.consoleUpdateFooterDownloading), locale: locale, version, percent)
            button.role = .tinted
            button.symbolName = "arrow.down.circle"
        case .downloaded(let version):
            text = String(format: L10n.text(.consoleUpdateFooterDownloaded), locale: locale, version)
            button.role = .tinted
            button.symbolName = "checkmark.circle.fill"
        case .downloadFailed(let version):
            text = String(format: L10n.text(.consoleUpdateFooterFailed), locale: locale, version)
            button.role = .warning
            button.symbolName = "exclamationmark.triangle.fill"
        case .installing(let version):
            text = String(format: L10n.text(.consoleUpdateFooterInstalling), locale: locale, version)
            button.role = .tinted
            button.symbolName = "arrow.down.circle"
        case .installFailed(let version):
            text = String(format: L10n.text(.consoleUpdateFooterInstallFailed), locale: locale, version)
            button.role = .warning
            button.symbolName = "exclamationmark.triangle.fill"
        }
        button.title = text
        button.toolTip = text
        button.setAccessibilityLabel(text)
        button.isHidden = false
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

private extension NSView {
    static func wrapping(_ child: NSView, leading: CGFloat, trailing: CGFloat) -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        child.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: host.topAnchor),
            child.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: leading),
            child.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: trailing),
        ])
        return host
    }
}

private final class ConsoleBrandMark: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        widthAnchor.constraint(equalToConstant: 18).isActive = true
        heightAnchor.constraint(equalToConstant: 18).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        ConsoleChrome.brandBlue(dark: ConsoleChrome.isDark(effectiveAppearance)).setFill()
        let gap: CGFloat = 2
        let side = (min(bounds.width, bounds.height) - gap) / 2
        for row in 0..<2 {
            for column in 0..<2 {
                let rect = NSRect(
                    x: CGFloat(column) * (side + gap),
                    y: CGFloat(row) * (side + gap),
                    width: side,
                    height: side
                )
                NSBezierPath(roundedRect: rect, xRadius: 2.2, yRadius: 2.2).fill()
            }
        }
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

private final class ConsolePassthroughView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class ConsoleMaterialView: NSVisualEffectView {
    private let tint = ConsolePassthroughView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Metrics.panelCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        autoresizingMask = [.width, .height]
        maskImage = Self.roundedMaskImage(cornerRadius: Metrics.panelCornerRadius)
        tint.frame = bounds
        tint.autoresizingMask = [.width, .height]
        tint.layer?.cornerRadius = Metrics.panelCornerRadius
        tint.layer?.cornerCurve = .continuous
        tint.layer?.borderWidth = 1
        addSubview(tint)
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        tint.frame = bounds
        applyTint()
        window?.invalidateShadow()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }

    private func applyTint() {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        tint.layer?.backgroundColor = ConsoleChrome.panelTint(dark: dark).cgColor
        tint.layer?.borderColor = (dark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.08)).cgColor
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

private enum Metrics {
    static let width: CGFloat = 400
    static let panelCornerRadius: CGFloat = 16
    static let panelInsets = NSEdgeInsets(top: 12, left: 14, bottom: 8, right: 14)
    static let sectionGap: CGFloat = 14
    static let headerHeight: CGFloat = 32
    static let displayRowHeight: CGFloat = 24
    static let featuredHeight: CGFloat = 86
    static let sectionHeaderHeight: CGFloat = 24
    static let footerHeight: CGFloat = 28
    static let columns = 3
    static let rowSpacing: CGFloat = 8
    static let contentWidth = width - panelInsets.left - panelInsets.right
    static let compactWidth = floor((contentWidth - 16) / CGFloat(columns))
    static let columnSpacing = floor((contentWidth - compactWidth * CGFloat(columns)) / CGFloat(columns - 1))
    static let compactHeight: CGFloat = 100
    static let compactPlateHeight: CGFloat = 64
    static let featuredPlateSize = NSSize(width: 112, height: 70)
    static let platePadding: CGFloat = 5
    static let maxGridRows = 2
    static let maxGridHeight = compactHeight * CGFloat(maxGridRows) + rowSpacing * CGFloat(maxGridRows - 1)
}

private final class LayoutGridView: NSView {
    override var isFlipped: Bool { true }

    static func height(forTileCount count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = Int(ceil(Double(count) / Double(Metrics.columns)))
        return CGFloat(rows) * Metrics.compactHeight + CGFloat(rows - 1) * Metrics.rowSpacing
    }

    func setTiles(_ tiles: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        for tile in tiles {
            tile.translatesAutoresizingMaskIntoConstraints = true
            addSubview(tile)
        }
        needsLayout = true
        setFrameSize(NSSize(width: Metrics.contentWidth, height: Self.height(forTileCount: tiles.count)))
    }

    func reconcileHoverState() {
        for case let tile as LayoutCardView in subviews {
            tile.reconcileHoverState()
        }
    }

    override func layout() {
        super.layout()
        for (index, tile) in subviews.enumerated() {
            let row = index / Metrics.columns
            let col = index % Metrics.columns
            tile.frame = NSRect(
                x: CGFloat(col) * (Metrics.compactWidth + Metrics.columnSpacing),
                y: CGFloat(row) * (Metrics.compactHeight + Metrics.rowSpacing),
                width: Metrics.compactWidth,
                height: Metrics.compactHeight
            )
        }
        let height = Self.height(forTileCount: subviews.count)
        if abs(frame.height - height) > 0.5 || abs(frame.width - Metrics.contentWidth) > 0.5 {
            setFrameSize(NSSize(width: Metrics.contentWidth, height: height))
        }
        reconcileHoverState()
    }
}

private final class LayoutCardView: ConsoleInteractiveView {
    enum Mode {
        case featured
        case compact
    }

    private let sourceLayout: Layout
    private let mode: Mode
    private let selected: Bool
    private let canDelete: Bool
    private let onSelect: () -> Void
    private let onEdit: () -> Void
    private let onDelete: () -> Void
    private let title: String
    private var thumbnails: [String: NSImage] = [:]
    private let editButton: ConsoleButton
    private let moreButton: ConsoleButton

    init(
        layout: Layout,
        displayTitle: String? = nil,
        mode: Mode,
        selected: Bool,
        canDelete: Bool,
        onSelect: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.sourceLayout = layout
        self.mode = mode
        self.selected = selected
        self.canDelete = canDelete
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.title = displayTitle ?? L10n.layoutDisplayName(layout.name)
        let editTitle = L10n.text(.consoleEdit)
        let moreTitle = L10n.text(.consoleMore)
        if mode == .featured {
            editButton = ConsoleButton(role: .surface, title: editTitle, symbol: "pencil")
            editButton.controlHeight = 28
            editButton.horizontalPadding = 11
            moreButton = ConsoleButton(role: .surface, symbol: "ellipsis")
            moreButton.controlHeight = 28
        } else {
            editButton = ConsoleButton(role: .surface, symbol: "pencil")
            editButton.controlHeight = 22
            editButton.fontSize = 10
            moreButton = ConsoleButton(role: .surface, symbol: "ellipsis")
            moreButton.controlHeight = 22
            moreButton.fontSize = 10
        }
        let size = mode == .featured
            ? NSSize(width: Metrics.contentWidth, height: Metrics.featuredHeight)
            : NSSize(width: Metrics.compactWidth, height: Metrics.compactHeight)
        super.init(frame: NSRect(origin: .zero, size: size))
        translatesAutoresizingMaskIntoConstraints = true

        for (button, label, action) in [
            (editButton, editTitle, #selector(editTapped)),
            (moreButton, moreTitle, #selector(moreTapped)),
        ] {
            button.translatesAutoresizingMaskIntoConstraints = true
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.target = self
            button.action = action
            addSubview(button)
        }

        var parts = [title]
        if mode == .featured {
            parts.insert(L10n.text(.consoleCurrentLayout), at: 0)
            parts.append(selected ? L10n.text(.consoleInUse) : L10n.text(.consoleNotApplied))
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(parts.joined(separator: ", "))
        setAccessibilitySelected(selected)
        toolTip = title
        interactionStateDidChange()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        mode == .featured
            ? NSSize(width: Metrics.contentWidth, height: Metrics.featuredHeight)
            : NSSize(width: Metrics.compactWidth, height: Metrics.compactHeight)
    }

    override func interactionStateDidChange() {
        super.interactionStateDidChange()
        if mode == .compact {
            editButton.isHidden = !isHovering
            moreButton.isHidden = !isHovering
        }
    }

    override func layout() {
        super.layout()
        if mode == .featured {
            let side = moreButton.controlHeight
            let editWidth = editButton.intrinsicContentSize.width
            let y = ((bounds.height - side) / 2).rounded()
            moreButton.frame = NSRect(x: bounds.maxX - 12 - side, y: y, width: side, height: side)
            editButton.frame = NSRect(x: moreButton.frame.minX - 6 - editWidth, y: y, width: editWidth, height: side)
        } else {
            let side = moreButton.controlHeight
            let plate = compactPlateRect
            moreButton.frame = NSRect(x: plate.maxX - 3 - side, y: plate.maxY - 3 - side, width: side, height: side)
            editButton.frame = NSRect(x: moreButton.frame.minX - 3 - side, y: moreButton.frame.minY, width: side, height: side)
        }
    }

    override func performPrimaryAction() {
        onSelect()
    }

    override func showContextMenu(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
    }

    @objc private func editTapped() { onEdit() }

    @objc private func deleteTapped() { onDelete() }

    @objc private func moreTapped() {
        makeMenu().popUp(positioning: nil, at: NSPoint(x: moreButton.frame.minX, y: moreButton.frame.minY), in: self)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let edit = NSMenuItem(title: L10n.text(.consoleEdit), action: #selector(editTapped), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(.separator())
        let delete = NSMenuItem(title: L10n.text(.editorDelete), action: #selector(deleteTapped), keyEquivalent: "")
        delete.target = self
        delete.isEnabled = canDelete
        menu.addItem(delete)
        return menu
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        thumbnails.removeAll()
        needsDisplay = true
    }

    // MARK: Drawing

    private var compactPlateRect: NSRect {
        NSRect(
            x: 8,
            y: bounds.height - 8 - Metrics.compactPlateHeight,
            width: bounds.width - 16,
            height: Metrics.compactPlateHeight
        )
    }

    private var featuredPlateRect: NSRect {
        NSRect(
            x: 8,
            y: ((bounds.height - Metrics.featuredPlateSize.height) / 2).rounded(),
            width: Metrics.featuredPlateSize.width,
            height: Metrics.featuredPlateSize.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let radius: CGFloat = mode == .featured ? 12 : 10
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        let blue = ConsoleChrome.brandBlue(dark: dark)

        ConsoleChrome.surface(dark: dark).setFill()
        card.fill()
        if isPressed {
            ConsoleChrome.pressedWash(dark: dark).setFill()
            card.fill()
        } else if isHovering {
            ConsoleChrome.hoverWash(dark: dark).setFill()
            card.fill()
        } else if selected {
            blue.withAlphaComponent(dark ? 0.12 : 0.06).setFill()
            card.fill()
        }

        let border: NSColor
        if isHovering || isPressed {
            border = ConsoleChrome.hoverBorder(dark: dark)
        } else if selected {
            border = blue.withAlphaComponent(dark ? 0.5 : 0.35)
        } else {
            border = ConsoleChrome.surfaceBorder(dark: dark)
        }
        border.setStroke()
        card.lineWidth = 1
        card.stroke()

        let active = selected || isHovering || isPressed
        if mode == .featured {
            drawFeatured(dark: dark, active: active)
        } else {
            drawCompact(dark: dark, active: active)
        }
    }

    private func drawPlate(_ plate: NSRect, dark: Bool, active: Bool) {
        ConsoleChrome.screenPlate(dark: dark).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 6, yRadius: 6).fill()
        let preview = plate.insetBy(dx: Metrics.platePadding, dy: Metrics.platePadding)
        thumbnail(size: preview.size, dark: dark, active: active).draw(in: preview)
    }

    private func drawFeatured(dark: Bool, active: Bool) {
        let plate = featuredPlateRect
        drawPlate(plate, dark: dark, active: active)

        let textX = plate.maxX + 14
        let textWidth = max(24, editButton.frame.minX - 10 - textX)
        let top = bounds.midY + 27
        drawLine(
            L10n.text(.consoleCurrentLayout),
            font: .systemFont(ofSize: 11, weight: .medium),
            color: .secondaryLabelColor,
            rect: NSRect(x: textX, y: top - 14, width: textWidth, height: 14)
        )
        drawLine(
            title,
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: .labelColor,
            rect: NSRect(x: textX, y: top - 35, width: textWidth, height: 19)
        )
        let statusY = top - 54
        let statusFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        guard selected else {
            drawLine(
                L10n.text(.consoleNotApplied),
                font: statusFont,
                color: .secondaryLabelColor,
                rect: NSRect(x: textX, y: statusY, width: textWidth, height: 16)
            )
            return
        }
        let blue = ConsoleChrome.brandBlue(dark: dark)
        ConsoleChrome.symbol("checkmark.circle.fill", size: 12, weight: .semibold, color: blue)?
            .draw(in: NSRect(x: textX, y: statusY + 1, width: 13, height: 13))
        let status = NSMutableAttributedString(
            string: L10n.text(.consoleInUse),
            attributes: [.font: statusFont, .foregroundColor: blue]
        )
        status.append(NSAttributedString(
            string: "  ·  " + zoneCountText,
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        status.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: status.length))
        status.draw(in: NSRect(x: textX + 17, y: statusY, width: max(10, textWidth - 17), height: 16))
    }

    private var zoneCountText: String {
        let count = sourceLayout.zones.count
        if count == 1 { return L10n.text(.consoleZoneCountSingle) }
        return String(format: L10n.text(.consoleZoneCount), locale: LanguageCenter.language.locale, count)
    }

    private func drawCompact(dark: Bool, active: Bool) {
        drawPlate(compactPlateRect, dark: dark, active: active)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(
            in: NSRect(x: 6, y: 7, width: max(0, bounds.width - 12), height: 16),
            withAttributes: attributes
        )
    }

    private func drawLine(_ text: String, font: NSFont, color: NSColor, rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func thumbnail(size: NSSize, dark: Bool, active: Bool) -> NSImage {
        let key = "\(dark)-\(active)-\(Int(size.width))x\(Int(size.height))"
        if let cached = thumbnails[key] { return cached }
        let featured = mode == .featured
        let image = LayoutThumbnailRenderer.image(
            for: sourceLayout,
            size: size,
            fill: active ? ConsoleChrome.zoneActive(dark: dark) : ConsoleChrome.zoneIdle(dark: dark),
            stroke: .clear,
            gutterPoints: featured ? 4 : 3,
            showNumbers: true,
            numberColor: .white,
            cornerRadius: featured ? 4 : 3,
            lineWidth: 0,
            minimumNumberSize: 7.5,
            maximumNumberSize: featured ? 17 : 13
        )
        thumbnails[key] = image
        return image
    }
}
