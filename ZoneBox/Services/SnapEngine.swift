import AppKit
import ZoneBoxCore

@MainActor
final class SnapEngine {
    private var phase: SnapSessionPhase = .idle
    private var downLocation: CGPoint?
    private var downFrame: CGRect?
    private var activeWindow: WindowIdentity?
    private var lastZones: [ResolvedZone] = []

    unowned var runtime: AppRuntime!

    func handleMouse(_ event: SnapMouseEvent) {
        let cursorArea = runtime.displays.area(containingAppKit: event.locationAppKit)
        let zones = runtime.resolvedZones(for: cursorArea)
        lastZones = zones
        let window = activeWindow ?? runtime.pendingWindow?.identity
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
            snapOnRightClickDrag: runtime.settings.snapOnRightClickDrag
        )
        if event.kind == .leftDown {
            downLocation = event.locationAppKit
            downFrame = runtime.pendingFrame
            activeWindow = runtime.pendingWindow?.identity
        }
        let output = SnapSessionReducer.reduce(input)
        phase = output.phase
        apply(output.effects)
        if phase == .idle {
            activeWindow = nil
            downFrame = nil
            downLocation = nil
            runtime.pendingWindow = nil
            runtime.pendingFrame = nil
        }
    }

    func snapFocused(to zoneNumber: Int) {
        guard runtime.trust.isTrusted(), runtime.settings.snapEnabled else { return }
        Task { @MainActor in
            guard let window = await runtime.ax.focusedWindow() else { return }
            let area = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
                ?? runtime.displays.workAreas.first
            let zones = runtime.resolvedZones(for: area)
            guard let zone = zones.first(where: { $0.number == zoneNumber }) else { return }
            let original = await runtime.ax.frame(of: window)
            if let applied = await runtime.ax.setFrame(zone.frameAX, of: window), let original {
                runtime.catalog.record(
                    UnsnapRecord(
                        identity: window.identity,
                        originalFrameAX: original,
                        snappedFrameAX: applied,
                        zoneIDs: [zone.zoneID]
                    )
                )
            }
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
