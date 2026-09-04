import AppKit
import ZoneBoxCore

@MainActor
final class AccessibilityGuideWindowController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: NSWindow?
    private var content: AccessibilityGuideView?
    private let model: AccessibilityGuideModel
    private var didLeaveSession = false

    init(runtime: AppRuntime) {
        self.runtime = runtime
        self.model = AccessibilityGuideModel(runtime: runtime)
        super.init()
        model.autoDismissOnGrant = true
        model.onPhaseChange = { [weak self] phase in
            self?.content?.apply(phase)
        }
        model.onTrusted = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self?.close()
            }
        }
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
        model.start()
    }

    var isKey: Bool { window?.isKeyWindow == true }

    func close() {
        model.stop()
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
        model.stop()
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

        let view = AccessibilityGuideView(showsHeader: true)
        view.onOpenSettings = { [weak self] in self?.model.openSettings() }
        view.onConfirmEnabled = { [weak self] in self?.model.userSaysEnabled() }
        view.onRelaunch = { [weak self] in self?.model.relaunch() }
        view.onContinue = { [weak self] in self?.close() }
        window.contentView = view
        content = view
        return window
    }
}
