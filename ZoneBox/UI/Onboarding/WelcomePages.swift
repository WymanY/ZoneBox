import AppKit
import ZoneBoxCore

@MainActor
final class WelcomeIntroPage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let menuCopy = NSTextField(wrappingLabelWithString: "")
    private let locateButton = NSButton()
    private let locateCaption = NSTextField(labelWithString: "")

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { nil }

    var view: NSView { self }

    func willAppear(state: OnboardingFlowState) { applyLanguage() }
    func willDisappear() {}
    func refresh(state: OnboardingFlowState) {}

    func applyLanguage() {
        titleLabel.stringValue = L10n.text(.welcomeIntroTitle)
        subtitleLabel.stringValue = L10n.text(.welcomeIntroSubtitle)
        menuCopy.stringValue = L10n.text(.welcomeIntroMenuBar)
        locateButton.title = L10n.text(.welcomeIntroLocate)
        locateCaption.stringValue = "ZoneBox"
    }

    private func build() {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 16
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.preferredMaxLayoutWidth = 640
        menuCopy.font = .systemFont(ofSize: 13)
        menuCopy.textColor = .secondaryLabelColor
        menuCopy.preferredMaxLayoutWidth = 640

        let bar = SimulatedMenuBarView()
        locateCaption.font = .systemFont(ofSize: 12, weight: .medium)
        locateCaption.textColor = .secondaryLabelColor
        locateCaption.alignment = .right

        locateButton.bezelStyle = .rounded
        locateButton.target = self
        locateButton.action = #selector(showMe)
        locateButton.setButtonType(.momentaryPushIn)

        locateCaption.stringValue = "ZoneBox"
        let barBlock = NSStackView(views: [bar, locateCaption])
        barBlock.orientation = .vertical
        barBlock.alignment = .trailing
        barBlock.spacing = 4

        let stack = NSStackView(views: [icon, titleLabel, subtitleLabel, barBlock, menuCopy, locateButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
            bar.widthAnchor.constraint(equalToConstant: 520),
            bar.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @objc private func showMe() {
        runtime.menuBar?.pulseStatusItem()
    }
}

private final class SimulatedMenuBarView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor

        let clock = NSTextField(labelWithString: "9:41")
        clock.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        clock.textColor = .white
        clock.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = (NSImage(named: "MenuBarIcon")?.copy() as? NSImage)
            ?? NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "ZoneBox")
        icon.image?.isTemplate = true
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let caption = NSTextField(labelWithString: "ZoneBox")
        caption.font = .systemFont(ofSize: 11, weight: .medium)
        caption.textColor = .white
        caption.translatesAutoresizingMaskIntoConstraints = false

        addSubview(clock)
        addSubview(icon)
        addSubview(caption)
        NSLayoutConstraint.activate([
            clock.centerYAnchor.constraint(equalTo: centerYAnchor),
            clock.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.trailingAnchor.constraint(equalTo: clock.leadingAnchor, constant: -10),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            caption.centerYAnchor.constraint(equalTo: centerYAnchor),
            caption.trailingAnchor.constraint(equalTo: icon.leadingAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
final class WelcomeMorePage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let titleLabel = NSTextField(labelWithString: "")
    private let editorBody = NSTextField(wrappingLabelWithString: "")
    private let dividerBody = NSTextField(wrappingLabelWithString: "")
    private let workspaceBody = NSTextField(wrappingLabelWithString: "")
    private let pinBody = NSTextField(wrappingLabelWithString: "")
    private let openEditor = NSButton()

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { nil }

    var view: NSView { self }

    func willAppear(state: OnboardingFlowState) { applyLanguage() }
    func willDisappear() {}
    func refresh(state: OnboardingFlowState) { applyLanguage() }

    func applyLanguage() {
        titleLabel.stringValue = L10n.text(.welcomeMoreTitle)
        editorBody.stringValue = L10n.welcomeMoreEditor(runtime.settings.editorHotkey.displayCaps.joined())
        dividerBody.stringValue = L10n.text(.welcomeMoreDivider)
        workspaceBody.stringValue = L10n.welcomeMoreWorkspaces(runtime.settings.applyWorkspaceHotkey.displayCaps.joined())
        pinBody.stringValue = L10n.welcomeMoreQuickAndPin(runtime.settings.quickSnapperHotkey.displayCaps.joined())
        openEditor.title = L10n.text(.welcomeMoreOpenEditor)
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        let grid = NSGridView(views: [
            [card("slider.horizontal.3", editorBody), card("arrow.left.and.right.square", dividerBody)],
            [card("square.grid.3x3.square", workspaceBody), card("pin.fill", pinBody)],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        openEditor.bezelStyle = .rounded
        openEditor.target = self
        openEditor.action = #selector(openLayoutEditor)

        let stack = NSStackView(views: [titleLabel, grid, openEditor])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func card(_ symbol: String, _ body: NSTextField) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 300
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        let stack = NSStackView(views: [icon, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            box.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        return box
    }

    @objc private func openLayoutEditor() {
        runtime.openEditor()
    }
}

@MainActor
final class WelcomeFinishPage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let reopenLabel = NSTextField(wrappingLabelWithString: "")
    private let loginSwitch = NSSwitch()
    private let loginLabel = NSTextField(labelWithString: "")
    private let openSettings = NSButton()
    private let shortcutStack = NSStackView()
    private let onOpenSettings: () -> Void

    init(runtime: AppRuntime, onOpenSettings: @escaping () -> Void) {
        self.runtime = runtime
        self.onOpenSettings = onOpenSettings
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { nil }

    var view: NSView { self }

    func willAppear(state: OnboardingFlowState) { applyLanguage() }
    func willDisappear() {}
    func refresh(state: OnboardingFlowState) { applyLanguage() }

    func applyLanguage() {
        titleLabel.stringValue = L10n.text(.welcomeFinishTitle)
        bodyLabel.stringValue = L10n.text(.welcomeFinishBody)
        reopenLabel.stringValue = L10n.text(.welcomeFinishReopen)
        loginLabel.stringValue = L10n.text(.settingsLaunchAtLogin)
        openSettings.title = L10n.text(.welcomeFinishOpenSettings)
        loginSwitch.state = runtime.settings.launchAtLogin ? .on : .off
        rebuildShortcuts()
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.preferredMaxLayoutWidth = 680
        reopenLabel.font = .systemFont(ofSize: 12)
        reopenLabel.textColor = .secondaryLabelColor
        reopenLabel.preferredMaxLayoutWidth = 680

        shortcutStack.orientation = .vertical
        shortcutStack.alignment = .leading
        shortcutStack.spacing = 8

        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)
        loginLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let loginRow = NSStackView(views: [loginSwitch, loginLabel])
        loginRow.orientation = .horizontal
        loginRow.alignment = .centerY
        loginRow.spacing = 8

        openSettings.bezelStyle = .rounded
        openSettings.target = self
        openSettings.action = #selector(tapSettings)

        let stack = NSStackView(views: [titleLabel, bodyLabel, shortcutStack, loginRow, reopenLabel, openSettings])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func rebuildShortcuts() {
        shortcutStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let grouped = ShortcutCatalog.grouped(from: runtime.settings)
        let wanted: Set<String> = ["snapZone1", "unsnap", "openEditor", "quickSnapper", "showShortcuts"]
        var rows: [(String, [String])] = []
        for group in grouped {
            for item in group.items {
                if item.id.hasPrefix("snapZone"), case .chord(let chord) = item.binding {
                    if !rows.contains(where: { $0.0 == L10n.text(.shortcutSnapZones) }) {
                        rows.append((L10n.text(.shortcutSnapZones), Array(chord.displayCaps.dropLast()) + ["1–9"]))
                    }
                    continue
                }
                guard wanted.contains(item.id), case .chord(let chord) = item.binding else { continue }
                rows.append((item.title(language: LanguageCenter.language), chord.displayCaps))
            }
        }
        for row in rows.prefix(5) {
            let title = NSTextField(labelWithString: row.0)
            title.font = .systemFont(ofSize: 13)
            let caps = NSStackView(views: row.1.map { WelcomeKeyCapView(symbol: $0) })
            caps.orientation = .horizontal
            caps.spacing = 4
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let line = NSStackView(views: [title, spacer, caps])
            line.orientation = .horizontal
            line.alignment = .centerY
            shortcutStack.addArrangedSubview(line)
        }
    }

    @objc private func toggleLogin() {
        LoginItemController.set(enabled: loginSwitch.state == .on, runtime: runtime)
    }

    @objc private func tapSettings() {
        onOpenSettings()
    }
}

final class WelcomeKeyCapView: NSView {
    init(symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        let label = NSTextField(labelWithString: symbol)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let width = max(22, ceil((symbol as NSString).size(withAttributes: [.font: label.font!]).width) + 10)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.10) : NSColor.white).cgColor
        layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.12)).cgColor
    }
}
