import AppKit
import ZoneBoxCore

@MainActor
final class DragMonitor {
    unowned var runtime: AppRuntime!
    private var monitors: [Any] = []
    private let query = CGWindowQuery()

    func start() {
        stop()
        let kinds: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .flagsChanged,
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds) { [weak self] event in
            self?.handle(event)
            return event
        } {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        guard !runtime.isEditorOpen, runtime.settings.snapEnabled else { return }
        guard runtime.trust.isTrusted() else { return }

        let kind: SnapMouseEvent.Kind?
        switch event.type {
        case .leftMouseDown: kind = .leftDown
        case .leftMouseDragged: kind = .leftDragged
        case .leftMouseUp: kind = .leftUp
        case .rightMouseDown: kind = .rightDown
        case .flagsChanged: kind = .flagsChanged
        default: kind = nil
        }
        guard let kind else { return }

        let location = NSEvent.mouseLocation
        let mouse = SnapMouseEvent(kind: kind, locationAppKit: location, modifiers: Self.modifiers(event))
        if kind == .leftDown {
            Task { @MainActor in
                await captureWindow(at: location)
                runtime.engine.handleMouse(mouse)
            }
            return
        }
        if kind == .leftDragged || kind == .leftUp, let window = runtime.pendingWindow {
            Task { @MainActor in
                runtime.pendingFrame = await runtime.ax.frame(of: window)
                runtime.engine.handleMouse(mouse)
            }
            return
        }
        runtime.engine.handleMouse(mouse)
    }

    private func captureWindow(at location: CGPoint) async {
        let flip = runtime.displays.primaryFlipHeight
        let axPoint = CoordinateConverter.axPoint(fromAppKit: location, primaryFlipHeight: flip)
        let ourPID = ProcessInfo.processInfo.processIdentifier
        guard let ref = query.topmostWindow(atAXPoint: axPoint, excludingPID: ourPID),
              runtime.ax.isSnappable(ref)
        else {
            runtime.pendingWindow = nil
            runtime.pendingFrame = nil
            return
        }
        runtime.pendingWindow = await runtime.ax.resolveAsync(ref: ref)
        runtime.pendingFrame = ref.boundsAX
    }

    private static func modifiers(_ event: NSEvent) -> SnapModifiers {
        var set: SnapModifiers = []
        if event.modifierFlags.contains(.shift) { set.insert(.shift) }
        if event.modifierFlags.contains(.control) { set.insert(.control) }
        if event.modifierFlags.contains(.option) { set.insert(.option) }
        if event.modifierFlags.contains(.command) { set.insert(.command) }
        return set
    }
}
