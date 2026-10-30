import AppKit
import ZoneBoxCore

// MARK: - Shared Onboarding UI Components

final class WelcomeAutoWrapLabel: NSTextField {
    init(_ text: String = "", font: NSFont = .systemFont(ofSize: 13), color: NSColor = .secondaryLabelColor) {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        lineBreakMode = .byWordWrapping
        maximumNumberOfLines = 0
        cell?.wraps = true
        cell?.isScrollable = false
        self.font = font
        self.textColor = color
        self.stringValue = text
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = max(0, floor(bounds.width))
        if width > 0, abs(preferredMaxLayoutWidth - width) > 1 {
            preferredMaxLayoutWidth = width
            invalidateIntrinsicContentSize()
        }
    }
}

final class WelcomeCardView: NSView {
    enum Style {
        case surface
        case tinted
        case success
        case warning
    }

    var style: Style = .surface {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat = 12 {
        didSet { needsDisplay = true }
    }

    init(style: Style = .surface, cornerRadius: CGFloat = 12) {
        self.style = style
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let blue = ConsoleChrome.brandBlue(dark: dark)
        let orange = ConsoleChrome.warning(dark: dark)
        let green = dark
            ? NSColor(srgbRed: 0.24, green: 0.80, blue: 0.46, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.65, blue: 0.34, alpha: 1)

        let fill: NSColor
        let border: NSColor
        switch style {
        case .surface:
            fill = ConsoleChrome.surface(dark: dark)
            border = ConsoleChrome.surfaceBorder(dark: dark)
        case .tinted:
            fill = blue.withAlphaComponent(dark ? 0.13 : 0.065)
            border = blue.withAlphaComponent(dark ? 0.35 : 0.22)
        case .success:
            fill = green.withAlphaComponent(dark ? 0.14 : 0.08)
            border = green.withAlphaComponent(dark ? 0.42 : 0.28)
        case .warning:
            fill = orange.withAlphaComponent(dark ? 0.15 : 0.09)
            border = orange.withAlphaComponent(dark ? 0.45 : 0.30)
        }

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        fill.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class WelcomeIconBadgeView: NSView {
    var symbolName: String {
        didSet { needsDisplay = true }
    }
    var badgeText: String? {
        didSet { needsDisplay = true }
    }
    var customTintColor: NSColor? {
        didSet { needsDisplay = true }
    }
    private let badgeSize: CGFloat
    private let symbolPointSize: CGFloat

    init(symbol: String, badgeText: String? = nil, size: CGFloat = 36, symbolSize: CGFloat = 16, tint: NSColor? = nil) {
        self.symbolName = symbol
        self.badgeText = badgeText
        self.badgeSize = size
        self.symbolPointSize = symbolSize
        self.customTintColor = tint
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let accent = customTintColor ?? ConsoleChrome.brandBlue(dark: dark)
        let radius = min(10, badgeSize * 0.28)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        accent.withAlphaComponent(dark ? 0.18 : 0.11).setFill()
        path.fill()
        accent.withAlphaComponent(dark ? 0.30 : 0.18).setStroke()
        path.lineWidth = 1
        path.stroke()

        if let badgeText, !badgeText.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: symbolPointSize, weight: .bold),
                .foregroundColor: accent,
            ]
            let sz = (badgeText as NSString).size(withAttributes: attrs)
            (badgeText as NSString).draw(
                at: NSPoint(x: (bounds.midX - sz.width / 2).rounded(), y: (bounds.midY - sz.height / 2).rounded()),
                withAttributes: attrs
            )
            return
        }

        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [accent]))
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let size = image.size
            let origin = NSPoint(
                x: (bounds.midX - size.width / 2).rounded(),
                y: (bounds.midY - size.height / 2).rounded()
            )
            image.draw(in: NSRect(origin: origin, size: size))
        }
    }
}

final class WelcomeKeyCapView: NSView {
    private let symbol: String
    private let label: NSTextField

    init(symbol: String) {
        self.symbol = symbol
        self.label = NSTextField(labelWithString: symbol)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let width = max(24, ceil((symbol as NSString).size(withAttributes: [.font: label.font!]).width) + 12)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 23),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let blue = ConsoleChrome.brandBlue(dark: dark)
        label.textColor = blue

        let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: outer, xRadius: 5.5, yRadius: 5.5)
        blue.withAlphaComponent(dark ? 0.18 : 0.10).setFill()
        path.fill()
        blue.withAlphaComponent(dark ? 0.42 : 0.25).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

// MARK: - Page 1: Welcome Intro

@MainActor
final class WelcomeIntroPage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = WelcomeAutoWrapLabel(font: .systemFont(ofSize: 13.5), color: .secondaryLabelColor)
    private let menuCopy = WelcomeAutoWrapLabel(font: .systemFont(ofSize: 12.5), color: .secondaryLabelColor)
    private var locateButton: ConsoleButton!
    private let stageView = WelcomeDesktopStageView()

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
        stageView.pulseMenuBarHighlight()
    }

    func willDisappear() {
        stageView.stopAnimation()
    }

    func refresh(state: OnboardingFlowState) {}

    func applyLanguage() {
        titleLabel.stringValue = L10n.text(.welcomeIntroTitle)
        subtitleLabel.stringValue = L10n.text(.welcomeIntroSubtitle)
        menuCopy.stringValue = L10n.text(.welcomeIntroMenuBar)
        locateButton.title = L10n.text(.welcomeIntroLocate)
        stageView.needsDisplay = true
    }

    private func build() {
        // 1. Hero Header
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 15
        icon.layer?.cornerCurve = .continuous
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 25, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerTextStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 5
        headerTextStack.translatesAutoresizingMaskIntoConstraints = false

        let headerRow = NSStackView(views: [icon, headerTextStack])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 16
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        // 2. Desktop + Menu Bar Stage
        stageView.translatesAutoresizingMaskIntoConstraints = false

        // 3. Menu Bar Callout Card
        let calloutCard = WelcomeCardView(style: .surface, cornerRadius: 12)
        let badge = WelcomeIconBadgeView(symbol: "menubar.rectangle", size: 38, symbolSize: 17)

        let locate = ConsoleButton(
            role: .tinted,
            title: L10n.text(.welcomeIntroLocate),
            symbol: "sparkles",
            target: self,
            action: #selector(showMe)
        )
        locate.fontSize = 12.5
        locate.fontWeight = .semibold
        locate.controlHeight = 32
        locate.horizontalPadding = 14
        locate.setContentHuggingPriority(.required, for: .horizontal)
        locate.setContentCompressionResistancePriority(.required, for: .horizontal)
        locateButton = locate

        let calloutRow = NSStackView(views: [badge, menuCopy, locate])
        calloutRow.orientation = .horizontal
        calloutRow.alignment = .centerY
        calloutRow.spacing = 14
        calloutRow.translatesAutoresizingMaskIntoConstraints = false
        calloutCard.addSubview(calloutRow)

        let mainStack = NSStackView(views: [headerRow, stageView, calloutCard])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 16
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            headerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),

            stageView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            stageView.heightAnchor.constraint(equalToConstant: 236),

            calloutCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            calloutRow.topAnchor.constraint(equalTo: calloutCard.topAnchor, constant: 14),
            calloutRow.bottomAnchor.constraint(equalTo: calloutCard.bottomAnchor, constant: -14),
            calloutRow.leadingAnchor.constraint(equalTo: calloutCard.leadingAnchor, constant: 16),
            calloutRow.trailingAnchor.constraint(equalTo: calloutCard.trailingAnchor, constant: -16),

            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    @objc private func showMe() {
        stageView.pulseMenuBarHighlight()
        runtime.menuBar?.pulseStatusItem()
    }
}

private final class WelcomeDesktopStageView: NSView {
    private var pulsePhase: CGFloat = 0
    private var pulseTimer: Timer?
    private var pulseTicks = 0

    func pulseMenuBarHighlight() {
        stopAnimation()
        pulseTicks = 0
        pulsePhase = 1.0
        needsDisplay = true
        let timer = Timer(timeInterval: 0.04, target: self, selector: #selector(stepPulse), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    func stopAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    @objc private func stepPulse() {
        pulseTicks += 1
        let t = CGFloat(pulseTicks) / 36.0
        if t >= 1.0 {
            pulsePhase = 0
            stopAnimation()
        } else {
            pulsePhase = abs(sin(t * .pi * 3))
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let blue = ConsoleChrome.brandBlue(dark: dark)
        let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
        let screenPath = NSBezierPath(roundedRect: outer, xRadius: 14, yRadius: 14)

        NSGraphicsContext.saveGraphicsState()
        screenPath.addClip()

        // Desktop wallpaper gradient
        let topWall = dark
            ? NSColor(srgbRed: 0.13, green: 0.16, blue: 0.24, alpha: 1)
            : NSColor(srgbRed: 0.88, green: 0.92, blue: 0.98, alpha: 1)
        let bottomWall = dark
            ? NSColor(srgbRed: 0.08, green: 0.10, blue: 0.15, alpha: 1)
            : NSColor(srgbRed: 0.93, green: 0.95, blue: 0.99, alpha: 1)
        NSGradient(starting: topWall, ending: bottomWall)?.draw(in: outer, angle: -90)

        // Top Menu Bar
        let menuBarHeight: CGFloat = 32
        let menuBarRect = NSRect(x: outer.minX, y: outer.maxY - menuBarHeight, width: outer.width, height: menuBarHeight)
        let menuBarFill = dark
            ? NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 0.92)
            : NSColor(srgbRed: 0.14, green: 0.16, blue: 0.22, alpha: 0.92)
        menuBarFill.setFill()
        menuBarRect.fill()

        // Menu bar left items (Apple logo + menus)
        let menuFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let menuItemFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let menuAttrs: [NSAttributedString.Key: Any] = [.font: menuFont, .foregroundColor: NSColor.white.withAlphaComponent(0.92)]
        let dimAttrs: [NSAttributedString.Key: Any] = [.font: menuItemFont, .foregroundColor: NSColor.white.withAlphaComponent(0.55)]
        ("" as NSString).draw(at: NSPoint(x: outer.minX + 16, y: menuBarRect.midY - 7), withAttributes: menuAttrs)
        ("Finder" as NSString).draw(at: NSPoint(x: outer.minX + 36, y: menuBarRect.midY - 7), withAttributes: menuAttrs)
        ("File   Edit   View" as NSString).draw(at: NSPoint(x: outer.minX + 84, y: menuBarRect.midY - 7), withAttributes: dimAttrs)

        // Menu bar right items: Clock + Highlighted ZoneBox Icon + Wi-Fi
        let clockAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
        let clockStr = "9:41" as NSString
        let clockSize = clockStr.size(withAttributes: clockAttrs)
        let clockX = outer.maxX - 16 - clockSize.width
        clockStr.draw(at: NSPoint(x: clockX, y: menuBarRect.midY - clockSize.height / 2), withAttributes: clockAttrs)

        // ZoneBox highlighted status pill in menu bar
        let pillWidth: CGFloat = 86
        let pillHeight: CGFloat = 22
        let pillRect = NSRect(
            x: clockX - 12 - pillWidth,
            y: menuBarRect.midY - pillHeight / 2,
            width: pillWidth,
            height: pillHeight
        )
        if pulsePhase > 0.01 {
            let haloInset = -4.0 * pulsePhase
            let haloRect = pillRect.insetBy(dx: haloInset, dy: haloInset)
            let haloPath = NSBezierPath(roundedRect: haloRect, xRadius: haloRect.height / 2, yRadius: haloRect.height / 2)
            blue.withAlphaComponent(0.45 * pulsePhase).setStroke()
            haloPath.lineWidth = 2
            haloPath.stroke()
        }
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
        blue.withAlphaComponent(0.92 + 0.08 * pulsePhase).setFill()
        pillPath.fill()

        if let symbol = ConsoleChrome.symbol("rectangle.split.3x1", size: 11, weight: .semibold, color: .white) {
            symbol.draw(in: NSRect(x: pillRect.minX + 8, y: pillRect.midY - 6, width: 14, height: 12))
        }
        let zbAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        ("ZoneBox" as NSString).draw(at: NSPoint(x: pillRect.minX + 26, y: pillRect.midY - 6.5), withAttributes: zbAttrs)

        // Subtle Wi-Fi / Battery icons to the left of ZoneBox pill
        if let wifi = ConsoleChrome.symbol("wifi", size: 11, weight: .medium, color: NSColor.white.withAlphaComponent(0.65)) {
            wifi.draw(in: NSRect(x: pillRect.minX - 24, y: menuBarRect.midY - 6, width: 14, height: 12))
        }
        if let battery = ConsoleChrome.symbol("battery.100", size: 11, weight: .medium, color: NSColor.white.withAlphaComponent(0.65)) {
            battery.draw(in: NSRect(x: pillRect.minX - 48, y: menuBarRect.midY - 6, width: 18, height: 12))
        }

        // Desktop Workspace Canvas (Left: 3 Zones with Snapped Window; Right: Mini Console Popover under ZoneBox icon)
        let desktopRect = NSRect(x: outer.minX + 18, y: outer.minY + 16, width: outer.width - 36, height: outer.height - menuBarHeight - 30)
        let leftCanvasWidth = desktopRect.width * 0.62
        let gap: CGFloat = 10
        let leftZoneWidth = (leftCanvasWidth - gap) * 0.56
        let rightZoneWidth = leftCanvasWidth - gap - leftZoneWidth
        let halfHeight = (desktopRect.height - gap) / 2

        let zone1 = NSRect(x: desktopRect.minX, y: desktopRect.minY, width: leftZoneWidth, height: desktopRect.height)
        let zone2 = NSRect(x: zone1.maxX + gap, y: desktopRect.minY + halfHeight + gap, width: rightZoneWidth, height: halfHeight)
        let zone3 = NSRect(x: zone1.maxX + gap, y: desktopRect.minY, width: rightZoneWidth, height: halfHeight)

        for (index, zRect) in [zone1, zone2, zone3].enumerated() {
            let active = index == 0
            let zPath = NSBezierPath(roundedRect: zRect, xRadius: 9, yRadius: 9)
            blue.withAlphaComponent(active ? (dark ? 0.28 : 0.20) : (dark ? 0.12 : 0.08)).setFill()
            zPath.fill()
            let strokeColor = active
                ? blue.withAlphaComponent(dark ? 0.85 : 0.70)
                : blue.withAlphaComponent(dark ? 0.35 : 0.28)
            strokeColor.setStroke()
            zPath.lineWidth = active ? 1.6 : 1.2
            if !active {
                let dash: [CGFloat] = [5, 3.5]
                zPath.setLineDash(dash, count: dash.count, phase: 0)
            }
            zPath.stroke()

            // Zone number badge
            let numStr = "\(index + 1)" as NSString
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold),
                .foregroundColor: active ? blue : blue.withAlphaComponent(0.65),
            ]
            let numSize = numStr.size(withAttributes: numAttrs)
            if index > 0 {
                numStr.draw(
                    at: NSPoint(x: zRect.midX - numSize.width / 2, y: zRect.midY - numSize.height / 2),
                    withAttributes: numAttrs
                )
            }
        }

        // Draw miniature snapped window inside Zone 1
        let winRect = zone1.insetBy(dx: 8, dy: 8)
        let winPath = NSBezierPath(roundedRect: winRect, xRadius: 7, yRadius: 7)
        (dark ? NSColor(srgbRed: 0.18, green: 0.20, blue: 0.25, alpha: 0.96) : NSColor.white.withAlphaComponent(0.96)).setFill()
        winPath.fill()
        ConsoleChrome.surfaceBorder(dark: dark).setStroke()
        winPath.lineWidth = 1
        winPath.stroke()

        // Miniature window traffic lights & content lines
        let dotColors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (idx, dotColor) in dotColors.enumerated() {
            dotColor.withAlphaComponent(0.85).setFill()
            let dRect = NSRect(x: winRect.minX + 10 + CGFloat(idx) * 10, y: winRect.maxY - 14, width: 6, height: 6)
            NSBezierPath(ovalIn: dRect).fill()
        }
        let barColor = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.08)
        barColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: winRect.minX + 10, y: winRect.maxY - 34, width: winRect.width * 0.55, height: 8), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(roundedRect: NSRect(x: winRect.minX + 10, y: winRect.maxY - 48, width: winRect.width * 0.78, height: 6), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(roundedRect: NSRect(x: winRect.minX + 10, y: winRect.minY + 12, width: winRect.width - 20, height: winRect.height - 68), xRadius: 5, yRadius: 5).fill()

        // Draw miniature Console Popover under the ZoneBox menu bar icon on the right
        let popWidth: CGFloat = min(210, desktopRect.width - leftCanvasWidth - 18)
        let popHeight: CGFloat = desktopRect.height + 4
        let popRect = NSRect(
            x: outer.maxX - 18 - popWidth,
            y: desktopRect.minY,
            width: popWidth,
            height: popHeight
        )
        let popPath = NSBezierPath(roundedRect: popRect, xRadius: 10, yRadius: 10)
        (dark ? NSColor(srgbRed: 0.15, green: 0.16, blue: 0.20, alpha: 0.96) : NSColor.white.withAlphaComponent(0.96)).setFill()
        popPath.fill()
        blue.withAlphaComponent(dark ? 0.45 : 0.30).setStroke()
        popPath.lineWidth = 1.2
        popPath.stroke()

        // Pointer triangle from popover to ZoneBox menu bar pill
        let arrowX = min(popRect.maxX - 20, max(popRect.minX + 20, pillRect.midX))
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: arrowX - 6, y: popRect.maxY))
        arrow.line(to: NSPoint(x: arrowX, y: popRect.maxY + 6))
        arrow.line(to: NSPoint(x: arrowX + 6, y: popRect.maxY))
        arrow.close()
        (dark ? NSColor(srgbRed: 0.15, green: 0.16, blue: 0.20, alpha: 0.96) : NSColor.white.withAlphaComponent(0.96)).setFill()
        arrow.fill()

        // Mini popover header & layout thumbnails
        let popHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        ("ZoneBox" as NSString).draw(at: NSPoint(x: popRect.minX + 12, y: popRect.maxY - 22), withAttributes: popHeaderAttrs)

        let presets = Array(LayoutTemplates.editorPresets().prefix(3))
        let thumbW = (popRect.width - 24 - 12) / 3
        let thumbH: CGFloat = 34
        let thumbY = popRect.maxY - 28 - thumbH
        for (i, preset) in presets.enumerated() {
            let tRect = NSRect(x: popRect.minX + 12 + CGFloat(i) * (thumbW + 6), y: thumbY, width: thumbW, height: thumbH)
            let tPath = NSBezierPath(roundedRect: tRect, xRadius: 5, yRadius: 5)
            ConsoleChrome.screenPlate(dark: dark).setFill()
            tPath.fill()
            if i == 0 {
                blue.setStroke()
                tPath.lineWidth = 1.2
                tPath.stroke()
            }
            let img = LayoutThumbnailRenderer.image(
                for: preset,
                size: tRect.insetBy(dx: 3, dy: 3).size,
                fill: i == 0 ? ConsoleChrome.zoneActive(dark: dark) : ConsoleChrome.zoneIdle(dark: dark),
                stroke: .clear,
                gutterPoints: 2,
                showNumbers: false,
                cornerRadius: 2,
                lineWidth: 0
            )
            img.draw(in: tRect.insetBy(dx: 3, dy: 3))
        }

        // Mini workspace pills inside popover
        for row in 0..<2 {
            let rRect = NSRect(
                x: popRect.minX + 12,
                y: thumbY - 12 - CGFloat(row + 1) * 22,
                width: popRect.width - 24,
                height: 17
            )
            guard rRect.minY >= popRect.minY + 8 else { continue }
            let rPath = NSBezierPath(roundedRect: rRect, xRadius: 4, yRadius: 4)
            (row == 0 ? blue.withAlphaComponent(dark ? 0.18 : 0.10) : barColor).setFill()
            rPath.fill()
        }

        NSGraphicsContext.restoreGraphicsState()

        ConsoleChrome.surfaceBorder(dark: dark).setStroke()
        screenPath.lineWidth = 1
        screenPath.stroke()
    }
}

// MARK: - Page 5: Welcome More (Beyond Snapping)

@MainActor
final class WelcomeMorePage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let titleLabel = NSTextField(labelWithString: "")
    private var openEditorButton: ConsoleButton!
    private var editorCard: WelcomeFeatureBentoCard!
    private var dividerCard: WelcomeFeatureBentoCard!
    private var workspaceCard: WelcomeFeatureBentoCard!
    private var pinCard: WelcomeFeatureBentoCard!

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
        openEditorButton.title = L10n.text(.welcomeMoreOpenEditor)

        let editorCaps = runtime.settings.editorHotkey.displayCaps
        let workspaceCaps = runtime.settings.applyWorkspaceHotkey.displayCaps
        let quickCaps = runtime.settings.quickSnapperHotkey.displayCaps

        editorCard.configure(
            fullText: L10n.welcomeMoreEditor(editorCaps.joined()),
            caps: editorCaps
        )
        dividerCard.configure(
            fullText: L10n.text(.welcomeMoreDivider),
            caps: ["↔ Drag"]
        )
        workspaceCard.configure(
            fullText: L10n.welcomeMoreWorkspaces(workspaceCaps.joined()),
            caps: workspaceCaps
        )
        pinCard.configure(
            fullText: L10n.welcomeMoreQuickAndPin(quickCaps.joined()),
            caps: quickCaps
        )
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let openBtn = ConsoleButton(
            role: .tinted,
            title: L10n.text(.welcomeMoreOpenEditor),
            symbol: "slider.horizontal.3",
            target: self,
            action: #selector(openLayoutEditor)
        )
        openBtn.fontSize = 12.5
        openBtn.fontWeight = .semibold
        openBtn.controlHeight = 32
        openBtn.horizontalPadding = 14
        openEditorButton = openBtn

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerRow = NSStackView(views: [titleLabel, spacer, openBtn])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        editorCard = WelcomeFeatureBentoCard(symbol: "slider.horizontal.3")
        dividerCard = WelcomeFeatureBentoCard(symbol: "arrow.left.and.right.square")
        workspaceCard = WelcomeFeatureBentoCard(symbol: "square.grid.3x3.square")
        pinCard = WelcomeFeatureBentoCard(symbol: "pin.fill")

        let topRow = NSStackView(views: [editorCard, dividerCard])
        topRow.orientation = .horizontal
        topRow.distribution = .fillEqually
        topRow.spacing = 14
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let bottomRow = NSStackView(views: [workspaceCard, pinCard])
        bottomRow.orientation = .horizontal
        bottomRow.distribution = .fillEqually
        bottomRow.spacing = 14
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [headerRow, topRow, bottomRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            headerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            topRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            topRow.heightAnchor.constraint(equalToConstant: 170),
            bottomRow.heightAnchor.constraint(equalToConstant: 170),

            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    @objc private func openLayoutEditor() {
        runtime.openEditor()
    }
}

private final class WelcomeFeatureBentoCard: NSView {
    private let card = WelcomeCardView(style: .surface, cornerRadius: 12)
    private let iconBadge: WelcomeIconBadgeView
    private let capsStack = NSStackView()
    private let headingLabel = NSTextField(labelWithString: "")
    private let bodyLabel = WelcomeAutoWrapLabel(font: .systemFont(ofSize: 12.5), color: .secondaryLabelColor)

    init(symbol: String) {
        self.iconBadge = WelcomeIconBadgeView(symbol: symbol, size: 36, symbolSize: 16)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(fullText: String, caps: [String]) {
        let (heading, detail) = Self.splitHeadingAndBody(fullText)
        headingLabel.stringValue = heading
        headingLabel.isHidden = heading.isEmpty
        bodyLabel.stringValue = detail

        capsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for cap in caps {
            capsStack.addArrangedSubview(WelcomeKeyCapView(symbol: cap))
        }
    }

    private static func splitHeadingAndBody(_ text: String) -> (String, String) {
        if let range = text.range(of: "：") {
            let title = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let body = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (title, body)
        }
        if let range = text.range(of: ":") {
            let title = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let body = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (title, body)
        }
        return ("Quick Snapper & Pin", text)
    }

    private func build() {
        addSubview(card)

        capsStack.orientation = .horizontal
        capsStack.spacing = 4
        capsStack.alignment = .centerY

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [iconBadge, spacer, capsStack])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false

        headingLabel.font = .systemFont(ofSize: 14.5, weight: .semibold)
        headingLabel.textColor = .labelColor
        headingLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [headingLabel, bodyLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 5
        textStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(topRow)
        card.addSubview(textStack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),

            topRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            topRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            topRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            textStack.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 14),
            textStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14),
        ])
    }
}

// MARK: - Page 6: Welcome Finish

@MainActor
final class WelcomeFinishPage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = WelcomeAutoWrapLabel(font: .systemFont(ofSize: 13.5), color: .secondaryLabelColor)
    private let reopenLabel = WelcomeAutoWrapLabel(font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
    private let loginSwitch = NSSwitch()
    private let loginLabel = NSTextField(labelWithString: "")
    private var openSettingsButton: ConsoleButton!
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
        loginSwitch.setAccessibilityLabel(L10n.text(.settingsLaunchAtLogin))
        openSettingsButton.title = L10n.text(.welcomeFinishOpenSettings)
        loginSwitch.state = runtime.settings.launchAtLogin ? .on : .off
        rebuildShortcuts()
    }

    private func build() {
        // 1. Header with badge + Open Settings button
        let heroBadge = WelcomeIconBadgeView(
            symbol: "checkmark.circle.fill",
            size: 46,
            symbolSize: 22,
            tint: .systemGreen
        )

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .labelColor

        let headerText = NSStackView(views: [titleLabel, bodyLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 4

        let openSettings = ConsoleButton(
            role: .surface,
            title: L10n.text(.welcomeFinishOpenSettings),
            symbol: "gearshape",
            target: self,
            action: #selector(tapSettings)
        )
        openSettings.fontSize = 12.5
        openSettings.fontWeight = .medium
        openSettings.controlHeight = 32
        openSettings.horizontalPadding = 14
        openSettingsButton = openSettings

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerRow = NSStackView(views: [heroBadge, headerText, headerSpacer, openSettings])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 14
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        // 2. Shortcuts Cheat-Sheet Card
        let shortcutsCard = WelcomeCardView(style: .surface, cornerRadius: 12)
        shortcutStack.orientation = .vertical
        shortcutStack.alignment = .leading
        shortcutStack.spacing = 0
        shortcutStack.translatesAutoresizingMaskIntoConstraints = false
        shortcutsCard.addSubview(shortcutStack)

        // 3. Launch at Login + Reopen Hint Card
        let loginCard = WelcomeCardView(style: .surface, cornerRadius: 12)
        let loginIcon = WelcomeIconBadgeView(symbol: "power.circle.fill", size: 36, symbolSize: 17)

        loginLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        loginLabel.textColor = .labelColor

        let loginTextStack = NSStackView(views: [loginLabel, reopenLabel])
        loginTextStack.orientation = .vertical
        loginTextStack.alignment = .leading
        loginTextStack.spacing = 3

        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)
        loginSwitch.setContentHuggingPriority(.required, for: .horizontal)

        let loginSpacer = NSView()
        loginSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let loginRow = NSStackView(views: [loginIcon, loginTextStack, loginSpacer, loginSwitch])
        loginRow.orientation = .horizontal
        loginRow.alignment = .centerY
        loginRow.spacing = 12
        loginRow.translatesAutoresizingMaskIntoConstraints = false
        loginCard.addSubview(loginRow)

        let mainStack = NSStackView(views: [headerRow, shortcutsCard, loginCard])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            headerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),

            shortcutsCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            shortcutStack.topAnchor.constraint(equalTo: shortcutsCard.topAnchor, constant: 4),
            shortcutStack.bottomAnchor.constraint(equalTo: shortcutsCard.bottomAnchor, constant: -4),
            shortcutStack.leadingAnchor.constraint(equalTo: shortcutsCard.leadingAnchor),
            shortcutStack.trailingAnchor.constraint(equalTo: shortcutsCard.trailingAnchor),

            loginCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            loginRow.topAnchor.constraint(equalTo: loginCard.topAnchor, constant: 13),
            loginRow.bottomAnchor.constraint(equalTo: loginCard.bottomAnchor, constant: -13),
            loginRow.leadingAnchor.constraint(equalTo: loginCard.leadingAnchor, constant: 16),
            loginRow.trailingAnchor.constraint(equalTo: loginCard.trailingAnchor, constant: -16),

            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    private func rebuildShortcuts() {
        shortcutStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let grouped = ShortcutCatalog.grouped(from: runtime.settings)
        let wanted: Set<String> = ["snapZone1", "unsnap", "openEditor", "quickSnapper", "showShortcuts"]
        let symbolsByID: [String: String] = [
            "snapZone1": "rectangle.split.3x1",
            "unsnap": "arrow.uturn.backward.square",
            "openEditor": "slider.horizontal.3",
            "quickSnapper": "number.square",
            "showShortcuts": "command.square",
        ]
        var rows: [(symbol: String, title: String, caps: [String])] = []
        for group in grouped {
            for item in group.items {
                if item.id.hasPrefix("snapZone"), case .chord(let chord) = item.binding {
                    if !rows.contains(where: { $0.title == L10n.text(.shortcutSnapZones) }) {
                        rows.append((
                            symbol: "rectangle.split.3x1",
                            title: L10n.text(.shortcutSnapZones),
                            caps: Array(chord.displayCaps.dropLast()) + ["1–9"]
                        ))
                    }
                    continue
                }
                guard wanted.contains(item.id), case .chord(let chord) = item.binding else { continue }
                rows.append((
                    symbol: symbolsByID[item.id] ?? "keyboard",
                    title: item.title(language: LanguageCenter.language),
                    caps: chord.displayCaps
                ))
            }
        }

        let displayRows = Array(rows.prefix(5))
        for (idx, row) in displayRows.enumerated() {
            let rowView = makeShortcutRow(symbol: row.symbol, title: row.title, caps: row.caps, showDivider: idx < displayRows.count - 1)
            shortcutStack.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: shortcutStack.widthAnchor).isActive = true
        }
    }

    private func makeShortcutRow(symbol: String, title: String, caps: [String], showDivider: Bool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13.5, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.textColor = .labelColor
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let capsRow = NSStackView(views: caps.map { WelcomeKeyCapView(symbol: $0) })
        capsRow.orientation = .horizontal
        capsRow.spacing = 5
        capsRow.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let line = NSStackView(views: [icon, titleField, spacer, capsRow])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 10
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)

        if showDivider {
            let divider = NSBox()
            divider.boxType = .separator
            divider.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(divider)
            NSLayoutConstraint.activate([
                divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
                divider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                divider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 42),
        ])
        return container
    }

    @objc private func toggleLogin() {
        LoginItemController.set(enabled: loginSwitch.state == .on, runtime: runtime)
    }

    @objc private func tapSettings() {
        onOpenSettings()
    }
}
