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
    private var overlayPreviewView: SettingsOverlayPreviewView?
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
    private var layoutStripSwitch: NSSwitch?
    private var previewLayoutOnSelectSwitch: NSSwitch?
    private var gutterLabel: NSTextField?
    private var gutterSlider: NSSlider?
    private var hotkeysLabel: NSTextField?
    private var shortcutsButton: NSButton?
    private var loginSwitch: NSSwitch?
    private var hoverPinSwitch: NSSwitch?
    private var languagePopup: NSPopUpButton?
    private var hotkeyList: NSStackView?
    private var workspaceList: NSStackView?
    private var expandedWorkspaceIDs = Set<WorkspaceProfile.ID>()
    private var didInitializeWorkspaceExpansion = false
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
        NSApp.activate(ignoringOtherApps: true)
    }

    func showWorkspaces() {
        selectedCategory = .workspaces
        showWindow()
        categoryControl?.selectedSegment = SettingsCategory.workspaces.rawValue
        for (candidate, page) in pageViews { page.isHidden = candidate != .workspaces }
        updatePreview()
    }

    func showKeyboard() {
        selectedCategory = .keyboard
        showWindow()
        categoryControl?.selectedSegment = SettingsCategory.keyboard.rawValue
        for (candidate, page) in pageViews { page.isHidden = candidate != .keyboard }
        updatePreview()
    }

    private func applyPresentation() {
        guard let window else { return }
        applyPresentation(to: window)
    }

    private func applyPresentation(to window: NSWindow) {
        window.hidesOnDeactivate = false
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
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
            categories.widthAnchor.constraint(equalToConstant: 540),
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
        case .workspaces: group = makeWorkspacesGroup()
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

        let hoverPin = settingSwitch(
            titleKey: .settingsHoverPin,
            on: runtime.settings.hoverPinEnabled,
            action: #selector(toggleHoverPin(_:))
        )
        hoverPinSwitch = hoverPin

        return makeGroupedRows([
            makeSettingRow(symbol: "globe", titleKey: .settingsLanguage, detailKey: .settingsLanguageDetail, trailing: popup),
            makeSettingRow(
                symbol: "pin",
                customIcon: PinIconArtwork.image(state: .pin, size: 17),
                titleKey: .settingsHoverPin,
                detailKey: .settingsHoverPinDetail,
                trailing: hoverPin,
                badgeKey: .settingsBeta
            ),
            makeSettingRow(symbol: "power", titleKey: .settingsLaunchAtLogin, detailKey: .settingsLaunchAtLoginDetail, trailing: login),
            makeSettingRow(
                symbol: "questionmark.circle",
                titleKey: .settingsWelcomeTour,
                detailKey: .settingsWelcomeTourDetail,
                trailing: localizedButton(.settingsShowWelcomeTour, action: #selector(showWelcomeTour))
            ),
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
        let strip = settingSwitch(titleKey: .settingsShowLayoutStrip, on: runtime.settings.showLayoutStrip, action: #selector(toggleLayoutStrip(_:)))
        layoutStripSwitch = strip
        let preview = settingSwitch(titleKey: .settingsPreviewLayoutOnSelect, on: runtime.settings.previewLayoutOnSelect, action: #selector(togglePreviewLayoutOnSelect(_:)))
        previewLayoutOnSelectSwitch = preview
        return makeGroupedRows([
            makeSettingRow(symbol: "number.square.fill", titleKey: .settingsShowNumbers, detailKey: .settingsShowNumbersDetail, trailing: numbers),
            makeSettingRow(symbol: "rectangle.split.3x1", titleKey: .settingsShowLayoutStrip, detailKey: .settingsShowLayoutStripDetail, trailing: strip),
            makeSettingRow(symbol: "rectangle.dashed", titleKey: .settingsPreviewLayoutOnSelect, detailKey: .settingsPreviewLayoutOnSelectDetail, trailing: preview),
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
        let hint = makeInfoRow(label: hotkeys)
        stack.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeHotkeyList())
        stack.addArrangedSubview(makeHotkeyErrorLabel())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeActionRow())
        return SettingsGroupSurfaceView(content: stack)
    }

    private func makeWorkspacesGroup() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)
        stack.detachesHiddenViews = true
        workspaceList = stack
        reloadWorkspaceProfiles()
        return stack
    }

    func reloadWorkspaceProfiles() {
        guard let list = workspaceList else { return }
        for view in list.arrangedSubviews {
            list.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let profiles = runtime.document.orderedProfilesForSettings()
        expandedWorkspaceIDs.formIntersection(profiles.map(\.id))
        if !profiles.isEmpty, !didInitializeWorkspaceExpansion {
            let initialID = runtime.document.activeProfileID ?? profiles[0].id
            expandedWorkspaceIDs.insert(initialID)
            didInitializeWorkspaceExpansion = true
        }
        if profiles.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: L10n.text(.settingsWorkspaceEmpty))
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            let emptyContent = NSStackView(views: [empty])
            emptyContent.orientation = .vertical
            emptyContent.edgeInsets = NSEdgeInsets(top: 24, left: 18, bottom: 24, right: 18)
            let surface = SettingsGroupSurfaceView(content: emptyContent)
            list.addArrangedSubview(surface)
            surface.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            return
        }
        for profile in profiles {
            let card = makeWorkspaceRow(profile)
            list.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
    }

    private func makeWorkspaceRow(_ profile: WorkspaceProfile) -> NSView {
        let isActive = profile.id == runtime.document.activeProfileID
        let workspaceIcon = SettingsRowIconView(
            symbolName: "square.grid.2x2.fill",
            title: profile.name,
            tint: .systemIndigo
        )
        let title = NSTextField(labelWithString: profile.name)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var titleViews: [NSView] = [title]
        if isActive {
            titleViews.append(WorkspaceStatusBadgeView(text: L10n.text(.settingsWorkspaceActive)))
        }
        titleViews.append(NSView())
        let titleRow = NSStackView(views: titleViews)
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 7

        let detail = NSTextField(
            labelWithString: String(
                format: L10n.text(.settingsWorkspaceSummary),
                profile.sections.count,
                profile.applicationCount
            )
        )
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor

        let expanded = expandedWorkspaceIDs.contains(profile.id)
        let detailsToggle = NSButton(
            title: L10n.text(expanded ? .settingsWorkspaceHideDetails : .settingsWorkspaceShowDetails),
            target: self,
            action: #selector(toggleWorkspaceDetails(_:))
        )
        detailsToggle.bezelStyle = .inline
        detailsToggle.controlSize = .small
        detailsToggle.identifier = NSUserInterfaceItemIdentifier(profile.id.uuidString)
        detailsToggle.image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: detailsToggle.title
        )
        detailsToggle.imagePosition = .imageLeading
        detailsToggle.contentTintColor = .secondaryLabelColor
        detailsToggle.setContentHuggingPriority(.required, for: .horizontal)

        let summary = NSStackView(views: [detail, detailsToggle, NSView()])
        summary.orientation = .horizontal
        summary.alignment = .centerY
        summary.spacing = 6

        let labels = NSStackView(views: [titleRow, summary])
        labels.orientation = .vertical
        labels.alignment = .width
        labels.spacing = 3
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let launch = NSButton(
            checkboxWithTitle: L10n.text(.settingsWorkspaceLaunchMissing),
            target: self,
            action: #selector(toggleWorkspaceLaunch(_:))
        )
        launch.state = profile.launchMissingApps ? .on : .off
        launch.controlSize = .small
        launch.identifier = NSUserInterfaceItemIdentifier(profile.id.uuidString)

        let recapture = NSButton(
            title: L10n.text(.settingsWorkspaceRecapture),
            target: self,
            action: #selector(recaptureWorkspace(_:))
        )
        recapture.bezelStyle = .rounded
        recapture.controlSize = .small
        recapture.identifier = NSUserInterfaceItemIdentifier(profile.id.uuidString)
        recapture.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: recapture.title)
        recapture.imagePosition = .imageLeading
        recapture.setContentHuggingPriority(.required, for: .horizontal)

        let rename = workspaceIconButton(
            symbol: "pencil",
            title: L10n.text(.settingsWorkspaceRename),
            profile: profile,
            action: #selector(renameWorkspace(_:)),
            tint: .secondaryLabelColor
        )
        let delete = workspaceIconButton(
            symbol: "trash",
            title: L10n.text(.settingsWorkspaceDelete),
            profile: profile,
            action: #selector(deleteWorkspace(_:)),
            tint: .systemRed
        )

        let actions = NSStackView(views: [recapture, rename, delete])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 4
        actions.setContentHuggingPriority(.required, for: .horizontal)
        let header = NSStackView(views: [workspaceIcon, labels, NSView(), actions])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = 11
        header.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let options = NSStackView(views: [launch, NSView()])
        options.orientation = .horizontal
        options.alignment = .centerY
        options.spacing = 20
        options.edgeInsets = NSEdgeInsets(top: 0, left: 39, bottom: 0, right: 0)

        var rowViews: [NSView] = [header]
        if expanded {
            rowViews.append(makeWorkspaceDetails(profile))
        }
        rowViews.append(makeSeparator(inset: 39))
        rowViews.append(options)
        let row = NSStackView(views: rowViews)
        row.orientation = .vertical
        row.alignment = .width
        row.spacing = 11
        row.edgeInsets = NSEdgeInsets(top: 15, left: 16, bottom: 13, right: 14)
        return WorkspaceCardView(content: row, active: isActive)
    }

    private func makeWorkspaceDetails(_ profile: WorkspaceProfile) -> NSView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        for (sectionIndex, section) in profile.sections.enumerated() {
            let displayName = runtime.document.displays.first(where: { $0.id == section.space.displayID })?.localizedName
                ?? L10n.text(.settingsWorkspaceUnavailableDisplay)
            let layoutName = runtime.document.layouts.first(where: { $0.id == section.layoutID })
                .map { L10n.layoutDisplayName($0.name) }
                ?? L10n.text(.settingsWorkspaceUnavailableLayout)
            let sectionTitle = NSTextField(
                labelWithString: String(
                    format: L10n.text(.settingsWorkspaceSectionSummary),
                    displayName,
                    layoutName
                )
            )
            sectionTitle.font = .systemFont(ofSize: 11, weight: .semibold)
            sectionTitle.textColor = .secondaryLabelColor
            let displayIcon = NSImageView()
            displayIcon.image = NSImage(systemSymbolName: "display", accessibilityDescription: displayName)
            displayIcon.symbolConfiguration = .init(pointSize: 11, weight: .medium)
            displayIcon.contentTintColor = .secondaryLabelColor
            displayIcon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                displayIcon.widthAnchor.constraint(equalToConstant: 16),
                displayIcon.heightAnchor.constraint(equalToConstant: 16),
            ])
            let sectionHeader = NSStackView(views: [displayIcon, sectionTitle, NSView()])
            sectionHeader.orientation = .horizontal
            sectionHeader.alignment = .centerY
            sectionHeader.spacing = 6
            content.addArrangedSubview(sectionHeader)

            for rule in section.rules {
                content.addArrangedSubview(makeWorkspaceApplicationRow(rule))
            }
            if sectionIndex < profile.sections.count - 1 {
                content.addArrangedSubview(makeSeparator())
            }
        }
        return WorkspaceDetailsSurfaceView(content: content)
    }

    private func makeWorkspaceApplicationRow(_ rule: AppPlacementRule) -> NSView {
        let info = workspaceApplicationInfo(bundleID: rule.bundleID)
        let icon = NSImageView()
        icon.image = info.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel(info.name)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
        ])

        let name = NSTextField(labelWithString: info.name)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        let bundle = NSTextField(labelWithString: rule.bundleID)
        bundle.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        bundle.textColor = .secondaryLabelColor
        bundle.lineBreakMode = .byTruncatingMiddle
        let labels = NSStackView(views: [name, bundle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let zone = WorkspaceZoneBadgeView(
            text: String(format: L10n.text(.settingsWorkspaceZone), rule.zoneNumber)
        )

        let row = NSStackView(views: [icon, labels, NSView(), zone])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func workspaceApplicationInfo(bundleID: String) -> (name: String, icon: NSImage?) {
        let runningName = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.localizedName
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return (
                runningName ?? bundleID,
                NSImage(systemSymbolName: "app.fill", accessibilityDescription: runningName ?? bundleID)
            )
        }
        let bundle = Bundle(url: url)
        let storedName = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let name = runningName ?? storedName ?? url.deletingPathExtension().lastPathComponent
        let icon = (NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage)
            ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: name)
        return (name, icon)
    }

    private func workspaceIconButton(
        symbol: String,
        title: String,
        profile: WorkspaceProfile,
        action: Selector,
        tint: NSColor
    ) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = tint
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.identifier = NSUserInterfaceItemIdentifier(profile.id.uuidString)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
        return button
    }

    private func workspaceProfile(for control: NSControl) -> WorkspaceProfile? {
        guard let raw = control.identifier?.rawValue, let id = UUID(uuidString: raw) else { return nil }
        return runtime.document.profiles.first(where: { $0.id == id })
    }

    @objc private func toggleWorkspaceDetails(_ sender: NSButton) {
        guard let profile = workspaceProfile(for: sender) else { return }
        if expandedWorkspaceIDs.contains(profile.id) {
            expandedWorkspaceIDs.remove(profile.id)
        } else {
            expandedWorkspaceIDs.insert(profile.id)
        }
        reloadWorkspaceProfiles()
    }

    @objc private func toggleWorkspaceLaunch(_ sender: NSButton) {
        guard var profile = workspaceProfile(for: sender) else { return }
        profile.launchMissingApps = sender.state == .on
        runtime.workspace.updateProfile(profile)
    }

    @objc private func recaptureWorkspace(_ sender: NSButton) {
        guard let profile = workspaceProfile(for: sender) else { return }
        runtime.workspace.capture(name: profile.name, replacing: profile.id)
    }

    @objc private func renameWorkspace(_ sender: NSButton) {
        guard var profile = workspaceProfile(for: sender) else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text(.settingsWorkspaceRename)
        let field = NSTextField(string: profile.name)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text(.workspaceSave))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        profile.name = LayoutEditTransaction.uniqueName(
            base: name,
            existingNames: runtime.document.profiles.filter { $0.id != profile.id }.map(\.name)
        )
        runtime.workspace.updateProfile(profile)
    }

    @objc private func deleteWorkspace(_ sender: NSButton) {
        guard let profile = workspaceProfile(for: sender) else { return }
        let alert = NSAlert()
        alert.messageText = String(format: L10n.text(.settingsWorkspaceDeleteTitle), profile.name)
        alert.addButton(withTitle: L10n.text(.settingsWorkspaceDelete))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runtime.workspace.deleteProfile(id: profile.id)
    }

    private func makeSettingRow(
        symbol: String,
        fallbackSymbol: String? = nil,
        customIcon: NSImage? = nil,
        titleKey: L10nKey,
        detailKey: L10nKey?,
        trailing: NSView,
        footer: NSView? = nil,
        badgeKey: L10nKey? = nil
    ) -> NSView {
        let icon = SettingsRowIconView(
            image: customIcon ?? NSImage(
                systemSymbolName: availableSymbol(symbol, fallback: fallbackSymbol),
                accessibilityDescription: L10n.text(titleKey)
            ),
            title: L10n.text(titleKey),
            tint: .controlAccentColor
        )
        let title = localizedLabel(titleKey, font: .systemFont(ofSize: 14, weight: .medium), color: .labelColor)
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.alignment = .left
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleView: NSView
        if let badgeKey {
            let badge = SettingsBetaBadgeView(text: L10n.text(badgeKey))
            localizedLabels.append((badge.label, badgeKey))
            let titleRow = NSStackView(views: [title, badge, NSView()])
            titleRow.orientation = .horizontal
            titleRow.alignment = .centerY
            titleRow.spacing = 6
            titleRow.translatesAutoresizingMaskIntoConstraints = false
            titleRow.setContentHuggingPriority(.defaultLow, for: .horizontal)
            titleRow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            title.setContentHuggingPriority(.required, for: .horizontal)
            title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            titleView = titleRow
        } else {
            titleView = title
        }

        let detail: NSTextField?
        if let detailKey {
            let label = localizedWrappingLabel(detailKey, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
            label.maximumNumberOfLines = badgeKey == nil ? 2 : 3
            label.alignment = .left
            detail = label
        } else {
            detail = nil
        }

        return SettingsPreferenceRowView(
            icon: icon,
            title: titleView,
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
        SettingsInfoHintRow(label: label)
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
        reloadWorkspaceProfiles()
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
        image.imageScaling = .scaleProportionallyDown
        image.translatesAutoresizingMaskIntoConstraints = false
        previewImageView = image

        let overlayPreview = SettingsOverlayPreviewView()
        overlayPreview.translatesAutoresizingMaskIntoConstraints = false
        overlayPreview.isHidden = true
        overlayPreviewView = overlayPreview

        let previewHost = NSView()
        previewHost.translatesAutoresizingMaskIntoConstraints = false
        previewHost.addSubview(image)
        previewHost.addSubview(overlayPreview)
        NSLayoutConstraint.activate([
            image.topAnchor.constraint(equalTo: previewHost.topAnchor),
            image.leadingAnchor.constraint(equalTo: previewHost.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: previewHost.trailingAnchor),
            image.bottomAnchor.constraint(equalTo: previewHost.bottomAnchor),
            overlayPreview.topAnchor.constraint(equalTo: previewHost.topAnchor),
            overlayPreview.leadingAnchor.constraint(equalTo: previewHost.leadingAnchor),
            overlayPreview.trailingAnchor.constraint(equalTo: previewHost.trailingAnchor),
            overlayPreview.bottomAnchor.constraint(equalTo: previewHost.bottomAnchor),
        ])

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
        panel.addSubview(previewHost)
        panel.addSubview(description)
        panel.addSubview(separator)
        panel.addSubview(statusRow)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
            previewHost.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            previewHost.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            previewHost.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            previewHost.heightAnchor.constraint(equalTo: previewHost.widthAnchor, multiplier: 0.72),
            description.topAnchor.constraint(equalTo: previewHost.bottomAnchor, constant: 10),
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
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
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
        let overlayPreview = overlayPreviewView

        imageView.isHidden = selectedCategory == .overlay
        overlayPreview?.isHidden = selectedCategory != .overlay

        if selectedCategory == .overlay {
            overlayPreview?.showNumbers = runtime.settings.showZoneNumbers
            overlayPreview?.gutterPoints = runtime.settings.gutterPoints
            overlayPreview?.showCandidateLayouts = runtime.settings.showLayoutStrip
            overlayPreview?.candidateLayouts = runtime.document.orderedLayouts(
                assignedID: runtime.document.layouts.first?.id
            )
        } else if selectedCategory == .snapping, let image = NSImage(named: "SnapPreview") {
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

    func refreshPreview() {
        updatePreview()
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

    func refreshLoginSwitch() {
        loginSwitch?.state = runtime.settings.launchAtLogin ? .on : .off
    }

    @objc private func showWelcomeTour() {
        runtime.openWelcomeTour()
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
        layoutStripSwitch?.setAccessibilityLabel(L10n.text(.settingsShowLayoutStrip))
        previewLayoutOnSelectSwitch?.setAccessibilityLabel(L10n.text(.settingsPreviewLayoutOnSelect))
        loginSwitch?.setAccessibilityLabel(L10n.text(.settingsLaunchAtLogin))
        hoverPinSwitch?.setAccessibilityLabel(L10n.text(.settingsHoverPin))
        refreshLoginSwitch()
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
    @objc private func toggleNumbers(_ sender: NSSwitch) {
        runtime.settings.showZoneNumbers = sender.state == .on
        runtime.persistSettings()
        updatePreview()
    }
    @objc private func toggleLayoutStrip(_ sender: NSSwitch) {
        runtime.setShowLayoutStrip(sender.state == .on)
        updatePreview()
    }
    @objc private func togglePreviewLayoutOnSelect(_ sender: NSSwitch) { runtime.setPreviewLayoutOnSelect(sender.state == .on) }
    @objc private func toggleRestore(_ sender: NSSwitch) { runtime.settings.restoreSizeOnUnsnap = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleHoverPin(_ sender: NSSwitch) { runtime.setHoverPinEnabled(sender.state == .on) }
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
        LoginItemController.set(enabled: sender.state == .on, runtime: runtime)
    }
}

private enum SettingsCategory: Int, CaseIterable {
    case general
    case snapping
    case overlay
    case keyboard
    case workspaces

    var titleKey: L10nKey {
        switch self {
        case .general: .settingsSectionGeneral
        case .snapping: .settingsSectionSnapping
        case .overlay: .settingsSectionOverlay
        case .keyboard: .settingsSectionKeyboard
        case .workspaces: .settingsSectionWorkspaces
        }
    }
    var subtitleKey: L10nKey {
        switch self {
        case .general: .settingsGeneralSubtitle
        case .snapping: .settingsSnappingSubtitle
        case .overlay: .settingsOverlaySubtitle
        case .keyboard: .settingsKeyboardSubtitle
        case .workspaces: .settingsWorkspacesSubtitle
        }
    }
    var previewTitleKey: L10nKey {
        switch self {
        case .general: .settingsGeneralPreviewTitle
        case .snapping: .settingsSnappingPreviewTitle
        case .overlay: .settingsOverlayPreviewTitle
        case .keyboard: .settingsKeyboardPreviewTitle
        case .workspaces: .settingsWorkspacesPreviewTitle
        }
    }
    var previewDescriptionKey: L10nKey {
        switch self {
        case .general: .settingsGeneralPreviewDescription
        case .snapping: .settingsSnappingPreviewDescription
        case .overlay: .settingsOverlayPreviewDescription
        case .keyboard: .settingsKeyboardPreviewDescription
        case .workspaces: .settingsWorkspacesPreviewDescription
        }
    }
    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .snapping: "link"
        case .overlay: "square.grid.2x2.fill"
        case .keyboard: "keyboard.fill"
        case .workspaces: "square.grid.3x3.square"
        }
    }
    var tint: NSColor {
        switch self {
        case .general: .systemBlue
        case .snapping: .controlAccentColor
        case .overlay: .systemMint
        case .keyboard: .systemOrange
        case .workspaces: .systemIndigo
        }
    }
}


private enum SettingsMetrics {
    static let rowInset: CGFloat = 14
    static let iconSize: CGFloat = 28
    static let iconTitleGap: CGFloat = 10
}

private final class SettingsPreferenceRowView: NSView {
    init(icon: NSView, title: NSView, detail: NSTextField?, accessory: NSView?, footer: NSView? = nil) {
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
        ]
        if let accessory {
            constraints.append(contentsOf: [
                labels.trailingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: -12),
                accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsMetrics.rowInset),
                accessory.centerYAnchor.constraint(equalTo: title.centerYAnchor, constant: 1),
            ])
        } else {
            constraints.append(labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsMetrics.rowInset))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SettingsInfoHintRow: NSView {
    private let icon = NSImageView()
    private let label: NSTextField

    init(label: NSTextField) {
        self.label = label
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleNone
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentHuggingPriority(.required, for: .vertical)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .vertical)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.alignment = .left
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)

        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = max(0, floor(label.bounds.width))
        if label.preferredMaxLayoutWidth != width {
            label.preferredMaxLayoutWidth = width
            needsUpdateConstraints = true
        }
    }
}

private final class SettingsFlippedView: NSView { override var isFlipped: Bool { true } }



    private final class SettingsOverlayPreviewView: NSView {
        var showNumbers = true {
            didSet { needsDisplay = true }
        }

        var gutterPoints = 16 {
            didSet { needsDisplay = true }
        }

        var showCandidateLayouts = true {
            didSet { needsDisplay = true }
        }

        var candidateLayouts: [Layout] = [] {
            didSet { needsDisplay = true }
        }

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard !bounds.isEmpty else { return }

            let tileColor = NSColor.systemTeal
            let borderColor = NSColor.white.withAlphaComponent(0.65)
            effectiveAppearance.performAsCurrentDrawingAppearance {
                if showCandidateLayouts {
                    drawCandidateList(tileColor: tileColor, borderColor: borderColor)
                } else {
                    drawZoneGrid(in: bounds.insetBy(dx: 18, dy: 18), tileColor: tileColor, borderColor: borderColor)
                }
            }
        }

        private func drawZoneGrid(in outer: CGRect, tileColor: NSColor, borderColor: NSColor) {
            let gap = CGFloat(gutterPoints)
            let tileWidth = max(0, (outer.width - gap) / 2)
            let tileHeight = max(0, (outer.height - gap) / 2)
            guard tileWidth > 0, tileHeight > 0 else { return }
            let tiles = [
                CGRect(x: outer.minX, y: outer.minY, width: tileWidth, height: tileHeight),
                CGRect(x: outer.minX + tileWidth + gap, y: outer.minY, width: tileWidth, height: tileHeight),
                CGRect(x: outer.minX, y: outer.minY + tileHeight + gap, width: tileWidth, height: tileHeight),
                CGRect(x: outer.minX + tileWidth + gap, y: outer.minY + tileHeight + gap, width: tileWidth, height: tileHeight),
            ]
            for (index, rect) in tiles.enumerated() {
                drawZoneTile(rect, number: index + 1, tileColor: tileColor, borderColor: borderColor, corner: 18)
            }
        }

        private func drawCandidateList(tileColor: NSColor, borderColor: NSColor) {
            let layouts = Array(candidateLayouts.prefix(LayoutStripGeometry.maxVisibleCards))
            guard !layouts.isEmpty else {
                drawZoneGrid(in: bounds.insetBy(dx: 18, dy: 18), tileColor: tileColor, borderColor: borderColor)
                return
            }

            let visibleCount = min(layouts.count, 4)
            let cardWidth: CGFloat = 54
            let cardHeight: CGFloat = 36
            let cardSpacing: CGFloat = 6
            let stripPadding: CGFloat = 7
            let overflowWidth: CGFloat = layouts.count > visibleCount ? 18 : 0
            let overflowGap: CGFloat = overflowWidth > 0 ? cardSpacing : 0
            let stripWidth = min(
                bounds.width - 16,
                CGFloat(visibleCount) * cardWidth
                    + CGFloat(max(0, visibleCount - 1)) * cardSpacing
                    + overflowGap
                    + overflowWidth
                    + stripPadding * 2
            )
            let stripHeight = cardHeight + stripPadding * 2
            let stripGap: CGFloat = 10
            let strip = CGRect(
                x: bounds.midX - stripWidth / 2,
                y: bounds.minY + 8,
                width: stripWidth,
                height: stripHeight
            )
            let zoneOuter = CGRect(
                x: bounds.minX + 16,
                y: strip.maxY + stripGap,
                width: bounds.width - 32,
                height: max(64, bounds.maxY - 12 - (strip.maxY + stripGap))
            )
            drawZoneGrid(in: zoneOuter, tileColor: tileColor, borderColor: borderColor)

            NSColor.controlBackgroundColor.withAlphaComponent(0.92).setFill()
            let stripPath = NSBezierPath(roundedRect: strip, xRadius: 11, yRadius: 11)
            stripPath.fill()
            NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
            stripPath.lineWidth = 1
            stripPath.stroke()

            let fittedCardWidth = max(
                36,
                (strip.width - stripPadding * 2 - overflowGap - overflowWidth - CGFloat(max(0, visibleCount - 1)) * cardSpacing) / CGFloat(visibleCount)
            )
            for (index, layout) in layouts.prefix(visibleCount).enumerated() {
                let card = CGRect(
                    x: strip.minX + stripPadding + CGFloat(index) * (fittedCardWidth + cardSpacing),
                    y: strip.minY + stripPadding,
                    width: fittedCardWidth,
                    height: cardHeight
                )
                let selected = index == 0
                NSColor.white.withAlphaComponent(selected ? 0.96 : 0.72).setFill()
                let cardPath = NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7)
                cardPath.fill()
                (selected ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.7)).setStroke()
                cardPath.lineWidth = selected ? 1.6 : 1
                cardPath.stroke()
                drawLayoutThumbnail(layout, in: card.insetBy(dx: 4, dy: 4), tileColor: tileColor)
            }

            if overflowWidth > 0 {
                let overflow = CGRect(
                    x: strip.maxX - stripPadding - overflowWidth,
                    y: strip.minY + stripPadding,
                    width: overflowWidth,
                    height: cardHeight
                )
                NSColor.separatorColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: overflow, xRadius: 6, yRadius: 6).fill()
                let dots = "⋯" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                let size = dots.size(withAttributes: attrs)
                dots.draw(
                    at: CGPoint(x: overflow.midX - size.width / 2, y: overflow.midY - size.height / 2),
                    withAttributes: attrs
                )
            }
        }

        private func drawLayoutThumbnail(_ layout: Layout, in canvas: CGRect, tileColor: NSColor) {
            let zones = LayoutTemplates.thumbnailGeometry(for: layout)
            guard canvas.width > 1, canvas.height > 1, !zones.isEmpty else { return }
            let panes = zones.map { zone in
                CGRect(
                    x: canvas.minX + zone.rect.x * canvas.width,
                    y: canvas.minY + zone.rect.y * canvas.height,
                    width: max(1, zone.rect.width * canvas.width),
                    height: max(1, zone.rect.height * canvas.height)
                )
            }
            let maximumGutter = min(canvas.width, canvas.height) * 0.18
            let effectiveGutter = min(max(0, CGFloat(gutterPoints) * 0.18), maximumGutter)
            let guttered = Gutter.apply(panes, gutter: effectiveGutter, workAreaAX: canvas)
            for (zone, pane) in zip(zones, guttered) {
                let inset = pane.insetBy(dx: 0.5, dy: 0.5)
                guard inset.width > 0.8, inset.height > 0.8 else { continue }
                drawZoneTile(
                    inset,
                    number: zone.number,
                    tileColor: tileColor,
                    borderColor: NSColor.white.withAlphaComponent(0.55),
                    corner: 2.5,
                    showNumber: false
                )
            }
        }

        private func drawZoneTile(
            _ rect: CGRect,
            number: Int,
            tileColor: NSColor,
            borderColor: NSColor,
            corner: CGFloat,
            showNumber: Bool? = nil
        ) {
            let rounded = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
            tileColor.withAlphaComponent(0.96).setFill()
            rounded.fill()
            borderColor.setStroke()
            rounded.lineWidth = corner >= 10 ? 1.5 : 0.8
            rounded.stroke()
            guard showNumber ?? showNumbers else { return }
            let label = "\(number)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: min(22, min(rect.width, rect.height) * 0.28), weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(
                at: CGPoint(
                    x: rect.midX - size.width / 2,
                    y: rect.midY - size.height / 2
                ),
                withAttributes: attrs
            )
        }
    }

private final class SettingsRowIconView: NSView {
    private let tint: NSColor
    init(symbolName: String, title: String, tint: NSColor) {
        self.tint = tint
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        super.init(frame: .zero)
        configure(image: image, title: title)
    }
    init(image: NSImage?, title: String, tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        configure(image: image, title: title)
    }
    private func configure(image: NSImage?, title: String) {
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        let imageView = NSImageView()
        imageView.image = image
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel(title)
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

private final class SettingsBetaBadgeView: NSView {
    let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 9, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            heightAnchor.constraint(equalToConstant: 15),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        updateColors()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.systemOrange.cgColor
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

private final class WorkspaceCardView: NSVisualEffectView {
    private let active: Bool

    init(content: NSView, active: Bool) {
        self.active = active
        super.init(frame: .zero)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        wantsLayer = true
        layer?.cornerRadius = 12
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

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = active
                ? NSColor.controlAccentColor.withAlphaComponent(0.075).cgColor
                : NSColor.controlBackgroundColor.withAlphaComponent(0.74).cgColor
            layer?.borderColor = active
                ? NSColor.controlAccentColor.withAlphaComponent(0.48).cgColor
                : NSColor.separatorColor.withAlphaComponent(0.52).cgColor
            layer?.borderWidth = active ? 1 : 0.5
        }
    }
}

private final class WorkspaceStatusBadgeView: NSView {
    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 9.5, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateColors()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }
}

private final class WorkspaceZoneBadgeView: NSView {
    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        label.textColor = .systemIndigo
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateColors()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.systemIndigo.withAlphaComponent(0.12).cgColor
            layer?.borderColor = NSColor.systemIndigo.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = 0.5
        }
    }
}

private final class WorkspaceDetailsSurfaceView: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updateColors()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor
                .withAlphaComponent(0.42).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
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
