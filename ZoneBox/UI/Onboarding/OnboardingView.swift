import AppKit

final class OnboardingView: NSView {
    enum Phase {
        case needsPermission
        case waiting
        case granted
        case needsRelaunch
        case runningUnderDebugger
    }

    var onOpenSettings: (() -> Void)?
    var onConfirmEnabled: (() -> Void)?
    var onRelaunch: (() -> Void)?
    var onContinue: (() -> Void)?

    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let statusIcon = NSImageView()
    private let primaryButton = NSButton()
    private let secondaryButton = NSButton()
    private let checkButton = NSButton()
    private var phase: Phase = .needsPermission

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
        apply(.needsPermission)
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ phase: Phase) {
        self.phase = phase
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        checkButton.isHidden = true
        secondaryButton.isHidden = false
        switch phase {
        case .needsPermission:
            statusIcon.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
            statusIcon.contentTintColor = .secondaryLabelColor
            statusLabel.stringValue = "Snapping is paused until Accessibility is allowed."
            primaryButton.title = "Open Accessibility Settings"
            primaryButton.action = #selector(tapOpen)
            secondaryButton.title = "Not now"
            secondaryButton.action = #selector(tapContinue)
            checkButton.isHidden = false
        case .waiting:
            statusIcon.image = nil
            spinner.isHidden = false
            spinner.startAnimation(nil)
            statusLabel.stringValue = "Waiting for the switch next to ZoneBox…"
            primaryButton.title = "Open Accessibility Settings again"
            primaryButton.action = #selector(tapOpen)
            secondaryButton.title = "Quit & Relaunch"
            secondaryButton.action = #selector(tapRelaunch)
            checkButton.isHidden = false
        case .granted:
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            statusLabel.stringValue = "Accessibility is on. You can snap windows now."
            primaryButton.title = "Continue"
            primaryButton.action = #selector(tapContinue)
            secondaryButton.isHidden = true
            checkButton.isHidden = true
        case .needsRelaunch:
            statusIcon.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemOrange
            statusLabel.stringValue = "The switch can be on while this process still isn’t trusted. Quit & Relaunch (not Xcode Run) applies the grant."
            primaryButton.title = "Quit & Relaunch ZoneBox"
            primaryButton.action = #selector(tapRelaunch)
            secondaryButton.title = "Open Settings again"
            secondaryButton.action = #selector(tapOpen)
            checkButton.isHidden = true
        case .runningUnderDebugger:
            statusIcon.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemOrange
            statusLabel.stringValue = "Xcode is debugging this process. macOS often keeps Accessibility off for the debug session even when the ZoneBox switch is already on."
            primaryButton.title = "Quit & Open without Debugger"
            primaryButton.action = #selector(tapRelaunch)
            secondaryButton.title = "Open Accessibility Settings"
            secondaryButton.action = #selector(tapOpen)
            checkButton.isHidden = true
        }
    }

    private func build() {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "ZoneBox")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .vertical)

        let title = label("Allow ZoneBox to arrange windows", font: .systemFont(ofSize: 22, weight: .semibold))
        let subtitle = wrapping("macOS requires Accessibility permission before ZoneBox can move and resize other apps. This stays on your Mac — nothing is uploaded.")
        subtitle.textColor = .secondaryLabelColor

        let pathCaption = label("Enable this exact build (Xcode Debug ≠ a copy in /Applications):", font: .systemFont(ofSize: 11, weight: .medium))
        pathCaption.textColor = .secondaryLabelColor
        let pathField = NSTextField(wrappingLabelWithString: TrustMonitor.currentBuildPath)
        pathField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathField.textColor = .labelColor
        pathField.translatesAutoresizingMaskIntoConstraints = false

        let guide = mockList()
        let stack = NSStackView(views: [
            icon, title, subtitle,
            pathCaption, pathField,
            stepRow(1, title: "Open Accessibility settings", detail: "Use the button below. System Settings opens to Privacy & Security → Accessibility."),
            stepRow(2, title: "Turn on THIS ZoneBox", detail: "You may see several ZoneBox rows (Xcode Debug, another folder, /Applications). Enable the one that matches the path above."),
            stepRow(3, title: "Don’t test with Xcode Run", detail: "Stop in Xcode, then Quit & Open without Debugger — or Finder-open the .app. The debugger makes macOS ignore an already-on switch."),
            guide,
            statusRow(),
            buttonRow(),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(16, after: guide)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
            icon.heightAnchor.constraint(equalToConstant: 40),
            icon.widthAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func stepRow(_ number: Int, title: String, detail: String) -> NSView {
        let badge = NSImageView()
        badge.image = NSImage(systemSymbolName: "\(number).circle.fill", accessibilityDescription: "Step \(number)")
        badge.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        badge.contentTintColor = .controlAccentColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.setContentHuggingPriority(.required, for: .horizontal)

        let heading = label(title, font: .systemFont(ofSize: 14, weight: .semibold))
        let body = wrapping(detail)
        body.textColor = .secondaryLabelColor
        body.font = .systemFont(ofSize: 12)

        let text = NSStackView(views: [heading, body])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: [badge, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        badge.widthAnchor.constraint(equalToConstant: 24).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return row
    }

    private func mockList() -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let header = label("Accessibility", font: .systemFont(ofSize: 12, weight: .semibold))
        header.textColor = .secondaryLabelColor

        let zone = mockRow(name: "ZoneBox", on: false, highlight: true)
        let finder = mockRow(name: "Finder", on: true, highlight: false)
        let zoom = mockRow(name: "Zoom", on: false, highlight: false)

        let inner = NSStackView(views: [header, zone, finder, zoom])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            box.widthAnchor.constraint(greaterThanOrEqualToConstant: 480),
        ])
        return box
    }

    private func mockRow(name: String, on: Bool, highlight: Bool) -> NSView {
        let nameField = label(name, font: .systemFont(ofSize: 13, weight: highlight ? .semibold : .regular))
        if highlight { nameField.textColor = .controlAccentColor }
        let toggle = NSSwitch()
        toggle.state = on ? .on : .off
        toggle.isEnabled = false
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [nameField, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        if highlight {
            row.wantsLayer = true
            row.layer?.cornerRadius = 6
            row.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            row.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        }
        return row
    }

    private func statusRow() -> NSView {
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [spinner, statusIcon, statusLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func buttonRow() -> NSView {
        primaryButton.bezelStyle = .rounded
        primaryButton.setButtonType(.momentaryPushIn)
        primaryButton.target = self
        primaryButton.action = #selector(tapOpen)
        primaryButton.keyEquivalent = "\r"
        if #available(macOS 14.0, *) {
            primaryButton.controlSize = .large
        }

        secondaryButton.bezelStyle = .rounded
        secondaryButton.target = self
        secondaryButton.action = #selector(tapContinue)

        checkButton.bezelStyle = .rounded
        checkButton.title = "I've turned it on"
        checkButton.target = self
        checkButton.action = #selector(tapConfirm)

        let spacer = NSView()
        let row = NSStackView(views: [secondaryButton, spacer, checkButton, primaryButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func label(_ text: String, font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func wrapping(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.preferredMaxLayoutWidth = 500
        return field
    }

    @objc private func tapOpen() { onOpenSettings?() }
    @objc private func tapConfirm() { onConfirmEnabled?() }
    @objc private func tapRelaunch() { onRelaunch?() }
    @objc private func tapContinue() { onContinue?() }
}
