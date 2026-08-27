import AppKit
import ZoneBoxCore

@MainActor
final class OverlayController {
    private var panels: [UUID: OverlayPanel] = [:]
    private var views: [UUID: ZoneOverlayView] = [:]
    private var keySink: NSWindow?
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
        hideAll()
        guard let panel = panels[displayID], let view = views[displayID] else { return }
        view.zones = zones
        view.showNumbers = forceNumbers || settings.showZoneNumbers
        view.inactiveOpacity = settings.inactiveFillOpacity
        view.activeOpacity = settings.activeFillOpacity
        view.primaryFlipHeight = primaryFlipHeight
        applyHighlight(view, highlight)
        view.needsDisplay = true
        panel.orderFrontRegardless()
        if captureKeys {
            grabKeys()
        }
    }

    func highlight(_ target: SnapTarget) {
        for view in views.values {
            applyHighlight(view, target)
            view.needsDisplay = true
        }
    }

    private func applyHighlight(_ view: ZoneOverlayView, _ target: SnapTarget) {
        switch target {
        case .none:
            view.highlightID = nil
            view.highlightFrameAX = nil
        case .zone(let zone):
            view.highlightID = zone.zoneID
            view.highlightFrameAX = nil
        case .span(let frameAX, _):
            view.highlightID = nil
            view.highlightFrameAX = frameAX
        }
    }

    func hideAll() {
        for panel in panels.values {
            panel.orderOut(nil)
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
        keySink?.makeKeyAndOrderFront(nil)
    }

    private func releaseKeys() {
        keySink?.orderOut(nil)
    }
}

private final class OverlayKeySinkWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
