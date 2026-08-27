import AppKit
import ZoneBoxCore

@MainActor
final class OverlayController {
    private var panels: [UUID: OverlayPanel] = [:]
    private var views: [UUID: ZoneOverlayView] = [:]
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

    func show(displayID: UUID, zones: [ResolvedZone], highlight: SnapTarget) {
        hideAll()
        guard let panel = panels[displayID], let view = views[displayID] else { return }
        view.zones = zones
        view.showNumbers = settings.showZoneNumbers
        view.inactiveOpacity = settings.inactiveFillOpacity
        view.activeOpacity = settings.activeFillOpacity
        view.primaryFlipHeight = primaryFlipHeight
        if case .zone(let zone) = highlight {
            view.highlightID = zone.zoneID
        } else {
            view.highlightID = nil
        }
        view.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func highlight(_ target: SnapTarget) {
        for view in views.values {
            if case .zone(let zone) = target {
                view.highlightID = zone.zoneID
            } else {
                view.highlightID = nil
            }
            view.needsDisplay = true
        }
    }

    func hideAll() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }
}
