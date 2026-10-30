import AppKit
import ZoneBoxCore

@MainActor
protocol WelcomePage: AnyObject {
    var view: NSView { get }
    func willAppear(state: OnboardingFlowState)
    func willDisappear()
    func refresh(state: OnboardingFlowState)
    func applyLanguage()
}

@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: NSWindow?
    private var pageHost: NSView?
    private var currentPageView: (any WelcomePage)?
    private var stepBadgeLabel: NSTextField?
    private var skipButton: ConsoleButton?
    private var backButton: ConsoleButton?
    private var primaryButton: ConsoleButton?
    private var stepIndicator: WelcomeStepIndicatorView?
    private var didLeaveSession = false
    private var isClosing = false
    private var didMarkCompleted = false
    private var sessionHeld = false
    private var pages: [OnboardingPage: any WelcomePage] = [:]
    private var state: OnboardingFlowState
    private var screenObserver: NSObjectProtocol?

    init(runtime: AppRuntime, resume: OnboardingPage?) {
        self.runtime = runtime
        let trusted = runtime.trust.isTrusted()
        let pages = OnboardingPolicy.pages(trusted: trusted)
        let index = OnboardingPolicy.initialIndex(resume: resume, pages: pages)
        self.state = OnboardingFlowState(pages: pages, index: index, trusted: trusted)
        super.init()
    }

    var isKey: Bool { window?.isKeyWindow == true }
    var windowNumber: CGWindowID? {
        window.flatMap { OwnWindowFrameMutation.cgWindowID(fromAppKitWindowNumber: $0.windowNumber) }
    }

    func nsWindow(matching number: CGWindowID) -> NSWindow? {
        guard windowNumber == number else { return nil }
        return window
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        isClosing = false
        if didLeaveSession || !sessionHeld {
            didLeaveSession = false
            sessionHeld = true
            runtime.uiSession.enterRegular()
        }
        applyWindowLevel()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        showPage(state.page, animated: false)
        observeScreens()
        runtime.refreshSnappableOwnWindows()
        Log.onboarding.info("Welcome tour shown page=\(self.state.page.rawValue, privacy: .public)")
    }

    func close(markCompleted: Bool = true) {
        guard !isClosing else { return }
        isClosing = true
        if markCompleted {
            markCompletedIfNeeded()
        }
        currentPageView?.willDisappear()
        currentPageView = nil
        removeScreenObserver()
        let win = window
        window = nil
        pageHost = nil
        win?.delegate = nil
        win?.close()
        leaveSessionIfNeeded()
        runtime.welcomeDidClose()
    }

    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }
        handle(.closeRequested)
    }

    func applyLanguage() {
        window?.title = L10n.text(.welcomeWindowTitle)
        skipButton?.title = L10n.text(.welcomeSkip)
        backButton?.title = L10n.text(.welcomeBack)
        refreshNavigation()
        currentPageView?.applyLanguage()
        currentPageView?.refresh(state: state)
    }

    func handle(_ event: OnboardingFlowEvent) {
        let effects = OnboardingFlowReducer.reduce(&state, event)
        for effect in effects {
            apply(effect)
        }
    }

    func jumpToAccessibilityPage() -> Bool {
        guard let index = state.pages.firstIndex(of: .accessibility) else { return false }
        state.index = index
        apply(.showPage(.accessibility))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func jumpToStep(at index: Int) {
        guard index >= 0, index < state.pages.count, index != state.index else { return }
        state.index = index
        apply(.showPage(state.page))
    }

    private func apply(_ effect: OnboardingFlowEffect) {
        switch effect {
        case .showPage(let page):
            showPage(page, animated: true)
        case .refreshCurrentPage:
            currentPageView?.refresh(state: state)
            refreshNavigation()
        case .markCompleted:
            markCompletedIfNeeded()
        case .close:
            close()
        }
    }

    private func showPage(_ page: OnboardingPage, animated: Bool) {
        guard let pageHost else { return }
        let next = pageView(for: page)
        currentPageView?.willDisappear()
        let previous = currentPageView
        currentPageView = next
        let nextView = next.view
        nextView.translatesAutoresizingMaskIntoConstraints = false
        nextView.alphaValue = animated ? 0 : 1
        pageHost.addSubview(nextView)
        NSLayoutConstraint.activate([
            nextView.topAnchor.constraint(equalTo: pageHost.topAnchor),
            nextView.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            nextView.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            nextView.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
        ])
        next.willAppear(state: state)
        next.applyLanguage()
        next.refresh(state: state)
        applyWindowLevel()
        refreshNavigation()
        let previousView = previous?.view
        if animated, let previous {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                previous.view.animator().alphaValue = 0
                nextView.animator().alphaValue = 1
            }, completionHandler: {
                Task { @MainActor in
                    previousView?.removeFromSuperview()
                }
            })
        } else {
            nextView.alphaValue = 1
            previousView?.removeFromSuperview()
        }
    }

    private func pageView(for page: OnboardingPage) -> any WelcomePage {
        if let existing = pages[page] { return existing }
        let created: any WelcomePage
        switch page {
        case .welcome:
            created = WelcomeIntroPage(runtime: runtime)
        case .layouts:
            created = WelcomeLayoutsPage(runtime: runtime) { [weak self] in self?.targetDisplayID() }
        case .accessibility:
            created = WelcomeAccessibilityPage(runtime: runtime)
        case .firstSnap:
            created = WelcomeFirstSnapPage(runtime: runtime)
        case .more:
            created = WelcomeMorePage(runtime: runtime)
        case .finish:
            created = WelcomeFinishPage(runtime: runtime) { [weak self] in
                guard let self else { return }
                let runtime = self.runtime
                self.handle(.finish)
                runtime.openSettings()
            }
        }
        pages[page] = created
        return created
    }

    private func applyWindowLevel() {
        window?.level = state.page == .accessibility ? .floating : .normal
    }

    private func refreshNavigation() {
        skipButton?.isHidden = !OnboardingNavigation.showsSkip(state)
        backButton?.isHidden = !OnboardingNavigation.showsBack(state)
        let titleKey = OnboardingNavigation.primaryTitle(state)
        primaryButton?.title = L10n.text(titleKey)
        if state.isLast {
            primaryButton?.symbolName = "checkmark"
            primaryButton?.trailingSymbolName = nil
        } else {
            primaryButton?.symbolName = nil
            primaryButton?.trailingSymbolName = nil
        }
        let step = OnboardingNavigation.stepLabel(state)
        let stepText = L10n.welcomeStepOf(step.current, step.total)
        stepBadgeLabel?.stringValue = stepText
        stepIndicator?.update(
            currentIndex: state.index,
            pages: state.pages,
            accessibilityLabel: stepText
        )
    }

    func targetDisplayID() -> DisplayIdentity.ID? {
        guard let window else { return nil }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        return runtime.displays.area(containingAppKit: center)?.display.id
            ?? runtime.displays.workAreas.first?.display.id
    }

    private func markCompletedIfNeeded() {
        guard !didMarkCompleted else { return }
        didMarkCompleted = true
        runtime.markOnboardingCompleted()
    }

    private func leaveSessionIfNeeded() {
        guard !didLeaveSession else { return }
        didLeaveSession = true
        sessionHeld = false
        runtime.uiSession.leaveRegular()
    }

    private func observeScreens() {
        removeScreenObserver()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentPageView?.refresh(state: self.state)
            }
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.welcomeWindowTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 760, height: 560)
        window.maxSize = NSSize(width: 760, height: 560)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let root = WelcomeChromeRootView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let topBar = makeTopBar()
        root.addSubview(topBar)

        let host = NSView(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(host)
        pageHost = host

        let nav = makeNavBar()
        root.addSubview(nav)

        let hostWidth = host.widthAnchor.constraint(equalToConstant: 688)
        hostWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 78),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            topBar.heightAnchor.constraint(equalToConstant: 26),

            host.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 6),
            host.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            hostWidth,
            host.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 36),
            host.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -36),
            host.bottomAnchor.constraint(equalTo: nav.topAnchor, constant: -14),

            nav.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            nav.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            nav.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            nav.heightAnchor.constraint(equalToConstant: 62),
        ])
        return window
    }

    private func makeTopBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false

        let pill = WelcomePillBadgeView()
        let stepLabel = NSTextField(labelWithString: "")
        stepLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        stepLabel.textColor = .secondaryLabelColor
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        stepBadgeLabel = stepLabel
        pill.addSubview(stepLabel)

        bar.addSubview(pill)
        NSLayoutConstraint.activate([
            stepLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            stepLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            stepLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 22),
            pill.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            pill.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func makeNavBar() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let skip = ConsoleButton(
            role: .plain,
            title: L10n.text(.welcomeSkip),
            target: self,
            action: #selector(tapSkip)
        )
        skip.fontSize = 13
        skip.fontWeight = .medium
        skip.controlHeight = 32
        skip.horizontalPadding = 12
        skipButton = skip

        let back = ConsoleButton(
            role: .surface,
            title: L10n.text(.welcomeBack),
            symbol: "chevron.left",
            target: self,
            action: #selector(tapBack)
        )
        back.fontSize = 13
        back.fontWeight = .medium
        back.controlHeight = 34
        back.horizontalPadding = 14
        backButton = back

        let primary = ConsoleButton(
            role: .primary,
            title: L10n.text(.welcomeContinue),
            target: self,
            action: #selector(tapPrimary)
        )
        primary.fontSize = 13
        primary.fontWeight = .semibold
        primary.controlHeight = 34
        primary.horizontalPadding = 20
        primary.keyEquivalent = "\r"
        primaryButton = primary

        let indicator = WelcomeStepIndicatorView(count: state.pages.count) { [weak self] index in
            self?.jumpToStep(at: index)
        }
        stepIndicator = indicator

        let rightButtons = NSStackView(views: [back, primary])
        rightButtons.orientation = .horizontal
        rightButtons.alignment = .centerY
        rightButtons.spacing = 10
        rightButtons.detachesHiddenViews = true
        rightButtons.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(skip)
        container.addSubview(indicator)
        container.addSubview(rightButtons)

        NSLayoutConstraint.activate([
            skip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            skip.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            rightButtons.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightButtons.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    @objc private func tapSkip() { handle(.skip) }
    @objc private func tapBack() { handle(.back) }
    @objc private func tapPrimary() { handle(.next) }
}

// MARK: - Window Chrome Views

private final class WelcomeChromeRootView: NSView {
    static let footerHeight: CGFloat = 62

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let base = dark
            ? NSColor(srgbRed: 0.11, green: 0.114, blue: 0.128, alpha: 1)
            : NSColor(srgbRed: 0.962, green: 0.966, blue: 0.976, alpha: 1)
        base.setFill()
        bounds.fill()

        // Subtle ambient top wash
        let blue = ConsoleChrome.brandBlue(dark: dark)
        let glowHeight: CGFloat = min(220, bounds.height * 0.45)
        let glowRect = NSRect(x: 0, y: bounds.height - glowHeight, width: bounds.width, height: glowHeight)
        NSGradient(
            starting: blue.withAlphaComponent(dark ? 0.11 : 0.065),
            ending: blue.withAlphaComponent(0)
        )?.draw(in: glowRect, angle: -90)

        // Footer bar background & separator
        let footerRect = NSRect(x: 0, y: 0, width: bounds.width, height: Self.footerHeight)
        let footerFill = dark
            ? NSColor.black.withAlphaComponent(0.22)
            : NSColor.white.withAlphaComponent(0.72)
        footerFill.setFill()
        footerRect.fill()

        ConsoleChrome.surfaceBorder(dark: dark).setFill()
        NSRect(x: 0, y: Self.footerHeight, width: bounds.width, height: 1).fill()
    }
}

private final class WelcomePillBadgeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.045)).setFill()
        path.fill()
        ConsoleChrome.surfaceBorder(dark: dark).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class WelcomeStepIndicatorView: NSView {
    private var pills: [WelcomeStepPillButton] = []
    private let stack = NSStackView()
    private let onSelect: (Int) -> Void

    init(count: Int, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        stack.orientation = .horizontal
        stack.spacing = 7
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 18),
        ])

        for index in 0..<count {
            let pill = WelcomeStepPillButton(index: index) { [weak self] tapped in
                self?.onSelect(tapped)
            }
            pills.append(pill)
            stack.addArrangedSubview(pill)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(currentIndex: Int, pages: [OnboardingPage], accessibilityLabel: String) {
        setAccessibilityLabel(accessibilityLabel)
        for (index, pill) in pills.enumerated() {
            let state: WelcomeStepPillButton.StepState
            if index == currentIndex {
                state = .current
            } else if index < currentIndex {
                state = .completed
            } else {
                state = .upcoming
            }
            let title: String
            if index < pages.count {
                switch pages[index] {
                case .welcome: title = L10n.text(.welcomeIntroTitle)
                case .layouts: title = L10n.text(.welcomeLayoutsTitle)
                case .accessibility: title = L10n.text(.welcomeAccessTitle)
                case .firstSnap: title = L10n.text(.welcomeSnapTitle)
                case .more: title = L10n.text(.welcomeMoreTitle)
                case .finish: title = L10n.text(.welcomeFinishTitle)
                }
            } else {
                title = ""
            }
            pill.configure(state: state, tooltip: title)
        }
    }
}

private final class WelcomeStepPillButton: ConsoleInteractiveView {
    enum StepState {
        case completed
        case current
        case upcoming
    }

    private let index: Int
    private let onTap: (Int) -> Void
    private var stepState: StepState = .upcoming
    private var widthConstraint: NSLayoutConstraint!

    init(index: Int, onTap: @escaping (Int) -> Void) {
        self.index = index
        self.onTap = onTap
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 8)
        NSLayoutConstraint.activate([
            widthConstraint,
            heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(state: StepState, tooltip: String) {
        self.stepState = state
        self.toolTip = tooltip
        setAccessibilityLabel(tooltip)
        widthConstraint.constant = state == .current ? 24 : 8
        needsDisplay = true
    }

    override func performPrimaryAction() {
        onTap(index)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let blue = ConsoleChrome.brandBlue(dark: dark)
        let color: NSColor
        switch stepState {
        case .current:
            color = blue
        case .completed:
            color = blue.withAlphaComponent(isHovering ? 0.65 : 0.42)
        case .upcoming:
            color = NSColor.secondaryLabelColor.withAlphaComponent(isHovering ? 0.45 : 0.25)
        }
        let pillRect = bounds.insetBy(dx: 0, dy: 0.5)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)
        color.setFill()
        path.fill()
    }
}
