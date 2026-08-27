import AppKit
import ServiceManagement
import ZoneBoxCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: NSWindow?
    private var banner: NSTextField?
    private var guideButton: NSButton?
    private var snapCheckbox: NSButton?
    private var shiftCheckbox: NSButton?
    private var rightCheckbox: NSButton?
    private var shakeCheckbox: NSButton?
    private var shakeIntensityLabel: NSTextField?
    private var shakeIntensityHint: NSTextField?
    private var shakeIntensitySlider: NSSlider?
    private var quickSnapperCheckbox: NSButton?
    private var magneticCheckbox: NSButton?
    private var numbersCheckbox: NSButton?
    private var restoreCheckbox: NSButton?
    private var gutterLabel: NSTextField?
    private var hotkeysLabel: NSTextField?
    private var shortcutsButton: NSButton?
    private var accessButton: NSButton?
    private var loginCheckbox: NSButton?
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 740),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.settingsTitle)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        if !runtime.trust.isTrusted() {
            let banner = NSTextField(wrappingLabelWithString: L10n.text(.settingsAccessBanner))
            banner.textColor = .systemOrange
            banner.font = .systemFont(ofSize: 12, weight: .medium)
            stack.addArrangedSubview(banner)
            self.banner = banner
            let guide = NSButton(title: L10n.text(.settingsShowGuide), target: self, action: #selector(openAccess))
            guide.bezelStyle = .rounded
            stack.addArrangedSubview(guide)
            self.guideButton = guide
        }

        let languageLabel = NSTextField(labelWithString: L10n.text(.settingsLanguage))
        languageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: Self.languageTitles())
        popup.selectItem(at: Self.languageIndex(runtime.settings.uiLanguage))
        popup.target = self
        popup.action = #selector(languageChanged(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let languageRow = NSStackView(views: [languageLabel, popup])
        languageRow.orientation = .horizontal
        languageRow.alignment = .centerY
        languageRow.spacing = 12
        stack.addArrangedSubview(languageRow)
        self.languageLabel = languageLabel
        self.languagePopup = popup

        snapCheckbox = checkbox(L10n.text(.settingsEnableSnapping), runtime.settings.snapEnabled, #selector(toggleSnap))
        shiftCheckbox = checkbox(L10n.text(.settingsShiftDrag), runtime.settings.snapOnShiftDrag, #selector(toggleShift))
        rightCheckbox = checkbox(L10n.text(.settingsRightClick), runtime.settings.snapOnRightClickDrag, #selector(toggleRight))
        shakeCheckbox = checkbox(L10n.text(.settingsShakeToSnap), runtime.settings.shakeToSnapEnabled, #selector(toggleShake))
        quickSnapperCheckbox = checkbox(L10n.text(.settingsQuickSnapper), runtime.settings.quickSnapperEnabled, #selector(toggleQuickSnapper))
        magneticCheckbox = checkbox(L10n.text(.settingsMagneticResize), runtime.settings.magneticResizeEnabled, #selector(toggleMagnetic))
        numbersCheckbox = checkbox(L10n.text(.settingsShowNumbers), runtime.settings.showZoneNumbers, #selector(toggleNumbers))
        restoreCheckbox = checkbox(L10n.text(.settingsRestoreSize), runtime.settings.restoreSizeOnUnsnap, #selector(toggleRestore))
        stack.addArrangedSubview(snapCheckbox!)
        stack.addArrangedSubview(shiftCheckbox!)
        stack.addArrangedSubview(rightCheckbox!)
        stack.addArrangedSubview(shakeCheckbox!)
        let shakeLabel = NSTextField(labelWithString: L10n.shakeIntensity(runtime.settings.shakeIntensity))
        shakeLabel.tag = 51
        shakeLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(shakeLabel)
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
        shakeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        stack.addArrangedSubview(shakeSlider)
        self.shakeIntensitySlider = shakeSlider
        let shakeHint = NSTextField(labelWithString: L10n.text(.settingsShakeIntensityHint))
        shakeHint.textColor = .secondaryLabelColor
        shakeHint.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(shakeHint)
        self.shakeIntensityHint = shakeHint
        stack.addArrangedSubview(quickSnapperCheckbox!)
        stack.addArrangedSubview(magneticCheckbox!)
        stack.addArrangedSubview(numbersCheckbox!)
        stack.addArrangedSubview(restoreCheckbox!)

        let gutterLabel = NSTextField(labelWithString: L10n.gutter(runtime.settings.gutterPoints))
        gutterLabel.tag = 50
        gutterLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(gutterLabel)
        self.gutterLabel = gutterLabel
        let slider = NSSlider(value: Double(runtime.settings.gutterPoints), minValue: 0, maxValue: 40, target: self, action: #selector(gutterChanged(_:)))
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        stack.addArrangedSubview(slider)

        let hotkeys = NSTextField(wrappingLabelWithString: L10n.text(.settingsHotkeys))
        hotkeys.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hotkeys)
        self.hotkeysLabel = hotkeys

        let shortcuts = NSButton(
            title: L10n.text(.settingsShowShortcuts),
            target: self,
            action: #selector(openShortcuts)
        )
        shortcuts.bezelStyle = .rounded
        stack.addArrangedSubview(shortcuts)
        self.shortcutsButton = shortcuts

        let access = NSButton(title: L10n.text(.settingsOpenAccess), target: self, action: #selector(openAccess))
        access.bezelStyle = .rounded
        stack.addArrangedSubview(access)
        self.accessButton = access

        let login = checkbox(L10n.text(.settingsLaunchAtLogin), runtime.settings.launchAtLogin, #selector(toggleLogin))
        stack.addArrangedSubview(login)
        self.loginCheckbox = login

        window.contentView = NSView()
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: content.topAnchor),
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            ])
        }
        return window
    }

    private func checkbox(_ title: String, _ on: Bool, _ selector: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: selector)
        button.state = on ? .on : .off
        return button
    }

    func applyLanguage() {
        window?.title = L10n.text(.settingsTitle)
        banner?.stringValue = L10n.text(.settingsAccessBanner)
        guideButton?.title = L10n.text(.settingsShowGuide)
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
        loginCheckbox?.title = L10n.text(.settingsLaunchAtLogin)
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
        runtime.persistSettings()
    }

    @objc private func shakeIntensityChanged(_ sender: NSSlider) {
        runtime.settings.shakeIntensity = ShakeProfile.clampedIntensity(Int(sender.doubleValue.rounded()))
        if let label = window?.contentView?.viewWithTag(51) as? NSTextField {
            label.stringValue = L10n.shakeIntensity(runtime.settings.shakeIntensity)
        }
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
        if let label = window?.contentView?.viewWithTag(50) as? NSTextField {
            label.stringValue = L10n.gutter(runtime.settings.gutterPoints)
        }
        runtime.persistSettings()
    }

    @objc private func toggleLogin(_ sender: NSButton) {
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
