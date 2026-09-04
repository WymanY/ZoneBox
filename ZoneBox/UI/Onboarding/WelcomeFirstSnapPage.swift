import AppKit
import ZoneBoxCore

@MainActor
final class WelcomeFirstSnapPage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let footnote = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let showZones = NSButton()
    private let goAccess = NSButton()
    private let cards = NSStackView()

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
    }

    func willDisappear() {}

    func refresh(state: OnboardingFlowState) {
        applyLanguage()
        rebuildCards()
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        goAccess.isHidden = true
        if !state.trusted {
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemOrange
            statusLabel.stringValue = L10n.text(.welcomeSnapNeedsAccess)
            goAccess.isHidden = false
        } else if state.didSnap {
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            statusLabel.stringValue = L10n.welcomeSnapDone(runtime.settings.unsnapHotkey.displayCaps.joined())
        } else {
            statusIcon.image = nil
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
        footnote.stringValue = notes.joined(separator: " ")
        showZones.title = L10n.text(.welcomeSnapShowZones)
        goAccess.title = L10n.text(.welcomeSnapGoToAccess)
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.preferredMaxLayoutWidth = 680
        footnote.font = .systemFont(ofSize: 12)
        footnote.textColor = .tertiaryLabelColor
        footnote.preferredMaxLayoutWidth = 680
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        spinner.style = .spinning
        spinner.controlSize = .small
        cards.orientation = .horizontal
        cards.spacing = 12
        cards.alignment = .top
        showZones.bezelStyle = .rounded
        showZones.target = self
        showZones.action = #selector(tapShowZones)
        goAccess.bezelStyle = .rounded
        goAccess.target = self
        goAccess.action = #selector(tapAccess)
        let status = NSStackView(views: [spinner, statusIcon, statusLabel, goAccess])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 8
        let stack = NSStackView(views: [titleLabel, bodyLabel, cards, footnote, showZones, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func rebuildCards() {
        cards.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if runtime.settings.snapOnShiftDrag {
            cards.addArrangedSubview(card("hand.draw", L10n.text(.welcomeSnapShiftDrag)))
        }
        if runtime.settings.snapOnRightClickDrag {
            cards.addArrangedSubview(card("computermouse.fill", L10n.text(.welcomeSnapRightClick)))
        }
        if runtime.settings.snapZoneHotkeysEnabled {
            let chord = KeyChord(keyCode: AppSettings.zoneKeyCodes[0], carbonModifiers: runtime.settings.zoneHotkeyModifiers)
            cards.addArrangedSubview(card("keyboard", L10n.welcomeSnapKeyboard(chord.displayCaps.joined())))
        }
    }

    private func card(_ symbol: String, _ text: String) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        let body = NSTextField(wrappingLabelWithString: text)
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 200
        let stack = NSStackView(views: [icon, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            box.widthAnchor.constraint(equalToConstant: 220),
        ])
        return box
    }

    @objc private func tapShowZones() {
        if let id = runtime.welcomeDisplayID() {
            runtime.previewZones(on: id)
        } else {
            runtime.previewZones()
        }
    }

    @objc private func tapAccess() {
        if runtime.welcome?.jumpToAccessibilityPage() == true {
            return
        }
        runtime.openAccessibility()
    }
}
