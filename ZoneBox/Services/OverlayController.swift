import AppKit
import ZoneBoxCore

@MainActor
final class OverlayController {
    private var panels: [UUID: OverlayPanel] = [:]
    private var views: [UUID: ZoneOverlayView] = [:]
    private var keySink: NSWindow?
    private var visibleDisplayID: UUID?
    private var visibleZones: [ResolvedZone] = []
    private var visibleHighlight: SnapTarget = .none
    private var visibleCaptureKeys = false
    var settings: AppSettings = .default
    var primaryFlipHeight: CGFloat = 0
    var isVisible: Bool { visibleDisplayID != nil }
    private(set) var isPreviewVisible = false
    private var fadeGeneration = 0

    func rebuild(workAreas: [WorkArea], screens: [NSScreen]) {
        hideAll()
        for panel in panels.values { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        views.removeAll()

        for area in workAreas {
            let screen = screens.first(where: { abs($0.frame.minX - area.frameAppKit.minX) < 1 && abs($0.frame.minY - area.frameAppKit.minY) < 1 && abs($0.frame.width - area.frameAppKit.width) < 1 })
                ?? screens.first
            guard let screen else { continue }
            let panel = OverlayPanel(screen: screen)
            let view = ZoneOverlayView(frame: panel.contentLayoutRect)
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            panels[area.display.id] = panel
            views[area.display.id] = view
        }
    }

    /// `showNumbers` overrides the user setting for this presentation only;
    /// nil follows the setting.
    func show(
        displayID: UUID,
        zones: [ResolvedZone],
        highlight: SnapTarget,
        captureKeys: Bool = false,
        presentation: OverlayPresentation = .empty,
        showNumbers: Bool? = nil
    ) {
        present(
            displayID: displayID,
            zones: zones,
            highlight: highlight,
            captureKeys: captureKeys,
            presentation: presentation,
            isPreview: false,
            showNumbers: showNumbers
        )
    }

    func showPreview(
        displayID: UUID,
        zones: [ResolvedZone],
        presentation: OverlayPresentation
    ) {
        present(
            displayID: displayID,
            zones: zones,
            highlight: .none,
            presentation: presentation,
            isPreview: true
        )
    }

    private func present(
        displayID: UUID,
        zones: [ResolvedZone],
        highlight: SnapTarget,
        captureKeys: Bool = false,
        presentation: OverlayPresentation = .empty,
        isPreview: Bool,
        showNumbers numbersOverride: Bool? = nil,
        cancelsFade: Bool = true
    ) {
        guard let panel = panels[displayID], let view = views[displayID] else { return }
        if cancelsFade { cancelFade() }
        let isAlreadyVisible = visibleDisplayID == displayID && panel.isVisible
        let showNumbers = numbersOverride ?? settings.showZoneNumbers
        var needsDisplay = false
        if view.zones != zones {
            view.zones = zones
            needsDisplay = true
        }
        if view.showNumbers != showNumbers {
            view.showNumbers = showNumbers
            needsDisplay = true
        }
        if view.inactiveOpacity != settings.inactiveFillOpacity {
            view.inactiveOpacity = settings.inactiveFillOpacity
            needsDisplay = true
        }
        if view.activeOpacity != settings.activeFillOpacity {
            view.activeOpacity = settings.activeFillOpacity
            needsDisplay = true
        }
        if view.primaryFlipHeight != primaryFlipHeight {
            view.primaryFlipHeight = primaryFlipHeight
            needsDisplay = true
        }
        if view.presentation != presentation {
            view.presentation = presentation
            needsDisplay = true
        }
        if applyHighlight(view, highlight) {
            needsDisplay = true
        }

        let previousDisplayID = visibleDisplayID
        if !isAlreadyVisible {
            if let previousDisplayID, previousDisplayID != displayID {
                panels[previousDisplayID]?.orderOut(nil)
            }
            visibleDisplayID = displayID
            needsDisplay = true
        }
        let decision = OverlayStackingPolicy.present(
            isPreview: isPreview,
            alreadyVisible: isAlreadyVisible,
            stackingMatches: isAlreadyVisible && isPreviewVisible == isPreview
        )
        panel.applyStacking(decision.kind)
        // Avoid repeated window ordering while the system owns title-bar
        // tracking. Previews still restack to cover the console / welcome.
        if decision.restack {
            panel.orderFrontRegardless()
        }
        if needsDisplay {
            view.needsDisplay = true
            if decision.flushDisplay {
                view.displayIfNeeded()
            }
        }
        if captureKeys {
            grabKeys()
        } else {
            releaseKeys()
        }

        visibleDisplayID = displayID
        visibleZones = zones
        visibleHighlight = highlight
        visibleCaptureKeys = captureKeys
        isPreviewVisible = isPreview
    }

    func highlight(_ target: SnapTarget) {
        guard let visibleDisplayID, let view = views[visibleDisplayID] else { return }
        guard applyHighlight(view, target) else { return }
        view.needsDisplay = true
        visibleHighlight = target
    }

    func refreshVisible(zones: [ResolvedZone]? = nil) {
        guard let visibleDisplayID else { return }
        // A settings refresh is the same presentation, including its lifetime.
        present(
            displayID: visibleDisplayID,
            zones: zones ?? visibleZones,
            highlight: visibleHighlight,
            captureKeys: visibleCaptureKeys,
            presentation: views[visibleDisplayID]?.presentation ?? .empty,
            isPreview: isPreviewVisible,
            cancelsFade: false
        )
    }

    @discardableResult
    private func applyHighlight(_ view: ZoneOverlayView, _ target: SnapTarget) -> Bool {
        let highlightID: UUID?
        let highlightFrameAX: CGRect?
        switch target {
        case .none:
            highlightID = nil
            highlightFrameAX = nil
        case .zone(let zone):
            highlightID = zone.zoneID
            highlightFrameAX = nil
        case .span(let frameAX, _):
            highlightID = nil
            highlightFrameAX = frameAX
        }
        guard view.highlightID != highlightID || view.highlightFrameAX != highlightFrameAX else {
            return false
        }
        view.highlightID = highlightID
        view.highlightFrameAX = highlightFrameAX
        return true
    }

    /// Fades the visible overlay out before hiding it. A new presentation or
    /// `hideAll()` during the fade cancels it.
    func fadeOutAll(duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        guard let visibleDisplayID, let panel = panels[visibleDisplayID], panel.isVisible else {
            hideAll()
            completion?()
            return
        }
        fadeGeneration += 1
        let generation = fadeGeneration
        let finish = { [weak self] in
            guard let self, generation == self.fadeGeneration else { return }
            self.hideAll()
            completion?()
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in finish() }
        })
        // Window animations stall while the display sleeps; never leave the overlay up.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2, execute: finish)
    }

    private func cancelFade() {
        fadeGeneration += 1
        for panel in panels.values where panel.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
        }
    }

    func hideAll() {
        isPreviewVisible = false
        if let visibleDisplayID {
            panels[visibleDisplayID]?.orderOut(nil)
            self.visibleDisplayID = nil
        } else {
            for panel in panels.values where panel.isVisible {
                panel.orderOut(nil)
            }
        }
        visibleZones = []
        visibleHighlight = .none
        visibleCaptureKeys = false
        for view in views.values {
            view.presentation = .empty
        }
        releaseKeys()
        cancelFade()
    }

    func hideSessionOverlay() {
        guard !isPreviewVisible else { return }
        hideAll()
    }

    private func grabKeys() {
        if keySink == nil {
            let window = OverlayKeySinkWindow(
                contentRect: NSRect(x: -64, y: -64, width: 8, height: 8),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 2)
            window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .transient, .fullScreenAuxiliary]
            keySink = window
        }
        if keySink?.isVisible != true {
            keySink?.makeKeyAndOrderFront(nil)
        }
    }

    private func releaseKeys() {
        if keySink?.isVisible == true {
            keySink?.orderOut(nil)
        }
    }
}

private final class OverlayKeySinkWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
