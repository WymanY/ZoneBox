import AppKit
import ZoneBoxCore

@MainActor
final class SnapEngine {
    private var phase: SnapSessionPhase = .idle
    private var downLocation: CGPoint?
    private var downFrame: CGRect?
    private var activeWindow: WindowIdentity?
    private var lastZones: [ResolvedZone] = []
    private var pointerTrace: [CGPoint] = []
    private var stickyArm = false
    private var armOrigin: CGPoint?
    private var quickSnapperPhase: QuickSnapperPhase = .hidden
    private var quickSnapperPending = false
    private var quickSnapperSerial: Task<Void, Never>?

    /// Overlay digit 1...9; hover must not replace it until mouse-up.
    private var lockedTarget: SnapTarget?

    unowned var runtime: AppRuntime!

    var isQuickSnapperShowing: Bool {
        if quickSnapperPending { return true }
        if case .showing = quickSnapperPhase { return true }
        return false
    }

    var isOverlayArmed: Bool {
        isArmed(phase)
    }

    func handleMouse(_ event: SnapMouseEvent) {
        if event.kind == .leftDown, isQuickSnapperShowing {
            handleQuickSnapper(.dismiss)
        }
        let cursorArea = runtime.displays.area(containingAppKit: event.locationAppKit)
        let zones = runtime.resolvedZones(for: cursorArea)
        lastZones = zones
        let window = activeWindow ?? runtime.pendingWindow?.identity
        if event.kind == .leftDown {
            pointerTrace = [event.locationAppKit]
            stickyArm = false
            armOrigin = nil
            lockedTarget = nil
        } else if event.kind == .leftDragged {
            pointerTrace.append(event.locationAppKit)
            if pointerTrace.count > 64 {
                pointerTrace.removeFirst(pointerTrace.count - 64)
            }
        }
        let grid = runtime.gridCoverage(for: cursorArea)
        let input = SnapReducerInput(
            phase: phase,
            event: event,
            workAreas: runtime.displays.workAreas,
            primaryFlipHeight: runtime.displays.primaryFlipHeight,
            window: window,
            downFrameAX: downFrame,
            currentFrameAX: runtime.pendingFrame,
            downLocationAppKit: downLocation,
            resolvedZones: zones,
            unsnapRecord: window.flatMap { runtime.catalog.record(for: $0) },
            trusted: runtime.trust.isTrusted(),
            snapEnabled: runtime.settings.snapEnabled,
            isEditorOpen: runtime.isEditorOpen,
            restoreSizeOnUnsnap: runtime.settings.restoreSizeOnUnsnap,
            overlapPolicy: runtime.settings.overlapPolicy,
            snapOnShiftDrag: runtime.settings.snapOnShiftDrag,
            snapOnRightClickDrag: runtime.settings.snapOnRightClickDrag,
            shakeToSnapEnabled: runtime.settings.shakeToSnapEnabled,
            shakeIntensity: runtime.settings.shakeIntensity,
            pointerTrace: pointerTrace,
            stickyArm: stickyArm,
            armOriginAppKit: armOrigin,
            gridCells: grid.cells,
            gridGutter: grid.gutter,
            gridWorkAreaAX: grid.workAreaAX,
            magneticResizeEnabled: runtime.settings.magneticResizeEnabled,
            magneticThreshold: CGFloat(runtime.settings.magneticThresholdPoints),
            lockedTarget: lockedTarget
        )
        if event.kind == .leftDown {
            downLocation = event.locationAppKit
            downFrame = runtime.pendingFrame
            activeWindow = runtime.pendingWindow?.identity
        }
        let output = SnapSessionReducer.reduce(input)
        if isArmed(output.phase) {
            if armOrigin == nil {
                armOrigin = event.locationAppKit
            }
            stickyArm = true
        }
        if case .digit = event.kind, isArmed(output.phase) {
            stickyArm = true
            if case .highlighting(_, let target) = output.phase {
                lockedTarget = target
            }
        }
        phase = output.phase
        apply(output.effects)
        if phase == .idle {
            activeWindow = nil
            downFrame = nil
            downLocation = nil
            pointerTrace = []
            stickyArm = false
            armOrigin = nil
            lockedTarget = nil
            runtime.pendingWindow = nil
            runtime.pendingFrame = nil
        }
    }

    func handleOverlayDigit(_ number: Int) {
        handleMouse(
            SnapMouseEvent(
                kind: .digit(number),
                locationAppKit: NSEvent.mouseLocation,
                modifiers: []
            )
        )
    }

    func handleQuickSnapper(_ event: QuickSnapperEvent) {
        if case .invoke = event {
            quickSnapperPending = true
        }
        let previous = quickSnapperSerial
        quickSnapperSerial = Task { @MainActor in
            await previous?.value
            await self.runQuickSnapper(event)
        }
    }

    /// Snapshot AX focus on invoke *before* the HUD activates. Digit snaps that
    /// identity via `window(matching:)`, never `focusedWindow()` after key-sink.
    private func runQuickSnapper(_ event: QuickSnapperEvent) async {
        let invokeFocus: WindowIdentity?
        if case .invoke = event {
            invokeFocus = await runtime.ax.focusedWindow()?.identity
        } else {
            invokeFocus = nil
        }
        let area = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
            ?? runtime.displays.workAreas.first
        let zones = runtime.resolvedZones(for: area)
        lastZones = zones
        let input = QuickSnapperInput(
            phase: quickSnapperPhase,
            event: event,
            zoneNumbers: Set(zones.map(\.number)),
            trusted: runtime.trust.isTrusted(),
            snapEnabled: runtime.settings.snapEnabled,
            isEditorOpen: runtime.isEditorOpen,
            enabled: runtime.settings.quickSnapperEnabled,
            focusedWindow: invokeFocus
        )
        let output = QuickSnapperReducer.reduce(input)
        quickSnapperPhase = output.phase
        if case .hidden = output.phase {
            quickSnapperPending = false
        }
        for effect in output.effects {
            switch effect {
            case .showOverlay:
                guard let area else { break }
                runtime.noteQuickSnapperUI(showing: true)
                runtime.overlay.settings = runtime.settings
                runtime.overlay.primaryFlipHeight = runtime.displays.primaryFlipHeight
                runtime.overlay.show(
                    displayID: area.display.id,
                    zones: zones,
                    highlight: .none,
                    forceNumbers: true,
                    captureKeys: true
                )
            case .hideOverlay:
                runtime.overlay.hideAll()
                runtime.noteQuickSnapperUI(showing: false)
            case .snap(let identity, let number):
                await snap(identity, to: number)
            }
        }
    }

    func snapFocused(to zoneNumber: Int) {
        Task { @MainActor in
            guard runtime.trust.isTrusted(), runtime.settings.snapEnabled else { return }
            guard let target = await runtime.focusedWindowTarget() else { return }
            let zones = runtime.resolvedZones(for: target.area)
            guard let zone = zones.first(where: { $0.number == zoneNumber }) else { return }
            await snap(target, to: zone)
        }
    }

    private func snap(_ identity: WindowIdentity, to zoneNumber: Int) async {
        guard runtime.trust.isTrusted(), runtime.settings.snapEnabled else { return }
        guard let window = await runtime.ax.window(matching: identity),
              let frameAX = await runtime.ax.frame(of: window),
              let area = DisplayTargetResolver.workArea(
                  containingWindowFrameAX: frameAX,
                  from: runtime.displays.workAreas,
                  primaryFlipHeight: runtime.displays.primaryFlipHeight
              ),
              runtime.displays.isActive(displayID: area.display.id)
        else { return }
        let zones = runtime.resolvedZones(for: area)
        guard let zone = zones.first(where: { $0.number == zoneNumber }) else { return }
        await snap((window, frameAX, area), to: zone)
    }

    func snapAdjacent(delta: Int) {
        guard runtime.trust.isTrusted(), runtime.settings.snapEnabled else { return }
        Task { @MainActor in
            guard let target = await runtime.focusedWindowTarget() else { return }
            let zones = runtime.resolvedZones(for: target.area).sorted { $0.number < $1.number }
            guard !zones.isEmpty else { return }
            let current = runtime.catalog.zoneID(
                for: target.window.identity,
                displayID: target.area.display.id
            )
            let index = zones.firstIndex(where: { $0.zoneID == current }) ?? 0
            let next = zones[(index + delta + zones.count) % zones.count]
            await snap(target, to: next)
        }
    }

    func cycleWindowsInFocusedZone(delta: Int) {
        Task { @MainActor in
            guard let target = await runtime.focusedWindowTarget(),
                  let zoneID = runtime.catalog.zoneID(
                      for: target.window.identity,
                      displayID: target.area.display.id
                  )
            else { return }

            let identities = runtime.catalog.identities(in: zoneID, displayID: target.area.display.id)
            var ring: [(identity: WindowIdentity, window: AXWindow)] = []
            for identity in identities {
                let window: AXWindow?
                let frameAX: CGRect?
                if identity == target.window.identity {
                    window = target.window
                    frameAX = target.frameAX
                } else {
                    window = await runtime.ax.window(matching: identity)
                    frameAX = if let window { await runtime.ax.frame(of: window) } else { nil }
                }
                guard let window, let frameAX,
                      DisplayTargetResolver.workArea(
                          containingWindowFrameAX: frameAX,
                          from: runtime.displays.workAreas,
                          primaryFlipHeight: runtime.displays.primaryFlipHeight
                      )?.display.id == target.area.display.id
                else { continue }
                ring.append((identity, window))
            }

            guard ring.count > 1,
                  let index = ring.firstIndex(where: { $0.identity == target.window.identity })
            else { return }
            let next = ring[(index + delta + ring.count) % ring.count]
            guard runtime.displays.isActive(displayID: target.area.display.id) else { return }
            await runtime.ax.raise(next.window)
            NSRunningApplication(processIdentifier: next.identity.pid)?.activate()
        }
    }

    private func snap(
        _ target: (window: AXWindow, frameAX: CGRect, area: WorkArea),
        to zone: ResolvedZone
    ) async {
        guard runtime.displays.isActive(displayID: target.area.display.id) else { return }
        if let applied = await runtime.ax.setFrame(zone.frameAX, of: target.window) {
            runtime.catalog.record(
                UnsnapRecord(
                    identity: target.window.identity,
                    originalFrameAX: target.frameAX,
                    snappedFrameAX: applied,
                    zoneIDs: [zone.zoneID]
                ),
                displayID: target.area.display.id
            )
        }
    }

    func unsnapFocused() {
        Task { @MainActor in
            guard let window = await runtime.ax.focusedWindow(),
                  let record = runtime.catalog.record(for: window.identity)
            else { return }
            _ = await runtime.ax.setFrame(record.originalFrameAX, of: window)
            runtime.catalog.drop(identity: window.identity)
        }
    }

    func cancelSession() {
        phase = .idle
        runtime.overlay.hideAll()
        activeWindow = nil
        pointerTrace = []
        stickyArm = false
        armOrigin = nil
        lockedTarget = nil
        if isQuickSnapperShowing {
            handleQuickSnapper(.dismiss)
        }
    }

    private func isArmed(_ phase: SnapSessionPhase) -> Bool {
        switch phase {
        case .armed, .highlighting:
            true
        default:
            false
        }
    }

    private func apply(_ effects: [SnapEffect]) {
        var overlayDisplayID: UUID?
        var overlayHighlight: SnapTarget?
        var hideOverlay = false
        for effect in effects {
            switch effect {
            case .none:
                break
            case .showOverlay(let id):
                overlayDisplayID = id
                if overlayHighlight == nil {
                    overlayHighlight = .none
                }
                hideOverlay = false
            case .hideOverlay, .cancel:
                hideOverlay = true
                overlayDisplayID = nil
                overlayHighlight = nil
            case .highlight(let target):
                overlayHighlight = target
                hideOverlay = false
            case .applyFrame(let identity, let rect):
                let captured = runtime.pendingWindow
                Task { @MainActor in
                    if let window = captured, window.identity == identity {
                        _ = await runtime.ax.setFrame(rect, of: window)
                    } else if let window = await runtime.ax.window(matching: identity) {
                        _ = await runtime.ax.setFrame(rect, of: window)
                    }
                }
            case .recordUnsnap(let record):
                let area = DisplayTargetResolver.workArea(
                    containingWindowFrameAX: record.snappedFrameAX,
                    from: runtime.displays.workAreas,
                    primaryFlipHeight: runtime.displays.primaryFlipHeight
                )
                runtime.catalog.record(record, displayID: area?.display.id)
            }
        }
        if hideOverlay {
            runtime.overlay.hideAll()
            return
        }
        if let overlayDisplayID {
            runtime.menuBar?.closeConsole()
            runtime.overlay.settings = runtime.settings
            runtime.overlay.primaryFlipHeight = runtime.displays.primaryFlipHeight
            runtime.overlay.show(
                displayID: overlayDisplayID,
                zones: lastZones,
                highlight: overlayHighlight ?? .none,
                forceNumbers: true
            )
        } else if let overlayHighlight {
            runtime.overlay.highlight(overlayHighlight)
        }
    }
}
