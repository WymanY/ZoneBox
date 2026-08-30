import AppKit
import ServiceManagement
import ZoneBoxCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: NSWindow?

    private var categoryControl: NSSegmentedControl?
    private var pageViews: [SettingsCategory: NSView] = [:]
    private var selectedCategory: SettingsCategory = .snapping

    private var previewTitle: NSTextField?
    private var previewDescription: NSTextField?
    private var previewImageView: NSImageView?
    private var accessStatusIcon: NSImageView?
    private var accessStatusLabel: NSTextField?
    private var accessButton: NSButton?

    private var localizedLabels: [(NSTextField, L10nKey)] = []
    private var localizedButtons: [(NSButton, L10nKey)] = []

    private var shiftSwitch: NSSwitch?
    private var rightSwitch: NSSwitch?
    private var shakeSwitch: NSSwitch?
    private var shakeIntensityLabel: NSTextField?
    private var shakeIntensityHint: NSTextField?
    private var shakeIntensitySlider: NSSlider?
    private var shakeRow: NSView?
    private var quickSnapperSwitch: NSSwitch?
    private var magneticSwitch: NSSwitch?
    private var numbersSwitch: NSSwitch?
    private var restoreSwitch: NSSwitch?
    private var gutterLabel: NSTextField?
    private var gutterSlider: NSSlider?
    private var hotkeysLabel: NSTextField?
    private var shortcutsButton: NSButton?
    private var loginSwitch: NSSwitch?
    private var languagePopup: NSPopUpButton?
    private var hotkeyList: NSStackView?
    private var hotkeyErrorLabel: NSTextField?
    private var resetAllButton: NSButton?
    private var recordingID: ShortcutCustomizationID?
    private var localKeyMonitor: Any?

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
    }

    func showWindow() {
        if window == nil { window = makeWindow() }
        applyPresentation()
        refreshAccessStatus()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPresentation() {
        guard let window else { return }
        applyPresentation(to: window)
    }

    private func applyPresentation(to window: NSWindow) {
        window.hidesOnDeactivate = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    func close() { window?.close() }
    var isKey: Bool { window?.isKeyWindow == true }
    var isRecordingHotkey: Bool { recordingID != nil }

    @discardableResult
    func cancelHotkeyRecording() -> Bool {
        guard recordingID != nil else { return false }
        stopRecording()
        reloadHotkeyRows()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        window = nil
        runtime.settingsDidClose()
    }

    private func makeWindow() -> NSWindow {
        localizedLabels.removeAll()
        localizedButtons.removeAll()
        pageViews.removeAll()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.settingsTitle)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.center()
        window.minSize = NSSize(width: 860, height: 620)
        window.setContentSize(NSSize(width: 980, height: 720))
        applyPresentation(to: window)

        let content = NSVisualEffectView()
        content.material = .contentBackground
        content.blendingMode = .withinWindow
        content.state = .followsWindowActiveState
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        let categories = NSSegmentedControl(
            labels: SettingsCategory.allCases.map { L10n.text($0.titleKey) },
            trackingMode: .selectOne,
            target: self,
            action: #selector(categoryChanged(_:))
        )
        categories.controlSize = .large
        categories.segmentStyle = .automatic
        categories.selectedSegment = selectedCategory.rawValue
        categories.translatesAutoresizingMaskIntoConstraints = false
        categories.setAccessibilityLabel(L10n.text(.settingsTitle))
        categoryControl = categories
        content.addSubview(categories)

        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.setContentHuggingPriority(.defaultLow, for: .horizontal)
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for category in SettingsCategory.allCases {
            let page = makePage(for: category)
            page.translatesAutoresizingMaskIntoConstraints = false
            page.isHidden = category != selectedCategory
            host.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: host.topAnchor),
                page.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                page.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
            pageViews[category] = page
        }

        let preview = makePreviewPanel()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 300).isActive = true
        preview.setContentHuggingPriority(.required, for: .horizontal)
        preview.setContentHuggingPriority(.required, for: .vertical)
        preview.setContentCompressionResistancePriority(.required, for: .horizontal)
        preview.setContentCompressionResistancePriority(.required, for: .vertical)

        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(host)
        body.addSubview(preview)
        content.addSubview(body)

        NSLayoutConstraint.activate([
            categories.topAnchor.constraint(equalTo: content.topAnchor, constant: 52),
            categories.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            categories.widthAnchor.constraint(equalToConstant: 420),
            body.topAnchor.constraint(equalTo: categories.bottomAnchor, constant: 20),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            body.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            host.topAnchor.constraint(equalTo: body.topAnchor),
            host.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: preview.leadingAnchor, constant: -20),
            host.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            preview.topAnchor.constraint(equalTo: body.topAnchor),
            preview.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            preview.bottomAnchor.constraint(lessThanOrEqualTo: body.bottomAnchor),
        ])

        updatePreview()
        refreshAccessStatus()
        return window
    }

    private func makePage(for category: SettingsCategory) -> NSView {
        let content = SettingsFlippedView()
        content.translatesAutoresizingMaskIntoConstraints = false

        let title = localizedLabel(
            category.titleKey,
            font: .systemFont(ofSize: 22, weight: .semibold),
            color: .labelColor
        )
        title.alignment = .left
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = localizedWrappingLabel(
            category.subtitleKey,
            font: .systemFont(ofSize: 13),
            color: .secondaryLabelColor
        )
        subtitle.alignment = .left
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let group: NSView
        switch category {
        case .general: group = makeGeneralGroup()
        case .snapping: group = makeSnappingGroup()
        case .overlay: group = makeOverlayGroup()
        case .keyboard: group = makeKeyboardGroup()
        }
        group.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)
        content.addSubview(subtitle)
        content.addSubview(group)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            group.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            group.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            group.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        return makeScrollablePage(content)
    }

    private func makeGeneralGroup() -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: Self.languageTitles())
        popup.selectItem(at: Self.languageIndex(runtime.settings.uiLanguage))
        popup.target = self
        popup.action = #selector(languageChanged(_:))
        popup.controlSize = .regular
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        popup.setAccessibilityLabel(L10n.text(.settingsLanguage))
        languagePopup = popup

        let login = settingSwitch(
            titleKey: .settingsLaunchAtLogin,
            on: runtime.settings.launchAtLogin,
            action: #selector(toggleLogin(_:))
        )
        loginSwitch = login

        return makeGroupedRows([
            makeSettingRow(symbol: "globe", titleKey: .settingsLanguage, detailKey: .settingsLanguageDetail, trailing: popup),
            makeSettingRow(symbol: "power", titleKey: .settingsLaunchAtLogin, detailKey: .settingsLaunchAtLoginDetail, trailing: login),
        ])
    }

    private func makeSnappingGroup() -> NSView {
        let shift = settingSwitch(titleKey: .settingsShiftDrag, on: runtime.settings.snapOnShiftDrag, action: #selector(toggleShift(_:)))
        let right = settingSwitch(titleKey: .settingsRightClick, on: runtime.settings.snapOnRightClickDrag, action: #selector(toggleRight(_:)))
        let shake = settingSwitch(titleKey: .settingsShakeToSnap, on: runtime.settings.shakeToSnapEnabled, action: #selector(toggleShake(_:)))
        let magnetic = settingSwitch(titleKey: .settingsMagneticResize, on: runtime.settings.magneticResizeEnabled, action: #selector(toggleMagnetic(_:)))
        let restore = settingSwitch(titleKey: .settingsRestoreSize, on: runtime.settings.restoreSizeOnUnsnap, action: #selector(toggleRestore(_:)))
        let quick = settingSwitch(titleKey: .settingsQuickSnapper, on: runtime.settings.quickSnapperEnabled, action: #selector(toggleQuickSnapper(_:)))
        shiftSwitch = shift
        rightSwitch = right
        shakeSwitch = shake
        magneticSwitch = magnetic
        restoreSwitch = restore
        quickSnapperSwitch = quick

        return makeStackedSections([
            (
                .settingsSnappingTriggersSection,
                [
                    makeSettingRow(symbol: "arrow.up.right.square", titleKey: .settingsShiftDrag, detailKey: .settingsShiftDragDetail, trailing: shift),
                    makeSettingRow(symbol: "computermouse.fill", fallbackSymbol: "cursorarrow.click.2", titleKey: .settingsRightClick, detailKey: .settingsRightClickDetail, trailing: right),
                    makeShakeSettingRow(switchControl: shake),
                ]
            ),
            (
                .settingsSnappingBehaviorSection,
                [
                    makeSettingRow(symbol: "arrow.left.and.right.square", fallbackSymbol: "rectangle.split.2x1", titleKey: .settingsMagneticResize, detailKey: .settingsMagneticResizeDetail, trailing: magnetic),
                    makeSettingRow(symbol: "arrow.counterclockwise", titleKey: .settingsRestoreSize, detailKey: .settingsRestoreSizeDetail, trailing: restore),
                    makeSettingRow(symbol: "rectangle.stack.fill", titleKey: .settingsQuickSnapper, detailKey: .settingsQuickSnapperDetail, trailing: quick),
                ]
            ),
        ])
    }

    private func makeOverlayGroup() -> NSView {
        let numbers = settingSwitch(titleKey: .settingsShowNumbers, on: runtime.settings.showZoneNumbers, action: #selector(toggleNumbers(_:)))
        numbersSwitch = numbers
        return makeGroupedRows([
            makeSettingRow(symbol: "number.square.fill", titleKey: .settingsShowNumbers, detailKey: .settingsShowNumbersDetail, trailing: numbers),
            makeGutterControls(),
        ])
    }

    private func makeKeyboardGroup() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stack.detachesHiddenViews = true

        let hotkeys = localizedWrappingLabel(.settingsHotkeyCaptureHint, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        hotkeysLabel = hotkeys
        stack.addArrangedSubview(makeInfoRow(label: hotkeys))
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeHotkeyList())
        stack.addArrangedSubview(makeHotkeyErrorLabel())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeActionRow())
        return SettingsGroupSurfaceView(content: stack)
    }

    private func makeSettingRow(
        symbol: String,
        fallbackSymbol: String? = nil,
        titleKey: L10nKey,
        detailKey: L10nKey?,
        trailing: NSView,
        footer: NSView? = nil
    ) -> NSView {
        let icon = SettingsRowIconView(
            symbolName: availableSymbol(symbol, fallback: fallbackSymbol),
            title: L10n.text(titleKey),
            tint: .controlAccentColor
        )
        let title = localizedLabel(titleKey, font: .systemFont(ofSize: 14, weight: .medium), color: .labelColor)
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.alignment = .left
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let detail: NSTextField?
        if let detailKey {
            let label = localizedWrappingLabel(detailKey, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
            label.maximumNumberOfLines = 2
            label.alignment = .left
            detail = label
        } else {
            detail = nil
        }

        return SettingsPreferenceRowView(
            icon: icon,
            title: title,
            detail: detail,
            accessory: trailing,
            footer: footer
        )
    }

    private func makeShakeSettingRow(switchControl: NSSwitch) -> NSView {
        let slider = NSSlider(
            value: Double(runtime.settings.shakeIntensity),
            minValue: Double(ShakeProfile.intensityRange.lowerBound),
            maxValue: Double(ShakeProfile.intensityRange.upperBound),
            target: self,
            action: #selector(shakeIntensityChanged(_:))
        )
        slider.controlSize = .small
        slider.numberOfTickMarks = ShakeProfile.intensityRange.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.isEnabled = runtime.settings.shakeToSnapEnabled
        slider.setAccessibilityLabel(L10n.text(.settingsShakeIntensityHint))
        shakeIntensitySlider = slider

        let label = NSTextField(labelWithString: L10n.shakeIntensity(runtime.settings.shakeIntensity))
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.setContentHuggingPriority(.required, for: .horizontal)
        shakeIntensityLabel = label

        let hint = localizedLabel(.settingsShakeIntensityHint, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        hint.alignment = .right
        hint.setContentHuggingPriority(.required, for: .horizontal)
        shakeIntensityHint = hint

        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let caption = NSStackView(views: [label, NSView(), hint])
        caption.orientation = .horizontal
        caption.alignment = .centerY
        caption.spacing = 8
        let nested = NSStackView(views: [slider, caption])
        nested.orientation = .vertical
        nested.alignment = .width
        nested.spacing = 4
        nested.isHidden = !runtime.settings.shakeToSnapEnabled
        shakeRow = nested

        return makeSettingRow(
            symbol: "waveform.path",
            titleKey: .settingsShakeToSnap,
            detailKey: .settingsShakeToSnapDetail,
            trailing: switchControl,
            footer: nested
        )
    }

    private func makeGutterControls() -> NSView {
        let gutter = NSTextField(labelWithString: L10n.gutter(runtime.settings.gutterPoints))
        gutter.font = .systemFont(ofSize: 14, weight: .medium)
        gutter.textColor = .labelColor
        gutter.alignment = .left
        gutter.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gutter.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        gutterLabel = gutter

        let slider = NSSlider(value: Double(runtime.settings.gutterPoints), minValue: 0, maxValue: 40, target: self, action: #selector(gutterChanged(_:)))
        slider.controlSize = .small
        slider.isContinuous = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gutterSlider = slider
        applyGutterAccessibility()

        let icon = SettingsRowIconView(
            symbolName: availableSymbol("arrow.left.and.right.square", fallback: "rectangle.split.2x1"),
            title: L10n.text(.settingsGutter),
            tint: .controlAccentColor
        )
        let detail = localizedWrappingLabel(.settingsGutterDetail, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        detail.maximumNumberOfLines = 2
        return SettingsPreferenceRowView(
            icon: icon,
            title: gutter,
            detail: detail,
            accessory: nil,
            footer: slider
        )
    }

    private func makeStackedSections(_ sections: [(L10nKey, [NSView])]) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        var previous: NSView?
        for (index, section) in sections.enumerated() {
            let heading = localizedLabel(section.0, font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor)
            heading.alignment = .left
            heading.translatesAutoresizingMaskIntoConstraints = false
            let group = makeGroupedRows(section.1)
            group.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(heading)
            container.addSubview(group)
            var constraints = [
                heading.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                heading.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                group.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                group.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                group.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            ]
            if let previous {
                constraints.append(heading.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: 18))
            } else {
                constraints.append(heading.topAnchor.constraint(equalTo: container.topAnchor))
            }
            if index == sections.count - 1 {
                constraints.append(group.bottomAnchor.constraint(equalTo: container.bottomAnchor))
            }
            NSLayoutConstraint.activate(constraints)
            previous = group
        }
        return container
    }

    private func makeGroupedRows(_ rows: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 0
        stack.detachesHiddenViews = true
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for (index, row) in rows.enumerated() {
            row.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if index < rows.count - 1 {
                stack.addArrangedSubview(makeSeparator(inset: SettingsMetrics.rowInset + SettingsMetrics.iconSize + SettingsMetrics.iconTitleGap))
            }
        }
        return SettingsGroupSurfaceView(content: stack)
    }

    private func makeInfoRow(label: NSTextField) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func makeActionRow() -> NSView {
        let shortcuts = localizedButton(.settingsShowShortcuts, action: #selector(openShortcuts))
        shortcuts.bezelStyle = .rounded
        shortcuts.controlSize = .small
        shortcutsButton = shortcuts
        let resetAll = localizedButton(.settingsResetAllShortcuts, action: #selector(resetAllShortcuts))
        resetAll.bezelStyle = .rounded
        resetAll.controlSize = .small
        resetAllButton = resetAll
        let openAccess = localizedButton(.settingsOpenAccess, action: #selector(openAccess))
        openAccess.bezelStyle = .rounded
        openAccess.controlSize = .small
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [shortcuts, resetAll, spacer, openAccess])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makeHotkeyList() -> NSView {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .width
        list.distribution = .fill
        list.spacing = 6
        list.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hotkeyList = list
        reloadHotkeyRows()
        return list
    }

    private func makeHotkeyErrorLabel() -> NSView {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .systemRed
        label.isHidden = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hotkeyErrorLabel = label
        return label
    }

    private func makePreviewPanel() -> NSView {
        let panel = SettingsPreviewPanel()
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .left
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.translatesAutoresizingMaskIntoConstraints = false
        previewTitle = title

        let image = NSImageView()
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        previewImageView = image

        let description = NSTextField(wrappingLabelWithString: "")
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        description.alignment = .center
        description.maximumNumberOfLines = 3
        description.translatesAutoresizingMaskIntoConstraints = false
        previewDescription = description

        let statusIcon = NSImageView()
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        accessStatusIcon = statusIcon

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        accessStatusLabel = statusLabel

        let manageAccess = NSButton(title: "", target: self, action: #selector(openAccess))
        manageAccess.bezelStyle = .rounded
        manageAccess.controlSize = .small
        manageAccess.setContentHuggingPriority(.required, for: .horizontal)
        accessButton = manageAccess

        let statusRow = NSStackView(views: [statusIcon, statusLabel, manageAccess])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        let separator = makeSeparator()
        separator.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(title)
        panel.addSubview(image)
        panel.addSubview(description)
        panel.addSubview(separator)
        panel.addSubview(statusRow)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
            image.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            image.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            image.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: 0.72),
            description.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 10),
            description.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            description.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
            description.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -14),
            separator.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: statusRow.topAnchor, constant: -12),
            statusRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            statusRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            statusRow.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
        ])
        return panel
    }

    private func makeScrollablePage(_ stack: NSView) -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.contentView.drawsBackground = false
        let document = SettingsFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -4),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    private func settingSwitch(titleKey: L10nKey, on: Bool, action: Selector) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.state = on ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.controlSize = .regular
        toggle.setAccessibilityLabel(L10n.text(titleKey))
        return toggle
    }

    private func localizedLabel(_ key: L10nKey, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: L10n.text(key))
        label.font = font
        label.textColor = color
        label.alignment = .left
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        localizedLabels.append((label, key))
        return label
    }

    private func localizedWrappingLabel(_ key: L10nKey, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: L10n.text(key))
        label.font = font
        label.textColor = color
        label.alignment = .left
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        localizedLabels.append((label, key))
        return label
    }

    private func localizedButton(_ key: L10nKey, action: Selector) -> NSButton {
        let button = NSButton(title: L10n.text(key), target: self, action: action)
        localizedButtons.append((button, key))
        return button
    }

    private func makeSeparator(inset: CGFloat = 0) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: container.topAnchor),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 1),
        ])
        return container
    }

    private func availableSymbol(_ preferred: String, fallback: String? = nil) -> String {
        if NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil { return preferred }
        if let fallback, NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil { return fallback }
        return "circle.fill"
    }

    @objc private func categoryChanged(_ sender: NSSegmentedControl) {
        guard let category = SettingsCategory(rawValue: sender.selectedSegment) else { return }
        if selectedCategory == .keyboard, category != .keyboard, recordingID != nil {
            stopRecording()
            reloadHotkeyRows()
        }
        selectedCategory = category
        for (candidate, page) in pageViews { page.isHidden = candidate != category }
        updatePreview()
    }

    private func updatePreview() {
        previewTitle?.stringValue = L10n.text(selectedCategory.previewTitleKey)
        previewDescription?.stringValue = L10n.text(selectedCategory.previewDescriptionKey)
        guard let imageView = previewImageView else { return }
        if selectedCategory == .snapping, let image = NSImage(named: "SnapPreview") {
            imageView.image = image
            imageView.contentTintColor = nil
        } else {
            let configuration = NSImage.SymbolConfiguration(pointSize: 72, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [selectedCategory.tint]))
            imageView.image = NSImage(
                systemSymbolName: selectedCategory.symbolName,
                accessibilityDescription: L10n.text(selectedCategory.titleKey)
            )?.withSymbolConfiguration(configuration)
            imageView.contentTintColor = selectedCategory.tint
        }
        imageView.setAccessibilityLabel(L10n.text(selectedCategory.previewTitleKey))
    }

    func refreshAccessStatus() {
        let trusted = runtime.trust.isTrusted()
        accessStatusIcon?.image = NSImage(
            systemSymbolName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        accessStatusIcon?.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        accessStatusIcon?.contentTintColor = trusted ? .systemGreen : .systemOrange
        accessStatusLabel?.stringValue = L10n.text(trusted ? .settingsAccessGranted : .settingsAccessRequired)
        accessButton?.title = L10n.text(.settingsManageAccess)
    }

    func applyLanguage() {
        window?.title = L10n.text(.settingsTitle)
        for (label, key) in localizedLabels { label.stringValue = L10n.text(key) }
        for (button, key) in localizedButtons { button.title = L10n.text(key) }
        for category in SettingsCategory.allCases {
            categoryControl?.setLabel(L10n.text(category.titleKey), forSegment: category.rawValue)
        }
        categoryControl?.setAccessibilityLabel(L10n.text(.settingsTitle))
        shiftSwitch?.setAccessibilityLabel(L10n.text(.settingsShiftDrag))
        rightSwitch?.setAccessibilityLabel(L10n.text(.settingsRightClick))
        shakeSwitch?.setAccessibilityLabel(L10n.text(.settingsShakeToSnap))
        magneticSwitch?.setAccessibilityLabel(L10n.text(.settingsMagneticResize))
        restoreSwitch?.setAccessibilityLabel(L10n.text(.settingsRestoreSize))
        quickSnapperSwitch?.setAccessibilityLabel(L10n.text(.settingsQuickSnapper))
        numbersSwitch?.setAccessibilityLabel(L10n.text(.settingsShowNumbers))
        loginSwitch?.setAccessibilityLabel(L10n.text(.settingsLaunchAtLogin))
        shakeIntensityLabel?.stringValue = L10n.shakeIntensity(runtime.settings.shakeIntensity)
        shakeIntensityHint?.stringValue = L10n.text(.settingsShakeIntensityHint)
        shakeIntensitySlider?.setAccessibilityLabel(L10n.text(.settingsShakeIntensityHint))
        applyGutterAccessibility()
        if let popup = languagePopup {
            popup.removeAllItems()
            popup.addItems(withTitles: Self.languageTitles())
            popup.selectItem(at: Self.languageIndex(runtime.settings.uiLanguage))
            popup.setAccessibilityLabel(L10n.text(.settingsLanguage))
        }
        reloadHotkeyRows()
        updatePreview()
        refreshAccessStatus()
    }

    private static func languageTitles() -> [String] {
        [L10n.text(.settingsLanguageSystem), L10n.text(.settingsLanguageEnglish), L10n.text(.settingsLanguageChinese)]
    }

    private static func languageIndex(_ preference: AppLanguagePreference) -> Int {
        switch preference {
        case .system: 0
        case .english: 1
        case .chineseSimplified: 2
        }
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let preference: AppLanguagePreference
        switch sender.indexOfSelectedItem {
        case 1: preference = .english
        case 2: preference = .chineseSimplified
        default: preference = .system
        }
        runtime.setUILanguage(preference)
    }

    @objc private func toggleShift(_ sender: NSSwitch) { runtime.settings.snapOnShiftDrag = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleRight(_ sender: NSSwitch) { runtime.settings.snapOnRightClickDrag = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleShake(_ sender: NSSwitch) {
        runtime.settings.shakeToSnapEnabled = sender.state == .on
        shakeIntensitySlider?.isEnabled = runtime.settings.shakeToSnapEnabled
        shakeRow?.isHidden = !runtime.settings.shakeToSnapEnabled
        runtime.persistSettings()
    }
    @objc private func shakeIntensityChanged(_ sender: NSSlider) {
        runtime.settings.shakeIntensity = ShakeProfile.clampedIntensity(Int(sender.doubleValue.rounded()))
        shakeIntensityLabel?.stringValue = L10n.shakeIntensity(runtime.settings.shakeIntensity)
        runtime.persistSettings()
    }
    @objc private func toggleQuickSnapper(_ sender: NSSwitch) { runtime.settings.quickSnapperEnabled = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleMagnetic(_ sender: NSSwitch) { runtime.settings.magneticResizeEnabled = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleNumbers(_ sender: NSSwitch) { runtime.settings.showZoneNumbers = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleRestore(_ sender: NSSwitch) { runtime.settings.restoreSizeOnUnsnap = sender.state == .on; runtime.persistSettings() }
    @objc private func openAccess() { runtime.openAccessibility() }
    @objc private func openShortcuts() { runtime.openShortcutPanel() }

    @objc private func resetAllShortcuts() {
        stopRecording()
        runtime.resetAllHotkeys()
        clearHotkeyError()
        reloadHotkeyRows()
    }

    private func reloadHotkeyRows() {
        guard let list = hotkeyList else { return }
        for view in list.arrangedSubviews {
            list.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for binding in ShortcutCatalog.customizableBindings(from: runtime.settings) {
            let row = makeHotkeyRow(binding.id, titleKey: binding.titleKey, chord: binding.chord)
            row.setContentHuggingPriority(.defaultLow, for: .horizontal)
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
    }

    private func makeHotkeyRow(_ id: ShortcutCustomizationID, titleKey: L10nKey, chord: KeyChord) -> NSView {
        let title = NSTextField(labelWithString: L10n.text(titleKey))
        title.font = .systemFont(ofSize: 13)
        title.alignment = .left
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let record = NSButton(title: recordingTitle(for: id, chord: chord), target: self, action: #selector(beginRecording(_:)))
        record.bezelStyle = .rounded
        record.controlSize = .small
        record.tag = ShortcutCustomizationID.allCases.firstIndex(of: id) ?? 0
        record.setContentHuggingPriority(.required, for: .horizontal)
        let reset = NSButton(title: L10n.text(.settingsResetShortcut), target: self, action: #selector(resetShortcut(_:)))
        reset.bezelStyle = .inline
        reset.controlSize = .small
        reset.tag = record.tag
        reset.setContentHuggingPriority(.required, for: .horizontal)
        let buttons = NSStackView(views: [record, reset])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 6
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(title)
        row.addSubview(buttons)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -12),
            buttons.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            buttons.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])
        return row
    }

    private func recordingTitle(for id: ShortcutCustomizationID, chord: KeyChord) -> String {
        if recordingID == id { return L10n.text(.settingsHotkeyRecording) }
        if id == .snapZones { return (Array(chord.displayCaps.dropLast()) + ["1–9"]).joined(separator: " ") }
        return chord.displayCaps.joined(separator: " ")
    }

    @objc private func beginRecording(_ sender: NSButton) {
        guard ShortcutCustomizationID.allCases.indices.contains(sender.tag) else { return }
        let id = ShortcutCustomizationID.allCases[sender.tag]
        if recordingID == id {
            stopRecording()
            reloadHotkeyRows()
            return
        }
        startRecording(id)
        reloadHotkeyRows()
    }

    @objc private func resetShortcut(_ sender: NSButton) {
        guard ShortcutCustomizationID.allCases.indices.contains(sender.tag) else { return }
        let id = ShortcutCustomizationID.allCases[sender.tag]
        stopRecording()
        if let issue = runtime.resetHotkey(id) { showHotkeyError(issue.message(language: LanguageCenter.language)) }
        else { clearHotkeyError() }
        reloadHotkeyRows()
    }

    private func startRecording(_ id: ShortcutCustomizationID) {
        recordingID = id
        clearHotkeyError()
        runtime.setHotkeyRecording(true)
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordingEvent(event) ?? event
        }
    }

    private func stopRecording() {
        recordingID = nil
        if localKeyMonitor != nil { runtime.setHotkeyRecording(false) }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handleRecordingEvent(_ event: NSEvent) -> NSEvent? {
        guard let id = recordingID else { return event }
        if event.keyCode == HardwareKeyCode.escape {
            stopRecording()
            reloadHotkeyRows()
            return nil
        }
        if event.isARepeat { return nil }
        let modifiers = KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return nil }
        if HardwareKeyCode.isModifierKey(event.keyCode) { return nil }
        let chord: KeyChord
        if id == .snapZones { chord = KeyChord(keyCode: AppSettings.zoneKeyCodes[0], carbonModifiers: modifiers) }
        else { chord = KeyChord(keyCode: event.keyCode, carbonModifiers: modifiers) }
        if let issue = runtime.updateHotkey(id, to: chord) {
            showHotkeyError(issue.message(language: LanguageCenter.language))
            return nil
        }
        stopRecording()
        clearHotkeyError()
        reloadHotkeyRows()
        return nil
    }

    private func showHotkeyError(_ message: String) { hotkeyErrorLabel?.stringValue = message; hotkeyErrorLabel?.isHidden = false }
    private func clearHotkeyError() { hotkeyErrorLabel?.stringValue = ""; hotkeyErrorLabel?.isHidden = true }

    @objc private func gutterChanged(_ sender: NSSlider) {
        runtime.settings.gutterPoints = Int(sender.doubleValue.rounded())
        applyGutterAccessibility()
        runtime.persistSettings()
    }

    private func applyGutterAccessibility() {
        let value = L10n.gutter(runtime.settings.gutterPoints)
        gutterLabel?.stringValue = value
        gutterSlider?.setAccessibilityLabel(value)
        gutterSlider?.setAccessibilityValue(value)
    }

    @objc private func toggleLogin(_ sender: NSSwitch) {
        runtime.settings.launchAtLogin = sender.state == .on
        runtime.persistSettings()
        do {
            if runtime.settings.launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.app.error("Login item failed: \(error.localizedDescription, privacy: .public)")
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
    }
}

private enum SettingsCategory: Int, CaseIterable {
    case general
    case snapping
    case overlay
    case keyboard

    var titleKey: L10nKey {
        switch self {
        case .general: .settingsSectionGeneral
        case .snapping: .settingsSectionSnapping
        case .overlay: .settingsSectionOverlay
        case .keyboard: .settingsSectionKeyboard
        }
    }
    var subtitleKey: L10nKey {
        switch self {
        case .general: .settingsGeneralSubtitle
        case .snapping: .settingsSnappingSubtitle
        case .overlay: .settingsOverlaySubtitle
        case .keyboard: .settingsKeyboardSubtitle
        }
    }
    var previewTitleKey: L10nKey {
        switch self {
        case .general: .settingsGeneralPreviewTitle
        case .snapping: .settingsSnappingPreviewTitle
        case .overlay: .settingsOverlayPreviewTitle
        case .keyboard: .settingsKeyboardPreviewTitle
        }
    }
    var previewDescriptionKey: L10nKey {
        switch self {
        case .general: .settingsGeneralPreviewDescription
        case .snapping: .settingsSnappingPreviewDescription
        case .overlay: .settingsOverlayPreviewDescription
        case .keyboard: .settingsKeyboardPreviewDescription
        }
    }
    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .snapping: "link"
        case .overlay: "square.grid.2x2.fill"
        case .keyboard: "keyboard.fill"
        }
    }
    var tint: NSColor {
        switch self {
        case .general: .systemBlue
        case .snapping: .controlAccentColor
        case .overlay: .systemMint
        case .keyboard: .systemOrange
        }
    }
}


private enum SettingsMetrics {
    static let rowInset: CGFloat = 14
    static let iconSize: CGFloat = 28
    static let iconTitleGap: CGFloat = 10
}

private final class SettingsPreferenceRowView: NSView {
    init(icon: NSView, title: NSTextField, detail: NSTextField?, accessory: NSView?, footer: NSView? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.translatesAutoresizingMaskIntoConstraints = false
        if let accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.distribution = .fill
        labels.detachesHiddenViews = true
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.alignment = .left
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        labels.addArrangedSubview(title)
        if let detail {
            detail.setContentHuggingPriority(.defaultLow, for: .horizontal)
            labels.addArrangedSubview(detail)
        }
        if let footer {
            footer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            footer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            labels.setCustomSpacing(8, after: labels.arrangedSubviews.last!)
            labels.addArrangedSubview(footer)
            footer.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        }

        addSubview(icon)
        addSubview(labels)
        if let accessory { addSubview(accessory) }
        var constraints: [NSLayoutConstraint] = [
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsMetrics.rowInset),
            icon.topAnchor.constraint(equalTo: title.topAnchor),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: SettingsMetrics.iconTitleGap),
            labels.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            labels.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            title.widthAnchor.constraint(equalTo: labels.widthAnchor),
        ]
        if let accessory {
            constraints.append(contentsOf: [
                labels.trailingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: -12),
                accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsMetrics.rowInset),
                accessory.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            ])
        } else {
            constraints.append(labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsMetrics.rowInset))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SettingsFlippedView: NSView { override var isFlipped: Bool { true } }

private final class SettingsRowIconView: NSView {
    private let tint: NSColor
    init(symbolName: String, title: String, tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        imageView.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: SettingsMetrics.iconSize),
            heightAnchor.constraint(equalToConstant: SettingsMetrics.iconSize),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
        ])
        updateColors()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = tint.withAlphaComponent(0.12).cgColor
            layer?.borderColor = tint.withAlphaComponent(0.08).cgColor
            layer?.borderWidth = 0.5
        }
    }
}

private final class SettingsGroupSurfaceView: NSVisualEffectView {
    init(content: NSView) {
        super.init(frame: .zero)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.translatesAutoresizingMaskIntoConstraints = false
        content.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updateColors()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.76).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
            layer?.borderWidth = 0.5
        }
    }
}

private final class SettingsPreviewPanel: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        updateColors()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.68).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
            layer?.borderWidth = 0.5
        }
    }
}
