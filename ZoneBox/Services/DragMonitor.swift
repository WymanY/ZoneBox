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
    private var capturedRef: WindowRef?

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
        capturedRef = nil
    }

    private func handle(_ event: NSEvent) {
        guard !runtime.isEditorOpen else { return }
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
        guard !runtime.isEditorOpen else { return }
        guard runtime.trust.isTrusted() else { return }
        Log.snap.debug("Pointer hold began at x=\(mouse.locationAppKit.x, privacy: .public) y=\(mouse.locationAppKit.y, privacy: .public)")
        leftButtonHeld = true
        bufferedDrags.removeAll()
        dragSessionReady = false
        upSent = false
        lastSample = mouse.locationAppKit
        holdGeneration += 1
        capturedRef = nil
        runtime.pendingWindow = nil
        runtime.pendingIdentity = nil
        runtime.pendingFrame = nil
        runtime.pendingStartedOnMoveChrome = false

        // CGWindowList is synchronous. Waiting on AX here used to stall the
        // next Shift-drag behind the previous snap's setFrame retries.
        let snapshot = snapshotWindow(at: mouse.locationAppKit)
        capturedRef = snapshot?.ref
        runtime.pendingIdentity = snapshot?.identity
        runtime.pendingFrame = snapshot?.frame
        runtime.pendingStartedOnMoveChrome = snapshot?.startedOnMoveChrome ?? false
        runtime.engine.handleMouse(mouse)
        dragSessionReady = true
        resolveCapturedWindow(generation: holdGeneration)
    }

    private func ensureHold(at location: CGPoint, modifiers: SnapModifiers) {
        guard !leftButtonHeld else { return }
        beginHold(SnapMouseEvent(kind: .leftDown, locationAppKit: location, modifiers: modifiers))
    }

    private func ingestDrag(at location: CGPoint, modifiers: SnapModifiers) {
        if let last = lastSample, RectMath.chebyshev(location, last) < 1 { return }
        lastSample = location
        let mouse = SnapMouseEvent(kind: .leftDragged, locationAppKit: location, modifiers: modifiers)
        refreshCapturedFrame()
        if !dragSessionReady {
            bufferedDrags.append(mouse)
            if bufferedDrags.count > 64 {
                bufferedDrags.removeFirst(bufferedDrags.count - 64)
            }
            return
        }
        runtime.engine.handleMouse(mouse)
    }

    private func finishHold(_ mouse: SnapMouseEvent) {
        guard leftButtonHeld, !upSent else { return }
        Log.snap.debug("Pointer hold ended ready=\(self.dragSessionReady, privacy: .public) captured=\(self.runtime.pendingWindow != nil, privacy: .public)")
        leftButtonHeld = false
        upSent = true
        holdGeneration += 1
        bufferedDrags.removeAll()
        dragSessionReady = false
        runtime.engine.handleMouse(mouse)
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
        guard !runtime.isEditorOpen else { return }
        guard runtime.trust.isTrusted() else { return }
        ensureHold(at: location, modifiers: modifiers)
        ingestDrag(at: location, modifiers: modifiers)
    }

    private func snapshotWindow(at location: CGPoint) -> (
        ref: WindowRef,
        identity: WindowIdentity,
        frame: CGRect,
        startedOnMoveChrome: Bool
    )? {
        let flip = runtime.displays.primaryFlipHeight
        let axPoint = CoordinateConverter.axPoint(fromAppKit: location, primaryFlipHeight: flip)
        let ourPID = ProcessInfo.processInfo.processIdentifier
        guard let ref = query.topmostWindow(atAXPoint: axPoint, excludingPID: ourPID),
              runtime.ax.isSnappable(ref)
        else {
            Log.snap.debug("No snappable window captured for pointer hold")
            return nil
        }
        let identity = WindowIdentity(pid: ref.pid, windowNumber: ref.windowNumber, bundleID: ref.bundleID)
        let startedOnMoveChrome = WindowMoveChrome.contains(
            axPoint: axPoint,
            windowFrameAX: ref.boundsAX,
            hitRole: nil,
            hitSubrole: nil,
            ancestorRoles: []
        )
        Log.snap.debug(
            "Window capture pid=\(ref.pid, privacy: .public) id=\(ref.windowNumber, privacy: .public) moveChrome=\(startedOnMoveChrome, privacy: .public)"
        )
        return (ref, identity, ref.boundsAX, startedOnMoveChrome)
    }

    /// AX resolve is only needed to apply a snap. The overlay must arm from the
    /// CG snapshot even if the previous drop is still writing a frame.
    private func resolveCapturedWindow(generation: Int) {
        guard let ref = capturedRef else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let window = await self.runtime.ax.resolveAsync(ref: ref)
            guard self.leftButtonHeld, self.holdGeneration == generation else { return }
            self.runtime.pendingWindow = window
        }
    }

    private func refreshCapturedFrame() {
        guard let identity = runtime.pendingIdentity else { return }
        if let ref = query.windows(pid: identity.pid).first(where: { $0.windowNumber == identity.windowNumber }) {
            runtime.pendingFrame = ref.boundsAX
            capturedRef = ref
        }
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
