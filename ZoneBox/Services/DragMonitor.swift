import AppKit
import ZoneBoxCore

@MainActor
final class DragMonitor {
    unowned var runtime: AppRuntime!
    private var monitors: [Any] = []
    private let query = CGWindowQuery()
    private var bufferedDrags: [SnapMouseEvent] = []
    private var dragSessionReady = false
    private var leftButtonHeld = false
    private var upSent = false
    private var holdGeneration = 0
    private var sampleTimer: Timer?
    private var lastSample: CGPoint?
    private var frameRefreshTask: Task<Void, Never>?
    private var frameRefreshRequested = false

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
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: kinds,
            handler: { [weak self] event in
                self?.handle(event)
                return event
            }
        ) {
            monitors.append(local)
        }
        startSampling()
    }

    func stop() {
        stopSampling()
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        bufferedDrags.removeAll()
        dragSessionReady = false
        leftButtonHeld = false
        upSent = false
        holdGeneration += 1
        lastSample = nil
        frameRefreshTask?.cancel()
        frameRefreshTask = nil
        frameRefreshRequested = false
    }

    private func handle(_ event: NSEvent) {
        guard !runtime.isEditorOpen, runtime.settings.snapEnabled else { return }
        guard runtime.trust.isTrusted() else { return }

        if event.type == .mouseMoved {
            guard (NSEvent.pressedMouseButtons & 1) != 0 else { return }
            let location = NSEvent.mouseLocation
            let modifiers = Self.modifiers(flags: event.modifierFlags)
            ensureHold(at: location, modifiers: modifiers)
            ingestDrag(at: location, modifiers: modifiers)
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
            ensureHold(at: location, modifiers: mouse.modifiers)
            ingestDrag(at: location, modifiers: mouse.modifiers)
        case .leftUp:
            finishHold(mouse)
        default:
            runtime.engine.handleMouse(mouse)
        }
    }

    private func beginHold(_ mouse: SnapMouseEvent) {
        guard !leftButtonHeld else { return }
        guard !runtime.isEditorOpen, runtime.settings.snapEnabled else { return }
        guard runtime.trust.isTrusted() else { return }
        Log.snap.debug("Pointer hold began at x=\(mouse.locationAppKit.x, privacy: .public) y=\(mouse.locationAppKit.y, privacy: .public)")
        leftButtonHeld = true
        bufferedDrags.removeAll()
        dragSessionReady = false
        upSent = false
        lastSample = mouse.locationAppKit
        holdGeneration += 1
        frameRefreshTask?.cancel()
        frameRefreshTask = nil
        frameRefreshRequested = false
        let generation = holdGeneration
        Task { @MainActor in
            let capture = await captureWindow(at: mouse.locationAppKit)
            guard self.leftButtonHeld, self.holdGeneration == generation else { return }
            runtime.pendingWindow = capture?.window
            runtime.pendingFrame = capture?.frame
            runtime.engine.handleMouse(mouse)
            dragSessionReady = true
            let queued = bufferedDrags
            bufferedDrags.removeAll()
            for queuedEvent in queued {
                runtime.engine.handleMouse(queuedEvent)
            }
        }
    }

    private func ensureHold(at location: CGPoint, modifiers: SnapModifiers) {
        guard !leftButtonHeld else { return }
        beginHold(SnapMouseEvent(kind: .leftDown, locationAppKit: location, modifiers: modifiers))
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
        requestFrameRefresh()
    }

    /// AX reads run on a serial queue. Coalesce pointer samples so a fast drag
    /// never builds a backlog of stale frame requests behind the cursor.
    private func requestFrameRefresh() {
        frameRefreshRequested = true
        guard frameRefreshTask == nil else { return }
        let generation = holdGeneration
        frameRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.frameRefreshRequested,
                  self.leftButtonHeld,
                  self.holdGeneration == generation
            {
                self.frameRefreshRequested = false
                guard let window = self.runtime.pendingWindow else { break }
                let frame = await self.runtime.ax.frame(of: window)
                guard !Task.isCancelled,
                      self.leftButtonHeld,
                      self.holdGeneration == generation
                else { break }
                self.runtime.pendingFrame = frame
            }
            if self.holdGeneration == generation {
                self.frameRefreshTask = nil
            }
        }
    }

    private func finishHold(_ mouse: SnapMouseEvent) {
        guard leftButtonHeld, !upSent else { return }
        Log.snap.debug("Pointer hold ended ready=\(self.dragSessionReady, privacy: .public) captured=\(self.runtime.pendingWindow != nil, privacy: .public)")
        leftButtonHeld = false
        upSent = true
        holdGeneration += 1
        frameRefreshTask?.cancel()
        frameRefreshTask = nil
        frameRefreshRequested = false
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

    /// Foreign title-bar tracking can starve any of the global mouse events.
    /// Poll the physical button edge on the common run loop so a missing down,
    /// drag, or up event cannot prevent (or strand) a snap session.
    private func startSampling() {
        stopSampling()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.samplePointerState()
        }
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    private func stopSampling() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    private func samplePointerState() {
        let location = NSEvent.mouseLocation
        let modifiers = Self.modifiers(flags: NSEvent.modifierFlags)
        guard (NSEvent.pressedMouseButtons & 1) != 0 else {
            guard leftButtonHeld else { return }
            let mouse = SnapMouseEvent(
                kind: .leftUp,
                locationAppKit: location,
                modifiers: modifiers
            )
            finishHold(mouse)
            return
        }
        guard !runtime.isEditorOpen, runtime.settings.snapEnabled else { return }
        guard runtime.trust.isTrusted() else { return }
        ensureHold(at: location, modifiers: modifiers)
        ingestDrag(at: location, modifiers: modifiers)
    }

    private func captureWindow(at location: CGPoint) async -> (window: AXWindow, frame: CGRect)? {
        let flip = runtime.displays.primaryFlipHeight
        let axPoint = CoordinateConverter.axPoint(fromAppKit: location, primaryFlipHeight: flip)
        let ourPID = ProcessInfo.processInfo.processIdentifier
        guard let ref = query.topmostWindow(atAXPoint: axPoint, excludingPID: ourPID),
              runtime.ax.isSnappable(ref)
        else {
            Log.snap.debug("No snappable window captured for pointer hold")
            return nil
        }
        guard let window = await runtime.ax.resolveAsync(ref: ref) else {
            Log.snap.debug("Window capture pid=\(ref.pid, privacy: .public) id=\(ref.windowNumber, privacy: .public) resolved=false")
            return nil
        }
        Log.snap.debug("Window capture pid=\(ref.pid, privacy: .public) id=\(ref.windowNumber, privacy: .public) resolved=true")
        return (window, ref.boundsAX)
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
