import AppKit
import ZoneBoxCore

@MainActor
final class DividerController {
    unowned var runtime: AppRuntime!

    private var panels: [UUID: [DividerPanel]] = [:]
    private var views: [UUID: [DividerOverlayView]] = [:]
    private var handlesByDisplay: [UUID: [DividerHandleSpec]] = [:]
    private var refreshTimer: Timer?
    private var drag: DragState?
    private var windowResolutionTask: Task<Void, Never>?
    private var writeTask: Task<Void, Never>?
    private var writeTaskID: UUID?
    private var latestDragLayout: Layout?
    private var committing = false
    private let query = CGWindowQuery()
    private var dragMonitors: [Any] = []

    var isDragging: Bool { drag != nil }

    func start() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refresh()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        resetDrag()
        hidePanels()
        for panel in panels.values.flatMap({ $0 }) {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        views.removeAll()
        handlesByDisplay.removeAll()
    }

    func rebuild(workAreas: [WorkArea], screens: [NSScreen]) {
        _ = workAreas
        _ = screens
        resetDrag()
        hidePanels()
        for panel in panels.values.flatMap({ $0 }) {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        views.removeAll()
        handlesByDisplay.removeAll()

        refresh()
    }

    func hideAll() {
        resetDrag()
        hidePanels()
    }

    func refresh() {
        guard !isDragging else { return }
        guard runtime.trust.isTrusted(),
              !runtime.isEditorOpen,
              !runtime.isOrganizingWindows,
              !runtime.engine.isSessionActive
        else {
            hidePanels()
            return
        }

        let flip = runtime.displays.primaryFlipHeight
        var nextHandles: [UUID: [DividerHandleSpec]] = [:]
        var activeDisplayIDs = Set<UUID>()
        for area in runtime.displays.workAreas {
            activeDisplayIDs.insert(area.display.id)
            let handles = handles(for: area)
            nextHandles[area.display.id] = handles
            present(handles, on: area.display.id, primaryFlipHeight: flip)
        }
        for displayID in panels.keys where !activeDisplayIDs.contains(displayID) {
            hidePanels(on: displayID)
        }
        handlesByDisplay = nextHandles
    }

    func consumesPoint(_ pointAppKit: CGPoint) -> Bool {
        if isDragging { return true }
        let flip = runtime.displays.primaryFlipHeight
        for (displayID, handles) in handlesByDisplay {
            guard panels[displayID]?.contains(where: { $0.isVisible }) == true else { continue }
            if handles.contains(where: { DividerPlan.hitRect(for: $0, primaryFlipHeight: flip).contains(pointAppKit) }) {
                return true
            }
        }
        return false
    }

    func cancelDrag() {
        resetDrag()
        refresh()
    }

    private func hidePanels() {
        for panel in panels.values.flatMap({ $0 }) where panel.isVisible {
            panel.orderOut(nil)
        }
        for view in views.values.flatMap({ $0 }) {
            view.handles = []
            view.highlightedIndex = nil
        }
        handlesByDisplay.removeAll()
    }

    private func resetDrag() {
        removeDragMonitors()
        windowResolutionTask?.cancel()
        windowResolutionTask = nil
        writeTask?.cancel()
        writeTask = nil
        writeTaskID = nil
        latestDragLayout = nil
        drag = nil
        committing = false
        for view in views.values.flatMap({ $0 }) {
            view.resetInteraction()
        }
    }

    private func handles(for area: WorkArea) -> [DividerHandleSpec] {
        guard let layout = runtime.document.layout(for: area.display.id) else {
            return []
        }
        let workAX = CoordinateConverter.axRect(
            fromAppKit: area.visibleFrameAppKit,
            primaryFlipHeight: runtime.displays.primaryFlipHeight
        )
        let resolved = runtime.resolvedZones(for: area)
        let targetFrames = Dictionary(uniqueKeysWithValues: resolved.map { ($0.zoneID, $0.frameAX) })
        var windows: [(identity: WindowIdentity, frameAX: CGRect)] = []
        var seen = Set<WindowIdentity>()
        let excluded = Set(runtime.settings.excludedBundleIDs)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let preferred = Dictionary(
            uniqueKeysWithValues: runtime.catalog.snappedMemberships(on: area.display.id)
        )
        for ref in query.windows(excludingPID: ownPID) where ref.layer == 0 {
            guard !seen.contains(ref.identity) else { continue }
            if let bundleID = ref.bundleID, excluded.contains(bundleID) { continue }
            guard ref.alpha >= 0.15 else { continue }
            windows.append((ref.identity, ref.boundsAX))
            seen.insert(ref.identity)
        }
        let occupancy = DividerPlan.occupancy(
            resolvedFrames: targetFrames,
            windows: windows,
            preferred: preferred,
            workAreaAX: workAX
        )
        var displayFrames = targetFrames
        for window in windows {
            if let zoneID = occupancy.first(where: { $0.value.contains(window.identity) })?.key {
                let clipped = window.frameAX.intersection(workAX)
                displayFrames[zoneID] = clipped.isNull || clipped.isInfinite ? window.frameAX : clipped
            }
        }
        let handles = DividerPlan.handles(
            layout: layout,
            workAreaAX: workAX,
            resolvedFrames: displayFrames,
            snapped: occupancy
        )
        if handles.isEmpty {
            Log.divider.debug(
                "Divider hidden display=\(area.display.id.uuidString, privacy: .public) kind=\(String(describing: layout.kind), privacy: .public) windows=\(windows.count, privacy: .public) occupied=\(occupancy.count, privacy: .public) preferred=\(preferred.count, privacy: .public)"
            )
        } else {
            Log.divider.debug(
                "Divider visible display=\(area.display.id.uuidString, privacy: .public) handles=\(handles.count, privacy: .public) occupied=\(occupancy.count, privacy: .public)"
            )
        }
        return handles
    }

    private func beginDrag(
        displayID: UUID,
        handle: DividerHandleSpec,
        panel: DividerPanel,
        view: DividerOverlayView
    ) {
        guard drag == nil else { return }
        guard let area = runtime.displays.workAreas.first(where: { $0.display.id == displayID }),
              let layout = runtime.document.layout(for: displayID)
        else { return }
        let workAX = CoordinateConverter.axRect(
            fromAppKit: area.visibleFrameAppKit,
            primaryFlipHeight: runtime.displays.primaryFlipHeight
        )
        let dragID = UUID()
        drag = DragState(
            id: dragID,
            displayID: displayID,
            handle: handle,
            panel: panel,
            view: view,
            baseLayout: layout,
            latestLayout: layout,
            workAreaAX: workAX,
            windows: [:]
        )
        latestDragLayout = layout
        Log.divider.info("Divider drag began display=\(displayID.uuidString, privacy: .public) axis=\(String(describing: handle.axis), privacy: .public) after=\(handle.afterIndex, privacy: .public)")
        installDragMonitors()
        windowResolutionTask = Task { @MainActor [weak self] in
            await self?.resolveWindows(for: handle, displayID: displayID, dragID: dragID)
        }
    }


    private func installDragMonitors() {
        removeDragMonitors()
        let kinds: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { [weak self] event in
            self?.handleDragEvent(event)
            return event
        }) {
            dragMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] event in
            self?.handleDragEvent(event)
        }) {
            dragMonitors.append(global)
        }
    }

    private func removeDragMonitors() {
        for monitor in dragMonitors {
            NSEvent.removeMonitor(monitor)
        }
        dragMonitors.removeAll()
    }

    private func handleDragEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            updateDrag(locationAppKit: NSEvent.mouseLocation)
        case .leftMouseUp:
            commitDrag()
        default:
            break
        }
    }

    private func resolveWindows(for handle: DividerHandleSpec, displayID: UUID, dragID: UUID) async {
        guard drag?.id == dragID,
              drag?.displayID == displayID,
              drag?.handle.axis == handle.axis,
              drag?.handle.afterIndex == handle.afterIndex
        else { return }
        var windows: [WindowIdentity: AXWindow] = [:]
        for slot in handle.slots {
            guard !Task.isCancelled else { return }
            if let window = await runtime.ax.window(matching: slot.identity) {
                windows[slot.identity] = window
            }
        }
        guard !Task.isCancelled, drag?.id == dragID else { return }
        guard windows.count == handle.slots.count else {
            cancelDrag()
            return
        }
        drag?.windows = windows
        if let latest = latestDragLayout {
            enqueueWrite(latest)
        }
    }

    private func updateDrag(locationAppKit: NSPoint) {
        guard var current = drag else { return }
        let pointAX = CoordinateConverter.axPoint(
            fromAppKit: locationAppKit,
            primaryFlipHeight: runtime.displays.primaryFlipHeight
        )
        guard let t = DividerPlan.normalizedPosition(
            of: pointAX,
            axis: current.handle.axis,
            in: current.workAreaAX
        ) else { return }
        guard let next = DividerPlan.movedLayout(
            current.baseLayout,
            handle: current.handle,
            toNormalized: t
        ) else { return }
        current.latestLayout = next
        drag = current
        enqueueWrite(next)
    }

    private func previewHandle(from current: DragState) {
        var frames: [UUID: CGRect] = [:]
        var snapped: [UUID: [WindowIdentity]] = [:]
        for slot in current.handle.slots {
            let actual = query.frameAX(ofWindow: slot.identity.windowNumber)
            frames[slot.zoneID] = actual
            snapped[slot.zoneID] = [slot.identity]
        }
        let nextHandles = DividerPlan.handles(
            layout: current.latestLayout,
            workAreaAX: current.workAreaAX,
            resolvedFrames: frames,
            snapped: snapped
        )
        if let nextHandle = nextHandles.first(where: {
            $0.matches(current.handle)
        }) {
            let hitRect = DividerPlan.hitRect(
                for: nextHandle,
                primaryFlipHeight: runtime.displays.primaryFlipHeight
            )
            current.panel.setFrame(hitRect, display: true)
            current.view.handles = [nextHandle]
            current.view.highlightedIndex = 0
            if var live = drag {
                live.handle = nextHandle
                drag = live
            }
            if let index = handlesByDisplay[current.displayID]?.firstIndex(where: {
                $0.matches(nextHandle)
            }) {
                handlesByDisplay[current.displayID]?[index] = nextHandle
            }
        }
        current.view.needsDisplay = true
    }

    private func enqueueWrite(_ layout: Layout) {
        latestDragLayout = layout
        guard writeTask == nil else { return }
        guard let dragID = drag?.id else { return }
        let taskID = UUID()
        writeTaskID = taskID
        writeTask = Task { @MainActor [weak self] in
            await self?.drainWrites(dragID: dragID, taskID: taskID)
        }
    }

    private func drainWrites(dragID: UUID, taskID: UUID) async {
        while !Task.isCancelled {
            guard let current = drag, current.id == dragID, let layout = latestDragLayout else { break }
            guard !current.windows.isEmpty else { break }
            latestDragLayout = nil
            let resolved = (try? resolveLayout(
                layout,
                workAreaAX: current.workAreaAX,
                gutter: CGFloat(runtime.settings.gutterPoints)
            )) ?? []
            let frames = Dictionary(uniqueKeysWithValues: resolved.map { ($0.zoneID, $0.frameAX) })
            for slot in current.handle.slots {
                guard let window = current.windows[slot.identity],
                      let frame = frames[slot.zoneID]
                else { continue }
                _ = await runtime.ax.setFrame(frame, of: window)
            }
            guard !Task.isCancelled, let latest = drag, latest.id == dragID else { break }
            previewHandle(from: latest)
            if latestDragLayout.map({ !DividerPlan.geometryChanged(from: layout, to: $0) }) == true {
                latestDragLayout = nil
            }
            if latestDragLayout == nil {
                break
            }
        }
        guard writeTaskID == taskID else { return }
        writeTask = nil
        writeTaskID = nil
        if let leftover = latestDragLayout, drag?.id == dragID {
            enqueueWrite(leftover)
        }
    }

    private func commitDrag() {
        guard drag != nil, !committing else { return }
        committing = true
        removeDragMonitors()
        Task { @MainActor [weak self] in
            await self?.finishCommit()
        }
    }

    private func finishCommit() async {
        defer { committing = false }
        let resolving = windowResolutionTask
        await resolving?.value
        windowResolutionTask = nil
        guard let pending = drag else { return }
        enqueueWrite(pending.latestLayout)
        while let inflight = writeTask {
            await inflight.value
        }
        guard let current = drag else { return }
        let finalLayout = current.latestLayout
        if DividerPlan.geometryChanged(from: current.baseLayout, to: finalLayout) {
            _ = runtime.saveLayout(finalLayout, to: current.displayID)
            Log.divider.info("Divider committed display=\(current.displayID.uuidString, privacy: .public)")
        }
        let resolved = (try? resolveLayout(
            finalLayout,
            workAreaAX: current.workAreaAX,
            gutter: CGFloat(runtime.settings.gutterPoints)
        )) ?? []
        let frames = Dictionary(uniqueKeysWithValues: resolved.map { ($0.zoneID, $0.frameAX) })
        for slot in current.handle.slots {
            let actual: CGRect?
            if let window = current.windows[slot.identity] {
                actual = await runtime.ax.frame(of: window)
            } else {
                actual = query.frameAX(ofWindow: slot.identity.windowNumber)
            }
            let frame = actual ?? frames[slot.zoneID] ?? .zero
            runtime.catalog.updateSnappedFrame(
                frame,
                for: slot.identity,
                zoneID: slot.zoneID,
                displayID: current.displayID
            )
        }
        drag = nil
        latestDragLayout = nil
        writeTask = nil
        writeTaskID = nil
        current.view.resetInteraction()
        refresh()
    }

    private func present(
        _ handles: [DividerHandleSpec],
        on displayID: UUID,
        primaryFlipHeight: CGFloat
    ) {
        ensurePresentationSlots(for: displayID, count: handles.count)
        guard let displayPanels = panels[displayID], let displayViews = views[displayID] else { return }
        for index in displayPanels.indices {
            let panel = displayPanels[index]
            let view = displayViews[index]
            guard handles.indices.contains(index) else {
                view.handles = []
                panel.orderOut(nil)
                continue
            }
            let handle = handles[index]
            let hitRect = DividerPlan.hitRect(for: handle, primaryFlipHeight: primaryFlipHeight)
            panel.setFrame(hitRect, display: true)
            view.primaryFlipHeight = primaryFlipHeight
            view.handles = [handle]
            view.highlightedIndex = nil
            panel.orderFrontRegardless()
            view.displayIfNeeded()
        }
    }

    private func ensurePresentationSlots(for displayID: UUID, count: Int) {
        var displayPanels = panels[displayID] ?? []
        var displayViews = views[displayID] ?? []
        while displayPanels.count < count {
            let panel = DividerPanel(frame: NSRect(x: -64, y: -64, width: 1, height: 1))
            let view = DividerOverlayView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            view.autoresizingMask = [.width, .height]
            view.onBeginDrag = { [weak self, weak panel, weak view] handle in
                guard let panel, let view else { return }
                self?.beginDrag(displayID: displayID, handle: handle, panel: panel, view: view)
            }
            view.onDrag = { [weak self] location in
                self?.updateDrag(locationAppKit: location)
            }
            view.onEndDrag = { [weak self] in
                self?.commitDrag()
            }
            view.onCancelDrag = { [weak self] in
                self?.cancelDrag()
            }
            panel.contentView = view
            displayPanels.append(panel)
            displayViews.append(view)
        }
        panels[displayID] = displayPanels
        views[displayID] = displayViews
    }

    private func hidePanels(on displayID: UUID) {
        for panel in panels[displayID] ?? [] {
            panel.orderOut(nil)
        }
        for view in views[displayID] ?? [] {
            view.handles = []
            view.highlightedIndex = nil
        }
    }
}

private struct DragState {
    var id: UUID
    var displayID: UUID
    var handle: DividerHandleSpec
    var panel: DividerPanel
    var view: DividerOverlayView
    var baseLayout: Layout
    var latestLayout: Layout
    var workAreaAX: CGRect
    var windows: [WindowIdentity: AXWindow]
}
