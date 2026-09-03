import AppKit
import ZoneBoxCore

final class OnboardingView: NSView {
    enum Phase {
        case needsPermission
        case waiting
        case granted
        case needsRelaunch
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
    private var titleLabel: NSTextField?
    private var subtitleLabel: NSTextField?
    private var step1Title: NSTextField?
    private var step1Detail: NSTextField?
    private var step2Title: NSTextField?
    private var step2Detail: NSTextField?
    private var step3Title: NSTextField?
    private var step3Detail: NSTextField?
    private var mockHeaderLabel: NSTextField?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
        apply(.needsPermission)
    }

    required init?(coder: NSCoder) { nil }

    func applyLanguage() {
        titleLabel?.stringValue = L10n.text(.onboardingTitle)
        subtitleLabel?.stringValue = L10n.text(.onboardingSubtitle)
        step1Title?.stringValue = L10n.text(.onboardingStep1Title)
        step1Detail?.stringValue = L10n.text(.onboardingStep1Detail)
        step2Title?.stringValue = L10n.text(.onboardingStep2Title)
        step2Detail?.stringValue = L10n.text(.onboardingStep2Detail)
        step3Title?.stringValue = L10n.text(.onboardingStep3Title)
        step3Detail?.stringValue = L10n.text(.onboardingStep3Detail)
        mockHeaderLabel?.stringValue = L10n.text(.onboardingMockHeader)
        checkButton.title = L10n.text(.onboardingIveTurnedItOn)
        apply(phase)
    }

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
            statusLabel.stringValue = L10n.text(.onboardingStatusNeedsPermission)
            primaryButton.title = L10n.text(.onboardingOpenSettings)
            primaryButton.action = #selector(tapOpen)
            secondaryButton.title = L10n.text(.onboardingNotNow)
            secondaryButton.action = #selector(tapContinue)
            checkButton.isHidden = false
        case .waiting:
            statusIcon.image = nil
            spinner.isHidden = false
            spinner.startAnimation(nil)
            statusLabel.stringValue = L10n.text(.onboardingStatusWaiting)
            primaryButton.title = L10n.text(.onboardingOpenSettingsAgain)
            primaryButton.action = #selector(tapOpen)
            secondaryButton.title = L10n.text(.onboardingQuitRelaunch)
            secondaryButton.action = #selector(tapRelaunch)
            checkButton.isHidden = false
        case .granted:
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            statusLabel.stringValue = L10n.text(.onboardingStatusGranted)
            primaryButton.title = L10n.text(.onboardingContinue)
            primaryButton.action = #selector(tapContinue)
            secondaryButton.isHidden = true
            checkButton.isHidden = true
        case .needsRelaunch:
            statusIcon.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemOrange
            statusLabel.stringValue = L10n.text(.onboardingStatusNeedsRelaunch)
            primaryButton.title = L10n.text(.onboardingQuitRelaunchApp)
            primaryButton.action = #selector(tapRelaunch)
            secondaryButton.title = L10n.text(.onboardingOpenSettingsAgainShort)
            secondaryButton.action = #selector(tapOpen)
            checkButton.isHidden = true
        }
    }

    private func build() {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 12
        icon.layer?.masksToBounds = true
        icon.setAccessibilityLabel("ZoneBox")
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .vertical)

        let title = label(L10n.text(.onboardingTitle), font: .systemFont(ofSize: 22, weight: .semibold))
        titleLabel = title
        let subtitle = wrapping(L10n.text(.onboardingSubtitle))
        subtitle.textColor = .secondaryLabelColor
        subtitleLabel = subtitle

        let guide = mockList()
        let stack = NSStackView(views: [
            icon, title, subtitle,
            makeStep(1, titleKey: .onboardingStep1Title, detailKey: .onboardingStep1Detail),
            makeStep(2, titleKey: .onboardingStep2Title, detailKey: .onboardingStep2Detail),
            makeStep(3, titleKey: .onboardingStep3Title, detailKey: .onboardingStep3Detail),
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
            icon.heightAnchor.constraint(equalToConstant: 64),
            icon.widthAnchor.constraint(equalToConstant: 64),
        ])
    }

    private func makeStep(_ number: Int, titleKey: L10nKey, detailKey: L10nKey) -> NSView {
        let row = stepRow(number, title: L10n.text(titleKey), detail: L10n.text(detailKey))
        switch number {
        case 1:
            step1Title = heading(in: row)
            step1Detail = body(in: row)
        case 2:
            step2Title = heading(in: row)
            step2Detail = body(in: row)
        case 3:
            step3Title = heading(in: row)
            step3Detail = body(in: row)
        default:
            break
        }
        return row
    }

    private func heading(in row: NSView) -> NSTextField? {
        ((row as? NSStackView)?.arrangedSubviews.last as? NSStackView)?.arrangedSubviews.first as? NSTextField
    }

    private func body(in row: NSView) -> NSTextField? {
        ((row as? NSStackView)?.arrangedSubviews.last as? NSStackView)?.arrangedSubviews.last as? NSTextField
    }

    private func stepRow(_ number: Int, title: String, detail: String) -> NSView {
        let badge = NSImageView()
        badge.image = NSImage(systemSymbolName: "\(number).circle.fill", accessibilityDescription: L10n.stepAccessibility(number))
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

        let header = label(L10n.text(.onboardingMockHeader), font: .systemFont(ofSize: 12, weight: .semibold))
        mockHeaderLabel = header
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
        checkButton.title = L10n.text(.onboardingIveTurnedItOn)
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
