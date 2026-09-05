import AppKit
import ZoneBoxCore

@MainActor
final class PinHoverMonitor {
    unowned var runtime: PinHoverRuntimeHosting!

    private let query = CGWindowQuery()
    private let panel = PinButtonPanel(size: 24)
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var reconcileTimer: Timer?
    private var dwellTimer: Timer?
    private var dismissTimer: Timer?
    private var candidate: WindowRef?
    private var lastHitTestAt: TimeInterval = 0
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        panel.onClick = { [weak self] in self?.toggleCandidate() }
        installObservers()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reconcileTimer = timer
        reconcile()
    }

    func stop() {
        running = false
        removeEventMonitors()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        reconcileTimer?.invalidate()
        reconcileTimer = nil
        hideImmediately()
        panel.close()
    }

    func settingsChanged() {
        reconcile()
    }

    func refreshAppearance() {
        guard panel.isVisible else { return }
        configurePanel()
    }

    func consumesPoint(_ pointAppKit: CGPoint) -> Bool {
        (panel.isVisible && panel.frame.insetBy(dx: -8, dy: -8).contains(pointAppKit))
            || runtime.pins.consumesPoint(pointAppKit)
    }

    /// Unpinning usually leaves the pointer sitting right where the pin button
    /// belongs, so offer it again straight away rather than making the user
    /// leave the window and dwell a second time.
    func pinDidRemove(_ identity: WindowIdentity) {
        guard running, !monitors.isEmpty else { return }
        guard NSEvent.pressedMouseButtons == 0,
              runtime.settings.hoverPinEnabled,
              runtime.isTrusted(),
              runtime.allows(.presentPinHover)
        else { return }

        let axPoint = CoordinateConverter.axPoint(
            fromAppKit: NSEvent.mouseLocation,
            primaryFlipHeight: runtime.primaryFlipHeight
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let ref = query.topmostWindow(atAXPoint: axPoint, excludingPID: ownPID),
              ref.identity == identity,
              !runtime.pins.isPinned(ref),
              runtime.ax.isSnappable(ref),
              PinBadgeSlot.hoverButtonRect(windowFrameAX: ref.boundsAX) != nil,
              hoverArmRegion(for: ref).contains(axPoint)
        else { return }

        cancelDismiss()
        dwellTimer?.invalidate()
        dwellTimer = nil
        candidate = ref
        configurePanel()
        placePanel(for: ref)
    }

    func hideImmediately() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        candidate = nil
        panel.orderOut(nil)
    }

    private func reconcile() {
        guard running else { return }
        let eligible = runtime.settings.hoverPinEnabled && runtime.isTrusted()
        if eligible, monitors.isEmpty {
            installEventMonitors()
        } else if !eligible, !monitors.isEmpty {
            removeEventMonitors()
            hideImmediately()
        }
    }

    private func installEventMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func removeEventMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func installObservers() {
        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.hideImmediately()
                    self?.runtime.pins.hideForEnvironmentChange()
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.hideImmediately()
                    self?.runtime.pins.hideForEnvironmentChange()
                }
            }
        )
    }

    private func handle(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        runtime.pins.updateBadgeHover(at: point)

        switch event.type {
        case .leftMouseDown:
            if !consumesPoint(point) { hideImmediately() }
        case .leftMouseDragged:
            hideImmediately()
        case .mouseMoved:
            handleMouseMoved(at: point)
        default:
            break
        }
    }

    private func handleMouseMoved(at pointAppKit: CGPoint) {
        guard NSEvent.pressedMouseButtons == 0,
              runtime.settings.hoverPinEnabled,
              runtime.isTrusted(),
              runtime.allows(.presentPinHover)
        else {
            hideImmediately()
            return
        }

        if containsCurrentUnion(pointAppKit) {
            cancelDismiss()
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHitTestAt >= 0.05 else { return }
        lastHitTestAt = now

        let axPoint = CoordinateConverter.axPoint(
            fromAppKit: pointAppKit,
            primaryFlipHeight: runtime.primaryFlipHeight
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let ref = query.topmostWindow(atAXPoint: axPoint, excludingPID: ownPID),
              runtime.ax.isSnappable(ref),
              PinBadgeSlot.hoverButtonRect(windowFrameAX: ref.boundsAX) != nil,
              hoverArmRegion(for: ref).contains(axPoint)
        else {
            if runtime.pins.hasPins, runtime.pins.consumesPoint(pointAppKit) {
                cancelDismiss()
            } else {
                scheduleDismiss()
            }
            return
        }

        if runtime.pins.isPinned(ref) {
            candidate = ref
            dwellTimer?.invalidate()
            dwellTimer = nil
            panel.orderOut(nil)
            return
        }

        if candidate?.identity == ref.identity {
            candidate = ref
            cancelDismiss()
            if panel.isVisible {
                placePanel(for: ref)
            } else if dwellTimer == nil {
                // The candidate survives while its window is pinned, so without
                // this the button could never come back after an unpin until
                // the pointer left the window entirely.
                startDwell(for: ref.identity)
            }
            return
        }

        panel.orderOut(nil)
        dismissTimer?.invalidate()
        dismissTimer = nil
        dwellTimer?.invalidate()
        candidate = ref
        startDwell(for: ref.identity)
    }

    private func startDwell(for identity: WindowIdentity) {
        let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.dwellElapsed(identity: identity) }
        }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    private func dwellElapsed(identity: WindowIdentity) async {
        dwellTimer = nil
        guard let ref = candidate,
              ref.identity == identity,
              NSEvent.pressedMouseButtons == 0,
              !runtime.pins.isPinned(identity),
              containsCurrentUnion(NSEvent.mouseLocation)
        else { return }
        guard await runtime.ax.resolveAsync(ref: ref) != nil,
              candidate?.identity == identity,
              containsCurrentUnion(NSEvent.mouseLocation)
        else { return }
        configurePanel()
        placePanel(for: ref)
        Log.pin.debug("Hover button shown pid=\(identity.pid, privacy: .public) window=\(identity.windowNumber, privacy: .public)")
    }

    private func configurePanel() {
        panel.configure(state: .pin, toolTip: L10n.text(.pinOnTop))
    }

    private func placePanel(for ref: WindowRef) {
        guard let rectAX = PinBadgeSlot.hoverButtonRect(windowFrameAX: ref.boundsAX) else {
            hideImmediately()
            return
        }
        let rectAppKit = PinPanelPlacement.appKitRect(
            fromAX: rectAX,
            windowFrameAX: ref.boundsAX,
            primaryFlipHeight: runtime.primaryFlipHeight,
            clampToVisibleScreen: true
        )
        panel.show(frame: rectAppKit)
    }

    private func toggleCandidate() {
        guard let ref = candidate else { return }
        runtime.pins.toggle(ref: ref)
        hideImmediately()
    }

    private func containsCurrentUnion(_ pointAppKit: CGPoint) -> Bool {
        if panel.isVisible, panel.frame.insetBy(dx: -8, dy: -8).contains(pointAppKit) {
            return true
        }
        guard let ref = candidate else { return false }
        let axPoint = CoordinateConverter.axPoint(
            fromAppKit: pointAppKit,
            primaryFlipHeight: runtime.primaryFlipHeight
        )
        return WindowMoveChrome.titleBarBand(ref.boundsAX)
            .insetBy(dx: -8, dy: -8)
            .contains(axPoint)
    }

    private func hoverArmRegion(for ref: WindowRef) -> CGRect {
        let band = WindowMoveChrome.titleBarBand(ref.boundsAX)
        guard let button = PinBadgeSlot.hoverButtonRect(windowFrameAX: ref.boundsAX) else {
            return band
        }
        return band.union(button).insetBy(dx: -8, dy: -8)
    }

    private func scheduleDismiss() {
        guard candidate != nil || panel.isVisible else { return }
        guard dismissTimer == nil else { return }
        dwellTimer?.invalidate()
        dwellTimer = nil
        let timer = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideImmediately() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    private func cancelDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
}
