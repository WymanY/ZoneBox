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
    private var stripWindowLayoutID: Layout.ID?
    private var stripWindowStartID: Layout.ID?
    private var stripOverflowLatch: Int?
    private var stripDropLatch: StripDropLatch?
    private var stripLatchHistory = StripDropLatchHistory()
    private var suppressStripLatch = false
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    private var quickSnapperLayoutID: Layout.ID?
    private var pendingLayoutAssignment: PendingLayoutAssignment?
    private var layoutAssignmentGeneration = 0
    private var quickSnapperArea: WorkArea?

    unowned var runtime: SnapRuntimeHosting!

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

    private var snapWriteSession = UUID()
    private var outstandingSnapWrites = 0
    private var diagnosticSessionID: UUID?
    private var diagnosticActive = false
    private var diagnosticEventIndex = 0
    private var diagnosticInput = "none"
    private var diagnosticSource = "engine"
    private var diagnosticPoint = CGPoint.zero
    private var diagnosticStates: [String: [String: String]] = [:]
    private var diagnosticGeometry: LayoutStripGeometry?

    func handleMouse(_ event: SnapMouseEvent, source: String = "engine") {
        if event.kind == .leftDown {
            diagnosticSessionID = UUID()
            diagnosticActive = false
            diagnosticEventIndex = 0
            diagnosticStates.removeAll()
            diagnosticGeometry = nil
        }
        diagnosticEventIndex += 1
        diagnosticInput = String(describing: event.kind)
        diagnosticSource = source
        diagnosticPoint = event.locationAppKit
        if event.kind == .leftDown {
            runtime.dismissWorkspaceSwitcher()
        }
        if event.kind == .leftDown, isQuickSnapperShowing {
            handleQuickSnapper(.dismiss)
        }
        if event.kind == .leftDown {
            if runtime.mode != .snapping {
                guard runtime.begin(.snap) else { return }
            }
            if outstandingSnapWrites == 0 {
                snapWriteSession = UUID()
            }
        }
        let cursorArea = runtime.area(containingAppKit: event.locationAppKit)
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
            lastZones = []
            lastPresentation = .empty
            stripWindowLayoutID = nil
            stripWindowStartID = nil
            stripOverflowLatch = nil
            stripDropLatch = nil
            stripLatchHistory = StripDropLatchHistory()
            suppressStripLatch = false
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
            workAreas: runtime.workAreas,
            primaryFlipHeight: runtime.primaryFlipHeight,
            window: window,
            downFrameAX: downFrame,
            currentFrameAX: runtime.pendingFrame,
            downLocationAppKit: downLocation,
            resolvedZones: session.zones,
            unsnapRecord: window.flatMap { runtime.catalog.record(for: $0) },
            trusted: runtime.isTrusted(),
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
        if isArmed(output.phase), !diagnosticActive {
            diagnosticActive = true
            trace("drag.begin", fields: [
                "windowPID": window.map { "\($0.pid)" } ?? "nil",
                "windowNumber": window.map { "\($0.windowNumber)" } ?? "nil",
                "bundle": window?.bundleID ?? "nil",
                "downPoint": downLocation.map(Self.describe) ?? "nil",
                "downFrame": Self.describe(downFrame),
                "display": cursorArea?.display.id.uuidString ?? "nil",
                "workArea": Self.describe(cursorArea?.visibleFrameAppKit),
                "flipHeight": "\(runtime.primaryFlipHeight)",
                "startedOnMoveChrome": "\(startedOnMoveChrome)",
                "showLayoutStrip": "\(runtime.settings.showLayoutStrip)",
                "overlapPolicy": "\(runtime.settings.overlapPolicy)",
            ])
        }
        trace("drag.state", fields: [
            "phase": Self.describe(output.phase),
            "layout": session.layoutID?.uuidString ?? "nil",
            "assignedLayout": session.assignedLayoutID?.uuidString ?? "nil",
            "forced": session.forcedTarget.map(Self.describe) ?? "nil",
            "locked": lockedTarget.map(Self.describe) ?? "nil",
            "inStrip": "\(session.pointerInStrip)",
            "modifiers": "\(event.modifiers.rawValue)",
        ], changedOnly: true)
        if event.kind != .leftDragged {
            trace("drag.input", fields: ["phaseBefore": Self.describe(phase), "phaseAfter": Self.describe(output.phase)])
        }
        if event.kind == .leftUp {
            let frameDesc = output.effects.compactMap { effect -> String? in
                if case .applyFrame(_, let rect) = effect {
                    return "x=\(Int(rect.minX)) w=\(Int(rect.width))"
                }
                return nil
            }.first ?? "none"
            let assignDesc = output.effects.compactMap { effect -> String? in
                if case .assignLayout(let id) = effect { return id.uuidString.prefix(8).description }
                return nil
            }.first ?? "none"
            Log.snap.debug(
                "StripDrop leftUp inStrip=\(session.pointerInStrip, privacy: .public) forced=\(session.forcedTarget.map(Self.describe) ?? "nil", privacy: .public) latch=\(Self.describe(self.stripDropLatch), privacy: .public) apply=\(frameDesc, privacy: .public) assign=\(assignDesc, privacy: .public)"
            )
            trace("drag.drop", fields: [
                "phaseBefore": Self.describe(phase),
                "inStrip": "\(session.pointerInStrip)",
                "forced": session.forcedTarget.map(Self.describe) ?? "nil",
                "latch": Self.describe(stripDropLatch),
                "apply": frameDesc,
                "assign": assignDesc,
                "currentFrame": Self.describe(runtime.pendingFrame),
                "axResolved": "\(runtime.pendingWindow != nil)",
            ])
        }
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
                if output.effects.contains(where: { if case .applyFrame = $0 { return true }; return false }) {
                    let next = SnapLayoutSession.stripDropLatchAfterDigit(
                        previous: stripDropLatch,
                        currentSessionLayoutID: sessionLayoutID
                    )
                    stripDropLatch = next.latch
                    stripLatchHistory = StripDropLatchHistory()
                    sessionLayoutID = next.sessionLayoutID
                    suppressStripLatch = true
                }
            }
        }
        phase = output.phase
        apply(output.effects)
        if phase == .idle {
            trace("drag.end", fields: ["outstandingWrites": "\(outstandingSnapWrites)"])
            diagnosticActive = false
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
            releaseSnapOwnershipIfIdle()
            runtime.noteSnapSessionBecameIdle()
        }
    }

    func handleOverlayDigit(_ number: Int) {
        handleMouse(
            SnapMouseEvent(
                kind: .digit(number),
                locationAppKit: NSEvent.mouseLocation,
                modifiers: []
            ),
            source: "keyboard"
        )
    }

    func handleCycleLayout(_ delta: Int, source: String = "keyboard") {
        handleMouse(
            SnapMouseEvent(
                kind: .cycleLayout(delta),
                locationAppKit: NSEvent.mouseLocation,
                modifiers: []
            ),
            source: source
        )
    }

    func handleQuickSnapper(_ event: QuickSnapperEvent) {
        if case .invoke = event {
            guard runtime.begin(.snap) else { return }
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
        var area = runtime.area(containingAppKit: NSEvent.mouseLocation)
            ?? runtime.workAreas.first
        if case .invoke = event, let invokeFocus,
           let window = await runtime.ax.window(matching: invokeFocus),
           let frameAX = await runtime.ax.frame(of: window),
           let windowArea = DisplayTargetResolver.workArea(
               containingWindowFrameAX: frameAX,
               from: runtime.workAreas,
               primaryFlipHeight: runtime.primaryFlipHeight
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
            trusted: runtime.isTrusted(),
            snapEnabled: runtime.settings.snapEnabled,
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
            if phase == .idle {
                runtime.end(.snap)
            }
        }
        for effect in output.effects {
            switch effect {
            case .showOverlay:
                guard let area else { break }
                runtime.noteQuickSnapperUI(showing: true)
                runtime.overlay.settings = runtime.settings
                runtime.overlay.primaryFlipHeight = runtime.primaryFlipHeight
                let overlayZones = runtime.resolvedZones(for: area, layoutOverride: output.selectedLayoutID)
                runtime.overlay.show(
                    displayID: area.display.id,
                    zones: overlayZones,
                    highlight: .none,
                    captureKeys: true
                )
                runtime.refreshDivider()
            case .hideOverlay:
                runtime.overlay.hideSessionOverlay()
                runtime.noteQuickSnapperUI(showing: false)
                runtime.refreshDivider()
            case .snap(let identity, let number):
                await snap(identity, to: number, layoutID: output.selectedLayoutID)
            }
        }
    }

    func snapFocused(to zoneNumber: Int) {
        Task { @MainActor in
            guard runtime.isTrusted(), runtime.settings.snapEnabled else { return }
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
        guard runtime.isTrusted() else { return }
        guard let window = await runtime.ax.window(matching: identity),
              let frameAX = await runtime.ax.frame(of: window),
              let area = DisplayTargetResolver.workArea(
                  containingWindowFrameAX: frameAX,
                  from: runtime.workAreas,
                  primaryFlipHeight: runtime.primaryFlipHeight
              ),
              runtime.isActive(displayID: area.display.id)
        else { return }
        let zones = runtime.resolvedZones(for: area, layoutOverride: layoutID)
        guard let zone = zones.first(where: { $0.number == zoneNumber }) else { return }
        let applied = await snap((window, frameAX, area), to: zone)
        guard applied != nil, let layoutID else { return }
        pendingLayoutAssignment = PendingLayoutAssignment(
            layoutID: layoutID,
            pointAppKit: CoordinateConverter.appKitPoint(
                fromAX: CGPoint(x: zone.frameAX.midX, y: zone.frameAX.midY),
                primaryFlipHeight: runtime.primaryFlipHeight
            )
        )
        commitPendingLayoutAssignmentIfNeeded()
    }

    func snapAdjacent(delta: Int) {
        guard runtime.isTrusted(), runtime.settings.snapEnabled else { return }
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
                          from: runtime.workAreas,
                          primaryFlipHeight: runtime.primaryFlipHeight
                      )?.display.id == target.area.display.id
                else { continue }
                ring.append((identity, window))
            }

            guard ring.count > 1,
                  let index = ring.firstIndex(where: { $0.identity == target.window.identity })
            else { return }
            let next = ring[(index + delta + ring.count) % ring.count]
            guard runtime.isActive(displayID: target.area.display.id) else { return }
            _ = await runtime.raise(next.window, sessionID: UUID(), generation: 1)
            NSRunningApplication(processIdentifier: next.identity.pid)?.activate()
        }
    }

    private func snap(
        _ target: (window: AXWindow, frameAX: CGRect, area: WorkArea),
        to zone: ResolvedZone
    ) async -> CGRect? {
        guard runtime.isActive(displayID: target.area.display.id) else { return nil }
        if let applied = await runtime.applyFrame(zone.frameAX, of: target.window, sessionID: UUID(), generation: layoutAssignmentGeneration) {
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
            runtime.refreshDivider()
            return applied
        }
        return nil
    }

    func unsnapFocused() {
        Task { @MainActor in
            guard let window = await runtime.ax.focusedWindow(),
                  let record = runtime.catalog.record(for: window.identity)
            else { return }
            _ = await runtime.applyFrame(record.originalFrameAX, of: window, sessionID: UUID(), generation: 1)
            runtime.catalog.drop(identity: window.identity)
            runtime.refreshDivider()
        }
    }

    func cancelSession() {
        trace("drag.cancel", fields: ["phase": Self.describe(phase)])
        diagnosticActive = false
        phase = .idle
        outstandingSnapWrites = 0
        runtime.cancelMutations(sessionID: snapWriteSession)
        runtime.end(.snap)
        runtime.overlay.hideSessionOverlay()
        runtime.refreshDivider()
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

    private func finishSnapWrite() {
        if outstandingSnapWrites > 0 {
            outstandingSnapWrites -= 1
        }
        releaseSnapOwnershipIfIdle()
    }

    private func releaseSnapOwnershipIfIdle() {
        guard phase == .idle, outstandingSnapWrites == 0, !isQuickSnapperShowing else { return }
        runtime.end(.snap)
    }

    private static func describe(_ target: SnapTarget) -> String {
        switch target {
        case .none: return "none"
        case .zone(let zone): return "z\(zone.number)"
        case .span(_, let ids): return "span(\(ids.count))"
        }
    }

    private static func describe(_ latch: StripDropLatch?) -> String {
        guard let latch else { return "nil" }
        return "\(latch.layoutID.uuidString.prefix(8)):z\(latch.zone.number)"
    }

    private static func describe(_ point: CGPoint) -> String {
        "\(point.x),\(point.y)"
    }

    private static func describe(_ frame: CGRect?) -> String {
        guard let frame else { return "nil" }
        return "\(frame.minX),\(frame.minY),\(frame.width),\(frame.height)"
    }

    private static func describe(_ phase: SnapSessionPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .mouseDown: return "mouseDown"
        case .dragging: return "dragging"
        case .resizing: return "resizing"
        case .armed: return "armed"
        case .highlighting(_, let target): return "highlighting:\(describe(target))"
        }
    }

    private func trace(
        _ event: String,
        fields: [String: String],
        sample: [String: String] = [:],
        changedOnly: Bool = false
    ) {
        guard diagnosticActive, let diagnosticSessionID else { return }
        let key = event + (fields["stage"] ?? "")
        if changedOnly {
            guard diagnosticStates[key] != fields else { return }
            diagnosticStates[key] = fields
        }
        var values = fields
        values["eventIndex"] = "\(diagnosticEventIndex)"
        values["input"] = diagnosticInput
        values["source"] = diagnosticSource
        values["eventPoint"] = Self.describe(diagnosticPoint)
        values.merge(sample) { _, new in new }
        Log.snapDiagnostics.record(event, sessionID: diagnosticSessionID, fields: values)
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
                let diagnosticID = diagnosticActive ? diagnosticSessionID : nil
                let writeID = UUID().uuidString
                let requestedAt = ProcessInfo.processInfo.systemUptime
                trace("frame.request", fields: [
                    "writeID": writeID,
                    "requested": Self.describe(rect),
                    "windowPID": "\(identity.pid)",
                    "windowNumber": "\(identity.windowNumber)",
                    "layout": pending?.layoutID.uuidString ?? "nil",
                    "generation": "\(generation)",
                    "mutationSession": snapWriteSession.uuidString,
                ])
                outstandingSnapWrites += 1
                Task { @MainActor in
                    defer { self.finishSnapWrite() }
                    let resolved = await self.resolveWindowForApply(
                        captured: captured,
                        identity: identity
                    )
                    let appliedFrame: CGRect? = if let resolved {
                        await runtime.applyFrame(rect, of: resolved, sessionID: self.snapWriteSession, generation: generation)
                    } else {
                        nil
                    }
                    let applied = appliedFrame != nil
                    if let diagnosticID {
                        Log.snapDiagnostics.record("frame.result", sessionID: diagnosticID, fields: [
                            "writeID": writeID,
                            "requested": Self.describe(rect),
                            "returned": Self.describe(appliedFrame),
                            "windowResolved": "\(resolved != nil)",
                            "returnedFrame": "\(applied)",
                            "errorPoints": Self.frameError(appliedFrame, requested: rect),
                            "elapsedMs": "\(Int((ProcessInfo.processInfo.systemUptime - requestedAt) * 1000))",
                            "generation": "\(generation)",
                            "currentGeneration": "\(self.layoutAssignmentGeneration)",
                        ])
                        self.verifyDiagnosticFrame(rect, identity: identity, sessionID: diagnosticID, writeID: writeID)
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
                            generation: generation,
                            diagnosticID: diagnosticID,
                            writeID: writeID
                        )
                    }
                }
            case .recordUnsnap(let record):
                let area = DisplayTargetResolver.workArea(
                    containingWindowFrameAX: record.snappedFrameAX,
                    from: runtime.workAreas,
                    primaryFlipHeight: runtime.primaryFlipHeight
                )
                runtime.catalog.record(record, displayID: area?.display.id)
                runtime.noteUserSnapCompleted()
                runtime.refreshDivider()
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
               trace("layout.select", fields: ["layout": layoutID.uuidString, "stripSuppressed": "true"])
               sessionLayoutID = layoutID
               stripWindowLayoutID = layoutID
               stripOverflowLatch = nil
               stripDropLatch = nil
               stripLatchHistory = StripDropLatchHistory()
                suppressStripLatch = true
           }
        }
        if hideOverlay {
            trace("preview.hide", fields: [:])
            runtime.overlay.hideSessionOverlay()
            runtime.refreshDivider()
            return
        }
        if let overlayDisplayID {
            runtime.closeConsole()
            runtime.overlay.settings = runtime.settings
            runtime.overlay.primaryFlipHeight = runtime.primaryFlipHeight
            let zones = lastZones
            // Re-entering sessionContext here used live mouse location and
            // mutated the strip latch a second time, so the overlay could
            // show the new layout's panes with the previous card's highlight.
            let highlight = SnapLayoutSession.previewHighlight(
                overlayHighlight ?? .none,
                zones: zones,
                latch: stripDropLatch
            )
            runtime.overlay.show(
                displayID: overlayDisplayID,
                zones: zones,
                highlight: highlight,
                presentation: lastPresentation
            )
            if diagnosticActive {
                let stripModel = lastPresentation.strip
                if let geometry = stripModel?.geometry, geometry != diagnosticGeometry {
                    diagnosticGeometry = geometry
                    trace("strip.geometry", fields: [
                        "display": overlayDisplayID.uuidString,
                        "stripFrame": Self.describe(geometry.frameAppKit),
                        "cards": geometry.cards.map { card in
                            "\(card.layoutID.uuidString):\(Self.describe(card.frameAppKit)):["
                                + card.zones.map { "\($0.number)=\(Self.describe($0.frameAppKit))" }.joined(separator: ";") + "]"
                        }.joined(separator: "|"),
                    ])
                }
                trace("preview.show", fields: [
                    "display": overlayDisplayID.uuidString,
                    "layout": (stripDropLatch?.layoutID ?? sessionLayoutID)?.uuidString ?? "nil",
                    "highlight": Self.describe(highlight),
                    "highlightFrame": Self.describe(highlight.frameAX),
                    "stripLayout": stripModel?.highlightedLayoutID?.uuidString ?? "nil",
                    "stripZone": stripModel?.highlightedZoneNumber.map(String.init) ?? "nil",
                ], changedOnly: true)
            }
            runtime.refreshDivider()
        } else if let overlayHighlight {
            runtime.overlay.highlight(overlayHighlight)
        }
    }

    private func resetLayoutSession() {
        sessionLayoutID = nil
        lastCursorDisplayID = nil
        lastStrip = nil
        stripWindowLayoutID = nil
        stripWindowStartID = nil
       stripOverflowLatch = nil
       stripDropLatch = nil
       stripLatchHistory = StripDropLatchHistory()
        suppressStripLatch = false
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

    private func commit(
        _ pending: PendingLayoutAssignment,
        generation: Int,
        diagnosticID: UUID? = nil,
        writeID: String? = nil
    ) {
        var outcome = "stale-generation"
        var displayID: UUID?
        defer {
            if let diagnosticID {
                Log.snapDiagnostics.record("layout.commit", sessionID: diagnosticID, fields: [
                    "writeID": writeID ?? "nil",
                    "layout": pending.layoutID.uuidString,
                    "display": displayID?.uuidString ?? "nil",
                    "point": Self.describe(pending.pointAppKit),
                    "generation": "\(generation)",
                    "currentGeneration": "\(layoutAssignmentGeneration)",
                    "outcome": outcome,
                ])
            }
        }
        guard SnapLayoutAssignmentPolicy.shouldUpdateSession(
            completionGeneration: generation,
            currentGeneration: layoutAssignmentGeneration
        ) else { return }
        pendingLayoutAssignment = nil
        let area = runtime.area(containingAppKit: pending.pointAppKit)
            ?? runtime.workAreas.first
        outcome = "no-display"
        guard let area else { return }
        displayID = area.display.id
        runtime.document.assign(layoutID: pending.layoutID, to: area.display.id)
        runtime.markLayoutUsed(pending.layoutID)
        runtime.persist()
        runtime.reloadMenu()
        sessionLayoutID = pending.layoutID
        outcome = "assigned"
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
        committingStripSelection: Bool = false,
        diagnosticStage: String = "event"
    ) -> SessionContext {
        let previousLatch = stripDropLatch
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
            stripWindowLayoutID = nil
            stripWindowStartID = nil
           stripOverflowLatch = nil
           stripDropLatch = nil
           stripLatchHistory = StripDropLatchHistory()
            suppressStripLatch = false
       } else if lastCursorDisplayID == nil {
           lastCursorDisplayID = area?.display.id
       }

        let layouts = runtime.allResolvedLayouts(for: area)
        let layoutIDs = layouts.map(\.layout.id)

        var strip: LayoutStripGeometry?
        var pointerInStrip = false
        var pointerOnStrip = false
        var forcedTarget: SnapTarget?
        var highlightedLayoutID: Layout.ID?
        var highlightedZoneNumber: Int?
        var hoveredOverflow: LayoutStripOverflowHover?
        var hitLatch: StripDropLatch?
        if !isArmed(phase) {
            stripDropLatch = nil
            stripLatchHistory = StripDropLatchHistory()
        }
        if runtime.settings.showLayoutStrip, let area, isArmed(phase) {
            let workAX = CoordinateConverter.axRect(
                fromAppKit: area.visibleFrameAppKit,
                primaryFlipHeight: runtime.primaryFlipHeight
            )
            strip = LayoutStripGeometry.make(
                workAreaAppKit: area.visibleFrameAppKit,
                layouts: layouts,
                assignedLayoutID: assignedID,
                workAreaAX: workAX,
                focusedLayoutID: stripWindowLayoutID ?? sessionLayoutID ?? assignedID,
                previousStartLayoutID: stripWindowStartID
            )
            stripWindowStartID = strip?.cards.first?.layoutID
            if var visibleStrip = strip, visibleStrip.containsDropLinger(pointAppKit) {
                pointerOnStrip = visibleStrip.contains(pointAppKit)
                pointerInStrip = true
                let probePoint = visibleStrip.dropProbePoint(
                    for: pointAppKit,
                    preservingLayoutID: stripDropLatch?.layoutID,
                    zoneNumber: stripDropLatch?.zone.number
                )
                let overflowDelta = pointerOnStrip ? visibleStrip.hitOverflow(at: pointAppKit) : nil
                if let overflowDelta {
                    hoveredOverflow = overflowDelta > 0 ? .next : .previous
                    let visibleIDs = visibleStrip.cards.map { $0.layoutID }
                    let edgeID = overflowDelta > 0 ? visibleIDs.last : visibleIDs.first
                    let neighborID = LayoutStripGeometry.neighborLayoutID(of: edgeID, in: layoutIDs, delta: overflowDelta)
                    if let neighborID, stripOverflowLatch != overflowDelta {
                        stripOverflowLatch = overflowDelta
                        stripWindowLayoutID = neighborID
                        visibleStrip = LayoutStripGeometry.make(
                            workAreaAppKit: area.visibleFrameAppKit,
                            layouts: layouts,
                            assignedLayoutID: assignedID,
                            workAreaAX: workAX,
                            focusedLayoutID: neighborID,
                            previousStartLayoutID: visibleStrip.cards.first?.layoutID
                        )
                    }
                    if let revealed = overflowDelta > 0 ? visibleStrip.cards.last : visibleStrip.cards.first {
                        highlightedLayoutID = revealed.layoutID
                    }
                } else {
                    stripOverflowLatch = nil
                    let hitPoint = pointerOnStrip ? pointAppKit : probePoint
                    if let hit = visibleStrip.hitZone(at: hitPoint),
                       let layout = layouts.first(where: { $0.layout.id == hit.layoutID }),
                       let zone = layout.zones.first(where: { $0.number == hit.zoneNumber }) {
                        hitLatch = StripDropLatch(layoutID: hit.layoutID, zone: zone)
                    } else {
                        highlightedLayoutID = SnapLayoutSession.acceptedHighlight(
                            pointerOnStrip: pointerOnStrip,
                            hitCard: visibleStrip.hitCard(at: pointerOnStrip ? pointAppKit : probePoint)
                        )
                    }
                }
                strip = visibleStrip
                stripWindowStartID = visibleStrip.cards.first?.layoutID
            } else {
                stripOverflowLatch = nil
            }
        } else {
            stripOverflowLatch = nil
        }

        let rawHit = hitLatch
        let gate = SnapLayoutSession.acceptingStripHit(
            suppressStripLatch: suppressStripLatch,
            pointerInStrip: pointerInStrip
        )
        suppressStripLatch = gate.suppressStripLatch
        if !gate.acceptHit {
            hitLatch = nil
            highlightedLayoutID = nil
            highlightedZoneNumber = nil
        }
        hitLatch = SnapLayoutSession.acceptedStripHit(
            hit: hitLatch,
            previous: stripDropLatch,
            pointerOnStrip: pointerOnStrip
        )
        // Releasing a drag nudges the cursor a few points, which used to
        // re-hit-test onto the neighboring mini-zone. On the commit frame keep
        // whatever the drag already latched (what the user saw highlighted)
        // instead of letting release jitter switch columns.
        if committingStripSelection, stripDropLatch != nil {
            hitLatch = nil
        }

        let liveZone: ResolvedZone?
        if let previous = stripDropLatch,
           let layout = layouts.first(where: { $0.layout.id == previous.layoutID }) {
            let pointAX = CoordinateConverter.axPoint(
                fromAppKit: pointAppKit,
                primaryFlipHeight: runtime.primaryFlipHeight
            )
            if case .zone(let zone) = HitTester(policy: runtime.settings.overlapPolicy).target(
                at: pointAX,
                zones: layout.zones
            ) {
                liveZone = zone
            } else {
                liveZone = nil
            }
        } else {
            liveZone = nil
        }
        let frameLatch = SnapLayoutSession.stripDropLatch(
            pointerInStrip: pointerInStrip,
            hit: hitLatch,
            previous: stripDropLatch,
            liveZoneInLatchedLayout: liveZone,
            lingerNearStrip: strip?.containsDropLinger(pointAppKit) == true
        )
        let clock = now()
        let historyBeforeUpdate = stripLatchHistory
        if committingStripSelection {
            let beforeCommit = stripLatchHistory
            stripDropLatch = stripLatchHistory.committed(candidate: frameLatch, at: clock)
            Log.snap.debug(
                "StripDrop commit onStrip=\(pointerOnStrip, privacy: .public) linger=\(strip?.containsDropLinger(pointAppKit) == true, privacy: .public) frame=\(Self.describe(frameLatch), privacy: .public) held=\(Int((clock - beforeCommit.currentSince) * 1000), privacy: .public)ms settled=\(Self.describe(beforeCommit.settled), privacy: .public) settledEnded=\(beforeCommit.settledEndedAt.map { Int((clock - $0) * 1000) } ?? -1, privacy: .public)ms -> \(Self.describe(self.stripDropLatch), privacy: .public) pt=(\(Int(pointAppKit.x)),\(Int(pointAppKit.y)))"
            )
        } else {
            stripDropLatch = frameLatch
            stripLatchHistory.record(frameLatch, at: clock)
        }
        trace(committingStripSelection ? "strip.commit" : "strip.target", fields: [
            "stage": diagnosticStage,
            "display": area?.display.id.uuidString ?? "nil",
            "onStrip": "\(pointerOnStrip)",
            "inLinger": "\(pointerInStrip)",
            "suppressed": "\(suppressStripLatch)",
            "rawHit": Self.describe(rawHit),
            "acceptedHit": Self.describe(hitLatch),
            "previous": Self.describe(previousLatch),
            "liveZone": liveZone.map { "\($0.number)" } ?? "nil",
            "candidate": Self.describe(frameLatch),
            "selected": Self.describe(stripDropLatch),
            "settled": Self.describe(historyBeforeUpdate.settled),
            "releaseRetargeted": "\(committingStripSelection && stripDropLatch != frameLatch)",
        ], sample: [
            "point": Self.describe(pointAppKit),
            "heldMs": historyBeforeUpdate.current.map { _ in "\(Int((clock - historyBeforeUpdate.currentSince) * 1000))" } ?? "nil",
            "settledAgeMs": historyBeforeUpdate.settledEndedAt.map { "\(Int((clock - $0) * 1000))" } ?? "nil",
        ], changedOnly: !committingStripSelection)
        if let latch = stripDropLatch {
            forcedTarget = .zone(latch.zone)
            highlightedLayoutID = latch.layoutID
            highlightedZoneNumber = latch.zone.number
        }

        sessionLayoutID = SnapLayoutSession.sessionLayoutIDForPointer(
            forcedLayoutID: stripDropLatch?.layoutID,
            currentSessionLayoutID: sessionLayoutID,
            assignedLayoutID: assignedID,
            lockedTarget: lockedTarget,
            preferForcedLayout: committingStripSelection
        )

        let layoutID = stripDropLatch?.layoutID ?? highlightedLayoutID ?? sessionLayoutID ?? assignedID
        let zones = runtime.resolvedZones(for: area, layoutOverride: layoutID)
        let stripModel: OverlayStripRenderModel?
        if let strip, runtime.settings.showLayoutStrip {
            stripModel = OverlayStripRenderModel(
                geometry: strip,
                highlightedLayoutID: highlightedLayoutID ?? layoutID,
                highlightedZoneNumber: highlightedZoneNumber,
                hoveredOverflow: hoveredOverflow
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

    private static func frameError(_ actual: CGRect?, requested: CGRect) -> String {
        guard let actual else { return "nil" }
        return "\(max(abs(actual.minX - requested.minX), abs(actual.minY - requested.minY), abs(actual.width - requested.width), abs(actual.height - requested.height)))"
    }

    /// Mouse-up often arrives before AX re-lists the dragged window. Keep the
    /// already captured element when we have it, then retry matching once.
    private func resolveWindowForApply(captured: AXWindow?, identity: WindowIdentity) async -> AXWindow? {
        if let captured, captured.identity == identity { return captured }
        if let window = await runtime.ax.window(matching: identity) { return window }
        try? await Task.sleep(nanoseconds: 50_000_000)
        return await runtime.ax.window(matching: identity)
    }

    /// A later OS/app adjustment can overwrite a successful AX write. Read CG
    /// once after settling; never retry a write or inspect window contents.
    private func verifyDiagnosticFrame(_ requested: CGRect, identity: WindowIdentity, sessionID: UUID, writeID: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard self.diagnosticSessionID == sessionID else {
                Log.snapDiagnostics.record("frame.verify", sessionID: sessionID, fields: [
                    "writeID": writeID, "skipped": "new-drag",
                ])
                return
            }
            let actual = CGWindowQuery().frameAX(ofWindow: identity.windowNumber)
            Log.snapDiagnostics.record("frame.verify", sessionID: sessionID, fields: [
                "writeID": writeID,
                "requested": Self.describe(requested),
                "observed": Self.describe(actual),
                "errorPoints": Self.frameError(actual, requested: requested),
                "delayMs": "300",
            ])
        }
    }
}
