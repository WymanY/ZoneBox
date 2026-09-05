import AppKit
import CoreGraphics
import ScreenCaptureKit
import ZoneBoxCore

@MainActor
final class PinCenter {
    private struct Record {
        let identity: WindowIdentity
        let session: PinMirrorSession
        var lastKnownFrameAX: CGRect
        let pinnedAt: Date
        var goneSince: Date?
        var lastRaisedAt = Date.distantPast
    }

    private enum Watchdog {
        /// Follow rate while a mirrored window is being moved or resized. The
        /// mirror sits on top of the real window, so anything slower reads as
        /// the two edges tearing apart during a drag. Only the per-window
        /// geometry probe runs this often.
        static let activeInterval: TimeInterval = 1.0 / 60
        static let idleInterval: TimeInterval = 0.1
        /// Enumerating every on-screen window costs ~1.3ms, so it stays at the
        /// idle rate even while following a drag at 60Hz.
        static let fullScanInterval: TimeInterval = 0.1
        /// Stay at the fast rate briefly after the last observed frame change.
        static let motionWindow: TimeInterval = 0.4
        static let reorderInterval: TimeInterval = 0.5
        /// Enumerating every window on every Space costs ~27ms, so this runs as
        /// rarely as the retirement grace period allows.
        static let offScreenScanInterval: TimeInterval = 1.0
        /// A live window can drop out of one CGWindowList sample and come back
        /// in the next, so only retire a pin once the absence sticks.
        static let goneGrace: TimeInterval = 1.5
        /// Keep the real window in front of other layer-0 apps. Faster than
        /// this fights the app that currently has focus; slower lets another
        /// window cover the pin between ticks.
        static let raiseInterval: TimeInterval = 0.35
    }

    private enum StartError: LocalizedError {
        case sourceWindowUnavailable

        var errorDescription: String? {
            switch self {
            case .sourceWindowUnavailable:
                "The selected window is no longer available for capture."
            }
        }
    }

    unowned var runtime: PinRuntimeHosting!
    private var raiseGeneration = 0
    private func pinSessionID(for identity: WindowIdentity) -> UUID {
        UUID(uuidString: String(format: "AAAAAAAA-0000-4000-8000-%012x", Int(identity.windowNumber))) ?? UUID()
    }
    private func nextRaiseGeneration() -> Int {
        raiseGeneration += 1
        return raiseGeneration
    }

    private let query = CGWindowQuery()
    private var records: [Record] = []
    private var pending: Set<WindowIdentity> = []
    private var unpinning: Set<WindowIdentity> = []
    private var badges: [WindowIdentity: PinButtonPanel] = [:]
    private var watchdog: Timer?
    private var watchdogInterval: TimeInterval = Watchdog.idleInterval
    private var lastTickAt = Date.distantPast
    private var showingPermissionGuide = false
    private var lastMotionAt = Date.distantPast
    private var lastReorderAt = Date.distantPast
    private var lastFullScanAt = Date.distantPast
    private var lastOffScreenScanAt = Date.distantPast
    private var lastVisibleOrder: [WindowIdentity] = []
    private var mirrorsSuspended = false

    var count: Int { records.count }
    var hasPins: Bool { !records.isEmpty }

    func start() {
        Log.pin.info("Screen Recording granted=\(ScreenRecordingAccess.isGranted, privacy: .public)")
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        pending.removeAll()
        unpinning.removeAll()
        for record in records { record.session.stop() }
        records.removeAll()
        for panel in badges.values {
            panel.orderOut(nil)
            panel.close()
        }
        badges.removeAll()
        lastVisibleOrder.removeAll()
        mirrorsSuspended = false
    }

    func isPinned(_ identity: WindowIdentity) -> Bool {
        records.contains { $0.identity == identity }
    }

    func isPinned(_ ref: WindowRef) -> Bool {
        isPinned(ref.identity)
    }

    func togglePin(under axPoint: CGPoint) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let ref = query.topmostWindow(atAXPoint: axPoint, excludingPID: ownPID) else { return }
        toggle(ref: ref)
    }

    func toggle(ref: WindowRef) {
        guard runtime.isTrusted(), runtime.ax.isSnappable(ref) else { return }
        let identity = ref.identity
        if isPinned(identity) {
            unpin(identity)
            return
        }
        guard !pending.contains(identity) else { return }

        guard ScreenRecordingAccess.isGranted else {
            showPermissionGuide(for: ref)
            return
        }
        beginPin(ref)
    }

    func unpin(_ identity: WindowIdentity) {
        guard let record = record(for: identity), !unpinning.contains(identity) else { return }
        unpinning.insert(identity)
        badges[identity]?.orderOut(nil)
        let frameAX = record.lastKnownFrameAX

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Raise before tearing the mirror down: dropping the mirror first
            // would expose whatever was covering the real window until the
            // raise lands.
            await self.raiseSourceWindow(identity, frameAX: frameAX)
            NSRunningApplication(processIdentifier: identity.pid)?.activate()
            self.finishUnpin(identity)
        }
        scheduleUnpinTimeout([identity], after: 0.75)
    }

    func unpinAll() {
        let entries = records
            .filter { !unpinning.contains($0.identity) }
            .map { (identity: $0.identity, frameAX: $0.lastKnownFrameAX) }
        guard !entries.isEmpty else { return }
        for entry in entries { unpinning.insert(entry.identity) }
        hideBadges()

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Oldest first so the most recently pinned window ends up frontmost,
            // matching the order the mirrors were stacked in.
            for entry in entries {
                await self.raiseSourceWindow(entry.identity, frameAX: entry.frameAX)
            }
            if let last = entries.last {
                NSRunningApplication(processIdentifier: last.identity.pid)?.activate()
            }
            for entry in entries { self.finishUnpin(entry.identity) }
        }
        scheduleUnpinTimeout(entries.map(\.identity), after: 1.5)
    }

    private func finishUnpin(_ identity: WindowIdentity) {
        guard unpinning.remove(identity) != nil, remove(identity, notify: false) else { return }
        notifyCountChanged()
        runtime.pinHover.pinDidRemove(identity)
        Log.pin.info(
            "Unpinned pid=\(identity.pid, privacy: .public) window=\(identity.windowNumber, privacy: .public) count=\(self.count, privacy: .public)"
        )
    }

    /// A wedged application can stall the raise, and the mirror must not be
    /// left floating over the desktop if that happens.
    private func scheduleUnpinTimeout(_ identities: [WindowIdentity], after seconds: TimeInterval) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self else { return }
            for identity in identities { self.finishUnpin(identity) }
        }
    }

    /// Hands the real window back the front-most spot it had while mirrored, so
    /// unpinning only removes the "always on top" behaviour rather than dropping
    /// the window back down the stack.
    private func raiseSourceWindow(_ identity: WindowIdentity, frameAX: CGRect) async {
        guard runtime.isTrusted() else { return }
        let ref = WindowRef(
            pid: identity.pid,
            windowNumber: identity.windowNumber,
            boundsAX: frameAX,
            bundleID: identity.bundleID,
            layer: 0
        )
        guard let window = await runtime.ax.resolveAsync(ref: ref) else { return }
        _ = await runtime.raise(window, sessionID: pinSessionID(for: identity), generation: nextRaiseGeneration())
    }

    func drop(pid: pid_t) {
        let identities = records.filter { $0.identity.pid == pid }.map(\.identity)
        guard !identities.isEmpty else { return }
        for identity in identities { _ = remove(identity, notify: false) }
        notifyCountChanged()
        Log.pin.info("Dropped terminated pid=\(pid, privacy: .public) pins=\(identities.count, privacy: .public)")
    }

    func consumesPoint(_ pointAppKit: CGPoint) -> Bool {
        badges.values.contains { $0.isVisible && $0.frame.insetBy(dx: -4, dy: -4).contains(pointAppKit) }
    }

    func updateBadgeHover(at pointAppKit: CGPoint) {
        for panel in badges.values where panel.isVisible {
            panel.setBadgeHovered(panel.frame.insetBy(dx: -2, dy: -2).contains(pointAppKit))
        }
    }

    func hideBadges() {
        for panel in badges.values { panel.orderOut(nil) }
    }

    func hideForEnvironmentChange() {
        suspendMirrors()
    }

    func refreshAppearance() {
        for panel in badges.values {
            panel.configure(state: .unpin, toolTip: L10n.text(.pinUnpin))
        }
    }

    private func showPermissionGuide(for ref: WindowRef) {
        guard !showingPermissionGuide else { return }
        showingPermissionGuide = true
        runtime.pinHover.hideImmediately()
        runtime.closeConsole()
        runtime.uiSession.enterRegular()
        defer {
            runtime.uiSession.leaveRegular()
            showingPermissionGuide = false
        }

        let alert = NSAlert()
        alert.messageText = L10n.text(.pinScreenRecordingTitle)
        alert.informativeText = L10n.text(.pinScreenRecordingMessage)
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        alert.addButton(withTitle: L10n.text(.pinScreenRecordingRequest))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        alert.layout()

        let alertWindow = alert.window
        alertWindow.level = .modalPanel
        alertWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        {
            var frame = alertWindow.frame
            frame.origin.x = screen.visibleFrame.midX - frame.width / 2
            frame.origin.y = screen.visibleFrame.midY - frame.height / 2
            alertWindow.setFrame(frame, display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        alertWindow.orderFrontRegardless()

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if ScreenRecordingAccess.request() {
            beginPin(ref)
        } else {
            _ = ScreenRecordingAccess.openSettings()
            Log.pin.notice("Screen Recording access is required before pinning")
        }
    }

    private func beginPin(_ ref: WindowRef) {
        let identity = ref.identity
        guard pending.insert(identity).inserted else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pending.remove(identity) }

            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                guard let window = content.windows.first(where: { $0.windowID == ref.windowNumber }) else {
                    throw StartError.sourceWindowUnavailable
                }

                let session = PinMirrorSession(identity: identity) { [weak self] error in
                    self?.mirrorFailed(identity: identity, error: error)
                }
                try await session.start(window: window)

                guard !self.isPinned(identity) else {
                    session.stop()
                    return
                }
                self.records.append(
                    Record(
                        identity: identity,
                        session: session,
                        lastKnownFrameAX: ref.boundsAX,
                        pinnedAt: Date()
                    )
                )
                self.makeBadge(for: identity)
                session.show(
                    frameAX: ref.boundsAX,
                    primaryFlipHeight: self.runtime.primaryFlipHeight,
                    reorder: true
                )
                self.updateBadge(identity: identity, frameAX: ref.boundsAX, reorder: true)
                self.lastMotionAt = Date()
                self.startWatchdogIfNeeded()
                self.notifyCountChanged()
                Log.pin.info(
                    "Pinned mirror pid=\(identity.pid, privacy: .public) window=\(identity.windowNumber, privacy: .public) count=\(self.count, privacy: .public)"
                )
                await self.raiseSourceWindow(identity, frameAX: ref.boundsAX)
            } catch {
                Log.pin.error(
                    "Mirror start failed pid=\(identity.pid, privacy: .public) window=\(identity.windowNumber, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                NSSound.beep()
            }
        }
    }

    private func mirrorFailed(identity: WindowIdentity, error: Error) {
        guard isPinned(identity) else { return }
        Log.pin.error(
            "Mirror stopped pid=\(identity.pid, privacy: .public) window=\(identity.windowNumber, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )
        _ = remove(identity, notify: false)
        notifyCountChanged()
    }

    private func startWatchdogIfNeeded() {
        guard watchdog == nil, !records.isEmpty else { return }
        restartWatchdog(interval: Watchdog.activeInterval)
    }

    private func restartWatchdog(interval: TimeInterval) {
        watchdog?.invalidate()
        watchdogInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func setWatchdogInterval(_ interval: TimeInterval) {
        guard watchdog != nil, watchdogInterval != interval else { return }
        restartWatchdog(interval: interval)
    }

    private func tick() {
        guard !records.isEmpty else { return }
        // Timer fires are dispatched onto the main actor, so a busy run loop can
        // queue several of them; coalesce instead of replaying stale samples.
        let now = Date()
        guard now.timeIntervalSince(lastTickAt) >= watchdogInterval / 2 else { return }
        lastTickAt = now

        let suppressed = !ScreenRecordingAccess.isGranted
            || !runtime.allows(.followPinnedWindows)
        guard !suppressed else {
            if runtime.mode == .pinningFollow {
                runtime.end(.pinFollow)
            }
            suspendMirrors()
            setWatchdogInterval(Watchdog.idleInterval)
            return
        }
        mirrorsSuspended = false
        if pointerIsDraggingPin() {
            _ = runtime.begin(.pinFollow)
        } else if runtime.mode == .pinningFollow {
            runtime.end(.pinFollow)
        }

        if now.timeIntervalSince(lastFullScanAt) >= Watchdog.fullScanInterval {
            lastFullScanAt = now
            fullScan(now: now)
        } else {
            followFrames(now: now)
        }

        let moving = now.timeIntervalSince(lastMotionAt) < Watchdog.motionWindow
            || pointerIsDraggingPin()
        setWatchdogInterval(moving ? Watchdog.activeInterval : Watchdog.idleInterval)
    }

    /// Between full scans, refresh only the geometry of the pins the last scan
    /// found on screen. This is the path that runs at 60Hz during a drag.
    private func followFrames(now: Date) {
        let visible = Set(lastVisibleOrder)
        for index in records.indices {
            let identity = records[index].identity
            guard visible.contains(identity),
                  let frame = query.frameAX(ofWindow: identity.windowNumber),
                  !Self.framesMatch(records[index].lastKnownFrameAX, frame)
            else { continue }
            lastMotionAt = now
            records[index].lastKnownFrameAX = frame
            records[index].session.show(
                frameAX: frame,
                primaryFlipHeight: runtime.primaryFlipHeight,
                reorder: false
            )
            updateBadge(identity: identity, frameAX: frame, reorder: false)
        }
        raiseVisiblePins(now: now)
    }

    /// A held mouse button alone is not enough — the pointer has to be on a
    /// pinned window, with a margin for the resize edge just outside it.
    private func pointerIsDraggingPin() -> Bool {
        guard NSEvent.pressedMouseButtons != 0 else { return false }
        let axPoint = CoordinateConverter.axPoint(
            fromAppKit: NSEvent.mouseLocation,
            primaryFlipHeight: runtime.primaryFlipHeight
        )
        return records.contains { $0.lastKnownFrameAX.insetBy(dx: -12, dy: -12).contains(axPoint) }
    }

    private func fullScan(now: Date) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let snapshots = query.pinSnapshots(excludingPID: ownPID)
        let onScreen = Set(snapshots.lazy.filter { $0.layer == 0 }.map(\.identity))

        // The all-windows enumeration is the expensive one, and it only decides
        // dormant-versus-closed, so sample it just when a pin is missing.
        var offScreenIdentities: Set<WindowIdentity>?
        if records.contains(where: { !onScreen.contains($0.identity) }),
           now.timeIntervalSince(lastOffScreenScanAt) >= Watchdog.offScreenScanInterval
        {
            lastOffScreenScanAt = now
            offScreenIdentities = query.allWindowIdentities(excludingPID: ownPID)
        }

        let plan = PinPlanner.plan(
            frontToBack: snapshots,
            allWindowIdentities: offScreenIdentities,
            pinOrder: records.map(\.identity)
        )

        retireClosedWindows(plan, sampledOffScreen: offScreenIdentities != nil, now: now)
        guard !records.isEmpty else { return }

        let visible = Set(plan.visible)
        for index in records.indices {
            let identity = records[index].identity
            if let frame = plan.visibleFrames[identity] {
                if !Self.framesMatch(records[index].lastKnownFrameAX, frame) { lastMotionAt = now }
                records[index].lastKnownFrameAX = frame
            } else if !visible.contains(identity) {
                records[index].session.hide()
                records[index].session.setCapturePaused(true)
                badges[identity]?.orderOut(nil)
            }
        }

        // Ordering oldest to newest makes the newest pin win wherever two
        // mirrors overlap. Unrelated floating windows can shuffle the
        // WindowServer order at any time, so refresh it periodically even when
        // our own set has not changed.
        let reorder = plan.visible != lastVisibleOrder
            || now.timeIntervalSince(lastReorderAt) >= Watchdog.reorderInterval
        if reorder { lastReorderAt = now }
        lastVisibleOrder = plan.visible

        for identity in plan.visible {
            guard let record = record(for: identity),
                  let frame = plan.visibleFrames[identity]
            else { continue }
            record.session.setCapturePaused(false)
            record.session.show(
                frameAX: frame,
                primaryFlipHeight: runtime.primaryFlipHeight,
                reorder: reorder
            )
        }

        // Badges are ordered after all mirrors so the unpin escape hatch is
        // never hidden by a newer mirror panel.
        for identity in plan.visible {
            guard let frame = plan.visibleFrames[identity] else { continue }
            updateBadge(identity: identity, frameAX: frame, reorder: reorder)
        }
        raiseVisiblePins(now: now)
    }

    private func raiseVisiblePins(now: Date) {
        guard runtime.isTrusted() else { return }
        for index in records.indices {
            let identity = records[index].identity
            guard lastVisibleOrder.contains(identity) else { continue }
            guard now.timeIntervalSince(records[index].lastRaisedAt) >= Watchdog.raiseInterval else {
                continue
            }
            records[index].lastRaisedAt = now
            let frameAX = records[index].lastKnownFrameAX
            Task { @MainActor [weak self] in
                await self?.raiseSourceWindow(identity, frameAX: frameAX)
            }
        }
    }

    private func retireClosedWindows(_ plan: PinPlan, sampledOffScreen: Bool, now: Date) {
        var expired: [WindowIdentity] = []
        for index in records.indices {
            let identity = records[index].identity
            switch PinRetirement.status(for: identity, plan: plan, sampledOffScreen: sampledOffScreen) {
            case .present:
                records[index].goneSince = nil
            case .unknown:
                break
            case .gone:
                let since = records[index].goneSince ?? now
                records[index].goneSince = since
                if now.timeIntervalSince(since) >= Watchdog.goneGrace {
                    expired.append(identity)
                }
            }
        }
        guard !expired.isEmpty else { return }
        for identity in expired { _ = remove(identity, notify: false) }
        notifyCountChanged()
    }

    private func suspendMirrors() {
        guard !mirrorsSuspended else { return }
        mirrorsSuspended = true
        for record in records {
            record.session.hide()
            record.session.setCapturePaused(true)
        }
        hideBadges()
        lastVisibleOrder.removeAll()
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    private func makeBadge(for identity: WindowIdentity) {
        let panel = PinButtonPanel(size: 20)
        panel.configure(state: .unpin, toolTip: L10n.text(.pinUnpin))
        panel.onClick = { [weak self] in self?.unpin(identity) }
        badges[identity] = panel
    }

    private func updateBadge(identity: WindowIdentity, frameAX: CGRect, reorder: Bool) {
        guard let panel = badges[identity] else { return }
        guard runtime.allows(.followPinnedWindows), !unpinning.contains(identity) else {
            panel.orderOut(nil)
            return
        }
        let rectAX = PinBadgeSlot.rect(windowFrameAX: frameAX, size: 20, inset: 8)
        let rectAppKit = PinPanelPlacement.appKitRect(
            fromAX: rectAX,
            windowFrameAX: frameAX,
            primaryFlipHeight: runtime.primaryFlipHeight,
            clampToVisibleScreen: true
        )
        panel.show(frame: rectAppKit, reorder: reorder)
    }

    @discardableResult
    private func remove(_ identity: WindowIdentity, notify: Bool) -> Bool {
        guard let index = index(of: identity) else { return false }
        unpinning.remove(identity)
        let record = records.remove(at: index)
        record.session.stop()
        if let panel = badges.removeValue(forKey: identity) {
            panel.orderOut(nil)
            panel.close()
        }
        lastVisibleOrder.removeAll { $0 == identity }
        if records.isEmpty {
            watchdog?.invalidate()
            watchdog = nil
        }
        if notify { notifyCountChanged() }
        return true
    }

    private func notifyCountChanged() {
        runtime.reloadMenu()
    }

    private func index(of identity: WindowIdentity) -> Int? {
        records.firstIndex { $0.identity == identity }
    }

    private func record(for identity: WindowIdentity) -> Record? {
        records.first { $0.identity == identity }
    }
}
