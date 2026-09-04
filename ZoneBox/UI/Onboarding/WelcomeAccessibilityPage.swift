import AppKit
import ZoneBoxCore

@MainActor
final class WelcomeAccessibilityPage: NSView, WelcomePage {
    private unowned let runtime: AppRuntime
    private let titleLabel = NSTextField(labelWithString: "")
    private let model: AccessibilityGuideModel
    private let guide: AccessibilityGuideView

    init(runtime: AppRuntime) {
        self.runtime = runtime
        self.model = AccessibilityGuideModel(runtime: runtime)
        self.guide = AccessibilityGuideView(showsHeader: false)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        model.resumePage = .firstSnap
        model.autoDismissOnGrant = false
        model.onPhaseChange = { [weak self] phase in
            self?.guide.apply(phase)
        }
        model.onTrusted = { [weak self] in
            self?.runtime.welcome?.handle(.trustChanged(true))
        }
        guide.onOpenSettings = { [weak self] in self?.model.openSettings() }
        guide.onConfirmEnabled = { [weak self] in self?.model.userSaysEnabled() }
        guide.onRelaunch = { [weak self] in self?.model.relaunch() }
        guide.onContinue = { [weak self] in self?.runtime.welcome?.handle(.next) }
        build()
    }

    required init?(coder: NSCoder) { nil }

    var view: NSView { self }

    func willAppear(state: OnboardingFlowState) {
        applyLanguage()
        model.start()
        refresh(state: state)
    }

    func willDisappear() {
        model.stop()
    }

    func refresh(state: OnboardingFlowState) {
        applyLanguage()
    }

    func applyLanguage() {
        titleLabel.stringValue = L10n.text(.welcomeAccessTitle)
        guide.applyLanguage()
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        guide.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [titleLabel, guide])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            guide.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }
}
