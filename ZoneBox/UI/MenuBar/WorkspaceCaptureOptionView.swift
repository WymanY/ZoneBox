import AppKit
import ZoneBoxCore

/// A compact save preference shared with the workspace settings page.
@MainActor
final class WorkspaceCaptureOptionView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let help = HoverHelpButton()
    private let toggle = NSSwitch()
    var onChange: ((Bool) -> Void)?

    init(isOn: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)

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
            help.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 2),
            help.centerYAnchor.constraint(equalTo: centerYAnchor),
            help.widthAnchor.constraint(equalToConstant: 20),
            help.heightAnchor.constraint(equalToConstant: 20),
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
        help.helpText = detail
        toggle.toolTip = detail
        toggle.setAccessibilityLabel(L10n.text(.settingsCaptureFullyOccludedWindows))
        toggle.setAccessibilityHelp(detail)
        toggle.state = isOn ? .on : .off
    }

    @objc private func toggleChanged() {
        let enabled = toggle.state == .on
        // Defer persistence so the system switch can finish its own animation first.
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(enabled)
        }
    }
}
