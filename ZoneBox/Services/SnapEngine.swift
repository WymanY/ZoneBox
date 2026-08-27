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

    unowned var runtime: AppRuntime!

    var isQuickSnapperShowing: Bool {
        if quickSnapperPending { return true }
        if case .showing = quickSnapperPhase { return true }
        return false
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
            magneticThreshold: CGFloat(runtime.settings.magneticThresholdPoints)
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
            if !event.modifiers.contains(.shift) {
                stickyArm = true
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
            runtime.pendingWindow = nil
            runtime.pendingFrame = nil
        }
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
            guard let window = await runtime.ax.focusedWindow() else { return }
            await snap(window.identity, to: zoneNumber)
        }
    }

    private func snap(_ identity: WindowIdentity, to zoneNumber: Int) async {
        guard runtime.trust.isTrusted(), runtime.settings.snapEnabled else { return }
        guard let window = await runtime.ax.window(matching: identity) else { return }
        let area = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
            ?? runtime.displays.workAreas.first
        let zones = runtime.resolvedZones(for: area)
        guard let zone = zones.first(where: { $0.number == zoneNumber }) else { return }
        let original = await runtime.ax.frame(of: window)
        if let applied = await runtime.ax.setFrame(zone.frameAX, of: window), let original {
            runtime.catalog.record(
                UnsnapRecord(
                    identity: identity,
                    originalFrameAX: original,
                    snappedFrameAX: applied,
                    zoneIDs: [zone.zoneID]
                )
            )
        }
    }

    func cycleWindowsInFocusedZone(delta: Int) {
        Task { @MainActor in
            guard let focused = await runtime.ax.focusedWindow(),
                  let zoneID = runtime.catalog.zoneID(for: focused.identity)
            else { return }
            let ring = runtime.catalog.identities(in: zoneID)
            guard ring.count > 1, let idx = ring.firstIndex(of: focused.identity) else { return }
            let next = ring[(idx + delta + ring.count) % ring.count]
            if let window = await runtime.ax.window(matching: next) {
                await runtime.ax.raise(window)
                NSRunningApplication(processIdentifier: next.pid)?.activate()
            }
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
        for effect in effects {
            switch effect {
            case .none:
                break
            case .showOverlay(let id):
                runtime.overlay.settings = runtime.settings
                runtime.overlay.primaryFlipHeight = runtime.displays.primaryFlipHeight
                runtime.overlay.show(displayID: id, zones: lastZones, highlight: .none)
            case .hideOverlay:
                runtime.overlay.hideAll()
            case .highlight(let target):
                runtime.overlay.highlight(target)
            case .applyFrame(let identity, let rect):
                Task { @MainActor in
                    if let window = runtime.pendingWindow, window.identity == identity {
                        _ = await runtime.ax.setFrame(rect, of: window)
                    } else if let window = await runtime.ax.window(matching: identity) {
                        _ = await runtime.ax.setFrame(rect, of: window)
                    }
                }
            case .recordUnsnap(let record):
                runtime.catalog.record(record)
            case .cancel:
                runtime.overlay.hideAll()
            }
        }
    }
}
