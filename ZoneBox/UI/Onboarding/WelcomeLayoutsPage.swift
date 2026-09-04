import AppKit
import ZoneBoxCore

@MainActor
final class WelcomeLayoutsPage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let displayID: () -> DisplayIdentity.ID?
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let footnote = NSTextField(labelWithString: "")
    private let currentLabel = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []
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
        for (index, button) in buttons.enumerated() {
            let preset = LayoutTemplates.editorPresets()[index]
            button.title = L10n.layoutDisplayName(preset.name)
            button.setAccessibilityLabel(L10n.layoutDisplayName(preset.name))
        }
        updateCurrentLabel()
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.preferredMaxLayoutWidth = 680
        footnote.font = .systemFont(ofSize: 12)
        footnote.textColor = .tertiaryLabelColor
        currentLabel.font = .systemFont(ofSize: 12, weight: .medium)
        currentLabel.textColor = .secondaryLabelColor

        let presets = LayoutTemplates.editorPresets()
        let grid = NSGridView()
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        for row in 0..<2 {
            var cells: [NSView] = []
            for column in 0..<3 {
                let index = row * 3 + column
                cells.append(makeCell(preset: presets[index], index: index))
            }
            grid.addRow(with: cells)
        }

        let stack = NSStackView(views: [titleLabel, bodyLabel, grid, currentLabel, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func makeCell(preset: Layout, index: Int) -> NSView {
        let image = NSImageView()
        image.image = LayoutThumbnailRenderer.image(
            for: preset,
            size: NSSize(width: 148, height: 92),
            fill: .controlAccentColor,
            stroke: .white,
            gutterPoints: CGFloat(runtime.settings.gutterPoints),
            showNumbers: true
        )
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: L10n.layoutDisplayName(preset.name), target: self, action: #selector(selectPreset(_:)))
        button.tag = index
        button.bezelStyle = .recessed
        button.setButtonType(.toggle)
        button.setAccessibilityLabel(L10n.layoutDisplayName(preset.name))
        buttons.append(button)

        let stack = NSStackView(views: [image, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 148),
            image.heightAnchor.constraint(equalToConstant: 92),
        ])
        return stack
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
            syncButtons()
            updateCurrentLabel()
            return
        }
        selectedIndex = LayoutTemplates.matchingEditorPresetIndex(for: assigned, workAreaAX: workAreaAX(for: area))
        syncButtons()
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

    private func syncButtons() {
        for (index, button) in buttons.enumerated() {
            button.state = index == selectedIndex ? .on : .off
        }
    }

    @objc private func selectPreset(_ sender: NSButton) {
        let presets = LayoutTemplates.editorPresets()
        guard sender.tag >= 0, sender.tag < presets.count, let area = targetArea() else { return }
        let preset = presets[sender.tag]
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
        selectedIndex = sender.tag
        syncButtons()
        updateCurrentLabel()
    }
}
