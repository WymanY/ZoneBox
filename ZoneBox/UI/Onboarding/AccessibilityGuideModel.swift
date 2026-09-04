import AppKit
import Foundation
import ZoneBoxCore

@MainActor
final class AccessibilityGuideModel {
    private unowned let runtime: AppRuntime
    private var poll: Timer?
    private var openedSettingsAt: Date?
    private var hasReportedGranted = false
    var resumePage: OnboardingPage?
    var autoDismissOnGrant = true
    var onPhaseChange: ((AccessibilityGuideView.Phase) -> Void)?
    var onTrusted: (() -> Void)?

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    func start() {
        hasReportedGranted = false
        openedSettingsAt = nil
        onPhaseChange?(initialPhase())
        startPolling()
    }

    func stop() {
        stopPolling()
    }

    func openSettings() {
        openedSettingsAt = Date()
        _ = runtime.trust.openAccessibilitySettings()
        onPhaseChange?(.waiting)
    }

    func userSaysEnabled() {
        if runtime.trust.isTrusted() {
            onPhaseChange?(.granted)
            reportGrantedIfNeeded()
        } else {
            onPhaseChange?(.needsRelaunch)
        }
    }

    func relaunch() {
        if let resumePage {
            runtime.trust.relaunchApp(arguments: ["--welcome-page", resumePage.rawValue])
        } else {
            runtime.trust.relaunchApp()
        }
    }

    private func initialPhase() -> AccessibilityGuideView.Phase {
        runtime.trust.isTrusted() ? .granted : .needsPermission
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

    private func tick() {
        runtime.refreshTrustChrome()
        if runtime.trust.isTrusted() {
            onPhaseChange?(.granted)
            stopPolling()
            reportGrantedIfNeeded()
            return
        }
        if let openedSettingsAt, Date().timeIntervalSince(openedSettingsAt) > 14 {
            onPhaseChange?(.needsRelaunch)
        }
    }

    private func reportGrantedIfNeeded() {
        guard !hasReportedGranted else { return }
        hasReportedGranted = true
        runtime.accessibilityGranted()
        onTrusted?()
    }
}

