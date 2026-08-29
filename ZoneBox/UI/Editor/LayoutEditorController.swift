import AppKit
import ZoneBoxCore

@MainActor
final class LayoutEditorController: NSObject {
    private unowned let runtime: AppRuntime
    private let targetDisplayID: DisplayIdentity.ID
    private let isNew: Bool
    private var panel: EditorPanel?
    private var canvas: LayoutEditorCanvasView?
    private var toolbar: EditorToolbarChrome?
    private var saveButton: EditorChipButton?
    private var saveCopyButton: EditorChipButton?
    private var cancelButton: EditorChipButton?
    private var deleteButton: EditorChipButton?
    private var saveNameAlert: NSAlert?
    private var templatePopup: NSPopUpButton?
    private var templateLabel: NSTextField?
    private var selectedPresetIndex: Int?
    private var savedToolbarLayout: Layout?
    private var selectedSavedLayout = false
    private var hintLabel: NSTextField?
    private var modeControl: NSSegmentedControl?
    private let original: Layout
    private var transaction: LayoutEditTransaction?
    private var appSwitchObservations: [Any] = []
    private var canCancelOnAppSwitch = false
    private var toolbarHasCustomPosition = false

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
        self.toolbar = toolbar
        canvas.chromeView = toolbar

        let root = NSView()
        root.addSubview(canvas)
        root.addSubview(toolbar)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = root
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: root.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        toolbarHasCustomPosition = false
        toolbar.onMove = { [weak self] in
            self?.toolbarHasCustomPosition = true
            self?.canvas?.noteChromeMoved()
        }

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
        DispatchQueue.main.async { [weak self, weak panel, weak canvas] in
            guard let self, let panel, let canvas else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(canvas)
            self.layoutToolbar()
        }
    }

    private func makeToolbar() -> EditorToolbarChrome {
        let bar = EditorToolbarChrome()

        let template = makeTemplatePopup()
        templatePopup = template
        let templateLabel = NSTextField(labelWithString: L10n.text(.editorFromTemplate))
        templateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        templateLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        templateLabel.isBezeled = false
        templateLabel.drawsBackground = false
        templateLabel.isSelectable = false
        self.templateLabel = templateLabel
        let templateRow = NSStackView(views: [templateLabel, template])
        templateRow.orientation = .horizontal
        templateRow.alignment = .centerY
        templateRow.spacing = 6

        let mode = NSSegmentedControl(labels: [L10n.text(.editorModeGrid), L10n.text(.editorModeCanvas)], trackingMode: .selectOne, target: self, action: #selector(modeChanged(_:)))
        mode.segmentStyle = .rounded
        mode.setWidth(64, forSegment: 0)
        mode.setWidth(76, forSegment: 1)
        mode.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: L10n.text(.editorModeGrid)), forSegment: 0)
        mode.setImage(NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: L10n.text(.editorModeCanvas)), forSegment: 1)
        mode.setImageScaling(.scaleProportionallyDown, forSegment: 0)
        mode.setImageScaling(.scaleProportionallyDown, forSegment: 1)
        modeControl = mode
        refreshModeControl()

        let saveTitle = L10n.text(.editorSave)
        let save = EditorChipButton(title: saveTitle, symbol: nil, target: self, action: #selector(save), kind: .save)
        saveButton = save
        let saveCopy = EditorChipButton(title: L10n.text(.editorSaveCopy), symbol: nil, target: self, action: #selector(saveCopyShortcut), kind: .preset)
        saveCopy.toolTip = L10n.text(.editorSaveCopyTooltip)
        saveCopyButton = saveCopy
        let cancel = EditorChipButton(title: L10n.text(.editorCancel), symbol: nil, target: self, action: #selector(cancel), kind: .cancel)
        cancelButton = cancel
        var actionViews: [NSView] = [save, saveCopy, cancel]
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
        topRow.spacing = 10
        topRow.addArrangedSubview(mode)
        topRow.addArrangedSubview(templateRow)
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
        hint.stringValue = L10n.text(hintKey)
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.92)
        hint.alignment = .center
        hint.isBezeled = false
        hint.drawsBackground = false
        hint.isSelectable = false
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3
        hint.preferredMaxLayoutWidth = 520
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hintLabel = hint

        var rows: [NSView] = [topRowCenter]
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

    @objc private func applySavedToolbarLayout() {
        guard let saved = savedToolbarLayout else { return }
        applyDraftLayout(saved)
        selectedPresetIndex = nil
        selectedSavedLayout = true
        refreshPresetSelection()
    }

    private func refreshPresetSelection() {
        rebuildTemplateMenu()
    }

    private func makeTemplatePopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.bezelStyle = .rounded
        popup.target = self
        popup.action = #selector(templateChanged(_:))
        popup.toolTip = L10n.text(.editorFromTemplateTooltip)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 108).isActive = true
        rebuildTemplateMenu(in: popup)
        return popup
    }

    private func rebuildTemplateMenu(in popup: NSPopUpButton? = nil) {
        guard let popup = popup ?? templatePopup else { return }
        popup.removeAllItems()

        if let saved = savedToolbarLayout {
            popup.addItem(withTitle: L10n.layoutDisplayName(saved.name))
            popup.lastItem?.tag = -1
            popup.lastItem?.toolTip = L10n.layoutDisplayName(saved.name)
        }

        let keys: [L10nKey] = [
            .editorColumns2, .editorColumns3, .editorRows2, .editorGrid2x2, .editorPriority, .editorFocus,
        ]
        for (index, key) in keys.enumerated() {
            popup.addItem(withTitle: L10n.text(key))
            popup.lastItem?.tag = index
        }

        if selectedSavedLayout, savedToolbarLayout != nil {
            popup.selectItem(withTag: -1)
        } else if let index = selectedPresetIndex {
            popup.selectItem(withTag: index)
        } else {
            popup.addItem(withTitle: L10n.text(.editorCustomLayout))
            popup.lastItem?.tag = -2
            popup.lastItem?.isEnabled = false
            popup.selectItem(withTag: -2)
        }
    }

    @objc private func templateChanged(_ sender: NSPopUpButton) {
        let tag = sender.selectedItem?.tag ?? Int.min
        if tag == -1 {
            applySavedToolbarLayout()
            return
        }
        let presets = LayoutTemplates.editorPresets()
        guard presets.indices.contains(tag) else {
            refreshPresetSelection()
            return
        }
        applyPreset(presets[tag], index: tag)
    }

    private func applyDraftLayout(_ layout: Layout) {
        guard var transaction else { return }
        var draft = layout
        draft.id = transaction.draft.id
        draft.name = transaction.draft.name
        draft.createdAt = transaction.draft.createdAt
        transaction.updateDraft(draft)
        self.transaction = transaction
        canvas?.layout = draft
        canvas?.selectFirstZone()
        canvas?.needsDisplay = true
        hintLabel?.stringValue = L10n.text(hintKey)
        refreshModeControl()
        updateSaveState()
        layoutToolbar()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let wantsGrid = sender.selectedSegment == 0
        switchEditorMode(toGrid: wantsGrid)
    }

    private func switchEditorMode(toGrid: Bool) {
        guard let transaction else { return }
        let current = transaction.draft
        if toGrid, current.kind == .grid { refreshModeControl(); return }
        if !toGrid, current.kind == .canvas { refreshModeControl(); return }

        let next: Layout
        if toGrid {
            next = GridEditing.convertingCanvasToGrid(current)
        } else if let workAX = canvas?.workAreaAX, let converted = try? current.convertingGridToCanvas(workAreaAX: workAX) {
            next = converted
        } else {
            refreshModeControl()
            return
        }
        applyDraftLayout(next)
        selectedPresetIndex = canvas.flatMap { LayoutTemplates.matchingEditorPresetIndex(for: next, workAreaAX: $0.workAreaAX) }
        selectedSavedLayout = savedToolbarLayout.map { $0.id == next.id } ?? false
        refreshPresetSelection()
    }

    private func refreshModeControl() {
        let isGrid = (transaction?.draft.kind ?? original.kind) == .grid
        modeControl?.selectedSegment = isGrid ? 0 : 1
    }

    @objc private func save() {
        guard let transaction = validTransactionForSave() else { return }
        if isNew {
            promptForSaveName(defaultName: transaction.draft.name, kind: .newLayout)
            return
        }
        commitSave(requestedName: nil, createsCopy: false)
    }

    @objc private func saveCopyShortcut() {
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
        refreshPresetSelection()
        let saveTitle = L10n.text(.editorSave)
        saveButton?.setChipTitle(saveTitle)
        saveCopyButton?.setChipTitle(L10n.text(.editorSaveCopy))
        saveCopyButton?.toolTip = L10n.text(.editorSaveCopyTooltip)
        cancelButton?.setChipTitle(L10n.text(.editorCancel))
        deleteButton?.setChipTitle(L10n.text(.editorDelete))
        deleteButton?.toolTip = L10n.text(.editorDeleteTooltip)
        hintLabel?.stringValue = L10n.text(hintKey)
        templatePopup?.toolTip = L10n.text(.editorFromTemplateTooltip)
        templateLabel?.stringValue = L10n.text(.editorFromTemplate)
        if let mode = modeControl {
            mode.setLabel(L10n.text(.editorModeGrid), forSegment: 0)
            mode.setLabel(L10n.text(.editorModeCanvas), forSegment: 1)
            mode.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: L10n.text(.editorModeGrid)), forSegment: 0)
            mode.setImage(NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: L10n.text(.editorModeCanvas)), forSegment: 1)
        }
        refreshModeControl()
        updateSaveState()
    }

    private func updateDraft(_ layout: Layout) {
        transaction?.updateDraft(layout)
        if let workAX = canvas?.workAreaAX {
            selectedPresetIndex = LayoutTemplates.matchingEditorPresetIndex(for: layout, workAreaAX: workAX)
            selectedSavedLayout = savedToolbarLayout.map { saved in
                LayoutTemplates.matchingEditorPresetIndex(for: saved, workAreaAX: workAX) == nil
                    && LayoutTemplates.matchingEditorPresetIndex(for: layout, workAreaAX: workAX) == nil
                    && saved.id == original.id
            } ?? false
            if selectedSavedLayout {
                selectedPresetIndex = nil
            }
            refreshPresetSelection()
        }
        updateSaveState()
        hintLabel?.stringValue = L10n.text(hintKey)
        layoutToolbar()
    }

    private var hintKey: L10nKey {
        (transaction?.draft.kind ?? original.kind) == .grid ? .editorGridHint : .editorHint
    }

    fileprivate func chipHoverChanged(_ button: EditorChipButton, hovering: Bool) {
        _ = (button, hovering)
    }

    private func updateSaveState() {
        guard let transaction else { return }
        saveButton?.isEnabled = transaction.canCommit
        saveButton?.toolTip = transaction.canCommit ? L10n.text(.editorSaveTooltip) : L10n.text(.editorSaveDisabledTooltip)
        saveCopyButton?.isEnabled = transaction.canCommit
        saveCopyButton?.toolTip = transaction.canCommit ? L10n.text(.editorSaveCopyTooltip) : L10n.text(.editorSaveDisabledTooltip)
    }

    private func setToolbarReceded(_ receded: Bool) {
        guard let toolbar else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = receded ? 0.12 : 0.2
            toolbar.animator().alphaValue = receded ? 0.12 : 1
        }
    }

    private func layoutToolbar() {
        guard let toolbar, let root = toolbar.superview else { return }
        toolbar.layoutSubtreeIfNeeded()
        var size = toolbar.fittingSize
        let inset: CGFloat = 16
        let maxWidth = max(root.bounds.width - inset * 2, 1)
        size.width = min(max(size.width, 1), maxWidth)
        size.height = max(size.height, 1)
        let origin: CGPoint
        if toolbarHasCustomPosition {
            origin = clampToolbarOrigin(toolbar.frame.origin, size: size, in: root.bounds)
        } else {
            origin = CGPoint(
                x: root.bounds.midX - size.width / 2,
                y: root.bounds.maxY - 14 - size.height
            )
        }
        toolbar.frame = CGRect(origin: clampToolbarOrigin(origin, size: size, in: root.bounds), size: size)
        canvas?.noteChromeMoved()
    }

    private func clampToolbarOrigin(_ origin: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        let inset: CGFloat = 16
        let minX = bounds.minX + inset
        let maxX = bounds.maxX - inset - size.width
        let minY = bounds.minY + inset
        let maxY = bounds.maxY - inset - size.height
        return CGPoint(
            x: min(max(origin.x, minX), max(minX, maxX)),
            y: min(max(origin.y, minY), max(minY, maxY))
        )
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
        saveCopyButton = nil
        cancelButton = nil
        deleteButton = nil
        templatePopup = nil
        templateLabel = nil
        selectedPresetIndex = nil
        savedToolbarLayout = nil
        selectedSavedLayout = false
        hintLabel = nil
        modeControl = nil
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

    func windowDidResize(_ notification: Notification) {
        layoutToolbar()
    }
}

private final class EditorToolbarChrome: NSView {
    var onMove: (() -> Void)?
    private var dragOrigin: CGPoint?
    private var dragMouseInSuperview: CGPoint?

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
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is NSButton || current is NSSegmentedControl || current is NSPopUpButton {
                return hit
            }
            view = current.superview
        }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func cursorUpdate(with event: NSEvent) {
        (dragOrigin == nil ? NSCursor.openHand : NSCursor.closedHand).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let superview else { return }
        dragOrigin = frame.origin
        dragMouseInSuperview = superview.convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview, let dragOrigin, let dragMouseInSuperview else { return }
        let current = superview.convert(event.locationInWindow, from: nil)
        var origin = CGPoint(
            x: dragOrigin.x + current.x - dragMouseInSuperview.x,
            y: dragOrigin.y + current.y - dragMouseInSuperview.y
        )
        let inset: CGFloat = 16
        let minX = superview.bounds.minX + inset
        let maxX = superview.bounds.maxX - inset - frame.width
        let minY = superview.bounds.minY + inset
        let maxY = superview.bounds.maxY - inset - frame.height
        origin.x = min(max(origin.x, minX), max(minX, maxX))
        origin.y = min(max(origin.y, minY), max(minY, maxY))
        setFrameOrigin(origin)
        onMove?()
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        dragMouseInSuperview = nil
        NSCursor.openHand.set()
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
