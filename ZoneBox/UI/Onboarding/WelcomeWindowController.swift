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
    private var skipButton: NSButton?
    private var backButton: NSButton?
    private var primaryButton: NSButton?
    private var stepDots: [NSView] = []
    private var stepStack: NSStackView?
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
                context.duration = 0.15
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
        primaryButton?.title = L10n.text(OnboardingNavigation.primaryTitle(state))
        let step = OnboardingNavigation.stepLabel(state)
        stepStack?.setAccessibilityLabel(L10n.welcomeStepOf(step.current, step.total))
        for (index, dot) in stepDots.enumerated() {
            dot.layer?.backgroundColor = (index == state.index
                ? NSColor.controlAccentColor
                : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).cgColor
        }
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

        let root = NSView(frame: .zero)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let host = NSView(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(host)
        pageHost = host

        let nav = makeNavBar()
        root.addSubview(nav)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: root.topAnchor, constant: 36),
            host.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            host.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            host.bottomAnchor.constraint(equalTo: nav.topAnchor, constant: -12),
            nav.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            nav.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            nav.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            nav.heightAnchor.constraint(equalToConstant: 36),
        ])
        return window
    }

    private func makeNavBar() -> NSView {
        let skip = NSButton(title: L10n.text(.welcomeSkip), target: self, action: #selector(tapSkip))
        skip.bezelStyle = .recessed
        skip.setButtonType(.momentaryPushIn)
        skipButton = skip

        let back = NSButton(title: L10n.text(.welcomeBack), target: self, action: #selector(tapBack))
        back.bezelStyle = .rounded
        backButton = back

        let primary = NSButton(title: L10n.text(.welcomeContinue), target: self, action: #selector(tapPrimary))
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"
        if #available(macOS 14.0, *) {
            primary.controlSize = .large
        }
        primaryButton = primary

        let dots = NSStackView()
        dots.orientation = .horizontal
        dots.spacing = 8
        dots.alignment = .centerY
        dots.setAccessibilityElement(true)
        dots.setAccessibilityRole(.group)
        stepDots = state.pages.indices.map { _ in
            let dot = NSView(frame: .zero)
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8),
            ])
            dots.addArrangedSubview(dot)
            return dot
        }
        stepStack = dots

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [skip, spacer, dots, back, primary])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    @objc private func tapSkip() { handle(.skip) }
    @objc private func tapBack() { handle(.back) }
    @objc private func tapPrimary() { handle(.next) }
}
