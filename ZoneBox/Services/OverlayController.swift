import AppKit
import ZoneBoxCore

@MainActor
final class OverlayController {
    private var panels: [UUID: OverlayPanel] = [:]
    private var views: [UUID: ZoneOverlayView] = [:]
    private var keySink: NSWindow?
    private var visibleDisplayID: UUID?
    var settings: AppSettings = .default
    var primaryFlipHeight: CGFloat = 0

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

    func show(
        displayID: UUID,
        zones: [ResolvedZone],
        highlight: SnapTarget,
        forceNumbers: Bool = false,
        captureKeys: Bool = false
    ) {
        guard let panel = panels[displayID], let view = views[displayID] else { return }
        let isAlreadyVisible = visibleDisplayID == displayID && panel.isVisible
        let showNumbers = forceNumbers || settings.showZoneNumbers
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
        if applyHighlight(view, highlight) {
            needsDisplay = true
        }

        let previousDisplayID = visibleDisplayID
        if !isAlreadyVisible {
            if let previousDisplayID, previousDisplayID != displayID {
                panels[previousDisplayID]?.orderOut(nil)
            }
            visibleDisplayID = displayID
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            needsDisplay = true
        }
        if needsDisplay {
            view.needsDisplay = true
        }
        if captureKeys {
            grabKeys()
        } else {
            releaseKeys()
        }
    }

    func highlight(_ target: SnapTarget) {
        guard let visibleDisplayID, let view = views[visibleDisplayID] else { return }
        guard applyHighlight(view, target) else { return }
        view.needsDisplay = true
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

    func hideAll() {
        if let visibleDisplayID {
            panels[visibleDisplayID]?.orderOut(nil)
            self.visibleDisplayID = nil
        } else {
            for panel in panels.values where panel.isVisible {
                panel.orderOut(nil)
            }
        }
        releaseKeys()
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
