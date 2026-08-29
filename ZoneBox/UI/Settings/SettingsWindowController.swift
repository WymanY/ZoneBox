import AppKit
import ServiceManagement
import ZoneBoxCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: NSWindow?
    private var banner: NSTextField?
    private var guideButton: NSButton?
    private var generalHeader: NSTextField?
    private var snappingHeader: NSTextField?
    private var overlayHeader: NSTextField?
    private var keyboardHeader: NSTextField?
    private var snapCheckbox: NSButton?
    private var shiftCheckbox: NSButton?
    private var rightCheckbox: NSButton?
    private var shakeCheckbox: NSButton?
    private var shakeIntensityLabel: NSTextField?
    private var shakeIntensityHint: NSTextField?
    private var shakeIntensitySlider: NSSlider?
    private var shakeRow: NSView?
    private var quickSnapperCheckbox: NSButton?
    private var magneticCheckbox: NSButton?
    private var numbersCheckbox: NSButton?
    private var restoreCheckbox: NSButton?
    private var gutterLabel: NSTextField?
    private var hotkeysLabel: NSTextField?
    private var shortcutsButton: NSButton?
    private var accessButton: NSButton?
    private var loginLabel: NSTextField?
    private var loginSwitch: NSSwitch?
    private var languageLabel: NSTextField?
    private var languagePopup: NSPopUpButton?

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
    }

    func showWindow() {
        if window == nil { window = makeWindow() }
        window?.level = runtime.isEditorOpen
            ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 3)
            : .normal
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        runtime.settingsDidClose()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
            styleMask: [.titled, .closable],
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

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false

        if !runtime.trust.isTrusted() {
            addFullWidth(makeAccessBanner(), to: stack)
            stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
        }

        let general = makeSection(
            title: L10n.text(.settingsSectionGeneral),
            symbolName: "gearshape.fill",
            tint: .systemBlue,
            header: &generalHeader
        )
        addSectionContent(makeLanguageRow(), to: general)
        addSectionContent(makeLoginRow(), to: general)
        addSection(general, to: stack, separated: true)

        let snapping = makeSection(
            title: L10n.text(.settingsSectionSnapping),
            symbolName: "link",
            tint: .systemPurple,
            header: &snappingHeader
        )
        snapCheckbox = checkbox(L10n.text(.settingsEnableSnapping), runtime.settings.snapEnabled, #selector(toggleSnap))
        snapCheckbox?.font = .systemFont(ofSize: 13, weight: .medium)
        shiftCheckbox = checkbox(L10n.text(.settingsShiftDrag), runtime.settings.snapOnShiftDrag, #selector(toggleShift))
        rightCheckbox = checkbox(L10n.text(.settingsRightClick), runtime.settings.snapOnRightClickDrag, #selector(toggleRight))
        shakeCheckbox = checkbox(L10n.text(.settingsShakeToSnap), runtime.settings.shakeToSnapEnabled, #selector(toggleShake))
        magneticCheckbox = checkbox(L10n.text(.settingsMagneticResize), runtime.settings.magneticResizeEnabled, #selector(toggleMagnetic))
        restoreCheckbox = checkbox(L10n.text(.settingsRestoreSize), runtime.settings.restoreSizeOnUnsnap, #selector(toggleRestore))
        quickSnapperCheckbox = checkbox(L10n.text(.settingsQuickSnapper), runtime.settings.quickSnapperEnabled, #selector(toggleQuickSnapper))
        addSectionContent(snapCheckbox!, to: snapping)
        addSectionContent(shiftCheckbox!, to: snapping, additionalLeading: 20)
        addSectionContent(rightCheckbox!, to: snapping, additionalLeading: 20)
        addSectionContent(shakeCheckbox!, to: snapping, additionalLeading: 20)
        addSectionContent(makeShakeControls(), to: snapping, additionalLeading: 20)
        addSectionContent(magneticCheckbox!, to: snapping, additionalLeading: 20)
        addSectionContent(restoreCheckbox!, to: snapping, additionalLeading: 20)
        addSectionContent(quickSnapperCheckbox!, to: snapping, additionalLeading: 20)
        addSection(snapping, to: stack, separated: true)

        let overlay = makeSection(
            title: L10n.text(.settingsSectionOverlay),
            symbolName: "square.grid.2x2.fill",
            tint: .systemMint,
            header: &overlayHeader
        )
        numbersCheckbox = checkbox(L10n.text(.settingsShowNumbers), runtime.settings.showZoneNumbers, #selector(toggleNumbers))
        addSectionContent(numbersCheckbox!, to: overlay)
        addSectionContent(makeGutterControls(), to: overlay)
        addSection(overlay, to: stack, separated: true)

        let keyboard = makeSection(
            title: L10n.text(.settingsSectionKeyboard),
            symbolName: "keyboard.fill",
            tint: .systemOrange,
            header: &keyboardHeader
        )
        let hotkeys = NSTextField(wrappingLabelWithString: L10n.text(.settingsHotkeys))
        hotkeys.textColor = .secondaryLabelColor
        hotkeys.font = .systemFont(ofSize: 12)
        hotkeys.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.hotkeysLabel = hotkeys
        addSectionContent(makeInfoBox(label: hotkeys), to: keyboard)
        addSectionContent(makeActionRow(), to: keyboard)
        addSection(keyboard, to: stack, separated: false)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.contentView.drawsBackground = false

        let clip = SettingsFlippedView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(stack)
        scroll.documentView = clip

        let content = NSVisualEffectView()
        content.material = .contentBackground
        content.blendingMode = .withinWindow
        content.state = .followsWindowActiveState
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        window.contentView = content
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.topAnchor.constraint(equalTo: clip.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: clip.bottomAnchor, constant: -20),
            clip.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return window
    }

    private func makeAccessBanner() -> NSView {
        let banner = NSTextField(wrappingLabelWithString: L10n.text(.settingsAccessBanner))
        banner.textColor = .labelColor
        banner.font = .systemFont(ofSize: 12, weight: .medium)
        banner.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.banner = banner

        let guide = NSButton(title: L10n.text(.settingsShowGuide), target: self, action: #selector(openAccess))
        guide.bezelStyle = .rounded
        guide.controlSize = .small
        self.guideButton = guide

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let row = NSStackView(views: [icon, banner, guide])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        banner.setContentHuggingPriority(.defaultLow, for: .horizontal)
        guide.setContentHuggingPriority(.required, for: .horizontal)
        return makeCallout(content: row, tint: .systemOrange)
    }

    private func makeSection(
        title: String,
        symbolName: String,
        tint: NSColor,
        header: inout NSTextField?
    ) -> NSStackView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        heading.textColor = .labelColor
        header = heading

        let symbol = SettingsSectionSymbolView(symbolName: symbolName, title: title, tint: tint)
        let headerRow = NSStackView(views: [symbol, heading])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        symbol.widthAnchor.constraint(equalToConstant: 30).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.detachesHiddenViews = true
        stack.addArrangedSubview(headerRow)
        stack.setCustomSpacing(10, after: headerRow)
        return stack
    }

    private func addSectionContent(
        _ view: NSView,
        to section: NSStackView,
        additionalLeading: CGFloat = 0
    ) {
        addFullWidth(inset(view, leading: 42 + additionalLeading), to: section)
    }

    private func addSection(_ section: NSStackView, to stack: NSStackView, separated: Bool) {
        addFullWidth(section, to: stack)
        guard separated else { return }
        stack.setCustomSpacing(12, after: section)
        let separator = makeSeparator()
        addFullWidth(separator, to: stack)
        stack.setCustomSpacing(12, after: separator)
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeLanguageRow() -> NSView {
        let languageLabel = NSTextField(labelWithString: L10n.text(.settingsLanguage))
        languageLabel.font = .systemFont(ofSize: 13)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: Self.languageTitles())
        popup.selectItem(at: Self.languageIndex(runtime.settings.uiLanguage))
        popup.target = self
        popup.action = #selector(languageChanged(_:))
        popup.controlSize = .regular
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [languageLabel, spacer, popup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        languageLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        popup.setContentHuggingPriority(.required, for: .horizontal)
        self.languageLabel = languageLabel
        self.languagePopup = popup
        return row
    }

    private func makeLoginRow() -> NSView {
        let label = NSTextField(labelWithString: L10n.text(.settingsLaunchAtLogin))
        label.font = .systemFont(ofSize: 13)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        self.loginLabel = label

        let toggle = NSSwitch()
        toggle.state = runtime.settings.launchAtLogin ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleLogin(_:))
        toggle.controlSize = .small
        toggle.setAccessibilityLabel(L10n.text(.settingsLaunchAtLogin))
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        self.loginSwitch = toggle

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makeShakeControls() -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4

        let shakeLabel = NSTextField(labelWithString: L10n.shakeIntensity(runtime.settings.shakeIntensity))
        shakeLabel.font = .systemFont(ofSize: 12)
        shakeLabel.textColor = .secondaryLabelColor
        column.addArrangedSubview(shakeLabel)
        self.shakeIntensityLabel = shakeLabel

        let shakeSlider = NSSlider(
            value: Double(runtime.settings.shakeIntensity),
            minValue: Double(ShakeProfile.intensityRange.lowerBound),
            maxValue: Double(ShakeProfile.intensityRange.upperBound),
            target: self,
            action: #selector(shakeIntensityChanged(_:))
        )
        shakeSlider.numberOfTickMarks = ShakeProfile.intensityRange.count
        shakeSlider.allowsTickMarkValuesOnly = true
        shakeSlider.isContinuous = true
        shakeSlider.isEnabled = runtime.settings.shakeToSnapEnabled
        shakeSlider.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(shakeSlider)
        shakeSlider.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        self.shakeIntensitySlider = shakeSlider

        let shakeHint = NSTextField(wrappingLabelWithString: L10n.text(.settingsShakeIntensityHint))
        shakeHint.textColor = .tertiaryLabelColor
        shakeHint.font = .systemFont(ofSize: 11)
        column.addArrangedSubview(shakeHint)
        shakeHint.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        self.shakeIntensityHint = shakeHint
        let inset = inset(column, leading: 20)
        shakeRow = inset
        inset.isHidden = !runtime.settings.shakeToSnapEnabled
        return inset
    }

    private func makeGutterControls() -> NSView {
        let gutterLabel = NSTextField(labelWithString: L10n.gutter(runtime.settings.gutterPoints))
        gutterLabel.font = .systemFont(ofSize: 13)
        self.gutterLabel = gutterLabel

        let slider = NSSlider(
            value: Double(runtime.settings.gutterPoints),
            minValue: 0,
            maxValue: 40,
            target: self,
            action: #selector(gutterChanged(_:))
        )
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false

        let column = NSStackView(views: [gutterLabel, slider])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        slider.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    private func makeInfoBox(label: NSTextField) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return makeCallout(content: row, tint: .controlAccentColor)
    }

    private func makeCallout(content: NSView, tint: NSColor) -> NSView {
        let box = SettingsMaterialView(tint: tint)
        box.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
        ])
        return box
    }

    private func makeActionRow() -> NSView {
        let shortcuts = NSButton(
            title: L10n.text(.settingsShowShortcuts),
            target: self,
            action: #selector(openShortcuts)
        )
        shortcuts.bezelStyle = .rounded
        shortcuts.controlSize = .small
        self.shortcutsButton = shortcuts

        let access = NSButton(title: L10n.text(.settingsOpenAccess), target: self, action: #selector(openAccess))
        access.bezelStyle = .rounded
        access.controlSize = .small
        self.accessButton = access

        let row = NSStackView(views: [shortcuts, access])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        return row
    }

    private func checkbox(_ title: String, _ on: Bool, _ selector: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: selector)
        button.state = on ? .on : .off
        button.font = .systemFont(ofSize: 13)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    private func inset(_ view: NSView, leading: CGFloat) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leading),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeSeparator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        return line
    }

    func applyLanguage() {
        window?.title = L10n.text(.settingsTitle)
        banner?.stringValue = L10n.text(.settingsAccessBanner)
        guideButton?.title = L10n.text(.settingsShowGuide)
        generalHeader?.stringValue = L10n.text(.settingsSectionGeneral)
        snappingHeader?.stringValue = L10n.text(.settingsSectionSnapping)
        overlayHeader?.stringValue = L10n.text(.settingsSectionOverlay)
        keyboardHeader?.stringValue = L10n.text(.settingsSectionKeyboard)
        snapCheckbox?.title = L10n.text(.settingsEnableSnapping)
        shiftCheckbox?.title = L10n.text(.settingsShiftDrag)
        rightCheckbox?.title = L10n.text(.settingsRightClick)
        shakeCheckbox?.title = L10n.text(.settingsShakeToSnap)
        shakeIntensityLabel?.stringValue = L10n.shakeIntensity(runtime.settings.shakeIntensity)
        shakeIntensityHint?.stringValue = L10n.text(.settingsShakeIntensityHint)
        quickSnapperCheckbox?.title = L10n.text(.settingsQuickSnapper)
        magneticCheckbox?.title = L10n.text(.settingsMagneticResize)
        numbersCheckbox?.title = L10n.text(.settingsShowNumbers)
        restoreCheckbox?.title = L10n.text(.settingsRestoreSize)
        gutterLabel?.stringValue = L10n.gutter(runtime.settings.gutterPoints)
        hotkeysLabel?.stringValue = L10n.text(.settingsHotkeys)
        shortcutsButton?.title = L10n.text(.settingsShowShortcuts)
        accessButton?.title = L10n.text(.settingsOpenAccess)
        loginLabel?.stringValue = L10n.text(.settingsLaunchAtLogin)
        loginSwitch?.setAccessibilityLabel(L10n.text(.settingsLaunchAtLogin))
        languageLabel?.stringValue = L10n.text(.settingsLanguage)
        if let popup = languagePopup {
            popup.removeAllItems()
            popup.addItems(withTitles: Self.languageTitles())
            popup.selectItem(at: Self.languageIndex(runtime.settings.uiLanguage))
        }
    }

    private static func languageTitles() -> [String] {
        [
            L10n.text(.settingsLanguageSystem),
            L10n.text(.settingsLanguageEnglish),
            L10n.text(.settingsLanguageChinese),
        ]
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

    @objc private func toggleSnap(_ sender: NSButton) { runtime.setSnapEnabled(sender.state == .on) }
    @objc private func toggleShift(_ sender: NSButton) { runtime.settings.snapOnShiftDrag = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleRight(_ sender: NSButton) { runtime.settings.snapOnRightClickDrag = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleShake(_ sender: NSButton) {
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
    @objc private func toggleQuickSnapper(_ sender: NSButton) { runtime.settings.quickSnapperEnabled = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleMagnetic(_ sender: NSButton) { runtime.settings.magneticResizeEnabled = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleNumbers(_ sender: NSButton) { runtime.settings.showZoneNumbers = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleRestore(_ sender: NSButton) { runtime.settings.restoreSizeOnUnsnap = sender.state == .on; runtime.persistSettings() }
    @objc private func openAccess() { runtime.openAccessibility() }
    @objc private func openShortcuts() { runtime.openShortcutPanel() }

    @objc private func gutterChanged(_ sender: NSSlider) {
        runtime.settings.gutterPoints = Int(sender.doubleValue.rounded())
        gutterLabel?.stringValue = L10n.gutter(runtime.settings.gutterPoints)
        runtime.persistSettings()
    }

    @objc private func toggleLogin(_ sender: NSSwitch) {
        runtime.settings.launchAtLogin = sender.state == .on
        runtime.persistSettings()
        do {
            if runtime.settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item failed: \(error.localizedDescription, privacy: .public)")
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}

private final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class SettingsSectionSymbolView: NSView {
    private let tint: NSColor

    init(symbolName: String, title: String, tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        imageView.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
        ])
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = tint.withAlphaComponent(0.13).cgColor
            layer?.borderColor = tint.withAlphaComponent(0.09).cgColor
            layer?.borderWidth = 0.5
        }
    }
}

private final class SettingsMaterialView: NSVisualEffectView {
    private let tint: NSColor

    init(tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        material = .menu
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        wantsLayer = true
        layer?.cornerRadius = 8
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = tint.withAlphaComponent(0.035).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
            layer?.borderWidth = 0.5
        }
    }
}
