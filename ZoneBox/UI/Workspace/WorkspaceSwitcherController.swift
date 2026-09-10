import AppKit
import ZoneBoxCore

@MainActor
final class WorkspaceSwitcherController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    unowned var runtime: WorkspaceSwitcherHosting!

    private var phase: WorkspaceSwitcherPhase = .hidden
    private var panel: SwitcherPanel?
    private var cardHost: NSStackView?
    private var titleLabel: NSTextField?
    private var hintLabel: NSTextField?
    private var nameField: NSTextField?
    private var summaryLabel: NSTextField?
    private var eventMonitors: [Any] = []
    private var activationObservers: [NSObjectProtocol] = []
    private var showingUI = false
    private var namingSeed = ""
    private var ignoreNameFieldChanges = false

    var isShowing: Bool { phase != .hidden }
    var isNaming: Bool {
        if case .naming = phase { return true }
        return false
    }

    func handle(_ event: WorkspaceSwitcherEvent) {
        if event == .invoke {
            guard runtime.requestProAccess(for: .workspace) else { return }
            if !runtime.isTrusted() {
                runtime.openAccessibility()
            }
        }
        let profiles = runtime.document.orderedProfilesForSettings()
        let preview = runtime.workspace.capturePreview()
        let output = WorkspaceSwitcherReducer.reduce(
            WorkspaceSwitcherInput(
                phase: phase,
                event: event,
                profileIDs: profiles.map(\.id),
                activeProfileID: runtime.document.activeProfileID,
                isIdle: runtime.mode == .idle && !runtime.isEditorOpen,
                trusted: runtime.isTrusted(),
                captureCount: preview.applicationCount,
                suggestedName: runtime.workspace.suggestedCaptureName()
            )
        )
        if case .naming(let text, _) = output.phase, event == .beginSave {
            namingSeed = text
        }
        phase = output.phase
        perform(output.effects)
        if isShowing {
            let skipRender: Bool
            if case .textChanged = event { skipRender = true } else { skipRender = false }
            if !skipRender {
                render()
            }
        }
    }

    func hide() {
        guard phase != .hidden else { return }
        phase = .hidden
        namingSeed = ""
        perform([.hide])
    }

    @discardableResult
    func hideIfShowing() -> Bool {
        guard isShowing else { return false }
        hide()
        return true
    }

    func displaysDidChange() {
        guard isShowing else { return }
        render()
    }

    func applyLanguage() {
        guard isShowing else { return }
        render()
    }

    private func perform(_ effects: [WorkspaceSwitcherEffect]) {
        for effect in effects {
            switch effect {
            case .show:
                present()
            case .hide:
                tearDown()
            case .apply(let id):
                runtime.closeConsole()
                runtime.workspace.apply(profileID: id)
            case .capture(let name):
                runtime.workspace.capture(name: name)
            case .updateProfile(let id):
                runtime.workspace.updateProfileFromCurrent(id: id)
            case .beep:
                NSSound.beep()
            }
        }
    }

    private func present() {
        if panel == nil {
            panel = makePanel()
        }
        render()
        positionOnPointerDisplay()
        panel?.orderFrontRegardless()
        panel?.makeKey()
        startDismissMonitors()
        noteShowing(true)
    }

    private func tearDown() {
        stopDismissMonitors()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        cardHost = nil
        titleLabel = nil
        hintLabel = nil
        nameField = nil
        summaryLabel = nil
        noteShowing(false)
    }

    private func noteShowing(_ showing: Bool) {
        guard showingUI != showing else { return }
        showingUI = showing
        runtime.noteWorkspaceSwitcherUI(showing: showing)
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.minHeight),
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
        let root = SwitcherMaterialView(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.minHeight))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        let title = NSTextField(labelWithString: L10n.text(.workspaceSwitcherTitle))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        titleLabel = title

        let hint = NSTextField(labelWithString: L10n.text(.workspaceSwitcherHint))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hintLabel = hint

        let header = NSStackView(views: [title, hint])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 10
        title.setContentHuggingPriority(.required, for: .horizontal)
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let cards = NSStackView()
        cards.orientation = .vertical
        cards.alignment = .leading
        cards.spacing = Metrics.rowSpacing
        cards.translatesAutoresizingMaskIntoConstraints = false
        cardHost = cards

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(cards)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        return root
    }

    private func render() {
        guard let cardHost else { return }
        titleLabel?.stringValue = L10n.text(.workspaceSwitcherTitle)
        hintLabel?.stringValue = L10n.text(.workspaceSwitcherHint)
        cardHost.arrangedSubviews.forEach {
            cardHost.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        nameField = nil
        summaryLabel = nil

        switch phase {
        case .hidden:
            break
        case .naming(let text, _):
            cardHost.addArrangedSubview(makeNamingView(text: text))
        case .browsing(let highlight):
            let profiles = runtime.document.orderedProfilesForSettings()
            if profiles.isEmpty {
                cardHost.addArrangedSubview(makeEmptyCard())
            } else {
                for row in stride(from: 0, to: profiles.count, by: Metrics.columns) {
                    let rowView = NSStackView()
                    rowView.orientation = .horizontal
                    rowView.spacing = Metrics.columnSpacing
                    rowView.alignment = .top
                    for column in 0..<Metrics.columns {
                        let index = row + column
                        if index < profiles.count {
                            rowView.addArrangedSubview(
                                makeCard(profiles[index], index: index, highlighted: index == highlight)
                            )
                        } else {
                            let spacer = NSView()
                            spacer.translatesAutoresizingMaskIntoConstraints = false
                            spacer.widthAnchor.constraint(equalToConstant: Metrics.cardWidth).isActive = true
                            rowView.addArrangedSubview(spacer)
                        }
                    }
                    cardHost.addArrangedSubview(rowView)
                }
            }
        }
        resizePanel()
        if case .naming = phase {
            scheduleNameFieldFocus()
        }
    }

    private func makeNamingView(text: String) -> NSView {
        let field = NSTextField(string: text.isEmpty ? namingSeed : text)
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = L10n.text(.workspaceNamePlaceholder)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 24).isActive = true
        nameField = field
        let preview = runtime.workspace.capturePreview()
        let summary = NSTextField(wrappingLabelWithString: summaryText(preview))
        summary.font = .systemFont(ofSize: 12)
        summary.textColor = preview.applicationCount == 0 ? .systemOrange : .secondaryLabelColor
        summaryLabel = summary
        field.isEnabled = preview.applicationCount > 0
        let stack = NSStackView(views: [field, summary])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: Metrics.contentWidth).isActive = true
        summary.widthAnchor.constraint(equalToConstant: Metrics.contentWidth).isActive = true
        return stack
    }

    private func summaryText(_ preview: (applicationCount: Int, displayCount: Int)) -> String {
        if preview.applicationCount == 0 {
            return L10n.text(.workspaceSwitcherSaveEmpty)
        }
        return String(
            format: L10n.text(.workspaceSwitcherSaveSummary),
            preview.applicationCount,
            preview.displayCount
        )
    }

    private func makeEmptyCard() -> NSView {
        let card = SwitcherEmptyCard()
        card.title = L10n.text(.workspaceSwitcherEmptyAction)
        card.detail = L10n.text(.workspaceSwitcherEmptyDetail)
        card.onSelect = { [weak self] in self?.handle(.beginSave) }
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: Metrics.contentWidth).isActive = true
        card.heightAnchor.constraint(equalToConstant: 72).isActive = true
        return card
    }

    private func makeCard(_ profile: WorkspaceProfile, index: Int, highlighted: Bool) -> NSView {
        let connectedIDs = Set(runtime.workAreas.map(\.display.id))
        let disconnected = profile.sections.contains { !connectedIDs.contains($0.space.displayID) }
        let card = SwitcherProfileCard(
            profile: profile,
            number: index < 9 ? index + 1 : nil,
            highlighted: highlighted,
            isCurrent: profile.id == runtime.document.activeProfileID,
            disconnected: disconnected,
            layouts: Dictionary(uniqueKeysWithValues: runtime.document.layouts.map { ($0.id, $0) }),
            applicationInfo: applicationInfo(for: profile),
            onSelect: { [weak self] in
                self?.phase = .hidden
                self?.perform([.hide, .apply(profile.id)])
            },
            onUpdate: { [weak self] in
                self?.phase = .hidden
                self?.perform([.hide, .updateProfile(profile.id)])
            },
            onRename: { [weak self] in self?.rename(profile) },
            onDelete: { [weak self] in self?.delete(profile) }
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: Metrics.cardWidth).isActive = true
        card.heightAnchor.constraint(equalToConstant: Metrics.cardHeight).isActive = true
        let label = [
            card.number.map(String.init),
            profile.name,
            profile.id == runtime.document.activeProfileID ? L10n.text(.workspaceSwitcherCurrent) : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        card.setAccessibilityLabel(label)
        return card
    }

    private func applicationInfo(for profile: WorkspaceProfile) -> [String: (name: String, icon: NSImage?)] {
        let ids = profile.sections.flatMap(\.rules).map(\.bundleID)
        return WorkspaceApplicationInfo.info(for: ids)
    }

    private func rename(_ profile: WorkspaceProfile) {
        guard var profile = runtime.document.profiles.first(where: { $0.id == profile.id }) else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text(.workspaceCardRename)
        let field = NSTextField(string: profile.name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text(.workspaceSave))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        guard let panel else { return }
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            profile.name = LayoutEditTransaction.uniqueName(
                base: name,
                existingNames: self.runtime.document.profiles.filter { $0.id != profile.id }.map(\.name)
            )
            self.runtime.workspace.updateProfile(profile)
            self.render()
        }
    }

    private func delete(_ profile: WorkspaceProfile) {
        let alert = NSAlert()
        alert.messageText = String(format: L10n.text(.settingsWorkspaceDeleteTitle), profile.name)
        alert.addButton(withTitle: L10n.text(.settingsWorkspaceDelete))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        alert.buttons.first?.hasDestructiveAction = true
        guard let panel else { return }
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.runtime.workspace.deleteProfile(id: profile.id)
            if self.runtime.document.profiles.isEmpty {
                self.phase = .browsing(highlight: 0)
            } else if case .browsing(let highlight) = self.phase {
                self.phase = .browsing(
                    highlight: min(highlight, max(self.runtime.document.profiles.count - 1, 0))
                )
            }
            self.render()
        }
    }

    private func resizePanel() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let fitting = content.fittingSize
        let size = NSSize(width: Metrics.width, height: max(fitting.height, Metrics.minHeight))
        var frame = panel.frame
        frame.size = size
        panel.setFrame(frame, display: true)
        content.setFrameSize(size)
        panel.invalidateShadow()
        positionOnPointerDisplay()
    }

    private func positionOnPointerDisplay() {
        guard let panel else { return }
        let area = runtime.area(containingAppKit: NSEvent.mouseLocation) ?? runtime.workAreas.first
        let screen = area.flatMap { runtime.screen(for: $0.display.id) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func scheduleNameFieldFocus() {
        DispatchQueue.main.async { [weak self] in
            self?.focusNameField()
        }
    }

    private func focusNameField() {
        guard case .naming = phase, let field = nameField, let panel, panel.isVisible else { return }
        ignoreNameFieldChanges = true
        let seed = namingSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || Self.isSwitcherTriggerGlyph(current) {
            field.stringValue = seed
        }
        field.delegate = self
        if field.isEnabled {
            panel.makeFirstResponder(field)
            field.selectText(nil)
        }
        ignoreNameFieldChanges = false
    }

    private static func isSwitcherTriggerGlyph(_ text: String) -> Bool {
        text.count == 1 && "sSuU".contains(text)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !ignoreNameFieldChanges, let field = obj.object as? NSTextField else { return }
        handle(.textChanged(field.stringValue))
    }

    func windowDidResignKey(_ notification: Notification) {
        if isShowing, panel?.attachedSheet == nil {
            hide()
        }
    }

    private func startDismissMonitors() {
        stopDismissMonitors()
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                self?.handleOutsideClick(event)
            }
        ) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                self?.handleOutsideClick(event)
                return event
            }
        ) {
            eventMonitors.append(monitor)
        }
        let resign = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
                Task { @MainActor in self.hide() }
            }
        }
        activationObservers.append(resign)
    }

    private func stopDismissMonitors() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        for observer in activationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        activationObservers.removeAll()
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard isShowing, let panel, panel.isVisible else { return }
        if panel.frame.contains(NSEvent.mouseLocation) { return }
        if let sheet = panel.attachedSheet, sheet.frame.contains(NSEvent.mouseLocation) { return }
        hide()
    }

    private enum Metrics {
        static let width: CGFloat = 492
        static let minHeight: CGFloat = 160
        static let columns = 3
        static let columnSpacing: CGFloat = 10
        static let rowSpacing: CGFloat = 10
        static let contentWidth: CGFloat = width - 28
        static let cardWidth: CGFloat = (contentWidth - columnSpacing * 2) / 3
        static let cardHeight: CGFloat = 132
        static let previewSize = NSSize(width: 132, height: 64)
    }
}

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? WorkspaceSwitcherController)?.handle(.dismiss)
    }
}

private final class SwitcherMaterialView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SwitcherEmptyCard: NSView {
    var title = ""
    var detail = ""
    var onSelect: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let titleRect = NSRect(x: 12, y: bounds.midY + 2, width: bounds.width - 24, height: 18)
        let detailRect = NSRect(x: 12, y: bounds.midY - 18, width: bounds.width - 24, height: 16)
        (title as NSString).draw(in: titleRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor,
        ])
        (detail as NSString).draw(in: detailRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}

private final class SwitcherProfileCard: NSView {
    let profile: WorkspaceProfile
    let number: Int?
    let highlighted: Bool
    let isCurrent: Bool
    let disconnected: Bool
    let onSelect: () -> Void
    let onUpdate: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    private var hovering = false
    private let menuButton = NSButton()

    init(
        profile: WorkspaceProfile,
        number: Int?,
        highlighted: Bool,
        isCurrent: Bool,
        disconnected: Bool,
        layouts: [Layout.ID: Layout],
        applicationInfo: [String: (name: String, icon: NSImage?)],
        onSelect: @escaping () -> Void,
        onUpdate: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.profile = profile
        self.number = number
        self.highlighted = highlighted
        self.isCurrent = isCurrent
        self.disconnected = disconnected
        self.onSelect = onSelect
        self.onUpdate = onUpdate
        self.onRename = onRename
        self.onDelete = onDelete
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        setAccessibilityRole(.button)
        build(layouts: layouts, applicationInfo: applicationInfo)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(layouts: [Layout.ID: Layout], applicationInfo: [String: (name: String, icon: NSImage?)]) {
        let previewRow = NSStackView()
        previewRow.orientation = .horizontal
        previewRow.spacing = 4
        previewRow.alignment = .centerY
        let sections = Array(profile.sections.prefix(2))
        for section in sections {
            let preview = WorkspaceLayoutPreviewView(
                layout: layouts[section.layoutID],
                rules: section.rules,
                applicationInfo: applicationInfo,
                canvasSize: NSSize(width: 64, height: 36)
            )
            previewRow.addArrangedSubview(preview)
        }
        if profile.sections.count > 2 {
            let extra = NSTextField(labelWithString: "+(profile.sections.count - 2)")
            extra.font = .systemFont(ofSize: 10, weight: .medium)
            extra.textColor = .secondaryLabelColor
            previewRow.addArrangedSubview(extra)
        }

        let icons = NSStackView()
        icons.orientation = .horizontal
        icons.spacing = 2
        let bundleIDs = Array(NSOrderedSet(array: profile.sections.flatMap(\.rules).map(\.bundleID)).compactMap { $0 as? String })
        for bundleID in bundleIDs.prefix(5) {
            let view = NSImageView(image: applicationInfo[bundleID]?.icon ?? NSImage())
            view.imageScaling = .scaleProportionallyDown
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: 14).isActive = true
            view.heightAnchor.constraint(equalToConstant: 14).isActive = true
            icons.addArrangedSubview(view)
        }
        if bundleIDs.count > 5 {
            let extra = NSTextField(labelWithString: "+(bundleIDs.count - 5)")
            extra.font = .systemFont(ofSize: 9)
            extra.textColor = .secondaryLabelColor
            icons.addArrangedSubview(extra)
        }

        let name = NSTextField(labelWithString: profile.name)
        name.font = .systemFont(ofSize: 11, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [previewRow, name, icons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 8, bottom: 8, right: 8)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if let number {
            let badge = NSTextField(labelWithString: String(number))
            badge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            badge.textColor = .labelColor
            badge.wantsLayer = true
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                badge.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            ])
        }
        if isCurrent {
            let current = NSTextField(labelWithString: L10n.text(.workspaceSwitcherCurrent))
            current.font = .systemFont(ofSize: 9, weight: .semibold)
            current.textColor = .controlAccentColor
            current.translatesAutoresizingMaskIntoConstraints = false
            addSubview(current)
            NSLayoutConstraint.activate([
                current.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                current.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            ])
        }
        if disconnected {
            let warning = NSImageView(
                image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: L10n.text(.workspaceSwitcherDisconnected)) ?? NSImage()
            )
            warning.contentTintColor = .systemOrange
            warning.toolTip = L10n.text(.workspaceSwitcherDisconnected)
            warning.translatesAutoresizingMaskIntoConstraints = false
            addSubview(warning)
            NSLayoutConstraint.activate([
                warning.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                warning.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
                warning.widthAnchor.constraint(equalToConstant: 12),
                warning.heightAnchor.constraint(equalToConstant: 12),
            ])
        }

        menuButton.bezelStyle = .inline
        menuButton.isBordered = false
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L10n.text(.workspaceCardRename))
        menuButton.imagePosition = .imageOnly
        menuButton.target = self
        menuButton.action = #selector(showMenu)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.isHidden = true
        addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            menuButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            menuButton.widthAnchor.constraint(equalToConstant: 18),
            menuButton.heightAnchor.constraint(equalToConstant: 18),
        ])
        alphaValue = disconnected ? 0.55 : 1
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        menuButton.isHidden = false
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        menuButton.isHidden = true
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !menuButton.isHidden, menuButton.frame.contains(point) {
            showMenu()
            return
        }
        onSelect()
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = highlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.22)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.55)
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        if highlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            let stroke = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            stroke.lineWidth = 1.5
            stroke.stroke()
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

    @objc private func updateTapped() { onUpdate() }
    @objc private func renameTapped() { onRename() }
    @objc private func deleteTapped() { onDelete() }
}
