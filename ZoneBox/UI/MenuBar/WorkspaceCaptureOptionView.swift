import AppKit
import ZoneBoxCore

/// A compact save preference shared with the workspace settings page.
@MainActor
final class WorkspaceCaptureOptionView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let help = NSImageView()
    private let toggle = NSSwitch()
    var onChange: ((Bool) -> Void)?

    init(isOn: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)

        help.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        help.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        help.contentTintColor = .tertiaryLabelColor
        help.imageScaling = .scaleProportionallyDown

        toggle.controlSize = .mini
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.setContentHuggingPriority(.required, for: .horizontal)

        for view in [label, help, toggle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            help.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 5),
            help.centerYAnchor.constraint(equalTo: centerYAnchor),
            help.widthAnchor.constraint(equalToConstant: 14),
            help.heightAnchor.constraint(equalToConstant: 14),
            help.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh(isOn: isOn)
    }

    required init?(coder: NSCoder) { nil }

    func refresh(isOn: Bool) {
        let title = L10n.text(.consoleCaptureOccludedWindows)
        let detail = L10n.text(.settingsCaptureFullyOccludedWindowsDetail)
        label.stringValue = title
        label.toolTip = detail
        help.toolTip = detail
        help.setAccessibilityLabel(detail)
        toggle.toolTip = detail
        toggle.setAccessibilityLabel(L10n.text(.settingsCaptureFullyOccludedWindows))
        toggle.setAccessibilityHelp(detail)
        toggle.state = isOn ? .on : .off
    }

    @objc private func toggleChanged() {
        onChange?(toggle.state == .on)
    }
}
