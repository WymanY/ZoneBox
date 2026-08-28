import AppKit
import ZoneBoxCore

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: NSWindow?
    private var content: OnboardingView?
    private var poll: Timer?
    private var openedSettingsAt: Date?
    private var didLeaveSession = false

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
    }

    func applyLanguage() {
        window?.title = L10n.text(.onboardingWindowTitle)
        content?.applyLanguage()
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        didLeaveSession = false
        runtime.uiSession.enterRegular()
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        content?.apply(initialPhase())
        startPolling()
    }

    func close() {
        stopPolling()
        let win = window
        window = nil
        content = nil
        win?.delegate = nil
        win?.close()
        leaveSessionIfNeeded()
        runtime.accessibilityGuideClosed()
    }

    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }
        stopPolling()
        window = nil
        content = nil
        leaveSessionIfNeeded()
        runtime.accessibilityGuideClosed()
    }

    private func leaveSessionIfNeeded() {
        guard !didLeaveSession else { return }
        didLeaveSession = true
        runtime.uiSession.leaveRegular()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.onboardingWindowTitle)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.isMovableByWindowBackground = true

        let view = OnboardingView(frame: .zero)
        view.onOpenSettings = { [weak self] in self?.openSettings() }
        view.onConfirmEnabled = { [weak self] in self?.userSaysEnabled() }
        view.onRelaunch = { [weak self] in self?.runtime.trust.relaunchApp() }
        view.onContinue = { [weak self] in self?.dismissOrRelaunch() }
        window.contentView = view
        content = view
        return window
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(pollTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
        tick()
    }

    @objc private func pollTimerFired(_ timer: Timer) {
        tick()
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    private func initialPhase() -> OnboardingView.Phase {
        runtime.trust.isTrusted() ? .granted : .needsPermission
    }

    private func tick() {
        runtime.refreshTrustChrome()
        guard let content else { return }
        if runtime.trust.isTrusted() {
            content.apply(.granted)
            stopPolling()
            runtime.accessibilityGranted()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.close()
            }
            return
        }
        if let openedSettingsAt, Date().timeIntervalSince(openedSettingsAt) > 14 {
            content.apply(.needsRelaunch)
        }
    }

    private func openSettings() {
        openedSettingsAt = Date()
        _ = runtime.trust.openAccessibilitySettings()
        content?.apply(.waiting)
    }

    private func userSaysEnabled() {
        if runtime.trust.isTrusted() {
            content?.apply(.granted)
            runtime.accessibilityGranted()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.close()
            }
        } else {
            content?.apply(.needsRelaunch)
        }
    }

    private func dismissOrRelaunch() {
        if runtime.trust.isTrusted() {
            close()
        } else {
            close()
        }
    }
}
