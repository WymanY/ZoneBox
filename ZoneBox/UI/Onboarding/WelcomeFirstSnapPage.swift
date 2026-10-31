import AppKit
import ZoneBoxCore

@MainActor
final class WelcomeFirstSnapPage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = WelcomeAutoWrapLabel(font: .systemFont(ofSize: 13.5), color: .secondaryLabelColor)
    private let footnoteLabel = WelcomeAutoWrapLabel(font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
    private let statusCard = WelcomeCardView(style: .tinted, cornerRadius: 12)
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    private let spinner = NSProgressIndicator()
    private var showZonesButton: ConsoleButton!
    private var goAccessButton: ConsoleButton!
    private let cardsStack = NSStackView()
    private let demoCanvas = WelcomeSnapAnimatedCanvasView()

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { nil }

    var view: NSView { self }

    func willAppear(state: OnboardingFlowState) {
        applyLanguage()
        refresh(state: state)
        demoCanvas.startAnimation()
    }

    func willDisappear() {
        demoCanvas.stopAnimation()
        spinner.stopAnimation(nil)
    }

    func refresh(state: OnboardingFlowState) {
        applyLanguage()
        rebuildCards()
        demoCanvas.isSnappedCompleted = state.didSnap
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        statusIcon.isHidden = false
        goAccessButton.isHidden = true

        if !state.trusted {
            statusCard.style = .warning
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemOrange
            statusLabel.stringValue = L10n.text(.welcomeSnapNeedsAccess)
            goAccessButton.isHidden = false
        } else if state.didSnap {
            statusCard.style = .success
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            statusLabel.stringValue = L10n.welcomeSnapDone(runtime.settings.unsnapHotkey.displayCaps.joined())
        } else {
            statusCard.style = .tinted
            statusIcon.image = nil
            statusIcon.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
            statusLabel.stringValue = L10n.text(.welcomeSnapWaiting)
        }
    }

    func applyLanguage() {
        titleLabel.stringValue = L10n.text(.welcomeSnapTitle)
        bodyLabel.stringValue = L10n.text(.welcomeSnapBody)
        var notes = [L10n.text(.welcomeSnapWhileArmed)]
        if runtime.settings.shakeToSnapEnabled {
            notes.append(L10n.text(.welcomeSnapShake))
        }
        footnoteLabel.stringValue = notes.joined(separator: " ")
        showZonesButton.title = L10n.text(.welcomeSnapShowZones)
        goAccessButton.title = L10n.text(.welcomeSnapGoToAccess)
    }

    private func build() {
        // 1. Header
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [titleLabel, bodyLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        // 2. Interactive Demo Stage Card
        let stageCard = WelcomeCardView(style: .surface, cornerRadius: 12)
        demoCanvas.translatesAutoresizingMaskIntoConstraints = false

        let showZones = ConsoleButton(
            role: .tinted,
            title: L10n.text(.welcomeSnapShowZones),
            symbol: "rectangle.split.3x1",
            target: self,
            action: #selector(tapShowZones)
        )
        showZones.fontSize = 12.5
        showZones.fontWeight = .semibold
        showZones.controlHeight = 32
        showZones.horizontalPadding = 14
        showZonesButton = showZones

        let stageRightStack = NSStackView(views: [footnoteLabel, showZones])
        stageRightStack.orientation = .vertical
        stageRightStack.alignment = .leading
        stageRightStack.spacing = 10
        stageRightStack.translatesAutoresizingMaskIntoConstraints = false

        let stageRow = NSStackView(views: [demoCanvas, stageRightStack])
        stageRow.orientation = .horizontal
        stageRow.alignment = .centerY
        stageRow.spacing = 16
        stageRow.translatesAutoresizingMaskIntoConstraints = false
        stageCard.addSubview(stageRow)

        // 3. Snap Method Cards
        cardsStack.orientation = .horizontal
        cardsStack.distribution = .fillEqually
        cardsStack.spacing = 12
        cardsStack.alignment = .top
        cardsStack.translatesAutoresizingMaskIntoConstraints = false

        // 4. Status Banner
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let goAccess = ConsoleButton(
            role: .warning,
            title: L10n.text(.welcomeSnapGoToAccess),
            symbol: "lock.open.fill",
            target: self,
            action: #selector(tapAccess)
        )
        goAccess.fontSize = 12
        goAccess.fontWeight = .semibold
        goAccess.controlHeight = 28
        goAccess.horizontalPadding = 12
        goAccessButton = goAccess

        let statusSpacer = NSView()
        statusSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let statusRow = NSStackView(views: [spinner, statusIcon, statusLabel, statusSpacer, goAccess])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 10
        statusRow.detachesHiddenViews = true
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusRow)

        let mainStack = NSStackView(views: [headerStack, stageCard, cardsStack, statusCard])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            headerStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),

            stageCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            demoCanvas.widthAnchor.constraint(equalToConstant: 268),
            demoCanvas.heightAnchor.constraint(equalToConstant: 96),
            stageRow.topAnchor.constraint(equalTo: stageCard.topAnchor, constant: 12),
            stageRow.bottomAnchor.constraint(equalTo: stageCard.bottomAnchor, constant: -12),
            stageRow.leadingAnchor.constraint(equalTo: stageCard.leadingAnchor, constant: 14),
            stageRow.trailingAnchor.constraint(equalTo: stageCard.trailingAnchor, constant: -14),

            cardsStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            cardsStack.heightAnchor.constraint(equalToConstant: 142),

            statusCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            statusCard.heightAnchor.constraint(equalToConstant: 46),
            statusRow.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusRow.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -14),
            statusRow.centerYAnchor.constraint(equalTo: statusCard.centerYAnchor),

            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    private func rebuildCards() {
        cardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if runtime.settings.snapOnShiftDrag {
            cardsStack.addArrangedSubview(
                WelcomeSnapMethodCard(
                    symbol: "hand.draw.fill",
                    caps: ["⇧ Shift"],
                    text: L10n.text(.welcomeSnapShiftDrag)
                )
            )
        }
        if runtime.settings.snapOnRightClickDrag {
            cardsStack.addArrangedSubview(
                WelcomeSnapMethodCard(
                    symbol: "computermouse.fill",
                    caps: ["Right Click"],
                    text: L10n.text(.welcomeSnapRightClick)
                )
            )
        }
        if runtime.settings.snapZoneHotkeysEnabled {
            let chord = KeyChord(keyCode: AppSettings.zoneKeyCodes[0], carbonModifiers: runtime.settings.zoneHotkeyModifiers)
            cardsStack.addArrangedSubview(
                WelcomeSnapMethodCard(
                    symbol: "keyboard.fill",
                    caps: chord.displayCaps,
                    text: L10n.welcomeSnapKeyboard(chord.displayCaps.joined())
                )
            )
        }
    }

    /// Long enough to take in the zone layout and numbers, short of feeling stuck.
    private static let zonePreviewDuration: TimeInterval = 2.5

    @objc private func tapShowZones() {
        if let id = runtime.welcomeDisplayID() {
            runtime.previewZones(on: id, duration: Self.zonePreviewDuration)
        } else {
            runtime.previewZones(duration: Self.zonePreviewDuration)
        }
    }

    @objc private func tapAccess() {
        if runtime.welcome?.jumpToAccessibilityPage() == true {
            return
        }
        runtime.openAccessibility()
    }
}

private final class WelcomeSnapMethodCard: NSView {
    init(symbol: String, caps: [String], text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let card = WelcomeCardView(style: .surface, cornerRadius: 12)
        addSubview(card)

        let badge = WelcomeIconBadgeView(symbol: symbol, size: 34, symbolSize: 15)
        let capsRow = NSStackView(views: caps.map { WelcomeKeyCapView(symbol: $0) })
        capsRow.orientation = .horizontal
        capsRow.spacing = 4

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [badge, spacer, capsRow])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let body = WelcomeAutoWrapLabel(text, font: .systemFont(ofSize: 12.5), color: .labelColor)

        card.addSubview(topRow)
        card.addSubview(body)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),

            topRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            topRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            topRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            body.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            body.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class WelcomeSnapAnimatedCanvasView: NSView {
    var isSnappedCompleted = false {
        didSet { needsDisplay = true }
    }
    private var timer: Timer?
    private var phase: CGFloat = 0

    func startAnimation() {
        stopAnimation()
        let t = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {
        phase += 0.018
        if phase > 1.0 { phase = 0 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let blue = ConsoleChrome.brandBlue(dark: dark)
        let green = dark
            ? NSColor(srgbRed: 0.24, green: 0.80, blue: 0.46, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.65, blue: 0.34, alpha: 1)
        let accent = isSnappedCompleted ? green : blue

        let plate = bounds.insetBy(dx: 0.5, dy: 0.5)
        let platePath = NSBezierPath(roundedRect: plate, xRadius: 9, yRadius: 9)
        ConsoleChrome.screenPlate(dark: dark).setFill()
        platePath.fill()

        let inset: CGFloat = 8
        let gap: CGFloat = 7
        let inner = plate.insetBy(dx: inset, dy: inset)
        let zoneW = (inner.width - gap) / 2
        let zone1 = NSRect(x: inner.minX, y: inner.minY, width: zoneW, height: inner.height)
        let zone2 = NSRect(x: zone1.maxX + gap, y: inner.minY, width: zoneW, height: inner.height)

        // Smooth ease-in-out progress for the moving window
        let progress: CGFloat
        if isSnappedCompleted {
            progress = 1.0
        } else if phase < 0.55 {
            let t = phase / 0.55
            progress = t * t * (3 - 2 * t)
        } else if phase < 0.82 {
            progress = 1.0
        } else {
            let t = (phase - 0.82) / 0.18
            progress = 1.0 - t * t * (3 - 2 * t)
        }

        for (index, zRect) in [zone1, zone2].enumerated() {
            let isTarget = index == 0
            let highlight = isTarget && progress > 0.35
            let zPath = NSBezierPath(roundedRect: zRect, xRadius: 6, yRadius: 6)
            accent.withAlphaComponent(highlight ? (dark ? 0.28 : 0.18) : (dark ? 0.10 : 0.06)).setFill()
            zPath.fill()
            accent.withAlphaComponent(highlight ? 0.85 : 0.32).setStroke()
            zPath.lineWidth = highlight ? 1.5 : 1.0
            if !highlight {
                let dash: [CGFloat] = [4, 3]
                zPath.setLineDash(dash, count: dash.count, phase: 0)
            }
            zPath.stroke()

            let num = "\(index + 1)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: accent.withAlphaComponent(highlight ? 0.9 : 0.55),
            ]
            let sz = num.size(withAttributes: attrs)
            num.draw(at: NSPoint(x: zRect.midX - sz.width / 2, y: zRect.midY - sz.height / 2), withAttributes: attrs)
        }

        // Interpolate floating window from center-right into Zone 1
        let startRect = NSRect(
            x: inner.midX - 24,
            y: inner.midY - 22,
            width: zoneW * 0.78,
            height: inner.height * 0.68
        )
        let endRect = zone1.insetBy(dx: 4, dy: 4)
        let winRect = NSRect(
            x: startRect.minX + (endRect.minX - startRect.minX) * progress,
            y: startRect.minY + (endRect.minY - startRect.minY) * progress,
            width: startRect.width + (endRect.width - startRect.width) * progress,
            height: startRect.height + (endRect.height - startRect.height) * progress
        )

        let winPath = NSBezierPath(roundedRect: winRect, xRadius: 5, yRadius: 5)
        (dark ? NSColor(srgbRed: 0.20, green: 0.22, blue: 0.28, alpha: 0.96) : NSColor.white.withAlphaComponent(0.96)).setFill()
        winPath.fill()
        accent.withAlphaComponent(0.55).setStroke()
        winPath.lineWidth = 1.1
        winPath.stroke()

        // Mini window traffic lights
        let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (i, c) in colors.enumerated() {
            c.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: winRect.minX + 6 + CGFloat(i) * 7, y: winRect.maxY - 10, width: 4.5, height: 4.5)).fill()
        }
    }
}
