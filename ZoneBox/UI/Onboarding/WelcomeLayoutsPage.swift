import AppKit
import ZoneBoxCore

@MainActor
final class WelcomeLayoutsPage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let displayID: () -> DisplayIdentity.ID?
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = WelcomeAutoWrapLabel(font: .systemFont(ofSize: 13.5), color: .secondaryLabelColor)
    private let footnote = NSTextField(labelWithString: "")
    private let currentLabel = NSTextField(labelWithString: "")
    private var cards: [WelcomeLayoutPresetCard] = []
    private var selectedIndex: Int?

    init(runtime: AppRuntime, displayID: @escaping () -> DisplayIdentity.ID?) {
        self.runtime = runtime
        self.displayID = displayID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { nil }

    var view: NSView { self }

    func willAppear(state: OnboardingFlowState) {
        applyLanguage()
        refresh(state: state)
    }

    func willDisappear() {}

    func refresh(state: OnboardingFlowState) {
        applyLanguage()
        updateSelection()
    }

    func applyLanguage() {
        titleLabel.stringValue = L10n.text(.welcomeLayoutsTitle)
        bodyLabel.stringValue = L10n.text(.welcomeLayoutsBody)
        footnote.stringValue = L10n.text(.welcomeLayoutsPerDisplay)
        let presets = LayoutTemplates.editorPresets()
        for (index, card) in cards.enumerated() where index < presets.count {
            let preset = presets[index]
            card.update(
                title: L10n.layoutDisplayName(preset.name),
                selected: index == selectedIndex,
                gutterPoints: CGFloat(runtime.settings.gutterPoints)
            )
        }
        updateCurrentLabel()
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [titleLabel, bodyLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let presets = LayoutTemplates.editorPresets()
        var builtCards: [WelcomeLayoutPresetCard] = []
        for (index, preset) in presets.enumerated() {
            let card = WelcomeLayoutPresetCard(
                preset: preset,
                title: L10n.layoutDisplayName(preset.name),
                gutterPoints: CGFloat(runtime.settings.gutterPoints)
            ) { [weak self] in
                self?.selectPreset(at: index)
            }
            builtCards.append(card)
        }
        self.cards = builtCards

        let row1 = NSStackView(views: Array(builtCards.prefix(3)))
        row1.orientation = .horizontal
        row1.distribution = .fillEqually
        row1.spacing = 12
        row1.translatesAutoresizingMaskIntoConstraints = false

        let row2 = NSStackView(views: Array(builtCards.suffix(from: min(3, builtCards.count))))
        row2.orientation = .horizontal
        row2.distribution = .fillEqually
        row2.spacing = 12
        row2.translatesAutoresizingMaskIntoConstraints = false

        // Footer bar
        let footerCard = WelcomeCardView(style: .surface, cornerRadius: 10)
        let displayIcon = NSImageView()
        displayIcon.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)
        displayIcon.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        displayIcon.contentTintColor = .controlAccentColor
        displayIcon.translatesAutoresizingMaskIntoConstraints = false
        displayIcon.setContentHuggingPriority(.required, for: .horizontal)

        footnote.font = .systemFont(ofSize: 12.5, weight: .medium)
        footnote.textColor = .secondaryLabelColor
        footnote.translatesAutoresizingMaskIntoConstraints = false

        currentLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        currentLabel.textColor = .controlAccentColor
        currentLabel.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footerRow = NSStackView(views: [displayIcon, footnote, spacer, currentLabel])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 8
        footerRow.detachesHiddenViews = true
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        footerCard.addSubview(footerRow)

        let mainStack = NSStackView(views: [headerStack, row1, row2, footerCard])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            headerStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            row1.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            row2.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            row1.heightAnchor.constraint(equalToConstant: 144),
            row2.heightAnchor.constraint(equalToConstant: 144),

            footerCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            footerRow.topAnchor.constraint(equalTo: footerCard.topAnchor, constant: 10),
            footerRow.bottomAnchor.constraint(equalTo: footerCard.bottomAnchor, constant: -10),
            footerRow.leadingAnchor.constraint(equalTo: footerCard.leadingAnchor, constant: 14),
            footerRow.trailingAnchor.constraint(equalTo: footerCard.trailingAnchor, constant: -14),

            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    private func targetArea() -> WorkArea? {
        guard let id = displayID() else { return runtime.displays.workAreas.first }
        return runtime.displays.workAreas.first { $0.display.id == id } ?? runtime.displays.workAreas.first
    }

    private func workAreaAX(for area: WorkArea) -> CGRect {
        CoordinateConverter.axRect(fromAppKit: area.visibleFrameAppKit, primaryFlipHeight: runtime.displays.primaryFlipHeight)
    }

    private func updateSelection() {
        guard let area = targetArea(), let assigned = runtime.document.layout(for: area.display.id) else {
            selectedIndex = nil
            syncCards()
            updateCurrentLabel()
            return
        }
        selectedIndex = LayoutTemplates.matchingEditorPresetIndex(for: assigned, workAreaAX: workAreaAX(for: area))
        syncCards()
        updateCurrentLabel()
    }

    private func updateCurrentLabel() {
        guard let area = targetArea(), let assigned = runtime.document.layout(for: area.display.id) else {
            currentLabel.isHidden = true
            return
        }
        currentLabel.isHidden = selectedIndex != nil
        currentLabel.stringValue = L10n.welcomeLayoutsCurrent(L10n.layoutDisplayName(assigned.name))
    }

    private func syncCards() {
        let presets = LayoutTemplates.editorPresets()
        for (index, card) in cards.enumerated() where index < presets.count {
            card.update(
                title: L10n.layoutDisplayName(presets[index].name),
                selected: index == selectedIndex,
                gutterPoints: CGFloat(runtime.settings.gutterPoints)
            )
        }
    }

    private func selectPreset(at index: Int) {
        let presets = LayoutTemplates.editorPresets()
        guard index >= 0, index < presets.count, let area = targetArea() else { return }
        let preset = presets[index]
        let workAX = workAreaAX(for: area)
        let presetIndex = LayoutTemplates.matchingEditorPresetIndex(for: preset, workAreaAX: workAX)
        if let existing = runtime.document.layouts.first(where: {
            LayoutTemplates.matchingEditorPresetIndex(for: $0, workAreaAX: workAX) == presetIndex
        }) {
            runtime.selectLayout(existing, on: area.display.id)
        } else {
            _ = runtime.saveLayout(preset, to: area.display.id)
        }
        runtime.previewZones(on: area.display.id)
        selectedIndex = index
        syncCards()
        updateCurrentLabel()
    }
}

private final class WelcomeLayoutPresetCard: ConsoleInteractiveView {
    private let preset: Layout
    private var title: String
    private var selected = false
    private var gutterPoints: CGFloat
    private let onSelect: () -> Void

    init(
        preset: Layout,
        title: String,
        gutterPoints: CGFloat,
        onSelect: @escaping () -> Void
    ) {
        self.preset = preset
        self.title = title
        self.gutterPoints = gutterPoints
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, selected: Bool, gutterPoints: CGFloat) {
        self.title = title
        self.selected = selected
        self.gutterPoints = gutterPoints
        setAccessibilityLabel(title)
        setAccessibilitySelected(selected)
        toolTip = title
        needsDisplay = true
    }

    override func performPrimaryAction() {
        onSelect()
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let blue = ConsoleChrome.brandBlue(dark: dark)
        let outer = bounds.insetBy(dx: 1, dy: 1)
        let cardPath = NSBezierPath(roundedRect: outer, xRadius: 12, yRadius: 12)

        ConsoleChrome.surface(dark: dark).setFill()
        cardPath.fill()

        if isPressed {
            ConsoleChrome.pressedWash(dark: dark).setFill()
            cardPath.fill()
        } else if isHovering {
            ConsoleChrome.hoverWash(dark: dark).setFill()
            cardPath.fill()
        } else if selected {
            blue.withAlphaComponent(dark ? 0.14 : 0.07).setFill()
            cardPath.fill()
        }

        let border: NSColor
        let borderWidth: CGFloat
        if selected {
            border = blue.withAlphaComponent(dark ? 0.85 : 0.72)
            borderWidth = 1.8
        } else if isHovering || isPressed {
            border = ConsoleChrome.hoverBorder(dark: dark)
            borderWidth = 1.2
        } else {
            border = ConsoleChrome.surfaceBorder(dark: dark)
            borderWidth = 1
        }
        border.setStroke()
        cardPath.lineWidth = borderWidth
        cardPath.stroke()

        // Screen plate
        let plateInset: CGFloat = 10
        let labelAreaHeight: CGFloat = 34
        let plateRect = NSRect(
            x: bounds.minX + plateInset,
            y: bounds.minY + labelAreaHeight,
            width: max(20, bounds.width - plateInset * 2),
            height: max(20, bounds.height - labelAreaHeight - plateInset)
        )
        ConsoleChrome.screenPlate(dark: dark).setFill()
        NSBezierPath(roundedRect: plateRect, xRadius: 8, yRadius: 8).fill()

        let active = selected || isHovering || isPressed
        let previewRect = plateRect.insetBy(dx: 6, dy: 6)
        let image = LayoutThumbnailRenderer.image(
            for: preset,
            size: previewRect.size,
            fill: active ? ConsoleChrome.zoneActive(dark: dark) : ConsoleChrome.zoneIdle(dark: dark),
            stroke: .clear,
            gutterPoints: max(3, min(6, gutterPoints * 0.35)),
            showNumbers: true,
            numberColor: .white,
            cornerRadius: 4,
            lineWidth: 0,
            minimumNumberSize: 9,
            maximumNumberSize: 15
        )
        image.draw(in: previewRect)

        // Bottom title + checkmark badge
        let font = NSFont.systemFont(ofSize: 12.5, weight: selected ? .semibold : .medium)
        let textColor = selected ? blue : NSColor.labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let textSize = (title as NSString).size(withAttributes: attrs)
        let iconSpace: CGFloat = selected ? 18 : 0
        let totalWidth = textSize.width + iconSpace
        let startX = (bounds.midX - totalWidth / 2).rounded()
        let textY = ((labelAreaHeight - textSize.height) / 2).rounded()

        if selected, let check = ConsoleChrome.symbol("checkmark.circle.fill", size: 12.5, weight: .semibold, color: blue) {
            check.draw(in: NSRect(x: startX, y: ((labelAreaHeight - 14) / 2).rounded(), width: 14, height: 14))
        }
        (title as NSString).draw(
            at: NSPoint(x: startX + iconSpace, y: textY),
            withAttributes: attrs
        )
    }
}
