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
    private var startedOnMoveChrome = false
    private var sessionLayoutID: Layout.ID?
    private var lastCursorDisplayID: DisplayIdentity.ID?
    private var lastStrip: LayoutStripGeometry?
    private var lastPresentation = OverlayPresentation.empty
    private var quickSnapperLayoutID: Layout.ID?
    private var pendingLayoutAssignment: PendingLayoutAssignment?
    private var layoutAssignmentGeneration = 0
    private var quickSnapperArea: WorkArea?

    unowned var runtime: AppRuntime!

    var isQuickSnapperShowing: Bool {
        if quickSnapperPending { return true }
        if case .showing = quickSnapperPhase { return true }
        return false
    }

    var isOverlayArmed: Bool {
        isArmed(phase)
    }

    var isSessionActive: Bool {
        phase != .idle || isQuickSnapperShowing
    }

    var isSnapGestureActive: Bool {
        switch phase {
        case .idle:
            false
        default:
            true
        }
    }

    func handleMouse(_ event: SnapMouseEvent) {
        if event.kind == .leftDown, isQuickSnapperShowing {
            handleQuickSnapper(.dismiss)
        }
        let cursorArea = runtime.displays.area(containingAppKit: event.locationAppKit)
        let window = activeWindow ?? runtime.pendingWindow?.identity ?? runtime.pendingIdentity
        if event.kind == .leftDown {
            pointerTrace = [event.locationAppKit]
            stickyArm = false
            armOrigin = nil
            lockedTarget = nil
            startedOnMoveChrome = runtime.pendingStartedOnMoveChrome
            sessionLayoutID = nil
            lastCursorDisplayID = nil
            lastStrip = nil
            layoutAssignmentGeneration = SnapLayoutAssignmentPolicy.generationAfterSessionReset(
                current: layoutAssignmentGeneration,
                startingNewDrag: true
            )
        } else if event.kind == .leftDragged {
            pointerTrace.append(event.locationAppKit)
            if pointerTrace.count > 64 {
                pointerTrace.removeFirst(pointerTrace.count - 64)
            }
        }
        let session = sessionContext(
            at: event.locationAppKit,
            area: cursorArea,
            committingStripSelection: event.kind == .leftUp
        )
        lastZones = session.zones
        lastStrip = session.strip
        lastPresentation = session.presentation
        let grid = runtime.gridCoverage(for: cursorArea, layoutOverride: session.layoutID)
        let input = SnapReducerInput(
            phase: phase,
            event: event,
            workAreas: runtime.displays.workAreas,
            primaryFlipHeight: runtime.displays.primaryFlipHeight,
            window: window,
            downFrameAX: downFrame,
            currentFrameAX: runtime.pendingFrame,
            downLocationAppKit: downLocation,
            resolvedZones: session.zones,
            unsnapRecord: window.flatMap { runtime.catalog.record(for: $0) },
            trusted: runtime.trust.isTrusted(),
            snapEnabled: true,
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
            lockedTarget: lockedTarget,
            startedOnMoveChrome: startedOnMoveChrome,
            layoutIDs: session.layoutIDs,
            assignedLayoutID: session.assignedLayoutID,
            sessionLayoutID: session.layoutID,
            pointerInLayoutStrip: session.pointerInStrip,
            forcedTarget: session.forcedTarget
        )
        if event.kind == .leftDown {
            downLocation = event.locationAppKit
            downFrame = runtime.pendingFrame
            activeWindow = runtime.pendingWindow?.identity ?? runtime.pendingIdentity
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
            resetLayoutSession()
            runtime.pendingWindow = nil
            runtime.pendingIdentity = nil
            runtime.pendingFrame = nil
            runtime.pendingStartedOnMoveChrome = false
            startedOnMoveChrome = false
            runtime.noteSnapSessionBecameIdle()
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

    func handleCycleLayout(_ delta: Int) {
        handleMouse(
            SnapMouseEvent(
                kind: .cycleLayout(delta),
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
        var area = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
            ?? runtime.displays.workAreas.first
        if case .invoke = event, let invokeFocus,
           let window = await runtime.ax.window(matching: invokeFocus),
           let frameAX = await runtime.ax.frame(of: window),
           let windowArea = DisplayTargetResolver.workArea(
               containingWindowFrameAX: frameAX,
               from: runtime.displays.workAreas,
               primaryFlipHeight: runtime.displays.primaryFlipHeight
           ) {
            area = QuickSnapperReducer.displayArea(pointerArea: area, targetWindowArea: windowArea)
        }
        area = QuickSnapperReducer.sessionArea(
            event: event,
            pointerArea: area,
            rememberedArea: quickSnapperArea
        )
        if case .invoke = event {
            quickSnapperLayoutID = area.flatMap { runtime.document.layout(for: $0.display.id)?.id }
            quickSnapperArea = area
        }
        let layouts = runtime.allResolvedLayouts(for: area)
        let layoutIDs = layouts.map(\.layout.id)
        if let selected = quickSnapperLayoutID, !layoutIDs.contains(selected) {
            quickSnapperLayoutID = layoutIDs.first
        }
        let zones = runtime.resolvedZones(for: area, layoutOverride: quickSnapperLayoutID)
        lastZones = zones
        let input = QuickSnapperInput(
            phase: quickSnapperPhase,
            event: event,
            zoneNumbers: Set(zones.map(\.number)),
            trusted: runtime.trust.isTrusted(),
            snapEnabled: true,
            isEditorOpen: runtime.isEditorOpen,
            enabled: runtime.settings.quickSnapperEnabled,
            focusedWindow: invokeFocus,
            layoutIDs: layoutIDs,
            selectedLayoutID: quickSnapperLayoutID ?? layoutIDs.first
        )
        let output = QuickSnapperReducer.reduce(input)
        quickSnapperPhase = output.phase
        quickSnapperLayoutID = output.selectedLayoutID
        if case .hidden = output.phase {
            quickSnapperPending = false
            quickSnapperLayoutID = nil
            quickSnapperArea = nil
        }
        for effect in output.effects {
            switch effect {
            case .showOverlay:
                guard let area else { break }
                runtime.noteQuickSnapperUI(showing: true)
                runtime.overlay.settings = runtime.settings
                runtime.overlay.primaryFlipHeight = runtime.displays.primaryFlipHeight
                let overlayZones = runtime.resolvedZones(for: area, layoutOverride: output.selectedLayoutID)
                runtime.overlay.show(
                    displayID: area.display.id,
                    zones: overlayZones,
                    highlight: .none,
                    captureKeys: true
                )
                runtime.divider.refresh()
            case .hideOverlay:
                runtime.overlay.hideSessionOverlay()
                runtime.noteQuickSnapperUI(showing: false)
                runtime.divider.refresh()
            case .snap(let identity, let number):
                await snap(identity, to: number, layoutID: output.selectedLayoutID)
            }
        }
    }

    func snapFocused(to zoneNumber: Int) {
        Task { @MainActor in
            guard runtime.trust.isTrusted() else { return }
            guard let target = await runtime.focusedWindowTarget() else { return }
            let zones = runtime.resolvedZones(for: target.area)
            guard let zone = zones.first(where: { $0.number == zoneNumber }) else { return }
            _ = await snap(target, to: zone)
        }
    }

    private func snap(_ identity: WindowIdentity, to zoneNumber: Int) async {
        await snap(identity, to: zoneNumber, layoutID: nil)
    }

    private func snap(_ identity: WindowIdentity, to zoneNumber: Int, layoutID: Layout.ID?) async {
        guard runtime.trust.isTrusted() else { return }
        guard let window = await runtime.ax.window(matching: identity),
              let frameAX = await runtime.ax.frame(of: window),
              let area = DisplayTargetResolver.workArea(
                  containingWindowFrameAX: frameAX,
                  from: runtime.displays.workAreas,
                  primaryFlipHeight: runtime.displays.primaryFlipHeight
              ),
              runtime.displays.isActive(displayID: area.display.id)
        else { return }
        let zones = runtime.resolvedZones(for: area, layoutOverride: layoutID)
        guard let zone = zones.first(where: { $0.number == zoneNumber }) else { return }
        let applied = await snap((window, frameAX, area), to: zone)
        guard applied != nil, let layoutID else { return }
        pendingLayoutAssignment = PendingLayoutAssignment(
            layoutID: layoutID,
            pointAppKit: CoordinateConverter.appKitPoint(
                fromAX: CGPoint(x: zone.frameAX.midX, y: zone.frameAX.midY),
                primaryFlipHeight: runtime.displays.primaryFlipHeight
            )
        )
        commitPendingLayoutAssignmentIfNeeded()
    }

    func snapAdjacent(delta: Int) {
        guard runtime.trust.isTrusted() else { return }
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
            _ = await snap(target, to: next)
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
    ) async -> CGRect? {
        guard runtime.displays.isActive(displayID: target.area.display.id) else { return nil }
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
            runtime.noteUserSnapCompleted()
            runtime.divider.refresh()
            return applied
        }
        return nil
    }

    func unsnapFocused() {
        Task { @MainActor in
            guard let window = await runtime.ax.focusedWindow(),
                  let record = runtime.catalog.record(for: window.identity)
            else { return }
            _ = await runtime.ax.setFrame(record.originalFrameAX, of: window)
            runtime.catalog.drop(identity: window.identity)
            runtime.divider.refresh()
        }
    }

    func cancelSession() {
        phase = .idle
        runtime.overlay.hideSessionOverlay()
        runtime.divider.refresh()
        activeWindow = nil
        pointerTrace = []
        stickyArm = false
        armOrigin = nil
        lockedTarget = nil
        if isQuickSnapperShowing {
            handleQuickSnapper(.dismiss)
        }
        resetLayoutSession()
        pendingLayoutAssignment = nil
        runtime.pendingWindow = nil
        runtime.pendingIdentity = nil
        runtime.pendingFrame = nil
        runtime.pendingStartedOnMoveChrome = false
        startedOnMoveChrome = false
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
        var pendingAssignmentForApply: PendingLayoutAssignment?
        for effect in effects {
            switch effect {
            case .none:
                break
            case .showOverlay(let id):
                overlayDisplayID = id
                if overlayHighlight == nil {
                    overlayHighlight = SnapTarget.none
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
                let pending = pendingAssignmentForApply
                pendingAssignmentForApply = nil
                let generation = layoutAssignmentGeneration
                Task { @MainActor in
                    let window = captured?.identity == identity
                        ? captured
                        : await runtime.ax.window(matching: identity)
                    let applied = if let window {
                        await runtime.ax.setFrame(rect, of: window) != nil
                    } else {
                        false
                    }
                    if let layoutID = SnapLayoutAssignmentPolicy.assignmentToCommit(
                        capturedForThisWrite: pending?.layoutID,
                        frameApplied: applied
                    ) {
                        self.commit(
                            pending ?? PendingLayoutAssignment(
                                layoutID: layoutID,
                                pointAppKit: NSEvent.mouseLocation
                            ),
                            generation: generation
                        )
                    }
                }
            case .recordUnsnap(let record):
                let area = DisplayTargetResolver.workArea(
                    containingWindowFrameAX: record.snappedFrameAX,
                    from: runtime.displays.workAreas,
                    primaryFlipHeight: runtime.displays.primaryFlipHeight
                )
                runtime.catalog.record(record, displayID: area?.display.id)
                runtime.noteUserSnapCompleted()
                runtime.divider.refresh()
            case .assignLayout(let layoutID):
                let pending = PendingLayoutAssignment(
                    layoutID: layoutID,
                    pointAppKit: NSEvent.mouseLocation
                )
                pendingLayoutAssignment = pending
                pendingAssignmentForApply = pending
                sessionLayoutID = layoutID
            case .clearLockedTarget:
                lockedTarget = nil
            case .selectLayout(let layoutID):
                sessionLayoutID = layoutID
            }
        }
        if hideOverlay {
            runtime.overlay.hideSessionOverlay()
            runtime.divider.refresh()
            return
        }
        if let overlayDisplayID {
            runtime.menuBar?.closeConsole()
            runtime.overlay.settings = runtime.settings
            runtime.overlay.primaryFlipHeight = runtime.displays.primaryFlipHeight
            let area = runtime.displays.workAreas.first(where: { $0.display.id == overlayDisplayID })
            let session = sessionContext(
                at: NSEvent.mouseLocation,
                area: area,
                committingStripSelection: false
            )
            lastZones = session.zones.isEmpty ? lastZones : session.zones
            lastStrip = session.strip
            lastPresentation = session.presentation
            let zones = lastZones
            var highlight = overlayHighlight ?? SnapTarget.none
            if case .none = highlight {
                if session.pointerInStrip {
                    highlight = session.forcedTarget ?? .none
                } else {
                    highlight = HitTester(policy: runtime.settings.overlapPolicy).target(
                        at: CoordinateConverter.axPoint(
                            fromAppKit: NSEvent.mouseLocation,
                            primaryFlipHeight: runtime.displays.primaryFlipHeight
                        ),
                        zones: zones
                    )
                }
            }
            runtime.overlay.show(
                displayID: overlayDisplayID,
                zones: zones,
                highlight: highlight,
                presentation: lastPresentation
            )
            runtime.divider.refresh()
        } else if let overlayHighlight {
            runtime.overlay.highlight(overlayHighlight)
        }
    }

    private func resetLayoutSession() {
        sessionLayoutID = nil
        lastCursorDisplayID = nil
        lastStrip = nil
        lastPresentation = .empty
        quickSnapperLayoutID = nil
    }

    private struct PendingLayoutAssignment {
        var layoutID: Layout.ID
        var pointAppKit: CGPoint
    }

    private func commitPendingLayoutAssignmentIfNeeded() {
        guard let pending = pendingLayoutAssignment else { return }
        pendingLayoutAssignment = nil
        commit(pending, generation: layoutAssignmentGeneration)
    }

    private func commit(_ pending: PendingLayoutAssignment, generation: Int) {
        guard SnapLayoutAssignmentPolicy.shouldUpdateSession(
            completionGeneration: generation,
            currentGeneration: layoutAssignmentGeneration
        ) else { return }
        pendingLayoutAssignment = nil
        let area = runtime.displays.area(containingAppKit: pending.pointAppKit)
            ?? runtime.displays.workAreas.first
        guard let area else { return }
        runtime.document.assign(layoutID: pending.layoutID, to: area.display.id)
        runtime.markLayoutUsed(pending.layoutID)
        runtime.persist()
        runtime.menuBar?.reloadMenu()
        sessionLayoutID = pending.layoutID
    }

    private struct SessionContext {
        var layoutID: Layout.ID?
        var assignedLayoutID: Layout.ID?
        var layoutIDs: [Layout.ID]
        var zones: [ResolvedZone]
        var strip: LayoutStripGeometry?
        var pointerInStrip: Bool
        var forcedTarget: SnapTarget?
        var presentation: OverlayPresentation
    }

    private func sessionContext(
        at pointAppKit: CGPoint,
        area: WorkArea?,
        committingStripSelection: Bool = false
    ) -> SessionContext {
        let assignedID = area.flatMap { runtime.document.layout(for: $0.display.id)?.id }
        let session = SnapLayoutSession.sessionLayoutID(
            previousDisplayID: lastCursorDisplayID,
            currentDisplayID: area?.display.id,
            assignedLayoutID: assignedID,
            currentSessionLayoutID: sessionLayoutID,
            lockedTarget: lockedTarget
        )
        if session.crossedDisplay {
            lastCursorDisplayID = area?.display.id
            sessionLayoutID = session.layoutID
        } else if lastCursorDisplayID == nil {
            lastCursorDisplayID = area?.display.id
        }

        let layouts = runtime.allResolvedLayouts(for: area)
        let layoutIDs = layouts.map(\.layout.id)

        var strip: LayoutStripGeometry?
        var pointerInStrip = false
        var forcedTarget: SnapTarget?
        var highlightedLayoutID: Layout.ID?
        var highlightedZoneNumber: Int?
        if runtime.settings.showLayoutStrip, let area, isArmed(phase) {
            let workAX = CoordinateConverter.axRect(
                fromAppKit: area.visibleFrameAppKit,
                primaryFlipHeight: runtime.displays.primaryFlipHeight
            )
            strip = LayoutStripGeometry.make(
                workAreaAppKit: area.visibleFrameAppKit,
                layouts: layouts,
                assignedLayoutID: assignedID,
                workAreaAX: workAX
            )
            if let strip, strip.contains(pointAppKit) {
                pointerInStrip = true
                if let hit = strip.hitZone(at: pointAppKit),
                   let layout = layouts.first(where: { $0.layout.id == hit.layoutID }),
                   let zone = layout.zones.first(where: { $0.number == hit.zoneNumber }) {
                    forcedTarget = .zone(zone)
                    highlightedLayoutID = hit.layoutID
                    highlightedZoneNumber = hit.zoneNumber
                } else {
                    highlightedLayoutID = strip.hitCard(at: pointAppKit)
                }
            }
        }

        sessionLayoutID = SnapLayoutSession.sessionLayoutIDForPointer(
            forcedLayoutID: forcedTarget == nil ? nil : highlightedLayoutID,
            currentSessionLayoutID: sessionLayoutID,
            assignedLayoutID: assignedID,
            lockedTarget: lockedTarget,
            preferForcedLayout: committingStripSelection
        )

        let layoutID = sessionLayoutID ?? assignedID
        let zones = runtime.resolvedZones(for: area, layoutOverride: layoutID)
        let stripModel: OverlayStripRenderModel?
        if let strip, runtime.settings.showLayoutStrip {
            stripModel = OverlayStripRenderModel(
                geometry: strip,
                highlightedLayoutID: highlightedLayoutID ?? layoutID,
                highlightedZoneNumber: highlightedZoneNumber
            )
        } else {
            stripModel = nil
        }
        return SessionContext(
            layoutID: layoutID,
            assignedLayoutID: assignedID,
            layoutIDs: layoutIDs,
            zones: zones,
            strip: strip,
            pointerInStrip: pointerInStrip,
            forcedTarget: forcedTarget,
            presentation: OverlayPresentation.snapSession(strip: stripModel)
        )
    }
}
