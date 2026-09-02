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
    private var metricsRow: NSStackView?
    private var widthField: NSTextField?
    private var heightField: NSTextField?
    private var xField: NSTextField?
    private var yField: NSTextField?
    private var widthLabel: NSTextField?
    private var heightLabel: NSTextField?
    private var xLabel: NSTextField?
    private var yLabel: NSTextField?
    private var pixelUnitLabel: NSTextField?
    private var paneActionRow: NSStackView?
    private var insertPaneButton: NSButton?
    private var duplicatePaneButton: NSButton?
    private var splitVerticalButton: NSButton?
    private var splitHorizontalButton: NSButton?
    private var alignPopup: NSPopUpButton?
    private var deletePaneButton: NSButton?
    private var emptyTemplateButtons: [NSButton] = []
    private var emptyTemplateHost: NSStackView?
    private var aspectLabel: NSTextField?
    private var aspectPopup: NSPopUpButton?
    private var lockAspectButton: NSButton?
    private var metricsHintLabel: NSTextField?
    private var lockAspect = false
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
        let draft = original
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
        canvas.gutterPoints = CGFloat(runtime.settings.gutterPoints)
        canvas.showZoneNumbers = runtime.settings.showZoneNumbers
        canvas.selectFirstZone()
        canvas.onChange = { [weak self] layout in self?.finishDraft(layout) }
        canvas.onPreview = { [weak self] layout in self?.previewDraft(layout) }
        canvas.onInteractionBegin = { [weak self] in self?.transaction?.beginInteraction() }
        canvas.onCancel = { [weak self] in self?.cancel() }
        canvas.onInteractionChange = { [weak self] active in self?.setToolbarReceded(active) }
        canvas.onSelectionChange = { [weak self] in self?.refreshMetrics() }
        canvas.lockAspect = lockAspect
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
        panel.onUndo = { [weak self] in self?.undoLastEdit() }
        panel.onRedo = { [weak self] in self?.redoLastEdit() }
        panel.onDuplicate = { [weak self] in self?.duplicateSelectedPanes() }
        panel.onSelectAll = { [weak self] in _ = self?.canvas?.perform(.selectAll) }
        panel.onSplitVertical = { [weak self] in self?.splitSelected(.vertical) }
        panel.onSplitHorizontal = { [weak self] in self?.splitSelected(.horizontal) }
        canvas.onMenuWillOpen = { [weak self] in self?.canCancelOnAppSwitch = false }
        canvas.onMenuDidClose = { [weak self] in
            DispatchQueue.main.async { self?.canCancelOnAppSwitch = true }
        }
        panel.delegate = self
        self.panel = panel
        self.canvas = canvas
        updateSaveState()
        refreshEmptyTemplateButtons()
        makeEditorKey(panel: panel, canvas: canvas)
        observeAppSwitchToCancel()
    }

    func activate() {
        guard let panel, let canvas else { return }
        makeEditorKey(panel: panel, canvas: canvas)
    }

    func applySettings(_ settings: AppSettings) {
        canvas?.gutterPoints = CGFloat(settings.gutterPoints)
        canvas?.showZoneNumbers = settings.showZoneNumbers
        refreshChipThumbnails(gutterPoints: CGFloat(settings.gutterPoints))
    }

    func owns(_ window: NSWindow) -> Bool {
        panel === window
    }

    var isKey: Bool { panel?.isKeyWindow == true }

    var originalLayoutID: Layout.ID { original.id }

    @discardableResult
    func handleLocalKey(_ event: NSEvent) -> Bool {
        if isEditingMetrics {
            return false
        }
        if ShortcutCatalog.editorSaveChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        ) {
            saveCopyShortcut()
            return true
        }
        if ShortcutCatalog.isEditorUndoChord(
            keyCode: event.keyCode,
            carbonModifiers: KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        ) {
            undoLastEdit()
            return true
        }
        if ShortcutCatalog.isEditorRedoChord(
            keyCode: event.keyCode,
            carbonModifiers: KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        ) {
            redoLastEdit()
            return true
        }
        if ShortcutCatalog.editorDuplicateChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        ) {
            duplicateSelectedPanes()
            return true
        }
        if ShortcutCatalog.editorSelectAllChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        ) {
            _ = canvas?.perform(.selectAll)
            return true
        }
        if ShortcutCatalog.editorSplitVerticalChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        ) {
            splitSelected(.vertical)
            return true
        }
        if ShortcutCatalog.editorSplitHorizontalChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        ) {
            splitSelected(.horizontal)
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
        rows.append(makePaneActionRow())
        rows.append(makeMetricsRow())

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

    private func refreshChipThumbnails(gutterPoints: CGFloat) {
        for button in [saveButton, saveCopyButton, cancelButton, deleteButton] {
            button?.gutterPoints = gutterPoints
        }
    }

    private func makePaneActionRow() -> NSView {
        let insert = iconButton("plus.rectangle", tooltip: L10n.text(.canvasNewPane), action: #selector(insertDefaultPane))
        insertPaneButton = insert
        let duplicate = iconButton("plus.square.on.square", tooltip: L10n.text(.canvasDuplicate), action: #selector(duplicateSelectedPanes))
        duplicatePaneButton = duplicate
        let splitV = iconButton("rectangle.split.2x1", tooltip: L10n.text(.canvasSplitVertical), action: #selector(splitVerticalAction))
        splitVerticalButton = splitV
        let splitH = iconButton("rectangle.split.1x2", tooltip: L10n.text(.canvasSplitHorizontal), action: #selector(splitHorizontalAction))
        splitHorizontalButton = splitH
        let align = NSPopUpButton(frame: .zero, pullsDown: true)
        align.bezelStyle = .rounded
        align.imagePosition = .imageOnly
        align.translatesAutoresizingMaskIntoConstraints = false
        align.widthAnchor.constraint(equalToConstant: 44).isActive = true
        alignPopup = align
        rebuildAlignMenu()
        let delete = iconButton("trash", tooltip: L10n.text(.canvasDeletePane), action: #selector(deleteSelectedPanes))
        deletePaneButton = delete
        let row = NSStackView(views: [insert, duplicate, splitV, splitH, align, delete])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        paneActionRow = row
        refreshPaneActions()
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrap.topAnchor),
            row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            row.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: wrap.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor),
        ])
        return wrap
    }

    private func iconButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .rounded
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.refusesFirstResponder = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func rebuildAlignMenu() {
        guard let popup = alignPopup else { return }
        popup.removeAllItems()
        popup.addItem(withTitle: "")
        popup.lastItem?.image = NSImage(systemSymbolName: "align.horizontal.left", accessibilityDescription: L10n.text(.canvasAlign))
        func add(_ title: String, tag: Int, action: Selector) {
            popup.addItem(withTitle: title)
            popup.lastItem?.tag = tag
            popup.lastItem?.target = self
            popup.lastItem?.action = action
        }
        add(L10n.text(.canvasAlignLeft), tag: 0, action: #selector(alignAction(_:)))
        add(L10n.text(.canvasAlignCenterX), tag: 1, action: #selector(alignAction(_:)))
        add(L10n.text(.canvasAlignRight), tag: 2, action: #selector(alignAction(_:)))
        add(L10n.text(.canvasAlignTop), tag: 3, action: #selector(alignAction(_:)))
        add(L10n.text(.canvasAlignCenterY), tag: 4, action: #selector(alignAction(_:)))
        add(L10n.text(.canvasAlignBottom), tag: 5, action: #selector(alignAction(_:)))
        popup.menu?.addItem(.separator())
        add(L10n.text(.canvasMatchWidth), tag: 0, action: #selector(matchSizeAction(_:)))
        add(L10n.text(.canvasMatchHeight), tag: 1, action: #selector(matchSizeAction(_:)))
        add(L10n.text(.canvasMatchBoth), tag: 2, action: #selector(matchSizeAction(_:)))
        popup.menu?.addItem(.separator())
        add(L10n.text(.canvasDistributeHorizontal), tag: 0, action: #selector(distributeAction(_:)))
        add(L10n.text(.canvasDistributeVertical), tag: 1, action: #selector(distributeAction(_:)))
        popup.selectItem(at: 0)
    }

    private func makeMetricsRow() -> NSView {
        let xLabel = metricCaption(L10n.text(.editorX))
        self.xLabel = xLabel
        let xField = metricField()
        xField.identifier = NSUserInterfaceItemIdentifier("editor-x")
        self.xField = xField

        let yLabel = metricCaption(L10n.text(.editorY))
        self.yLabel = yLabel
        let yField = metricField()
        yField.identifier = NSUserInterfaceItemIdentifier("editor-y")
        self.yField = yField

        let widthLabel = metricCaption(L10n.text(.editorWidth))
        self.widthLabel = widthLabel
        let widthField = metricField()
        widthField.identifier = NSUserInterfaceItemIdentifier("editor-width")
        self.widthField = widthField

        let heightLabel = metricCaption(L10n.text(.editorHeight))
        self.heightLabel = heightLabel
        let heightField = metricField()
        heightField.identifier = NSUserInterfaceItemIdentifier("editor-height")
        self.heightField = heightField

        let px = metricCaption(L10n.text(.editorPixels))
        self.pixelUnitLabel = px

        let aspectLabel = metricCaption(L10n.text(.editorAspect))
        self.aspectLabel = aspectLabel
        let aspect = NSPopUpButton(frame: .zero, pullsDown: false)
        aspect.bezelStyle = .rounded
        aspect.target = self
        aspect.action = #selector(aspectChanged(_:))
        aspect.translatesAutoresizingMaskIntoConstraints = false
        aspect.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        aspect.refusesFirstResponder = true
        aspectPopup = aspect
        rebuildAspectMenu()

        let lock = NSButton(checkboxWithTitle: L10n.text(.editorLockAspect), target: self, action: #selector(toggleLockAspect(_:)))
        lock.font = .systemFont(ofSize: 12, weight: .medium)
        lock.contentTintColor = NSColor.white.withAlphaComponent(0.86)
        lock.state = lockAspect ? .on : .off
        lock.refusesFirstResponder = true
        lockAspectButton = lock

        let hint = metricCaption(L10n.text(.editorNoZoneSelected))
        hint.textColor = NSColor.white.withAlphaComponent(0.72)
        metricsHintLabel = hint

        let row = NSStackView(views: [xLabel, xField, yLabel, yField, widthLabel, widthField, heightLabel, heightField, px, aspectLabel, aspect, lock, hint])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        metricsRow = row
        refreshMetrics()
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrap.topAnchor),
            row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            row.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: wrap.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor),
        ])
        return wrap
    }

    private func metricCaption(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.72)
        label.isBezeled = false
        label.drawsBackground = false
        label.isSelectable = false
        return label
    }

    private func metricField() -> NSTextField {
        let field = EditorMetricsField(string: "")
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        field.alignment = .right
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.target = self
        field.action = #selector(metricsEditingEnded(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        return field
    }

    private func rebuildAspectMenu() {
        guard let popup = aspectPopup else { return }
        popup.removeAllItems()
        popup.addItem(withTitle: L10n.text(.editorAspectFree))
        popup.lastItem?.tag = 0
        popup.addItem(withTitle: L10n.text(.editorAspectSquare))
        popup.lastItem?.tag = 1
        popup.addItem(withTitle: L10n.text(.editorAspect16x9))
        popup.lastItem?.tag = 2
        popup.addItem(withTitle: L10n.text(.editorAspect4x3))
        popup.lastItem?.tag = 3
        popup.selectItem(withTag: 0)
    }

    private func selectedZoneRect() -> (id: UUID, rect: NormalizedRect)? {
        guard let canvas, let id = canvas.selectedID,
              let zone = canvas.layout.zones.first(where: { $0.id == id })
        else { return nil }
        if canvas.layout.kind == .grid {
            let rects = GridEditing.normalizedRects(for: canvas.layout, workAreaAX: canvas.workAreaAX)
            guard let rect = rects[id] else { return nil }
            return (id, rect)
        }
        return (id, zone.canvasRect ?? NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3))
    }

    private func refreshMetrics() {
        guard let canvas else { return }
        let selected = selectedZoneRect()
        let enabled = selected != nil
        let canMoveOrigin = enabled && canvas.layout.kind != .grid
        widthField?.isEnabled = enabled
        heightField?.isEnabled = enabled
        xField?.isEnabled = canMoveOrigin
        yField?.isEnabled = canMoveOrigin
        aspectPopup?.isEnabled = enabled
        lockAspectButton?.isEnabled = enabled
        metricsHintLabel?.isHidden = enabled
        widthLabel?.isHidden = !enabled
        heightLabel?.isHidden = !enabled
        xLabel?.isHidden = !canMoveOrigin
        yLabel?.isHidden = !canMoveOrigin
        pixelUnitLabel?.isHidden = !enabled
        aspectLabel?.isHidden = !enabled
        aspectPopup?.isHidden = !enabled
        lockAspectButton?.isHidden = !enabled
        widthField?.isHidden = !enabled
        heightField?.isHidden = !enabled
        xField?.isHidden = !canMoveOrigin
        yField?.isHidden = !canMoveOrigin
        refreshPaneActions()
        refreshEmptyTemplateButtons()
        guard let selected else {
            widthField?.stringValue = ""
            heightField?.stringValue = ""
            xField?.stringValue = ""
            yField?.stringValue = ""
            aspectPopup?.selectItem(withTag: 0)
            return
        }
        let pixels = ZonePixelMetrics.pixelSize(of: selected.rect, workAreaAX: canvas.workAreaAX)
        let origin = ZonePixelMetrics.origin(of: selected.rect, workAreaAX: canvas.workAreaAX)
        if widthField?.currentEditor() == nil {
            widthField?.integerValue = pixels.width
        }
        if heightField?.currentEditor() == nil {
            heightField?.integerValue = pixels.height
        }
        if xField?.currentEditor() == nil {
            xField?.integerValue = origin.x
        }
        if yField?.currentEditor() == nil {
            yField?.integerValue = origin.y
        }
        layoutToolbar()
        restoreCanvasKeyFocusIfNeeded()
    }

    private func applyPixelOrigin(x: Int?, y: Int?) {
        guard let canvas, let selected = selectedZoneRect() else { return }
        if canvas.layout.kind == .grid { return }
        applyCanvasRect(
            ZonePixelMetrics.moving(selected.rect, toX: x, y: y, workAreaAX: canvas.workAreaAX),
            to: selected.id
        )
    }

    private func applyPixelSize(width: Int?, height: Int?) {
        guard let canvas, let selected = selectedZoneRect() else { return }
        if canvas.layout.kind == .grid {
            if let next = GridEditing.resizingZone(
                canvas.layout,
                id: selected.id,
                toWidth: width,
                height: height,
                workAreaAX: canvas.workAreaAX,
                lockAspect: lockAspect
            ) {
                canvas.layout = next
                canvas.selectedID = selected.id
                canvas.commitFromMetrics()
                return
            }
        }
        let next = ZonePixelMetrics.resizing(
            selected.rect,
            toWidth: width,
            height: height,
            workAreaAX: canvas.workAreaAX,
            lockAspect: lockAspect
        )
        applyCanvasRect(next, to: selected.id)
    }

    private func applyAspect(_ aspect: ZoneAspectPreset) {
        guard let canvas, let selected = selectedZoneRect() else { return }
        if canvas.layout.kind == .grid {
            if let next = GridEditing.applyingAspect(
                canvas.layout,
                id: selected.id,
                aspect: aspect,
                workAreaAX: canvas.workAreaAX
            ) {
                canvas.layout = next
                canvas.selectedID = selected.id
                canvas.commitFromMetrics()
                return
            }
        }
        applyCanvasRect(
            ZonePixelMetrics.applying(aspect: aspect, to: selected.rect, workAreaAX: canvas.workAreaAX),
            to: selected.id
        )
    }

    private func applyCanvasRect(_ rect: NormalizedRect, to id: UUID) {
        guard let canvas else { return }
        var layout = canvas.layout
        guard let idx = layout.zones.firstIndex(where: { $0.id == id }) else { return }
        if layout.kind == .grid, let converted = try? layout.convertingGridToCanvas(workAreaAX: canvas.workAreaAX) {
            layout = converted
            guard let convertedIndex = layout.zones.firstIndex(where: { $0.id == id }) else { return }
            layout.zones[convertedIndex].canvasRect = rect
            canvas.layout = layout
            canvas.selectedID = id
            canvas.commitFromMetrics()
            return
        }
        layout.kind = .canvas
        layout.grid = nil
        layout.zones[idx].canvasRect = rect
        canvas.layout = layout
        canvas.selectedID = id
        canvas.commitFromMetrics()
    }

    @objc private func metricsEditingEnded(_ sender: NSTextField) {
        commitMetricsFields()
    }

    @objc private func toggleLockAspect(_ sender: NSButton) {
        lockAspect = sender.state == .on
        canvas?.lockAspect = lockAspect
        restoreCanvasKeyFocusIfNeeded()
    }

    @objc private func aspectChanged(_ sender: NSPopUpButton) {
        let aspect: ZoneAspectPreset
        switch sender.selectedItem?.tag {
        case 1: aspect = .square
        case 2: aspect = .wide16x9
        case 3: aspect = .photo4x3
        default: aspect = .free
        }
        if case .free = aspect { return }
        lockAspect = true
        lockAspectButton?.state = .on
        canvas?.lockAspect = true
        applyAspect(aspect)
        restoreCanvasKeyFocusIfNeeded()
    }

    private func commitMetricsFields() {
        guard let canvas, let selected = selectedZoneRect() else {
            refreshMetrics()
            return
        }
        let current = ZonePixelMetrics.pixelSize(of: selected.rect, workAreaAX: canvas.workAreaAX)
        let origin = ZonePixelMetrics.origin(of: selected.rect, workAreaAX: canvas.workAreaAX)
        let width = parsedPixel(widthField?.stringValue)
        let height = parsedPixel(heightField?.stringValue)
        let x = parsedPixel(xField?.stringValue)
        let y = parsedPixel(yField?.stringValue)
        var changed = false
        if x != nil || y != nil {
            let nextX = x ?? origin.x
            let nextY = y ?? origin.y
            if nextX != origin.x || nextY != origin.y {
                applyPixelOrigin(x: x, y: y)
                changed = true
            }
        }
        if width != nil || height != nil {
            let locked = ZonePixelMetrics.lockedFields(
                current: current,
                width: width,
                height: height,
                lockAspect: lockAspect
            )
            applyPixelSize(width: locked.width, height: locked.height)
            changed = true
        }
        if !changed {
            refreshMetrics()
        }
    }

    private func parsedPixel(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
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
        presentDraft(draft, reselectFirstZone: true)
    }

    private func undoLastEdit() {
        guard var transaction, let previous = transaction.undo() else { return }
        self.transaction = transaction
        presentDraft(previous, reselectFirstZone: false)
    }

    private func redoLastEdit() {
        guard var transaction, let next = transaction.redo() else { return }
        self.transaction = transaction
        presentDraft(next, reselectFirstZone: false)
    }

    @objc private func insertDefaultPane() {
        _ = canvas?.perform(.insertDefault)
    }

    @objc private func duplicateSelectedPanes() {
        _ = canvas?.perform(.duplicate)
    }

    @objc private func splitVerticalAction() { splitSelected(.vertical) }
    @objc private func splitHorizontalAction() { splitSelected(.horizontal) }

    private func splitSelected(_ axis: GridAxis) {
        _ = canvas?.perform(.split(axis))
    }

    @objc private func deleteSelectedPanes() {
        canvas?.deleteSelected()
    }

    @objc private func alignAction(_ sender: NSMenuItem) {
        let edges: [CanvasAlignment.Edge] = [.left, .centerX, .right, .top, .centerY, .bottom]
        guard edges.indices.contains(sender.tag) else { return }
        _ = canvas?.perform(.align(edges[sender.tag]))
    }

    @objc private func matchSizeAction(_ sender: NSMenuItem) {
        let matches: [CanvasAlignment.SizeMatch] = [.width, .height, .both]
        guard matches.indices.contains(sender.tag) else { return }
        _ = canvas?.perform(.matchSize(matches[sender.tag]))
    }

    @objc private func distributeAction(_ sender: NSMenuItem) {
        _ = canvas?.perform(.distribute(sender.tag == 1 ? .vertical : .horizontal))
    }

    private func refreshPaneActions() {
        let isCanvas = (transaction?.draft.kind ?? original.kind) != .grid
        let count = canvas?.selectedIDs.count ?? 0
        insertPaneButton?.isEnabled = isCanvas
        duplicatePaneButton?.isEnabled = isCanvas && count > 0
        splitVerticalButton?.isEnabled = isCanvas && count > 0
        splitHorizontalButton?.isEnabled = isCanvas && count > 0
        deletePaneButton?.isEnabled = count > 0
        alignPopup?.isEnabled = isCanvas && count >= 2
    }

    private func refreshEmptyTemplateButtons() {
        guard let canvas, let root = panel?.contentView else { return }
        let presets = [LayoutTemplates.columns(2), LayoutTemplates.grid2x2(), LayoutTemplates.rows(2)]
        let shouldShow = canvas.layout.kind == .canvas && canvas.layout.zones.isEmpty
        if emptyTemplateHost == nil {
            let host = NSStackView()
            host.orientation = .horizontal
            host.alignment = .centerY
            host.spacing = 10
            host.translatesAutoresizingMaskIntoConstraints = false
            var buttons: [NSButton] = []
            for (index, preset) in presets.enumerated() {
                let button = NSButton(title: "", target: self, action: #selector(emptyTemplatePressed(_:)))
                button.bezelStyle = .rounded
                button.imagePosition = .imageOnly
                button.tag = index
                button.refusesFirstResponder = true
                button.image = LayoutThumbnailRenderer.image(
                    for: preset,
                    size: NSSize(width: 72, height: 44),
                    fill: NSColor.white.withAlphaComponent(0.86),
                    stroke: NSColor.white.withAlphaComponent(0.35)
                )
                button.toolTip = preset.name
                buttons.append(button)
                host.addArrangedSubview(button)
            }
            root.addSubview(host)
            NSLayoutConstraint.activate([
                host.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                host.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 90),
            ])
            emptyTemplateHost = host
            emptyTemplateButtons = buttons
        }
        canvas.additionalChromeViews = [emptyTemplateHost].compactMap { $0 }
        canvas.chromeView = toolbar
        emptyTemplateHost?.isHidden = !shouldShow
        for (index, button) in emptyTemplateButtons.enumerated() where presets.indices.contains(index) {
            button.image = LayoutThumbnailRenderer.image(
                for: presets[index],
                size: NSSize(width: 72, height: 44),
                fill: NSColor.white.withAlphaComponent(0.86),
                stroke: NSColor.white.withAlphaComponent(0.35),
                gutterPoints: canvas.gutterPoints
            )
        }
    }

    @objc private func emptyTemplatePressed(_ sender: NSButton) {
        let presets = [LayoutTemplates.columns(2), LayoutTemplates.grid2x2(), LayoutTemplates.rows(2)]
        guard presets.indices.contains(sender.tag), let canvas else { return }
        canvas.applyTemplateKeepingCanvas(presets[sender.tag])
    }

    private func presentDraft(_ draft: Layout, reselectFirstZone: Bool) {
        canvas?.layout = draft
        if reselectFirstZone {
            canvas?.selectFirstZone()
        } else if let selectedID = canvas?.selectedID,
                  !draft.zones.contains(where: { $0.id == selectedID }) {
            canvas?.selectFirstZone()
        }
        canvas?.needsDisplay = true
        hintLabel?.stringValue = L10n.text(hintKey)
        refreshModeControl()
        updateSaveState()
        refreshMetrics()
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
        guard let modeControl else { return }
        let target = isGrid ? 0 : 1
        guard modeControl.selectedSegment != target else { return }
        let action = modeControl.action
        modeControl.action = nil
        modeControl.selectedSegment = target
        modeControl.action = action
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
        alert.buttons.first?.hasDestructiveAction = true
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
        widthLabel?.stringValue = L10n.text(.editorWidth)
        heightLabel?.stringValue = L10n.text(.editorHeight)
        xLabel?.stringValue = L10n.text(.editorX)
        yLabel?.stringValue = L10n.text(.editorY)
        insertPaneButton?.toolTip = L10n.text(.canvasNewPane)
        duplicatePaneButton?.toolTip = L10n.text(.canvasDuplicate)
        splitVerticalButton?.toolTip = L10n.text(.canvasSplitVertical)
        splitHorizontalButton?.toolTip = L10n.text(.canvasSplitHorizontal)
        deletePaneButton?.toolTip = L10n.text(.canvasDeletePane)
        rebuildAlignMenu()
        pixelUnitLabel?.stringValue = L10n.text(.editorPixels)
        aspectLabel?.stringValue = L10n.text(.editorAspect)
        lockAspectButton?.title = L10n.text(.editorLockAspect)
        metricsHintLabel?.stringValue = L10n.text(.editorNoZoneSelected)
        rebuildAspectMenu()
        refreshModeControl()
        updateSaveState()
        refreshMetrics()
    }

    private func previewDraft(_ layout: Layout) {
        transaction?.previewDraft(layout)
        refreshLiveDraftChrome(layout)
    }

    private func finishDraft(_ layout: Layout) {
        transaction?.finishInteraction(layout)
        refreshLiveDraftChrome(layout)
    }

    private func updateDraft(_ layout: Layout) {
        transaction?.updateDraft(layout)
        refreshLiveDraftChrome(layout)
    }

    private func refreshLiveDraftChrome(_ layout: Layout) {
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
        refreshMetrics()
        refreshModeControl()
        layoutToolbar()
    }

    private var hintKey: L10nKey {
        (transaction?.draft.kind ?? original.kind) == .grid ? .editorGridHint : .editorHint
    }

    var isEditingMetrics: Bool {
        panel?.firstResponder === widthField || panel?.firstResponder === heightField
            || panel?.firstResponder === xField || panel?.firstResponder === yField
            || widthField?.currentEditor() != nil || heightField?.currentEditor() != nil
            || xField?.currentEditor() != nil || yField?.currentEditor() != nil
    }

    private func restoreCanvasKeyFocusIfNeeded() {
        guard !isEditingMetrics else { return }
        guard let canvas, panel?.firstResponder !== canvas else { return }
        panel?.makeFirstResponder(canvas)
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
        saveButton?.keyEquivalent = isEditingMetrics ? "" : "\r"
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
        metricsRow = nil
        widthField = nil
        heightField = nil
        xField = nil
        yField = nil
        widthLabel = nil
        heightLabel = nil
        xLabel = nil
        yLabel = nil
        paneActionRow = nil
        insertPaneButton = nil
        duplicatePaneButton = nil
        splitVerticalButton = nil
        splitHorizontalButton = nil
        alignPopup = nil
        deletePaneButton = nil
        emptyTemplateHost?.removeFromSuperview()
        emptyTemplateHost = nil
        emptyTemplateButtons = []
        pixelUnitLabel = nil
        aspectLabel = nil
        aspectPopup = nil
        lockAspectButton = nil
        metricsHintLabel = nil
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
        if !isEditingMetrics {
            panel?.makeFirstResponder(canvas)
        }
    }

    func windowDidResize(_ notification: Notification) {
        layoutToolbar()
    }
}

extension LayoutEditorController: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        updateSaveState()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitMetricsFields()
        updateSaveState()
        panel?.makeFirstResponder(canvas)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitMetricsFields()
            panel?.makeFirstResponder(canvas)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            refreshMetrics()
            panel?.makeFirstResponder(canvas)
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            commitMetricsFields()
            if control === xField {
                panel?.makeFirstResponder(yField)
            } else if control === yField {
                panel?.makeFirstResponder(widthField)
            } else if control === widthField {
                panel?.makeFirstResponder(heightField)
            } else {
                panel?.makeFirstResponder(canvas)
            }
            return true
        }
        return false
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
            if current is NSControl {
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
    var gutterPoints: CGFloat = 0 {
        didSet {
            guard usesThumbnail else { return }
            applyThumbnail(selected: layer?.backgroundColor == NSColor.white.withAlphaComponent(0.92).cgColor)
        }
    }

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
            stroke: stroke,
            gutterPoints: gutterPoints
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

/// Click-to-edit pixel fields. They stay out of the key loop so Delete/WASD
/// keep targeting the selected zone until the user actually clicks a field.
private final class EditorMetricsField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override var canBecomeKeyView: Bool { false }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
    }
}
