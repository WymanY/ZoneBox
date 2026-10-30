import AppKit
import ZoneBoxCore

final class AccessibilityGuideView: NSView {
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
    let showsHeader: Bool

    private let statusCard = WelcomeCardView(style: .surface, cornerRadius: 12)
    private let statusLabel = WelcomeAutoWrapLabel(font: .systemFont(ofSize: 12.5, weight: .medium), color: .labelColor)
    private let spinner = NSProgressIndicator()
    private let statusIcon = NSImageView()
    private var primaryButton: ConsoleButton!
    private var secondaryButton: ConsoleButton!
    private var checkButton: ConsoleButton!
    private var zoneSwitch: NSSwitch?
    private var phase: Phase = .needsPermission
    private var titleLabel: NSTextField?
    private var subtitleLabel: WelcomeAutoWrapLabel?
    private var step1Title: NSTextField?
    private var step1Detail: WelcomeAutoWrapLabel?
    private var step2Title: NSTextField?
    private var step2Detail: WelcomeAutoWrapLabel?
    private var step3Title: NSTextField?
    private var step3Detail: WelcomeAutoWrapLabel?
    private var mockHeaderLabel: NSTextField?

    init(showsHeader: Bool = true) {
        self.showsHeader = showsHeader
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
        apply(.needsPermission)
    }

    required init?(coder: NSCoder) { nil }

    func applyLanguage() {
        titleLabel?.isHidden = !showsHeader
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
        statusIcon.isHidden = false
        checkButton.isHidden = true
        secondaryButton.isHidden = false
        primaryButton.isHidden = false
        zoneSwitch?.state = phase == .granted ? .on : .off

        switch phase {
        case .needsPermission:
            statusCard.style = .surface
            statusIcon.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .controlAccentColor
            statusLabel.stringValue = L10n.text(.onboardingStatusNeedsPermission)
            primaryButton.role = .primary
            primaryButton.symbolName = "gearshape.fill"
            primaryButton.title = L10n.text(.onboardingOpenSettings)
            primaryButton.action = #selector(tapOpen)
            secondaryButton.title = L10n.text(.onboardingNotNow)
            secondaryButton.action = #selector(tapContinue)
            secondaryButton.isHidden = !showsHeader
            checkButton.isHidden = false
        case .waiting:
            statusCard.style = .tinted
            statusIcon.image = nil
            statusIcon.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
            statusLabel.stringValue = L10n.text(.onboardingStatusWaiting)
            primaryButton.role = .tinted
            primaryButton.symbolName = "arrow.up.forward.app"
            primaryButton.title = L10n.text(.onboardingOpenSettingsAgain)
            primaryButton.action = #selector(tapOpen)
            secondaryButton.title = L10n.text(.onboardingQuitRelaunch)
            secondaryButton.action = #selector(tapRelaunch)
            secondaryButton.isHidden = false
            checkButton.isHidden = false
        case .granted:
            statusCard.style = .success
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            statusLabel.stringValue = L10n.text(.onboardingStatusGranted)
            primaryButton.role = .primary
            primaryButton.symbolName = "checkmark"
            primaryButton.title = L10n.text(.onboardingContinue)
            primaryButton.action = #selector(tapContinue)
            primaryButton.isHidden = !showsHeader
            secondaryButton.isHidden = true
            checkButton.isHidden = true
        case .needsRelaunch:
            statusCard.style = .warning
            statusIcon.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemOrange
            statusLabel.stringValue = L10n.text(.onboardingStatusNeedsRelaunch)
            primaryButton.role = .primary
            primaryButton.symbolName = "arrow.clockwise"
            primaryButton.title = L10n.text(.onboardingQuitRelaunchApp)
            primaryButton.action = #selector(tapRelaunch)
            secondaryButton.title = L10n.text(.onboardingOpenSettingsAgainShort)
            secondaryButton.action = #selector(tapOpen)
            secondaryButton.isHidden = false
            checkButton.isHidden = true
        }
    }

    private func build() {
        var topViews: [NSView] = []

        if showsHeader {
            let icon = NSImageView()
            icon.image = NSApp.applicationIconImage
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 13
            icon.layer?.cornerCurve = .continuous
            icon.layer?.masksToBounds = true
            icon.setAccessibilityLabel("ZoneBox")
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

            let title = NSTextField(labelWithString: L10n.text(.onboardingTitle))
            title.font = .systemFont(ofSize: 22, weight: .bold)
            title.textColor = .labelColor
            titleLabel = title

            let subtitle = WelcomeAutoWrapLabel(L10n.text(.onboardingSubtitle), font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
            subtitleLabel = subtitle

            let headerText = NSStackView(views: [title, subtitle])
            headerText.orientation = .vertical
            headerText.alignment = .leading
            headerText.spacing = 4

            let headerRow = NSStackView(views: [icon, headerText])
            headerRow.orientation = .horizontal
            headerRow.alignment = .centerY
            headerRow.spacing = 14
            headerRow.translatesAutoresizingMaskIntoConstraints = false
            topViews.append(headerRow)
        } else {
            let subtitle = WelcomeAutoWrapLabel(L10n.text(.onboardingSubtitle), font: .systemFont(ofSize: 13.5), color: .secondaryLabelColor)
            subtitleLabel = subtitle
            topViews.append(subtitle)
        }

        // Two-column middle section: Steps card on left, Mock System Settings on right
        let stepsCard = makeStepsCard()
        let mockCard = makeMockListCard()

        let columnsRow = NSStackView(views: [stepsCard, mockCard])
        columnsRow.orientation = .horizontal
        columnsRow.distribution = .fillEqually
        columnsRow.alignment = .top
        columnsRow.spacing = 14
        columnsRow.translatesAutoresizingMaskIntoConstraints = false

        let bottomStatusCard = makeStatusAndActionsCard()

        topViews.append(contentsOf: [columnsRow, bottomStatusCard])

        let mainStack = NSStackView(views: topViews)
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        let horizontalInset: CGFloat = showsHeader ? 28 : 0
        let verticalInset: CGFloat = showsHeader ? 24 : 0

        NSLayoutConstraint.activate([
            columnsRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            stepsCard.heightAnchor.constraint(equalTo: mockCard.heightAnchor),
            bottomStatusCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),

            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: verticalInset),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -verticalInset),
        ])
    }

    private func makeStepsCard() -> NSView {
        let card = WelcomeCardView(style: .surface, cornerRadius: 12)
        let s1 = makeStep(1, titleKey: .onboardingStep1Title, detailKey: .onboardingStep1Detail)
        let s2 = makeStep(2, titleKey: .onboardingStep2Title, detailKey: .onboardingStep2Detail)
        let s3 = makeStep(3, titleKey: .onboardingStep3Title, detailKey: .onboardingStep3Detail)

        let stack = NSStackView(views: [s1, s2, s3])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            s1.widthAnchor.constraint(equalTo: stack.widthAnchor),
            s2.widthAnchor.constraint(equalTo: stack.widthAnchor),
            s3.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    private func makeStep(_ number: Int, titleKey: L10nKey, detailKey: L10nKey) -> NSView {
        let badge = WelcomeIconBadgeView(symbol: "", badgeText: "\(number)", size: 30, symbolSize: 14)

        let heading = NSTextField(labelWithString: L10n.text(titleKey))
        heading.font = .systemFont(ofSize: 13.5, weight: .semibold)
        heading.textColor = .labelColor
        heading.translatesAutoresizingMaskIntoConstraints = false

        let body = WelcomeAutoWrapLabel(L10n.text(detailKey), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)

        switch number {
        case 1:
            step1Title = heading
            step1Detail = body
        case 2:
            step2Title = heading
            step2Detail = body
        case 3:
            step3Title = heading
            step3Detail = body
        default:
            break
        }

        let text = NSStackView(views: [heading, body])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [badge, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeMockListCard() -> NSView {
        let card = WelcomeCardView(style: .surface, cornerRadius: 12)

        let shield = WelcomeIconBadgeView(symbol: "hand.raised.fill", size: 28, symbolSize: 13)
        let header = NSTextField(labelWithString: L10n.text(.onboardingMockHeader))
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .labelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        mockHeaderLabel = header

        let headerRow = NSStackView(views: [shield, header])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8

        let zone = mockRow(symbol: "rectangle.split.3x1", name: "ZoneBox", on: false, highlight: true)
        let finder = mockRow(symbol: "face.smiling", name: "Finder", on: true, highlight: false)
        let zoom = mockRow(symbol: "video.fill", name: "Zoom", on: false, highlight: false)

        let inner = NSStackView(views: [headerRow, zone, finder, zoom])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)

        NSLayoutConstraint.activate([
            zone.widthAnchor.constraint(equalTo: inner.widthAnchor),
            finder.widthAnchor.constraint(equalTo: inner.widthAnchor),
            zoom.widthAnchor.constraint(equalTo: inner.widthAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            inner.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func mockRow(symbol: String, name: String, on: Bool, highlight: Bool) -> NSView {
        let rowCard = WelcomeCardView(style: highlight ? .tinted : .surface, cornerRadius: 8)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        icon.contentTintColor = highlight ? .controlAccentColor : .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let nameField = NSTextField(labelWithString: name)
        nameField.font = .systemFont(ofSize: 13, weight: highlight ? .semibold : .regular)
        nameField.textColor = highlight ? .controlAccentColor : .labelColor
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.state = on ? .on : .off
        toggle.isEnabled = false
        if highlight {
            zoneSwitch = toggle
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, nameField, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        rowCard.addSubview(row)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            row.topAnchor.constraint(equalTo: rowCard.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: rowCard.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: rowCard.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: rowCard.trailingAnchor, constant: -10),
        ])
        return rowCard
    }

    private func makeStatusAndActionsCard() -> NSView {
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.setContentHuggingPriority(.required, for: .horizontal)

        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        statusIcon.setContentHuggingPriority(.required, for: .horizontal)

        let statusLeft = NSStackView(views: [spinner, statusIcon, statusLabel])
        statusLeft.orientation = .horizontal
        statusLeft.alignment = .centerY
        statusLeft.spacing = 8
        statusLeft.detachesHiddenViews = true
        statusLeft.translatesAutoresizingMaskIntoConstraints = false

        let check = ConsoleButton(
            role: .surface,
            title: L10n.text(.onboardingIveTurnedItOn),
            target: self,
            action: #selector(tapConfirm)
        )
        check.fontSize = 12
        check.fontWeight = .medium
        check.controlHeight = 30
        check.horizontalPadding = 12
        checkButton = check

        let secondary = ConsoleButton(
            role: .surface,
            title: L10n.text(.onboardingNotNow),
            target: self,
            action: #selector(tapContinue)
        )
        secondary.fontSize = 12
        secondary.fontWeight = .medium
        secondary.controlHeight = 30
        secondary.horizontalPadding = 12
        secondaryButton = secondary

        let primary = ConsoleButton(
            role: .primary,
            title: L10n.text(.onboardingOpenSettings),
            symbol: "gearshape.fill",
            target: self,
            action: #selector(tapOpen)
        )
        primary.fontSize = 12.5
        primary.fontWeight = .semibold
        primary.controlHeight = 32
        primary.horizontalPadding = 16
        if showsHeader {
            primary.keyEquivalent = "\r"
        }
        primaryButton = primary

        let buttonsRow = NSStackView(views: [secondary, check, primary])
        buttonsRow.orientation = .horizontal
        buttonsRow.alignment = .centerY
        buttonsRow.spacing = 8
        buttonsRow.detachesHiddenViews = true
        buttonsRow.setContentHuggingPriority(.required, for: .horizontal)
        buttonsRow.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [statusLeft, spacer, buttonsRow])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -14),
        ])
        return statusCard
    }

    @objc private func tapOpen() { onOpenSettings?() }
    @objc private func tapConfirm() { onConfirmEnabled?() }
    @objc private func tapRelaunch() { onRelaunch?() }
    @objc private func tapContinue() { onContinue?() }
}
