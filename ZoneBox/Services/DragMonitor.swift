import AppKit
import ZoneBoxCore

@MainActor
final class DragMonitor {
    unowned var runtime: AppRuntime!
    private var monitors: [Any] = []
    private let query = CGWindowQuery()
    private var bufferedDrags: [SnapMouseEvent] = []
    private var dragSessionReady = false
    private var upSent = false
    private var sampleTimer: Timer?
    private var lastSample: CGPoint?

    func start() {
        stop()
        let kinds: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .flagsChanged, .mouseMoved,
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
        stopSampling()
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        bufferedDrags.removeAll()
        dragSessionReady = false
    }

    private func handle(_ event: NSEvent) {
        guard !runtime.isEditorOpen, runtime.settings.snapEnabled else { return }
        guard runtime.trust.isTrusted() else { return }

        if event.type == .mouseMoved {
            guard (NSEvent.pressedMouseButtons & 1) != 0 else { return }
            ingestDrag(at: NSEvent.mouseLocation, modifiers: Self.modifiers(flags: event.modifierFlags))
            return
        }

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
        let mouse = SnapMouseEvent(kind: kind, locationAppKit: location, modifiers: Self.modifiers(flags: event.modifierFlags))
        switch kind {
        case .leftDown:
            beginHold(mouse)
        case .leftDragged:
            ingestDrag(at: location, modifiers: mouse.modifiers)
        case .leftUp:
            finishHold(mouse)
        default:
            runtime.engine.handleMouse(mouse)
        }
    }

    private func beginHold(_ mouse: SnapMouseEvent) {
        bufferedDrags.removeAll()
        dragSessionReady = false
        upSent = false
        lastSample = mouse.locationAppKit
        startSampling()
        Task { @MainActor in
            await captureWindow(at: mouse.locationAppKit)
            runtime.engine.handleMouse(mouse)
            dragSessionReady = true
            let queued = bufferedDrags
            bufferedDrags.removeAll()
            for queuedEvent in queued {
                runtime.engine.handleMouse(queuedEvent)
            }
        }
    }

    private func ingestDrag(at location: CGPoint, modifiers: SnapModifiers) {
        if let last = lastSample, RectMath.chebyshev(location, last) < 1 { return }
        lastSample = location
        let mouse = SnapMouseEvent(kind: .leftDragged, locationAppKit: location, modifiers: modifiers)
        if !dragSessionReady {
            bufferedDrags.append(mouse)
            if bufferedDrags.count > 64 {
                bufferedDrags.removeFirst(bufferedDrags.count - 64)
            }
            return
        }
        runtime.engine.handleMouse(mouse)
        let window = runtime.pendingWindow
        Task { @MainActor in
            if let window {
                runtime.pendingFrame = await runtime.ax.frame(of: window)
            }
        }
    }

    private func finishHold(_ mouse: SnapMouseEvent) {
        guard !upSent else { return }
        upSent = true
        stopSampling()
        bufferedDrags.removeAll()
        dragSessionReady = false
        if let window = runtime.pendingWindow {
            Task { @MainActor in
                runtime.pendingFrame = await runtime.ax.frame(of: window)
                runtime.engine.handleMouse(mouse)
            }
        } else {
            runtime.engine.handleMouse(mouse)
        }
    }

    /// Title-bar drags of other apps often starve global `leftMouseDragged`.
    /// Sample the pointer on the common run loop while the button is held.
    private func startSampling() {
        stopSampling()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sampleHeldDrag()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    private func stopSampling() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    private func sampleHeldDrag() {
        guard (NSEvent.pressedMouseButtons & 1) != 0 else {
            let mouse = SnapMouseEvent(
                kind: .leftUp,
                locationAppKit: NSEvent.mouseLocation,
                modifiers: Self.modifiers(flags: NSEvent.modifierFlags)
            )
            finishHold(mouse)
            return
        }
        ingestDrag(at: NSEvent.mouseLocation, modifiers: Self.modifiers(flags: NSEvent.modifierFlags))
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

    private static func modifiers(flags: NSEvent.ModifierFlags) -> SnapModifiers {
        var set: SnapModifiers = []
        if flags.contains(.shift) { set.insert(.shift) }
        if flags.contains(.control) { set.insert(.control) }
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.command) { set.insert(.command) }
        return set
    }
}
