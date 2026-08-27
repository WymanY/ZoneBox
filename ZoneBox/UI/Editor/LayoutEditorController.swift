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
    private var presetButtons: [EditorChipButton] = []
    private var hintLabel: NSTextField?
    private var protectionLabel: NSTextField?
    private let original: Layout
    private var transaction: LayoutEditTransaction?

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

        let canvas = LayoutEditorCanvasView(layout: draft, workAreaAX: workAX, primaryFlipHeight: flip)
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
        self.panel = panel
        self.canvas = canvas
        updateSaveState()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func activate() {
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

        let saveTitle = !isNew && original.kind == .grid ? L10n.text(.editorSaveCopy) : L10n.text(.editorSave)
        let save = EditorChipButton(title: saveTitle, symbol: nil, target: self, action: #selector(save), kind: .save)
        saveButton = save
        let cancel = EditorChipButton(title: L10n.text(.editorCancel), symbol: nil, target: self, action: #selector(cancel), kind: .cancel)
        cancelButton = cancel

        let actions = NSStackView(views: [save, cancel])
        actions.orientation = .horizontal
        actions.spacing = 6

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 12
        topRow.addArrangedSubview(presets)
        topRow.addArrangedSubview(actions)

        let hint = NSTextField(wrappingLabelWithString: L10n.text(.editorHint))
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.92)
        hint.isBezeled = false
        hint.drawsBackground = false
        hint.isSelectable = false
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hintLabel = hint

        var rows: [NSView] = [topRow]
        if !isNew && original.kind == .grid {
            let protection = NSTextField(wrappingLabelWithString: L10n.text(.editorGridProtected))
            protection.font = .systemFont(ofSize: 12, weight: .semibold)
            protection.textColor = .systemOrange
            protection.isBezeled = false
            protection.drawsBackground = false
            protection.isSelectable = false
            protectionLabel = protection
            rows.append(protection)
        }
        rows.append(hint)

        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .leading
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

    private func applyPreset(_ layout: Layout) {
        guard var transaction else { return }
        var draft = layout
        draft.id = transaction.draft.id
        draft.name = transaction.draft.name
        draft.createdAt = transaction.draft.createdAt
        transaction.updateDraft(draft)
        self.transaction = transaction
        canvas?.layout = draft
        canvas?.needsDisplay = true
        updateSaveState()
    }

    @objc private func presetColumns2() { applyPreset(LayoutTemplates.columns(2)) }
    @objc private func presetColumns3() { applyPreset(LayoutTemplates.columns(3)) }
    @objc private func presetRows2() { applyPreset(LayoutTemplates.rows(2)) }
    @objc private func presetGrid() { applyPreset(LayoutTemplates.grid2x2()) }
    @objc private func presetPriority() { applyPreset(LayoutTemplates.priority3()) }
    @objc private func presetFocus() { applyPreset(LayoutTemplates.focus()) }

    @objc private func save() {
        guard let transaction, transaction.canCommit else {
            NSSound.beep()
            return
        }
        if let layout = transaction.layoutForCommit(existingNames: runtime.document.layouts.map(\.name)) {
            runtime.saveLayout(layout, to: transaction.targetDisplayID)
        }
        dismiss()
    }

    @objc func cancel() {
        dismiss()
    }

    func cancelEditing() {
        dismiss()
    }

    func applyLanguage() {
        let keys: [L10nKey] = [
            .editorColumns2, .editorColumns3, .editorRows2, .editorGrid2x2, .editorPriority, .editorFocus,
        ]
        for (button, key) in zip(presetButtons, keys) {
            button.setChipTitle(L10n.text(key))
        }
        let saveTitle = !isNew && original.kind == .grid ? L10n.text(.editorSaveCopy) : L10n.text(.editorSave)
        saveButton?.setChipTitle(saveTitle)
        cancelButton?.setChipTitle(L10n.text(.editorCancel))
        hintLabel?.stringValue = L10n.text(.editorHint)
        protectionLabel?.stringValue = L10n.text(.editorGridProtected)
        updateSaveState()
    }

    private func updateDraft(_ layout: Layout) {
        transaction?.updateDraft(layout)
        updateSaveState()
    }

    private func updateSaveState() {
        guard let transaction else { return }
        saveButton?.isEnabled = transaction.canCommit
        saveButton?.toolTip = transaction.canCommit
            ? (!isNew && original.kind == .grid ? L10n.text(.editorSaveCopyTooltip) : L10n.text(.editorSaveTooltip))
            : L10n.text(.editorSaveDisabledTooltip)
    }

    private func setToolbarReceded(_ receded: Bool) {
        guard let toolbar else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = receded ? 0.12 : 0.2
            toolbar.animator().alphaValue = receded ? 0.12 : 1
        }
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        canvas = nil
        toolbar = nil
        saveButton = nil
        cancelButton = nil
        presetButtons = []
        hintLabel = nil
        protectionLabel = nil
        transaction = nil
        runtime.isEditorOpen = false
        runtime.uiSession.leaveRegular()
        runtime.editorDidClose()
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
        case .preset:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
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
        toolTip = title
    }

    func setChipTitle(_ title: String) {
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        )
        toolTip = title
        invalidateIntrinsicContentSize()
        needsDisplay = true
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
