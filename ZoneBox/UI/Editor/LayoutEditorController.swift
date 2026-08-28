import AppKit
import ZoneBoxCore

@MainActor
final class LayoutEditorController: NSObject {
    private unowned let runtime: AppRuntime
    private let targetDisplayID: DisplayIdentity.ID
    private let isNew: Bool
    private var panel: EditorPanel?
    private var canvas: LayoutEditorCanvasView?
    private var toolbar: NSView?
    private var saveButton: EditorChipButton?
    private var cancelButton: EditorChipButton?
    private var deleteButton: EditorChipButton?
    private var saveNameAlert: NSAlert?
    private var presetButtons: [EditorChipButton] = []
    private var selectedPresetIndex: Int?
    private var savedLayoutButton: EditorChipButton?
    private var savedToolbarLayout: Layout?
    private var selectedSavedLayout = false
    private var hintLabel: NSTextField?
    private var protectionLabel: NSTextField?
    private let original: Layout
    private var transaction: LayoutEditTransaction?
    private var appSwitchObservations: [Any] = []
    private var canCancelOnAppSwitch = false

    private enum SaveNamePromptKind {
        case newLayout
        case copy(warnsUnchanged: Bool)

        var createsCopy: Bool {
            if case .copy = self { return true }
            return false
        }
    }

    init(runtime: AppRuntime, layout: Layout, targetDisplayID: DisplayIdentity.ID, isNew: Bool) {
        self.runtime = runtime
        self.targetDisplayID = targetDisplayID
        self.isNew = isNew
        self.original = layout
        super.init()
    }

    func show(on screen: NSScreen) {
        runtime.isEditorOpen = true
        runtime.overlay.hideAll()
        runtime.uiSession.enterRegular()

        let panel = EditorPanel(screen: screen)
        let flip = runtime.displays.primaryFlipHeight
        let workAX = CoordinateConverter.axRect(fromAppKit: screen.visibleFrame, primaryFlipHeight: flip)
        var draft = original
        if draft.kind == .grid {
            draft = (try? draft.convertingGridToCanvas(workAreaAX: workAX)) ?? draft
        }
        transaction = LayoutEditTransaction(
            original: isNew ? nil : original,
            draft: draft,
            targetDisplayID: targetDisplayID
        )
        savedToolbarLayout = LayoutTemplates.editorToolbarSavedLayout(
            original: isNew ? nil : original,
            isNew: isNew,
            workAreaAX: workAX
        )
        selectedPresetIndex = LayoutTemplates.matchingEditorPresetIndex(for: draft, workAreaAX: workAX)
        selectedSavedLayout = savedToolbarLayout != nil

        let canvas = LayoutEditorCanvasView(layout: draft, workAreaAX: workAX, primaryFlipHeight: flip)
        canvas.selectFirstZone()
        canvas.onChange = { [weak self] layout in self?.updateDraft(layout) }
        canvas.onCancel = { [weak self] in self?.cancel() }
        canvas.onInteractionChange = { [weak self] active in self?.setToolbarReceded(active) }
        canvas.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = makeToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        self.toolbar = toolbar

        let root = NSView()
        root.addSubview(canvas)
        root.addSubview(toolbar)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = root
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            toolbar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            toolbar.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
            canvas.topAnchor.constraint(equalTo: root.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        panel.onEscape = { [weak self] in self?.cancel() }
        panel.onCycleZones = { [weak canvas] forward in
            canvas?.cycleSelection(forward: forward)
        }
        panel.onSaveCopy = { [weak self] in self?.saveCopyShortcut() }
        panel.delegate = self
        self.panel = panel
        self.canvas = canvas
        updateSaveState()
        makeEditorKey(panel: panel, canvas: canvas)
        observeAppSwitchToCancel()
    }

    func activate() {
        guard let panel, let canvas else { return }
        makeEditorKey(panel: panel, canvas: canvas)
    }

    func owns(_ window: NSWindow) -> Bool {
        panel === window
    }

    var isKey: Bool { panel?.isKeyWindow == true }

    var originalLayoutID: Layout.ID { original.id }

    @discardableResult
    func handleLocalKey(_ event: NSEvent) -> Bool {
        if ShortcutCatalog.editorSaveChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        ) {
            saveCopyShortcut()
            return true
        }
        if event.keyCode == HardwareKeyCode.return || event.keyCode == HardwareKeyCode.keypadEnter {
            save()
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifiers = !flags.subtracting(.shift).isEmpty
        switch event.keyCode {
        case HardwareKeyCode.a:
            guard !hasModifiers else { break }
            if event.isARepeat { return true }
            canvas?.moveSelection(.left)
            return true
        case HardwareKeyCode.d:
            guard !hasModifiers else { break }
            if event.isARepeat { return true }
            canvas?.moveSelection(.right)
            return true
        case HardwareKeyCode.w:
            guard !hasModifiers else { break }
            if event.isARepeat { return true }
            canvas?.moveSelection(.up)
            return true
        case HardwareKeyCode.s:
            guard !hasModifiers else { break }
            if event.isARepeat { return true }
            canvas?.moveSelection(.down)
            return true
        default:
            break
        }
        return canvas?.handleKeyEvent(event) ?? false
    }

    private func makeEditorKey(panel: EditorPanel, canvas: LayoutEditorCanvasView) {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(canvas)
        DispatchQueue.main.async { [weak panel, weak canvas] in
            guard let panel, let canvas else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(canvas)
        }
    }

    private func makeToolbar() -> NSView {
        let bar = EditorToolbarChrome()

        let presets = NSStackView()
        presets.orientation = .horizontal
        presets.spacing = 6
        presets.setHuggingPriority(.defaultHigh, for: .horizontal)
        presetButtons = []
        for (key, symbol, action) in [
            (L10nKey.editorColumns2, "rectangle.split.2x1", #selector(presetColumns2)),
            (L10nKey.editorColumns3, "rectangle.split.3x1", #selector(presetColumns3)),
            (L10nKey.editorRows2, "rectangle.split.1x2", #selector(presetRows2)),
            (L10nKey.editorGrid2x2, "square.grid.2x2", #selector(presetGrid)),
            (L10nKey.editorPriority, "rectangle.leadinghalf.inset.filled", #selector(presetPriority)),
            (L10nKey.editorFocus, "rectangle.center.inset.filled", #selector(presetFocus)),
        ] as [(L10nKey, String, Selector)] {
            let button = EditorChipButton(title: L10n.text(key), symbol: symbol, target: self, action: action, kind: .preset)
            presets.addArrangedSubview(button)
            presetButtons.append(button)
        }
        savedLayoutButton = nil
        if let saved = savedToolbarLayout {
            let button = EditorChipButton(
                title: savedLayoutChipTitle(saved.name),
                symbol: nil,
                target: self,
                action: #selector(applySavedToolbarLayout),
                kind: .preset
            )
            button.toolTip = L10n.layoutDisplayName(saved.name)
            button.setThumbnail(from: saved)
            presets.addArrangedSubview(button)
            savedLayoutButton = button
        }
        refreshPresetSelection()

        let saveTitle = !isNew && original.kind == .grid ? L10n.text(.editorSaveCopy) : L10n.text(.editorSave)
        let save = EditorChipButton(title: saveTitle, symbol: nil, target: self, action: #selector(save), kind: .save)
        saveButton = save
        let cancel = EditorChipButton(title: L10n.text(.editorCancel), symbol: nil, target: self, action: #selector(cancel), kind: .cancel)
        cancelButton = cancel
        var actionViews: [NSView] = [save, cancel]
        if canDeleteOriginal {
            let delete = EditorChipButton(
                title: L10n.text(.editorDelete),
                symbol: "trash",
                target: self,
                action: #selector(deleteOriginal),
                kind: .delete
            )
            delete.toolTip = L10n.text(.editorDeleteTooltip)
            deleteButton = delete
            actionViews.append(delete)
        }
        let actions = NSStackView(views: actionViews)
        actions.orientation = .horizontal
        actions.spacing = 6

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 12
        topRow.addArrangedSubview(presets)
        topRow.addArrangedSubview(actions)
        topRow.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        topRow.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let topRowCenter = NSView()
        topRowCenter.translatesAutoresizingMaskIntoConstraints = false
        topRowCenter.addSubview(topRow)
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: topRowCenter.topAnchor),
            topRow.bottomAnchor.constraint(equalTo: topRowCenter.bottomAnchor),
            topRow.centerXAnchor.constraint(equalTo: topRowCenter.centerXAnchor),
            topRow.leadingAnchor.constraint(greaterThanOrEqualTo: topRowCenter.leadingAnchor),
            topRow.trailingAnchor.constraint(lessThanOrEqualTo: topRowCenter.trailingAnchor),
        ])

        let hint = NSTextField(wrappingLabelWithString: L10n.text(.editorHint))
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.92)
        hint.alignment = .center
        hint.isBezeled = false
        hint.drawsBackground = false
        hint.isSelectable = false
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hintLabel = hint

        var rows: [NSView] = [topRowCenter]
        if !isNew && original.kind == .grid {
            let protection = NSTextField(wrappingLabelWithString: L10n.text(.editorGridProtected))
            protection.font = .systemFont(ofSize: 12, weight: .semibold)
            protection.textColor = .systemOrange
            protection.alignment = .center
            protection.isBezeled = false
            protection.drawsBackground = false
            protection.isSelectable = false
            protection.lineBreakMode = .byWordWrapping
            protection.maximumNumberOfLines = 2
            protection.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            protection.isHidden = true
            protectionLabel = protection
            rows.append(protection)
        }
        rows.append(hint)

        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .width
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            column.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            column.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -10),
        ])
        return bar
    }

    private func applyPreset(_ layout: Layout, index: Int) {
        applyDraftLayout(layout)
        selectedPresetIndex = index
        selectedSavedLayout = false
        refreshPresetSelection()
    }

    @objc private func presetColumns2() { applyPreset(LayoutTemplates.columns(2), index: 0) }
    @objc private func presetColumns3() { applyPreset(LayoutTemplates.columns(3), index: 1) }
    @objc private func presetRows2() { applyPreset(LayoutTemplates.rows(2), index: 2) }
    @objc private func presetGrid() { applyPreset(LayoutTemplates.grid2x2(), index: 3) }
    @objc private func presetPriority() { applyPreset(LayoutTemplates.priority3(), index: 4) }
    @objc private func presetFocus() { applyPreset(LayoutTemplates.focus(), index: 5) }

    @objc private func applySavedToolbarLayout() {
        guard let saved = savedToolbarLayout else { return }
        applyDraftLayout(saved)
        selectedPresetIndex = nil
        selectedSavedLayout = true
        refreshPresetSelection()
    }

    private func refreshPresetSelection() {
        for (index, button) in presetButtons.enumerated() {
            button.setPresetSelected(index == selectedPresetIndex)
        }
        savedLayoutButton?.setPresetSelected(selectedSavedLayout)
    }

    private func savedLayoutChipTitle(_ storedName: String) -> String {
        let title = L10n.layoutDisplayName(storedName)
        guard title.count > 18 else { return title }
        return String(title.prefix(17)) + "..."
    }

    private func applyDraftLayout(_ layout: Layout) {
        guard var transaction else { return }
        var draft = layout
        draft.id = transaction.draft.id
        draft.name = transaction.draft.name
        draft.createdAt = transaction.draft.createdAt
        if draft.kind == .grid, let workAreaAX = canvas?.workAreaAX {
            draft = (try? draft.convertingGridToCanvas(workAreaAX: workAreaAX)) ?? draft
        }
        transaction.updateDraft(draft)
        self.transaction = transaction
        canvas?.layout = draft
        canvas?.selectFirstZone()
        canvas?.needsDisplay = true
        updateSaveState()
    }

    @objc private func save() {
        guard let transaction = validTransactionForSave() else { return }
        if isNew {
            promptForSaveName(defaultName: transaction.draft.name, kind: .newLayout)
            return
        }
        if !isNew, original.kind == .grid {
            promptForCopyName(transaction)
            return
        }
        commitSave(requestedName: nil, createsCopy: false)
    }

    private func saveCopyShortcut() {
        guard let transaction = validTransactionForSave() else { return }
        Log.hotkey.info("Editor save-copy shortcut invoked newLayout=\(self.isNew, privacy: .public)")
        if isNew {
            promptForSaveName(defaultName: transaction.draft.name, kind: .newLayout)
        } else {
            promptForCopyName(transaction)
        }
    }

    private func validTransactionForSave() -> LayoutEditTransaction? {
        guard let transaction, transaction.canCommit else {
            NSSound.beep()
            return nil
        }
        guard transaction.targetIsAvailable(in: runtime.displays.activeDisplayIDs) else {
            NSSound.beep()
            return nil
        }
        return transaction
    }

    private func promptForCopyName(_ transaction: LayoutEditTransaction) {
        let presets = LayoutTemplates.editorPresets()
        let sourceName = selectedPresetIndex.flatMap { index in
            presets.indices.contains(index) ? presets[index].name : nil
        }
        promptForSaveName(
            defaultName: transaction.suggestedCopyName(
                sourceName: sourceName,
                existingNames: runtime.document.layouts.map(\.name)
            ),
            kind: .copy(warnsUnchanged: !transaction.hasChanges)
        )
    }

    private func promptForSaveName(defaultName: String, kind: SaveNamePromptKind) {
        guard saveNameAlert == nil, let panel else { return }

        let alert = NSAlert()
        switch kind {
        case .newLayout:
            alert.messageText = L10n.text(.editorSaveNameTitle)
            alert.informativeText = L10n.text(.editorSaveNameMessage)
        case .copy(let warnsUnchanged):
            alert.messageText = L10n.text(.editorCopyNameTitle)
            alert.informativeText = L10n.text(
                warnsUnchanged ? .editorCopyUnchangedMessage : .editorCopyNameMessage
            )
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text(.editorCopyNameConfirm))
        alert.addButton(withTitle: L10n.text(.editorCancel))

        let field = NSTextField(string: defaultName)
        field.placeholderString = L10n.text(.editorCopyNamePlaceholder)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        saveNameAlert = alert
        alert.beginSheetModal(for: panel) { [weak self, weak alert] response in
            guard let self, let alert else { return }
            Task { @MainActor in
                guard self.saveNameAlert === alert else { return }
                self.saveNameAlert = nil
                guard response == .alertFirstButtonReturn else {
                    self.panel?.makeFirstResponder(self.canvas)
                    return
                }
                let enteredName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.commitSave(
                    requestedName: enteredName.isEmpty ? defaultName : enteredName,
                    createsCopy: kind.createsCopy
                )
            }
        }
        DispatchQueue.main.async { [weak alert, weak field] in
            guard let alert, let field else { return }
            alert.window.makeFirstResponder(field)
            field.selectText(nil)
        }
    }

    private func commitSave(requestedName: String?, createsCopy: Bool) {
        guard let transaction else { return }
        if let layout = transaction.layoutForCommit(
            existingNames: runtime.document.layouts.map(\.name),
            requestedName: requestedName,
            createsCopy: createsCopy
        ) {
            guard runtime.saveLayout(layout, to: transaction.targetDisplayID) else {
                NSSound.beep()
                return
            }
        }
        dismiss()
    }

    @objc func cancel() {
        dismiss()
    }

    func cancelEditing() {
        dismiss()
    }

    private var canDeleteOriginal: Bool {
        !isNew && runtime.document.layouts.count > 1
    }

    @objc private func deleteOriginal() {
        guard canDeleteOriginal else {
            NSSound.beep()
            return
        }
        let name = L10n.layoutDisplayName(original.name)
        let alert = NSAlert()
        alert.messageText = String(format: L10n.text(.menuDeleteLayoutTitle), name)
        alert.informativeText = L10n.text(.menuDeleteLayoutMessage)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text(.menuDeleteLayoutConfirm))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        guard let panel else { return }
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                if !self.runtime.deleteLayout(self.original) {
                    NSSound.beep()
                }
            }
        }
    }

    func applyLanguage() {
        let keys: [L10nKey] = [
            .editorColumns2, .editorColumns3, .editorRows2, .editorGrid2x2, .editorPriority, .editorFocus,
        ]
        for (button, key) in zip(presetButtons, keys) {
            button.setChipTitle(L10n.text(key))
        }
        if let saved = savedToolbarLayout {
            savedLayoutButton?.setChipTitle(savedLayoutChipTitle(saved.name))
            savedLayoutButton?.toolTip = L10n.layoutDisplayName(saved.name)
        }
        refreshPresetSelection()
        let saveTitle = !isNew && original.kind == .grid ? L10n.text(.editorSaveCopy) : L10n.text(.editorSave)
        saveButton?.setChipTitle(saveTitle)
        cancelButton?.setChipTitle(L10n.text(.editorCancel))
        deleteButton?.setChipTitle(L10n.text(.editorDelete))
        deleteButton?.toolTip = L10n.text(.editorDeleteTooltip)
        hintLabel?.stringValue = L10n.text(.editorHint)
        protectionLabel?.stringValue = L10n.text(.editorGridProtected)
        updateSaveState()
    }

    private func updateDraft(_ layout: Layout) {
        transaction?.updateDraft(layout)
        updateSaveState()
    }

    fileprivate func chipHoverChanged(_ button: EditorChipButton, hovering: Bool) {
        guard button === saveButton, !isNew, original.kind == .grid else { return }
        protectionLabel?.isHidden = !hovering
    }

    private func updateSaveState() {
        guard let transaction else { return }
        saveButton?.isEnabled = transaction.canCommit
        saveButton?.toolTip = nil
    }

    private func setToolbarReceded(_ receded: Bool) {
        guard let toolbar else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = receded ? 0.12 : 0.2
            toolbar.animator().alphaValue = receded ? 0.12 : 1
        }
    }

    private func observeAppSwitchToCancel() {
        stopObservingAppSwitch()
        canCancelOnAppSwitch = false
        let resign = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.handleAppResign() }
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
        appSwitchObservations = [resign, switchApp]
        DispatchQueue.main.async { [weak self] in
            self?.canCancelOnAppSwitch = true
        }
    }

    private func stopObservingAppSwitch() {
        canCancelOnAppSwitch = false
        for observation in appSwitchObservations {
            NotificationCenter.default.removeObserver(observation)
            NSWorkspace.shared.notificationCenter.removeObserver(observation)
        }
        appSwitchObservations.removeAll()
    }

    private func handleAppResign() {
        guard canCancelOnAppSwitch, panel != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let controller = self else { return }
            guard controller.canCancelOnAppSwitch, controller.panel != nil, !NSApp.isActive else { return }
            controller.cancel()
        }
    }

    private func handleOtherAppActivated(_ app: NSRunningApplication?) {
        guard canCancelOnAppSwitch, panel != nil else { return }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        cancel()
    }

    private func dismiss() {
        guard panel != nil else { return }
        stopObservingAppSwitch()
        dismissSaveNameAlert()
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        canvas = nil
        toolbar = nil
        saveButton = nil
        cancelButton = nil
        deleteButton = nil
        presetButtons = []
        selectedPresetIndex = nil
        savedLayoutButton = nil
        savedToolbarLayout = nil
        selectedSavedLayout = false
        hintLabel = nil
        protectionLabel = nil
        transaction = nil
        runtime.isEditorOpen = false
        runtime.uiSession.leaveRegular()
        runtime.editorDidClose()
    }

    private func dismissSaveNameAlert() {
        guard let alert = saveNameAlert else { return }
        saveNameAlert = nil
        if let panel, panel.attachedSheet === alert.window {
            panel.endSheet(alert.window, returnCode: .cancel)
        } else {
            alert.window.orderOut(nil)
        }
    }
}

extension LayoutEditorController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        panel?.makeFirstResponder(canvas)
    }
}

private final class EditorToolbarChrome: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.94).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func updateLayer() {
        layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.94).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is NSButton { return hit }
            view = current.superview
        }
        return nil
    }
}

private final class EditorChipButton: NSButton {
    enum Kind {
        case preset
        case save
        case cancel
        case delete
    }

    private var usesThumbnail = false
    private var thumbnailLayout: Layout?

    init(title: String, symbol: String?, target: AnyObject, action: Selector, kind: Kind) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        refusesFirstResponder = true
        imageHugsTitle = true
        imagePosition = symbol == nil ? .noImage : .imageLeading
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        appearance = NSAppearance(named: .darkAqua)

        let titleColor = NSColor.white
        switch kind {
        case .save:
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            keyEquivalent = "\r"
        case .cancel:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            keyEquivalent = "\u{1b}"
        case .delete:
            layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.82).cgColor
        case .preset:
            applyPresetAppearance(selected: false)
        }

        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: titleColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        )
        if let symbol {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [titleColor]))
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(config)
            contentTintColor = titleColor
        }
        toolTip = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        (target as? LayoutEditorController)?.chipHoverChanged(self, hovering: true)
    }

    override func mouseExited(with event: NSEvent) {
        (target as? LayoutEditorController)?.chipHoverChanged(self, hovering: false)
    }

    func setPresetSelected(_ selected: Bool) {
        applyPresetAppearance(selected: selected)
    }

    private func applyPresetAppearance(selected: Bool) {
        let titleColor = selected ? NSColor.black : NSColor.white
        if selected {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
            layer?.borderWidth = 0
            layer?.borderColor = nil
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
        attributedTitle = NSAttributedString(
            string: attributedTitle.string,
            attributes: [
                .foregroundColor: titleColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        )
        if let image {
            if usesThumbnail {
                applyThumbnail(selected: selected)
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [titleColor]))
                self.image = image.withSymbolConfiguration(config)
                contentTintColor = titleColor
            }
        }
    }

    func setChipTitle(_ title: String) {
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        )
        toolTip = nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func setThumbnail(from layout: Layout) {
        thumbnailLayout = layout
        usesThumbnail = true
        applyThumbnail(selected: false)
        imagePosition = .imageLeading
        imageHugsTitle = true
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func applyThumbnail(selected: Bool) {
        guard let thumbnailLayout else { return }
        let fill = selected
            ? NSColor.black.withAlphaComponent(0.78)
            : NSColor.white.withAlphaComponent(0.86)
        let stroke = selected
            ? NSColor.black.withAlphaComponent(0.28)
            : NSColor.white.withAlphaComponent(0.35)
        image = LayoutThumbnailRenderer.image(
            for: thumbnailLayout,
            size: NSSize(width: 22, height: 14),
            fill: fill,
            stroke: stroke
        )
        contentTintColor = nil
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 18
        size.height = 30
        return size
    }

    override var isHighlighted: Bool {
        didSet { alphaValue = isHighlighted ? 0.72 : 1 }
    }
}
