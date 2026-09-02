import AppKit
import ZoneBoxCore

final class LayoutEditorCanvasView: NSView {
    var layout: Layout {
        didSet {
            pruneSelection()
            needsDisplay = true
        }
    }
    var primaryFlipHeight: CGFloat
    var workAreaAX: CGRect
    private var selection: Set<UUID> = []
    private var primaryID: UUID?
    var selectedID: UUID? {
        get { primaryID }
        set {
            let old = primaryID
            primaryID = newValue
            selection = newValue.map { [$0] } ?? []
            needsDisplay = true
            if old != primaryID {
                onSelectionChange?()
            }
        }
    }
    var selectedIDs: Set<UUID> { selection }
    var onChange: ((Layout) -> Void)?
    var onPreview: ((Layout) -> Void)?
    var onInteractionBegin: (() -> Void)?
    var onCancel: (() -> Void)?
    var onInteractionChange: ((Bool) -> Void)?
    var onSelectionChange: (() -> Void)?
    var onMenuWillOpen: (() -> Void)?
    var onMenuDidClose: (() -> Void)?
    var lockAspect = false
    var gutterPoints: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var showZoneNumbers = true {
        didSet { needsDisplay = true }
    }
    /// Floating editor chrome sits above the canvas but is click-through.
    /// Pointers over that chrome, or a zone's delete control, should not
    /// show a grid split preview.
    var chromeView: NSView?
    var additionalChromeViews: [NSView] = []

    private enum DragKind {
        case create(start: CGPoint)
        case move(id: UUID, startRect: NormalizedRect, start: CGPoint, clones: Bool)
        case resize(id: UUID, startRect: NormalizedRect, start: CGPoint, handle: Handle)
        case split(
            axis: SplitAxis,
            firstID: UUID,
            firstRect: NormalizedRect,
            secondID: UUID,
            secondRect: NormalizedRect,
            start: CGPoint
        )
        case gridLine(axis: GridAxis, afterIndex: Int)
        case gridMerge(start: CGPoint, normalizedStart: (x: Double, y: Double))
        case close
        case marquee(start: CGPoint)
    }

    private enum Handle: CaseIterable, Equatable {
        case n, s, e, w, ne, nw, se, sw
    }

    private enum SplitAxis: Equatable {
        /// Vertical divider; drag left/right (◀▶).
        case resizeWidth
        /// Horizontal divider; drag up/down (▲▼).
        case resizeHeight
        /// NE / SW corners; drag along ↗↙.
        case resizeDiagonalNESW
        /// NW / SE corners; drag along ↖↘.
        case resizeDiagonalNWSE
    }

    private struct EdgeInteraction: Equatable {
        var axis: SplitAxis
        var grabber: CGPoint
        var seamStart: CGPoint
        var seamEnd: CGPoint
        var primaryID: UUID
        var primaryHandle: Handle
        var neighborID: UUID?
        var neighborHandle: Handle?

        var isLinked: Bool { neighborID != nil }
    }

    private var drag: DragKind?
    private var hoverEdge: EdgeInteraction?
    private var hoverSplit: (axis: GridAxis, x: Double, y: Double, zoneID: UUID)?
    private var mergeIDs: Set<UUID> = []
    private var pointerOverChrome = false
    private var lastCycle: (forward: Bool, time: TimeInterval)?
    private var lastPaneMove: (direction: Layout.ArrowDirection, time: TimeInterval)?
    private var ghostRect: NormalizedRect?
    private var snapHits: (x: [Double], y: [Double]) = ([], [])
    private var snapCandidates = CanvasSnapCandidates(x: [0, 0.5, 1], y: [0, 0.5, 1])
    private var creatingID: UUID?
    private var nudgeInteractionStarted = false
    private var nudgeFinishWorkItem: DispatchWorkItem?
    private let closeButtonSize: CGFloat = 22
    private let closeButtonInset: CGFloat = 8
    private let edgeSlop: CGFloat = 12
    /// Wider than a single-edge hit so the always-visible linked sash is easy to grab.
    private let linkedEdgeSlop: CGFloat = 20
    private let gridSplitLineSlop: CGFloat = 6
    private let minSeamOverlap: CGFloat = 36
    private let cornerClearance: CGFloat = 18
    private let cornerSlop: CGFloat = 18
    private let cornerOutset: CGFloat = 10
    /// Empty pointer so the on-canvas grabber is the only capsule. Recent macOS
    /// resize cursors are themselves a pill and would stack on top of ours.
    private static let hiddenCursor: NSCursor = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.set()
            rect.fill(using: .copy)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    init(layout: Layout, workAreaAX: CGRect, primaryFlipHeight: CGFloat) {
        self.layout = layout
        self.workAreaAX = workAreaAX
        self.primaryFlipHeight = primaryFlipHeight
        super.init(frame: .zero)
        wantsLayer = true
        ensureCanvas()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        refreshHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard drag == nil else { return }
        hoverEdge = nil
        hoverSplit = nil
        pointerOverChrome = false
        ghostRect = nil
        snapHits = ([], [])
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func cursorUpdate(with event: NSEvent) {
        applyCursor()
    }

    override func flagsChanged(with event: NSEvent) {
        if drag == nil, let window {
            refreshHover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        super.flagsChanged(with: event)
    }

    func noteChromeMoved() {
        guard drag == nil, let window else { return }
        refreshHover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()

        let zones = layout.zones.sorted(by: { $0.number < $1.number })
        let displayedRects = gutteredCanvasRects()
        for zone in zones {
            let rect = viewRect(for: displayedRects[zone.id] ?? canvasRect(of: zone))
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
            let selected = selection.contains(zone.id)
            let body = rect.insetBy(dx: 3, dy: 3)
            NSColor.systemBlue.withAlphaComponent(selected ? (zone.id == primaryID ? 0.38 : 0.28) : 0.18).setFill()
            let path = NSBezierPath(roundedRect: body, xRadius: 8, yRadius: 8)
            path.fill()
            NSColor.white.withAlphaComponent(selected ? 0.95 : 0.6).setStroke()
            path.lineWidth = selected ? 3 : 1.5
            path.stroke()

            if showZoneNumbers {
                let label = "\(zone.number)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 36, weight: .semibold),
                    .foregroundColor: NSColor.white,
                ]
                let numberSize = label.size(withAttributes: attrs)
                label.draw(
                    at: NSPoint(x: rect.midX - numberSize.width / 2, y: rect.midY - numberSize.height / 2),
                    withAttributes: attrs
                )
            }

            let pixels = ZonePixelMetrics.pixelSize(
                of: displayedRects[zone.id] ?? canvasRect(of: zone),
                workAreaAX: workAreaAX
            )
            let sizeLabel = "\(pixels.width) × \(pixels.height)" as NSString
            let sizeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: selected ? 13 : 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(selected ? 0.95 : 0.78),
            ]
            let sizeText = sizeLabel.size(withAttributes: sizeAttrs)
            if sizeText.width + 16 < rect.width, sizeText.height + 40 < rect.height {
                sizeLabel.draw(
                    at: NSPoint(
                        x: rect.midX - sizeText.width / 2,
                        y: rect.midY - sizeText.height / 2 - 20
                    ),
                    withAttributes: sizeAttrs
                )
            }
        }

        if layout.kind == .grid {
            drawGridMergeHighlights()
            drawGridSplitPreview()
        }

        if let edge = visibleSplitHandle() {
            drawSplitHandle(edge)
        }

        let canDeleteGrid = layout.kind != .grid || layout.zones.count > 1
        for zone in zones {
            let rect = viewRect(for: displayedRects[zone.id] ?? canvasRect(of: zone))
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
            guard layout.kind != .grid else { continue }
            guard canDeleteGrid else { continue }
            drawCloseButton(in: closeButtonRect(for: rect), highlighted: zone.id == selectedID)
        }
        drawEmptyGuideIfNeeded()
        drawGhostIfNeeded()
        drawSnapGuides()
        drawMarqueeIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if layout.kind == .grid {
            handleGridMouseDown(at: point)
            return
        }

        if let zone = hitZone(at: point), closeButtonRect(for: viewRect(for: canvasRect(of: zone))).contains(point) {
            deleteZone(id: zone.id)
            drag = .close
            hoverEdge = nil
            setInteracting(false)
            return
        }

        if let edge = edgeInteraction(at: point) {
            selectOnly(edge.primaryID)
            hoverEdge = edge
            guard let primary = layout.zones.first(where: { $0.id == edge.primaryID }) else { return }
            if let neighborID = edge.neighborID,
               let neighbor = layout.zones.first(where: { $0.id == neighborID }) {
                drag = .split(
                    axis: edge.axis,
                    firstID: edge.primaryID,
                    firstRect: canvasRect(of: primary),
                    secondID: neighborID,
                    secondRect: canvasRect(of: neighbor),
                    start: point
                )
            } else {
                drag = .resize(
                    id: edge.primaryID,
                    startRect: canvasRect(of: primary),
                    start: point,
                    handle: edge.primaryHandle
                )
            }
            cacheSnapCandidates(excluding: [edge.primaryID, edge.neighborID].compactMap { $0 })
            beginUndoInteraction()
            setInteracting(true)
            applyCursor()
            needsDisplay = true
            return
        }

        if let zone = hitZone(at: point) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) || flags.contains(.command) {
                toggleSelection(zone.id)
                drag = nil
                hoverEdge = nil
                setInteracting(false)
                needsDisplay = true
                return
            }
            selectOnly(zone.id)
            let rect = canvasRect(of: zone)
            if let handle = handle(at: point, in: viewRect(for: rect)) {
                cacheSnapCandidates(excluding: [zone.id])
                drag = .resize(id: zone.id, startRect: rect, start: point, handle: handle)
            } else if flags.contains(.option) {
                beginUndoInteraction()
                if let cloned = cloneZonesForDrag(ids: selection.isEmpty ? [zone.id] : selection) {
                    cacheSnapCandidates(excluding: cloned.ids)
                    drag = .move(id: cloned.primary, startRect: cloned.startRect, start: point, clones: true)
                    hoverEdge = nil
                    setInteracting(true)
                    needsDisplay = true
                    return
                }
                cacheSnapCandidates(excluding: [zone.id])
                drag = .move(id: zone.id, startRect: rect, start: point, clones: false)
            } else {
                cacheSnapCandidates(excluding: selection.isEmpty ? [zone.id] : Array(selection))
                drag = .move(id: zone.id, startRect: rect, start: point, clones: false)
            }
        } else {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) {
                selectedID = nil
                drag = .marquee(start: point)
            } else {
                selectedID = nil
                cacheSnapCandidates(excluding: [])
                drag = .create(start: point)
            }
        }
        hoverEdge = nil
        beginUndoInteraction()
        setInteracting(true)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .create(let start):
            let rect = rubberBand(from: start, to: point)
            guard rect.width >= 24, rect.height >= 24 else { return }
            let snapped = snapRect(
                normalized(fromView: rect),
                intent: createIntent(from: start, to: point),
                event: event
            )
            upsertCreatingZone(snapped)
        case .move(let id, let startRect, let start, _):
            let dx = Double((point.x - start.x) / max(bounds.width, 1))
            let dy = Double(-(point.y - start.y) / max(bounds.height, 1))
            var moved = startRect
            moved.x += dx
            moved.y += dy
            let snapped = snapRect(moved.clamped(), intent: .move, event: event, lockAspectSingleAxis: false)
            updateZone(id) { zone in
                zone.canvasRect = snapped
            }
        case .resize(let id, let startRect, let start, let handle):
            let dx = Double((point.x - start.x) / max(bounds.width, 1))
            let dy = Double(-(point.y - start.y) / max(bounds.height, 1))
            let resized = resize(startRect, handle: handle, dx: dx, dy: dy, lockAspect: lockAspect).clamped()
            let snapped = snapRect(
                resized,
                intent: resizeIntent(for: handle),
                event: event,
                lockAspectFrom: lockAspect ? startRect : nil,
                usingWidth: lockAspectUsesWidth(handle: handle, dx: dx, dy: dy)
            )
            updateZone(id) { zone in
                zone.canvasRect = snapped
            }
            if let zone = layout.zones.first(where: { $0.id == id }) {
                hoverEdge = edgeHandle(for: zone, handle: handle, pointer: point)
            }
        case .split(let axis, let firstID, let firstRect, let secondID, let secondRect, let start):
            snapHits = ([], [])
            applySplitDrag(
                axis: axis,
                firstID: firstID,
                firstRect: firstRect,
                secondID: secondID,
                secondRect: secondRect,
                start: start,
                point: point
            )
        case .gridLine(let axis, let afterIndex):
            applyGridLineDrag(axis: axis, afterIndex: afterIndex, point: point)
        case .gridMerge:
            updateGridMergeSelection(at: point)
            previewDraft()
            return
        case .marquee(let start):
            selection = zonesIntersecting(rubberBand(from: start, to: point))
            primaryID = selection.sorted { lhs, rhs in
                zoneNumber(lhs) < zoneNumber(rhs)
            }.first
            onSelectionChange?()
            needsDisplay = true
            return
        case .close, nil:
            break
        }
        previewDraft()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if layout.kind == .grid {
            handleGridMouseUp(at: point)
            return
        }
        if case .create(let start) = drag {
            let traveled = hypot(point.x - start.x, point.y - start.y)
            if let creatingID, let zone = layout.zones.first(where: { $0.id == creatingID }) {
                selectOnly(zone.id)
                self.creatingID = nil
            } else if traveled < 8 {
                createDefaultZone(at: start)
            }
        } else if case .marquee = drag {
            onSelectionChange?()
        }
        drag = nil
        creatingID = nil
        snapHits = ([], [])
        setInteracting(false)
        ensureCanvas()
        refreshHover(at: point)
        commit()
    }

    override func scrollWheel(with event: NSEvent) {
        if layout.kind == .grid {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let targetID = selectedID ?? hitZone(at: point)?.id
        guard let id = targetID, let idx = layout.zones.firstIndex(where: { $0.id == id }) else {
            super.scrollWheel(with: event)
            return
        }
        selectedID = id

        var dx = event.scrollingDeltaX
        var dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas {
            dx *= 12
            dy *= 12
        }

        guard let axes = ZoneScrollZoom.axes(deltaX: dx, deltaY: dy) else { return }
        let widthFactor: Double?
        let heightFactor: Double?
        switch axes {
        case .width:
            widthFactor = zoomFactor(from: dx)
            heightFactor = lockAspect ? widthFactor : nil
        case .height:
            widthFactor = lockAspect ? zoomFactor(from: dy) : nil
            heightFactor = zoomFactor(from: dy)
        }

        let w = max(bounds.width, 1)
        let h = max(bounds.height, 1)
        let anchorX = Double(point.x / w)
        let anchorY = Double((h - point.y) / h)

        ensureCanvas()
        layout.zones[idx].canvasRect = canvasRect(of: layout.zones[idx]).scaled(
            widthFactor: widthFactor,
            heightFactor: heightFactor,
            anchorX: anchorX,
            anchorY: anchorY
        )
        commit()
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyEvent(event) { return }
        super.keyDown(with: event)
    }

    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == HardwareKeyCode.escape {
            onCancel?()
            return true
        }
        if event.keyCode == HardwareKeyCode.delete || event.keyCode == HardwareKeyCode.forwardDelete {
            if layout.kind == .grid { return true }
            deleteSelected()
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if HardwareKeyCode.isEditorNudge(event.keyCode) {
            return handleNudge(event)
        }
        if flags.subtracting([.shift, .option]).isEmpty,
           let direction = arrowDirection(for: event.keyCode)
        {
            if event.isARepeat { return true }
            moveSelection(direction)
            return true
        }
        if flags.isEmpty, let number = QuickSnapperReducer.zoneNumber(forKeyCode: event.keyCode) {
            return perform(.assignNumber(number))
        }
        return false
    }

    func deleteSelected() {
        if layout.kind == .grid {
            if let selectedID {
                deleteZone(id: selectedID)
            }
            return
        }
        _ = perform(.delete)
    }

    override func insertTab(_ sender: Any?) {
        cycleSelection(forward: true)
    }

    override func insertBacktab(_ sender: Any?) {
        cycleSelection(forward: false)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    func selectFirstZone() {
        selectOnly(layout.cycledZoneID(from: nil, forward: true))
    }

    func cycleSelection(forward: Bool) {
        guard drag == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastCycle, lastCycle.forward == forward, now - lastCycle.time < 0.05 {
            return
        }
        lastCycle = (forward, now)
        window?.makeFirstResponder(self)
        selectOnly(layout.cycledZoneID(from: selectedID, forward: forward))
    }

    func moveSelection(_ direction: Layout.ArrowDirection) {
        guard drag == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastPaneMove, lastPaneMove.direction == direction, now - lastPaneMove.time < 0.05 {
            return
        }
        lastPaneMove = (direction, now)
        window?.makeFirstResponder(self)
        let rects: [UUID: NormalizedRect]
        if layout.kind == .grid {
            rects = GridEditing.normalizedRects(for: layout, workAreaAX: workAreaAX)
        } else {
            rects = Dictionary(uniqueKeysWithValues: layout.zones.compactMap { zone -> (UUID, NormalizedRect)? in
                guard zone.id != creatingID else { return nil }
                return (zone.id, canvasRect(of: zone))
            })
        }
        selectedID = layout.neighborZoneID(from: selectedID, direction: direction, rects: rects)
        selectOnly(selectedID)
    }

    private func arrowDirection(for keyCode: UInt16) -> Layout.ArrowDirection? {
        switch keyCode {
        case HardwareKeyCode.a: return .left
        case HardwareKeyCode.d: return .right
        case HardwareKeyCode.w: return .up
        case HardwareKeyCode.s: return .down
        default: return nil
        }
    }

    private func createDefaultZone(at point: CGPoint) {
        ensureCanvas()
        let n = normalizedPoint(point)
        var rect = CanvasEditing.defaultRect(centeredAt: n, canvasSize: bounds.size)
        rect = snapRect(rect, intent: .move, event: nil)
        _ = perform(.insert(rect))
    }

    private func upsertCreatingZone(_ rect: NormalizedRect) {
        ensureCanvas()
        if let creatingID, let idx = layout.zones.firstIndex(where: { $0.id == creatingID }) {
            layout.zones[idx].canvasRect = rect
        } else {
            let number = (layout.zones.map(\.number).max() ?? 0) + 1
            let zone = Zone(number: number, canvasRect: rect)
            layout.zones.append(zone)
            creatingID = zone.id
        }
    }

    private func deleteZone(id: UUID) {
        if layout.kind == .grid {
            if let result = GridEditing.deletingZone(layout, id: id) {
                layout = result.layout
                selectedID = result.layout.zones.contains(where: { $0.id == result.absorbedInto })
                    ? result.absorbedInto
                    : result.layout.zones.first?.id
                commit()
            }
            return
        }
        layout.zones.removeAll { $0.id == id }
        layout = layout.packedNumbers()
        selection.remove(id)
        if primaryID == id { primaryID = selection.first }
        ensureCanvas()
        commit()
    }

    private func updateZone(_ id: UUID, _ body: (inout Zone) -> Void) {
        guard let idx = layout.zones.firstIndex(where: { $0.id == id }) else { return }
        body(&layout.zones[idx])
        ensureCanvas()
    }

    private func setInteracting(_ active: Bool) {
        onInteractionChange?(active)
    }

    private func beginUndoInteraction() {
        onInteractionBegin?()
    }

    private func previewDraft() {
        onPreview?(layout)
        needsDisplay = true
    }

    private func commit() {
        sanitizeCreatingZoneIfNeeded()
        onChange?(layout)
        needsDisplay = true
    }

    func commitFromMetrics() {
        commit()
        onSelectionChange?()
    }

    @discardableResult
    func perform(_ command: CanvasCommand) -> Bool {
        guard layout.kind != .grid || isGridCompatible(command) else {
            NSSound.beep()
            return false
        }
        guard let result = CanvasCommandRunner.perform(
            command,
            layout: layout,
            selection: selection,
            primaryID: primaryID,
            workAreaAX: workAreaAX,
            canvasSize: bounds.size
        ) else {
            NSSound.beep()
            return false
        }
        layout = result.layout
        applySelection(result.selection, primary: result.primaryID)
        ensureCanvas()
        commit()
        return true
    }

    func applyTemplateKeepingCanvas(_ preset: Layout) {
        _ = perform(.fillTemplate(preset))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        drag = nil
        ghostRect = nil
        snapHits = ([], [])
        if let zone = hitZone(at: point) {
            if !selection.contains(zone.id) {
                selectOnly(zone.id)
            } else {
                primaryID = zone.id
                onSelectionChange?()
            }
        }
        onMenuWillOpen?()
        let menu = CanvasContextMenu.make(
            layout: layout,
            hitZone: hitZone(at: point),
            selectionCount: selection.count,
            target: self,
            insert: #selector(menuInsert),
            duplicate: #selector(menuDuplicate),
            splitVertical: #selector(menuSplitVertical),
            splitHorizontal: #selector(menuSplitHorizontal),
            selectAll: #selector(menuSelectAll),
            delete: #selector(menuDelete),
            center: #selector(menuCenter),
            fillTemplate: #selector(menuFillTemplate(_:)),
            align: #selector(menuAlign(_:)),
            matchSize: #selector(menuMatchSize(_:)),
            distribute: #selector(menuDistribute(_:)),
            snapHalf: #selector(menuSnapHalf(_:)),
            assignNumber: #selector(menuAssignNumber(_:))
        )
        NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: menu,
            queue: .main
        ) { [weak self] _ in
            self?.onMenuDidClose?()
        }
        return menu
    }

    @objc private func menuInsert() { _ = perform(.insertDefault) }
    @objc private func menuDuplicate() { _ = perform(.duplicate) }
    @objc private func menuSplitVertical() { _ = perform(.split(.vertical)) }
    @objc private func menuSplitHorizontal() { _ = perform(.split(.horizontal)) }
    @objc private func menuSelectAll() { _ = perform(.selectAll) }
    @objc private func menuDelete() { deleteSelected() }
    @objc private func menuCenter() { _ = perform(.center) }

    @objc private func menuFillTemplate(_ sender: NSMenuItem) {
        let presets = LayoutTemplates.editorPresets()
        guard presets.indices.contains(sender.tag) else { return }
        _ = perform(.fillTemplate(presets[sender.tag]))
    }

    @objc private func menuAlign(_ sender: NSMenuItem) {
        let edges: [CanvasAlignment.Edge] = [.left, .centerX, .right, .top, .centerY, .bottom]
        guard edges.indices.contains(sender.tag) else { return }
        _ = perform(.align(edges[sender.tag]))
    }

    @objc private func menuMatchSize(_ sender: NSMenuItem) {
        let matches: [CanvasAlignment.SizeMatch] = [.width, .height, .both]
        guard matches.indices.contains(sender.tag) else { return }
        _ = perform(.matchSize(matches[sender.tag]))
    }

    @objc private func menuDistribute(_ sender: NSMenuItem) {
        _ = perform(.distribute(sender.tag == 1 ? .vertical : .horizontal))
    }

    @objc private func menuSnapHalf(_ sender: NSMenuItem) {
        let edges: [CanvasAlignment.Edge] = [.left, .right, .top, .bottom]
        guard edges.indices.contains(sender.tag) else { return }
        _ = perform(.snapToHalf(edges[sender.tag]))
    }

    @objc private func menuAssignNumber(_ sender: NSMenuItem) {
        _ = perform(.assignNumber(sender.tag))
    }

    private func isGridCompatible(_ command: CanvasCommand) -> Bool {
        switch command {
        case .selectAll, .delete:
            return true
        default:
            return false
        }
    }

    private func pruneSelection() {
        let valid = Set(layout.zones.map(\.id))
        selection = selection.intersection(valid)
        if let primaryID, !valid.contains(primaryID) {
            self.primaryID = selection.sorted { zoneNumber($0) < zoneNumber($1) }.first
        }
    }

    private func applySelection(_ ids: Set<UUID>, primary: UUID?) {
        let valid = Set(layout.zones.map(\.id))
        selection = ids.intersection(valid)
        if let primary, valid.contains(primary) {
            primaryID = primary
        } else {
            primaryID = selection.sorted { zoneNumber($0) < zoneNumber($1) }.first
        }
        onSelectionChange?()
        needsDisplay = true
    }

    private func selectOnly(_ id: UUID?) {
        applySelection(id.map { [$0] } ?? [], primary: id)
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
            if primaryID == id {
                primaryID = selection.sorted { zoneNumber($0) < zoneNumber($1) }.first
            }
        } else {
            selection.insert(id)
            primaryID = id
        }
        onSelectionChange?()
        needsDisplay = true
    }

    private func zoneNumber(_ id: UUID) -> Int {
        layout.zones.first(where: { $0.id == id })?.number ?? .max
    }

    private func handleNudge(_ event: NSEvent) -> Bool {
        guard layout.kind != .grid else { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let amount: CGFloat = flags.contains(.shift) ? 10 : 1
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        switch event.keyCode {
        case HardwareKeyCode.left: dx = -amount
        case HardwareKeyCode.right: dx = amount
        case HardwareKeyCode.up: dy = -amount
        case HardwareKeyCode.down: dy = amount
        default: return false
        }
        let resize = flags.contains(.option)
        if !nudgeInteractionStarted {
            beginUndoInteraction()
            nudgeInteractionStarted = true
        }
        var next = layout
        let ids = selection.isEmpty ? Set([primaryID].compactMap { $0 }) : selection
        for id in ids {
            guard let idx = next.zones.firstIndex(where: { $0.id == id }),
                  let rect = next.zones[idx].canvasRect
            else { continue }
            next.zones[idx].canvasRect = CanvasEditing.nudge(
                rect,
                dxPoints: dx,
                dyPoints: dy,
                resize: resize,
                workAreaAX: workAreaAX
            )
        }
        layout = next
        previewDraft()
        nudgeFinishWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.nudgeInteractionStarted = false
            self.commit()
        }
        nudgeFinishWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        return true
    }

    private func cloneZonesForDrag(ids: Set<UUID>) -> (primary: UUID, ids: [UUID], startRect: NormalizedRect)? {
        guard let result = CanvasEditing.duplicating(layout, ids: ids, offset: (0, 0)) else { return nil }
        layout = result.layout
        applySelection(Set(result.newIDs), primary: result.newIDs.last)
        guard let primary = result.newIDs.last,
              let zone = layout.zones.first(where: { $0.id == primary })
        else { return nil }
        return (primary, result.newIDs, canvasRect(of: zone))
    }

    private func cacheSnapCandidates(excluding ids: [UUID]) {
        let excluded = Set(ids)
        let rects = layout.zones.compactMap { zone -> NormalizedRect? in
            guard !excluded.contains(zone.id), zone.id != creatingID else { return nil }
            return canvasRect(of: zone)
        }
        snapCandidates = .from(rects: rects)
    }

    private func snapThresholds(event: NSEvent?) -> (x: Double, y: Double) {
        let flags = (event ?? NSApp.currentEvent)?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.control) { return (0, 0) }
        return (
            Double(CanvasSnapping.thresholdPoints / max(bounds.width, 1)),
            Double(CanvasSnapping.thresholdPoints / max(bounds.height, 1))
        )
    }

    private func snapRect(
        _ rect: NormalizedRect,
        intent: CanvasSnapping.Intent,
        event: NSEvent?,
        lockAspectSingleAxis: Bool = false,
        lockAspectFrom start: NormalizedRect? = nil,
        usingWidth: Bool = true
    ) -> NormalizedRect {
        let thresholds = snapThresholds(event: event)
        let result: CanvasSnapResult
        if let start {
            result = CanvasSnapping.snappingPreservingAspect(
                from: start,
                resized: rect,
                intent: intent,
                candidates: snapCandidates,
                thresholdX: thresholds.x,
                thresholdY: thresholds.y,
                usingWidth: usingWidth
            )
        } else if lockAspectSingleAxis {
            result = CanvasSnapping.snappingClosestAxis(
                rect,
                intent: intent,
                candidates: snapCandidates,
                thresholdX: thresholds.x,
                thresholdY: thresholds.y
            )
        } else {
            result = CanvasSnapping.snapping(
                rect,
                intent: intent,
                candidates: snapCandidates,
                thresholdX: thresholds.x,
                thresholdY: thresholds.y
            )
        }
        snapHits = (result.hitX, result.hitY)
        return result.rect.clamped()
    }

    private func lockAspectUsesWidth(handle: Handle, dx: Double, dy: Double) -> Bool {
        switch handle {
        case .e, .w, .ne, .nw, .se, .sw:
            return abs(dx) >= abs(dy)
        case .n, .s:
            return false
        }
    }

    private func createIntent(from start: CGPoint, to point: CGPoint) -> CanvasSnapping.Intent {
        CanvasSnapping.Intent.edges(
            left: point.x < start.x,
            right: point.x >= start.x,
            top: point.y > start.y,
            bottom: point.y <= start.y
        )
    }

    private func resizeIntent(for handle: Handle) -> CanvasSnapping.Intent {
        switch handle {
        case .n: return .edges(left: false, right: false, top: true, bottom: false)
        case .s: return .edges(left: false, right: false, top: false, bottom: true)
        case .e: return .edges(left: false, right: true, top: false, bottom: false)
        case .w: return .edges(left: true, right: false, top: false, bottom: false)
        case .ne: return .edges(left: false, right: true, top: true, bottom: false)
        case .nw: return .edges(left: true, right: false, top: true, bottom: false)
        case .se: return .edges(left: false, right: true, top: false, bottom: true)
        case .sw: return .edges(left: true, right: false, top: false, bottom: true)
        }
    }

    private func zonesIntersecting(_ rect: CGRect) -> Set<UUID> {
        var ids = Set<UUID>()
        for zone in layout.zones {
            let frame = viewRect(for: canvasRect(of: zone))
            if frame.intersects(rect) {
                ids.insert(zone.id)
            }
        }
        return ids
    }

    private func drawEmptyGuideIfNeeded() {
        guard layout.kind == .canvas else { return }
        let visible = layout.zones.filter { $0.id != creatingID }
        guard visible.isEmpty, drag == nil else { return }
        let guide = CGRect(
            x: bounds.midX - bounds.width * 0.21,
            y: bounds.midY - bounds.height * 0.15,
            width: bounds.width * 0.42,
            height: bounds.height * 0.30
        )
        NSColor.white.withAlphaComponent(0.5).setStroke()
        let path = NSBezierPath(roundedRect: guide, xRadius: 8, yRadius: 8)
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
        if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) {
            let size = NSSize(width: 28, height: 28)
            image.draw(
                in: CGRect(x: guide.midX - size.width / 2, y: guide.midY + 8, width: size.width, height: size.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 0.85
            )
        }
        let title = L10n.text(.canvasEmptyTitle) as NSString
        let subtitle = L10n.text(.canvasEmptySubtitle) as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.72),
        ]
        let titleSize = title.size(withAttributes: titleAttrs)
        let subtitleSize = subtitle.size(withAttributes: subtitleAttrs)
        title.draw(
            at: NSPoint(x: guide.midX - titleSize.width / 2, y: guide.midY - 18),
            withAttributes: titleAttrs
        )
        subtitle.draw(
            at: NSPoint(x: guide.midX - subtitleSize.width / 2, y: guide.midY - 40),
            withAttributes: subtitleAttrs
        )
    }

    private func drawGhostIfNeeded() {
        guard let ghostRect, drag == nil else { return }
        let rect = viewRect(for: ghostRect)
        guard !rect.isNull, rect.width > 2, rect.height > 2 else { return }
        NSColor.white.withAlphaComponent(0.45).setStroke()
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        path.stroke()
        if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) {
            let size = NSSize(width: 16, height: 16)
            image.draw(
                in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 0.7
            )
        }
        let pixels = ZonePixelMetrics.pixelSize(of: ghostRect, workAreaAX: workAreaAX)
        let label = "\(pixels.width) × \(pixels.height)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.8),
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: rect.maxX - size.width - 8, y: rect.minY + 8), withAttributes: attrs)
    }

    private func drawSnapGuides() {
        NSColor.systemTeal.withAlphaComponent(0.9).setStroke()
        for x in snapHits.x {
            let path = NSBezierPath()
            path.lineWidth = 1
            let vx = CGFloat(x) * bounds.width
            path.move(to: CGPoint(x: vx, y: 0))
            path.line(to: CGPoint(x: vx, y: bounds.height))
            path.stroke()
        }
        for y in snapHits.y {
            let path = NSBezierPath()
            path.lineWidth = 1
            let vy = CGFloat(1 - y) * bounds.height
            path.move(to: CGPoint(x: 0, y: vy))
            path.line(to: CGPoint(x: bounds.width, y: vy))
            path.stroke()
        }
    }

    private func drawMarqueeIfNeeded() {
        guard case .marquee(let start) = drag, let window else { return }
        let current = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let box = rubberBand(from: start, to: current)
        guard box.width > 2, box.height > 2 else { return }
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let path = NSBezierPath(rect: box)
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }


    private func sanitizeCreatingZoneIfNeeded() {
        creatingID = nil
    }

    private func ensureCanvas() {
        if layout.kind == .grid { return }
        layout.kind = .canvas
        layout.grid = nil
        for i in layout.zones.indices where layout.zones[i].canvasRect == nil {
            if let resolved = try? resolveLayout(layout, workAreaAX: workAreaAX, gutter: 0),
               let match = resolved.first(where: { $0.zoneID == layout.zones[i].id }) {
                layout.zones[i].canvasRect = NormalizedRect.normalize(match.frameAX, in: workAreaAX)
            }
        }
    }

    private func canvasRect(of zone: Zone) -> NormalizedRect {
        if layout.kind == .grid {
            let rects = GridEditing.normalizedRects(for: layout, workAreaAX: workAreaAX)
            if let rect = rects[zone.id] { return rect }
        }
        if let rect = zone.canvasRect { return rect }
        if let resolved = try? resolveLayout(layout, workAreaAX: workAreaAX, gutter: 0),
           let match = resolved.first(where: { $0.zoneID == zone.id }) {
            return NormalizedRect.normalize(match.frameAX, in: workAreaAX)
        }
        return NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
    }

    private func gutteredCanvasRects() -> [UUID: NormalizedRect] {
        let base = Dictionary(uniqueKeysWithValues: layout.zones.map { ($0.id, canvasRect(of: $0)) })
        guard gutterPoints > 0,
              let resolved = try? resolveLayout(layout, workAreaAX: workAreaAX, gutter: gutterPoints)
        else {
            return base
        }

        var result = base
        for zone in resolved {
            result[zone.zoneID] = NormalizedRect.normalize(zone.frameAX, in: workAreaAX)
        }
        return result
    }

    private func hitZone(at point: CGPoint) -> Zone? {
        for zone in layout.zones.reversed() {
            if viewRect(for: canvasRect(of: zone)).contains(point) {
                return zone
            }
        }
        return nil
    }

    private func refreshHover(at point: CGPoint) {
        guard drag == nil else { return }
        if layout.kind == .grid {
            ghostRect = nil
            snapHits = ([], [])
            refreshGridHover(at: point)
            return
        }
        if isPointOverChrome(point) {
            let changed = hoverEdge != nil || ghostRect != nil || !pointerOverChrome
            hoverEdge = nil
            ghostRect = nil
            snapHits = ([], [])
            pointerOverChrome = true
            if changed { needsDisplay = true }
            applyCursor()
            return
        }
        pointerOverChrome = false
        let next = edgeInteraction(at: point)
        var nextGhost: NormalizedRect?
        var nextHits: (x: [Double], y: [Double]) = ([], [])
        if next == nil, hitZone(at: point) == nil, !isPointOverCloseButton(point) {
            cacheSnapCandidates(excluding: [])
            let n = normalizedPoint(point)
            var rect = CanvasEditing.defaultRect(centeredAt: n, canvasSize: bounds.size)
            let snapped = snapRect(rect, intent: .move, event: NSApp.currentEvent)
            nextGhost = snapped
            nextHits = snapHits
        }
        if next != hoverEdge || nextGhost != ghostRect {
            hoverEdge = next
            ghostRect = nextGhost
            snapHits = nextHits
            needsDisplay = true
        }
        applyCursor()
    }

    private func applyCursor() {
        if layout.kind == .grid {
            if pointerOverChrome, drag == nil {
                NSCursor.arrow.set()
                return
            }
            if case .gridLine(let axis, _) = drag {
                (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                return
            }
            if hoverEdge?.axis == .resizeWidth {
                NSCursor.resizeLeftRight.set()
                return
            }
            if hoverEdge?.axis == .resizeHeight {
                NSCursor.resizeUpDown.set()
                return
            }
            NSCursor.crosshair.set()
            return
        }
        if pointerOverChrome, drag == nil {
            NSCursor.arrow.set()
            return
        }
        guard let edge = visibleSplitHandle() else {
            if ghostRect != nil, drag == nil {
                NSCursor.crosshair.set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }

        if let cursor = systemFrameResizeCursor(for: edge.primaryHandle) {
            cursor.set()
        } else {
            Self.hiddenCursor.set()
        }
    }

    private func systemFrameResizeCursor(for handle: Handle) -> NSCursor? {
#if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .ne: position = .topRight
            case .nw: position = .topLeft
            case .se: position = .bottomRight
            case .sw: position = .bottomLeft
            default: return nil
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
#endif
        return nil
    }

    private func visibleSplitHandle() -> EdgeInteraction? {
        switch drag {
        case .create, .move, .close, .gridMerge, .gridLine, .marquee: return nil
        case .resize, .split, nil: return hoverEdge
        }
    }


    private func handleGridMouseDown(at point: CGPoint) {
        hoverSplit = nil
        let n = normalizedPoint(point)
        if !NSEvent.modifierFlags.contains(.shift),
           let spec = layout.grid,
           let hit = GridEditing.hitLine(
            normalizedX: n.x,
            normalizedY: n.y,
            spec: spec,
            slopX: Double(gridSplitLineSlop / max(bounds.width, 1)),
            slopY: Double(gridSplitLineSlop / max(bounds.height, 1))
           ) {
            selectedID = GridEditing.zoneID(normalizedX: n.x, normalizedY: n.y, layout: layout)
            drag = .gridLine(axis: hit.axis, afterIndex: hit.afterIndex)
            hoverEdge = gridEdge(for: hit)
            beginUndoInteraction()
            setInteracting(true)
            applyCursor()
            needsDisplay = true
            return
        }
        if let id = GridEditing.zoneID(normalizedX: n.x, normalizedY: n.y, layout: layout) {
            selectedID = id
            mergeIDs = [id]
            drag = .gridMerge(start: point, normalizedStart: (n.x, n.y))
            beginUndoInteraction()
            setInteracting(true)
            needsDisplay = true
            return
        }
        setInteracting(false)
    }

    private func handleGridMouseUp(at point: CGPoint) {
        switch drag {
        case .gridMerge(let start, let normalizedStart):
            let traveled = hypot(point.x - start.x, point.y - start.y)
            if traveled < 8 {
                let axis: GridAxis = NSEvent.modifierFlags.contains(.shift) ? .horizontal : .vertical
                if let next = GridEditing.split(
                    layout,
                    normalizedX: normalizedStart.x,
                    normalizedY: normalizedStart.y,
                    axis: axis
                ) {
                    layout = next
                    selectedID = layout.zones.last?.id
                }
            } else if let ids = rectangularMergeIDs(),
                      ids.count >= 2,
                      let next = GridEditing.merge(layout, zoneIDs: ids) {
                layout = next
                selectedID = layout.zones.first { ids.contains($0.id) }?.id ?? layout.zones.first?.id
            }
        default:
            break
        }
        drag = nil
        mergeIDs = []
        setInteracting(false)
        refreshHover(at: point)
        commit()
    }

    private func applyGridLineDrag(axis: GridAxis, afterIndex: Int, point: CGPoint) {
        let n = normalizedPoint(point)
        let t = axis == .vertical ? n.x : n.y
        if let next = GridEditing.moveLine(layout, axis: axis, afterIndex: afterIndex, toNormalized: t) {
            layout = next
            hoverEdge = gridEdge(for: GridLineHit(axis: axis, afterIndex: afterIndex))
        }
    }

    private func updateGridMergeSelection(at point: CGPoint) {
        mergeIDs = zonesIntersectingMergeRect(to: point)
        let n = normalizedPoint(point)
        selectedID = GridEditing.zoneID(normalizedX: n.x, normalizedY: n.y, layout: layout) ?? selectedID
        needsDisplay = true
    }

    private func rectangularMergeIDs() -> Set<UUID>? {
        guard case .gridMerge(_, _) = drag else { return nil }
        guard let window else { return mergeIDs }
        let current = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let ids = zonesIntersectingMergeRect(to: current)
        return GridEditing.merge(layout, zoneIDs: ids) == nil ? nil : ids
    }

    private func zonesIntersectingMergeRect(to point: CGPoint) -> Set<UUID> {
        guard case .gridMerge(let start, _) = drag else { return [] }
        let box = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: max(abs(point.x - start.x), 1),
            height: max(abs(point.y - start.y), 1)
        )
        var ids = Set<UUID>()
        let displayed = gutteredCanvasRects()
        for zone in layout.zones {
            let rect = viewRect(for: displayed[zone.id] ?? canvasRect(of: zone))
            if rect.intersects(box) {
                ids.insert(zone.id)
            }
        }
        return ids
    }

    private func refreshGridHover(at point: CGPoint) {
        if isPointOverChrome(point) {
            let changed = hoverEdge != nil || hoverSplit != nil || !pointerOverChrome
            hoverEdge = nil
            hoverSplit = nil
            pointerOverChrome = true
            if changed {
                needsDisplay = true
            }
            applyCursor()
            return
        }
        pointerOverChrome = false
        let n = normalizedPoint(point)
        var nextEdge: EdgeInteraction?
        var nextSplit: (axis: GridAxis, x: Double, y: Double, zoneID: UUID)?
        if !NSEvent.modifierFlags.contains(.shift),
           let spec = layout.grid,
           let hit = GridEditing.hitLine(
            normalizedX: n.x,
            normalizedY: n.y,
            spec: spec,
            slopX: Double(gridSplitLineSlop / max(bounds.width, 1)),
            slopY: Double(gridSplitLineSlop / max(bounds.height, 1))
           ) {
            nextEdge = gridEdge(for: hit)
        } else if let spec = layout.grid,
                  let zoneID = GridEditing.zoneID(normalizedX: n.x, normalizedY: n.y, layout: layout) {
            let axis: GridAxis = NSEvent.modifierFlags.contains(.shift) ? .horizontal : .vertical
            if GridEditing.canSplit(spec: spec, normalizedX: n.x, normalizedY: n.y, axis: axis) {
                nextSplit = (axis, n.x, n.y, zoneID)
            }
        }
        let splitChanged = nextSplit?.axis != hoverSplit?.axis
            || nextSplit?.x != hoverSplit?.x
            || nextSplit?.y != hoverSplit?.y
            || nextSplit?.zoneID != hoverSplit?.zoneID
        if nextEdge != hoverEdge || splitChanged {
            hoverEdge = nextEdge
            hoverSplit = nextSplit
            needsDisplay = true
        }
        applyCursor()
    }

    private func isPointOverChrome(_ point: CGPoint) -> Bool {
        let views = [chromeView].compactMap { $0 } + additionalChromeViews
        for chrome in views {
            guard let chromeSuperview = chrome.superview else { continue }
            let chromeRect = convert(chrome.frame, from: chromeSuperview)
            if chromeRect.contains(point) { return true }
        }
        return false
    }

    private func isPointOverCloseButton(_ point: CGPoint) -> Bool {
        guard layout.kind != .grid || layout.zones.count > 1 else { return false }
        for zone in layout.zones {
            let rect = viewRect(for: canvasRect(of: zone))
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
            if closeButtonRect(for: rect).contains(point) {
                return true
            }
        }
        return false
    }

    private func gridEdge(for hit: GridLineHit) -> EdgeInteraction? {
        guard let spec = layout.grid else { return nil }
        let displayed = gutteredCanvasRects()
        var lo = CGFloat.greatestFiniteMagnitude
        var hi = -CGFloat.greatestFiniteMagnitude

        func accumulateOverlap(_ a: CGRect, _ b: CGRect, vertical: Bool) {
            guard !a.isNull, !b.isNull else { return }
            if vertical {
                let spanLo = max(a.minY, b.minY)
                let spanHi = min(a.maxY, b.maxY)
                guard spanHi > spanLo else { return }
                lo = min(lo, spanLo)
                hi = max(hi, spanHi)
            } else {
                let spanLo = max(a.minX, b.minX)
                let spanHi = min(a.maxX, b.maxX)
                guard spanHi > spanLo else { return }
                lo = min(lo, spanLo)
                hi = max(hi, spanHi)
            }
        }

        switch hit.axis {
        case .vertical:
            guard hit.afterIndex >= 0, hit.afterIndex < spec.columns - 1 else { return nil }
            let xFrac = Double(spec.columnWeights.prefix(hit.afterIndex + 1).reduce(0, +)) / 10_000
            let x = CGFloat(xFrac) * bounds.width
            for r in 0..<spec.rows {
                let leftIdx = spec.cellMap[r][hit.afterIndex]
                let rightIdx = spec.cellMap[r][hit.afterIndex + 1]
                guard leftIdx != rightIdx,
                      layout.zones.indices.contains(leftIdx),
                      layout.zones.indices.contains(rightIdx)
                else { continue }
                accumulateOverlap(
                    innerPaneRect(for: layout.zones[leftIdx], displayed: displayed),
                    innerPaneRect(for: layout.zones[rightIdx], displayed: displayed),
                    vertical: true
                )
            }
            guard lo < hi else { return nil }
            return EdgeInteraction(
                axis: .resizeWidth,
                grabber: CGPoint(x: x, y: (lo + hi) / 2),
                seamStart: CGPoint(x: x, y: lo),
                seamEnd: CGPoint(x: x, y: hi),
                primaryID: selectedID ?? layout.zones.first?.id ?? UUID(),
                primaryHandle: .e,
                neighborID: nil,
                neighborHandle: nil
            )
        case .horizontal:
            guard hit.afterIndex >= 0, hit.afterIndex < spec.rows - 1 else { return nil }
            let yFrac = Double(spec.rowWeights.prefix(hit.afterIndex + 1).reduce(0, +)) / 10_000
            let y = CGFloat(1 - yFrac) * bounds.height
            for c in 0..<spec.columns {
                let topIdx = spec.cellMap[hit.afterIndex][c]
                let bottomIdx = spec.cellMap[hit.afterIndex + 1][c]
                guard topIdx != bottomIdx,
                      layout.zones.indices.contains(topIdx),
                      layout.zones.indices.contains(bottomIdx)
                else { continue }
                accumulateOverlap(
                    innerPaneRect(for: layout.zones[topIdx], displayed: displayed),
                    innerPaneRect(for: layout.zones[bottomIdx], displayed: displayed),
                    vertical: false
                )
            }
            guard lo < hi else { return nil }
            return EdgeInteraction(
                axis: .resizeHeight,
                grabber: CGPoint(x: (lo + hi) / 2, y: y),
                seamStart: CGPoint(x: lo, y: y),
                seamEnd: CGPoint(x: hi, y: y),
                primaryID: selectedID ?? layout.zones.first?.id ?? UUID(),
                primaryHandle: .s,
                neighborID: nil,
                neighborHandle: nil
            )
        }
    }

    /// Keep split chrome inside the filled pane, inside the white stroke.
    private func innerPaneRect(for zone: Zone, displayed: [UUID: NormalizedRect]? = nil) -> CGRect {
        let displayed = displayed ?? gutteredCanvasRects()
        let rect = viewRect(for: displayed[zone.id] ?? canvasRect(of: zone))
        guard !rect.isNull, rect.width > 1, rect.height > 1 else { return .null }
        let stroke: CGFloat = zone.id == selectedID ? 3 : 1.5
        return rect.insetBy(dx: 3 + stroke / 2 + 0.5, dy: 3 + stroke / 2 + 0.5)
    }

    private func drawGridSplitPreview() {
        guard let preview = hoverSplit, drag == nil else { return }
        guard let zone = layout.zones.first(where: { $0.id == preview.zoneID }) else { return }
        let inner = innerPaneRect(for: zone)
        guard !inner.isNull, inner.width > 1, inner.height > 1 else { return }

        NSGraphicsContext.saveGraphicsState()
        let clipRadius = max(CGFloat(0), CGFloat(8 - 5))
        NSBezierPath(roundedRect: inner, xRadius: clipRadius, yRadius: clipRadius).addClip()

        NSColor.white.withAlphaComponent(0.7).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        switch preview.axis {
        case .vertical:
            let x = min(max(CGFloat(preview.x) * bounds.width, inner.minX), inner.maxX)
            path.move(to: CGPoint(x: x, y: inner.minY))
            path.line(to: CGPoint(x: x, y: inner.maxY))
        case .horizontal:
            let y = min(max(CGFloat(1 - preview.y) * bounds.height, inner.minY), inner.maxY)
            path.move(to: CGPoint(x: inner.minX, y: y))
            path.line(to: CGPoint(x: inner.maxX, y: y))
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGridMergeHighlights() {
        guard case .gridMerge(let start, _) = drag else { return }
        let ids = rectangularMergeIDs() ?? mergeIDs
        for zone in layout.zones where ids.contains(zone.id) {
            let displayed = gutteredCanvasRects()
            let rect = innerPaneRect(for: zone, displayed: displayed)
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
            NSColor.systemYellow.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        }
        if let window {
            let current = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let box = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            if box.width > 2, box.height > 2 {
                NSColor.white.withAlphaComponent(0.85).setStroke()
                let path = NSBezierPath(rect: box.insetBy(dx: -0.5, dy: -0.5))
                path.lineWidth = 1.5
                path.setLineDash([4, 3], count: 2, phase: 0)
                path.stroke()
            }
        }
    }

    private func normalizedPoint(_ point: CGPoint) -> (x: Double, y: Double) {
        let w = max(bounds.width, 1)
        let h = max(bounds.height, 1)
        return (Double(point.x / w), Double((h - point.y) / h))
    }

    private func applySplitDrag(
        axis: SplitAxis,
        firstID: UUID,
        firstRect: NormalizedRect,
        secondID: UUID,
        secondRect: NormalizedRect,
        start: CGPoint,
        point: CGPoint
    ) {
        let w = max(bounds.width, 1)
        let h = max(bounds.height, 1)
        switch axis {
        case .resizeWidth:
            let startSeam = (firstRect.x + firstRect.width + secondRect.x) / 2
            let seam = startSeam + Double((point.x - start.x) / w)
            let pair = ZoneSplit.movingVerticalSeam(left: firstRect, right: secondRect, to: seam)
            setCanvasRect(firstID, pair.left)
            setCanvasRect(secondID, pair.right)
            let x = CGFloat((pair.left.x + pair.left.width) * Double(w))
            if var edge = hoverEdge {
                edge.seamStart.x = x
                edge.seamEnd.x = x
                edge.grabber = grabberAlongSeam(edge, point: CGPoint(x: x, y: point.y))
                hoverEdge = edge
            }
        case .resizeHeight:
            let startSeam = (firstRect.y + firstRect.height + secondRect.y) / 2
            let seam = startSeam + Double(-(point.y - start.y) / h)
            let pair = ZoneSplit.movingHorizontalSeam(top: firstRect, bottom: secondRect, to: seam)
            setCanvasRect(firstID, pair.top)
            setCanvasRect(secondID, pair.bottom)
            let y = CGFloat((1 - pair.top.y - pair.top.height) * Double(h))
            if var edge = hoverEdge {
                edge.seamStart.y = y
                edge.seamEnd.y = y
                edge.grabber = grabberAlongSeam(edge, point: CGPoint(x: point.x, y: y))
                hoverEdge = edge
            }
        case .resizeDiagonalNESW, .resizeDiagonalNWSE:
            break
        }
        ensureCanvas()
    }

    private func setCanvasRect(_ id: UUID, _ rect: NormalizedRect) {
        guard let idx = layout.zones.firstIndex(where: { $0.id == id }) else { return }
        layout.zones[idx].canvasRect = rect
    }

    private func edgeInteraction(at point: CGPoint) -> EdgeInteraction? {
        let items: [(Zone, CGRect)] = layout.zones.compactMap { zone in
            let rect = viewRect(for: canvasRect(of: zone))
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { return nil }
            return (zone, rect)
        }
        for item in items where closeButtonRect(for: item.1).contains(point) {
            return nil
        }

        var bestDistance = CGFloat.greatestFiniteMagnitude
        var best: EdgeInteraction?
        func consider(_ hit: EdgeInteraction, distance: CGFloat, slop: CGFloat) {
            guard distance <= slop, distance < bestDistance else { return }
            bestDistance = distance
            best = hit
        }
        let onEdge: (EdgeInteraction, CGFloat) -> Void = { consider($0, distance: $1, slop: self.edgeSlop) }

        for seam in allSharedSeams(in: items) {
            if let distance = linkedHitDistance(seam, point: point) {
                var hit = seam
                hit.grabber = grabberAlongSeam(seam, point: point)
                consider(hit, distance: distance, slop: linkedEdgeSlop)
            }
        }
        for item in items {
            considerCorners(zone: item.0, rect: item.1, point: point) { hit, distance in
                consider(hit, distance: distance, slop: self.cornerSlop)
            }
            considerSingleEdges(zone: item.0, rect: item.1, point: point, consider: onEdge)
        }
        return best
    }

    private func considerCorners(
        zone: Zone,
        rect: CGRect,
        point: CGPoint,
        consider: (EdgeInteraction, CGFloat) -> Void
    ) {
        let corners: [(Handle, CGPoint, SplitAxis, CGPoint)] = [
            (.ne, CGPoint(x: rect.maxX, y: rect.maxY), .resizeDiagonalNESW, CGPoint(x: 1, y: 1)),
            (.nw, CGPoint(x: rect.minX, y: rect.maxY), .resizeDiagonalNWSE, CGPoint(x: -1, y: 1)),
            (.se, CGPoint(x: rect.maxX, y: rect.minY), .resizeDiagonalNWSE, CGPoint(x: 1, y: -1)),
            (.sw, CGPoint(x: rect.minX, y: rect.minY), .resizeDiagonalNESW, CGPoint(x: -1, y: -1)),
        ]
        for (handle, corner, axis, outward) in corners {
            let distance = hypot(point.x - corner.x, point.y - corner.y)
            let len = hypot(outward.x, outward.y)
            let dir = CGPoint(x: outward.x / len, y: outward.y / len)
            consider(
                EdgeInteraction(
                    axis: axis,
                    grabber: CGPoint(x: corner.x + dir.x * cornerOutset, y: corner.y + dir.y * cornerOutset),
                    seamStart: corner,
                    seamEnd: corner,
                    primaryID: zone.id,
                    primaryHandle: handle,
                    neighborID: nil,
                    neighborHandle: nil
                ),
                distance
            )
        }
    }

    private func grabberAlongSeam(_ seam: EdgeInteraction, point: CGPoint) -> CGPoint {
        switch seam.axis {
        case .resizeWidth:
            let lo = min(seam.seamStart.y, seam.seamEnd.y) + cornerClearance
            let hi = max(seam.seamStart.y, seam.seamEnd.y) - cornerClearance
            let y = lo <= hi ? min(max(point.y, lo), hi) : (seam.seamStart.y + seam.seamEnd.y) / 2
            return CGPoint(x: seam.seamStart.x, y: y)
        case .resizeHeight:
            let lo = min(seam.seamStart.x, seam.seamEnd.x) + cornerClearance
            let hi = max(seam.seamStart.x, seam.seamEnd.x) - cornerClearance
            let x = lo <= hi ? min(max(point.x, lo), hi) : (seam.seamStart.x + seam.seamEnd.x) / 2
            return CGPoint(x: x, y: seam.seamStart.y)
        case .resizeDiagonalNESW, .resizeDiagonalNWSE:
            return seam.grabber
        }
    }

    private func rotation(for axis: SplitAxis) -> CGFloat {
        switch axis {
        case .resizeWidth: 0
        case .resizeHeight: .pi / 2
        case .resizeDiagonalNESW: .pi / 4
        case .resizeDiagonalNWSE: -.pi / 4
        }
    }

    private func outwardUnit(for handle: Handle) -> CGPoint {
        switch handle {
        case .e: CGPoint(x: 1, y: 0)
        case .w: CGPoint(x: -1, y: 0)
        case .n: CGPoint(x: 0, y: 1)
        case .s: CGPoint(x: 0, y: -1)
        case .ne: CGPoint(x: 1, y: 1)
        case .nw: CGPoint(x: -1, y: 1)
        case .se: CGPoint(x: 1, y: -1)
        case .sw: CGPoint(x: -1, y: -1)
        }
    }

    private func zoneRects() -> [(Zone, CGRect)] {
        layout.zones.compactMap { zone in
            let rect = viewRect(for: canvasRect(of: zone))
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { return nil }
            return (zone, rect)
        }
    }

    private func allSharedSeams(in items: [(Zone, CGRect)]? = nil) -> [EdgeInteraction] {
        let items = items ?? zoneRects()
        var result: [EdgeInteraction] = []
        for i in items.indices {
            for j in items.indices where i != j {
                if let pair = verticalPair(left: items[i], right: items[j]) {
                    result.append(pair)
                }
                if let pair = horizontalPair(top: items[i], bottom: items[j]) {
                    result.append(pair)
                }
            }
        }
        return result
    }

    private func verticalPair(left: (Zone, CGRect), right: (Zone, CGRect)) -> EdgeInteraction? {
        let leftRect = left.1
        let rightRect = right.1
        guard abs(leftRect.maxX - rightRect.minX) <= edgeSlop else { return nil }
        let lo = max(leftRect.minY, rightRect.minY)
        let hi = min(leftRect.maxY, rightRect.maxY)
        guard hi - lo >= minSeamOverlap else { return nil }
        let x = (leftRect.maxX + rightRect.minX) / 2
        return EdgeInteraction(
            axis: .resizeWidth,
            grabber: CGPoint(x: x, y: (lo + hi) / 2),
            seamStart: CGPoint(x: x, y: lo),
            seamEnd: CGPoint(x: x, y: hi),
            primaryID: left.0.id,
            primaryHandle: .e,
            neighborID: right.0.id,
            neighborHandle: .w
        )
    }

    private func horizontalPair(top: (Zone, CGRect), bottom: (Zone, CGRect)) -> EdgeInteraction? {
        let topRect = top.1
        let bottomRect = bottom.1
        guard abs(topRect.minY - bottomRect.maxY) <= edgeSlop else { return nil }
        let lo = max(topRect.minX, bottomRect.minX)
        let hi = min(topRect.maxX, bottomRect.maxX)
        guard hi - lo >= minSeamOverlap else { return nil }
        let y = (topRect.minY + bottomRect.maxY) / 2
        return EdgeInteraction(
            axis: .resizeHeight,
            grabber: CGPoint(x: (lo + hi) / 2, y: y),
            seamStart: CGPoint(x: lo, y: y),
            seamEnd: CGPoint(x: hi, y: y),
            primaryID: top.0.id,
            primaryHandle: .s,
            neighborID: bottom.0.id,
            neighborHandle: .n
        )
    }

    private func linkedHitDistance(_ seam: EdgeInteraction, point: CGPoint) -> CGFloat? {
        let verticalSeam = seam.axis == .resizeWidth
        if ResizeGlyph.linkedHitRect(center: seam.grabber, verticalSeam: verticalSeam).contains(point) {
            return 0
        }
        switch seam.axis {
        case .resizeWidth:
            let lo = min(seam.seamStart.y, seam.seamEnd.y)
            let hi = max(seam.seamStart.y, seam.seamEnd.y)
            guard point.y >= lo + cornerClearance, point.y <= hi - cornerClearance else { return nil }
            let distance = abs(point.x - seam.seamStart.x)
            return distance <= linkedEdgeSlop ? distance : nil
        case .resizeHeight:
            let lo = min(seam.seamStart.x, seam.seamEnd.x)
            let hi = max(seam.seamStart.x, seam.seamEnd.x)
            guard point.x >= lo + cornerClearance, point.x <= hi - cornerClearance else { return nil }
            let distance = abs(point.y - seam.seamStart.y)
            return distance <= linkedEdgeSlop ? distance : nil
        case .resizeDiagonalNESW, .resizeDiagonalNWSE:
            return nil
        }
    }

    private func considerSingleEdges(
        zone: Zone,
        rect: CGRect,
        point: CGPoint,
        consider: (EdgeInteraction, CGFloat) -> Void
    ) {
        if point.y >= rect.minY + cornerClearance, point.y <= rect.maxY - cornerClearance {
            consider(
                EdgeInteraction(
                    axis: .resizeWidth,
                    grabber: CGPoint(x: rect.maxX, y: point.y),
                    seamStart: CGPoint(x: rect.maxX, y: rect.minY),
                    seamEnd: CGPoint(x: rect.maxX, y: rect.maxY),
                    primaryID: zone.id,
                    primaryHandle: .e,
                    neighborID: nil,
                    neighborHandle: nil
                ),
                abs(point.x - rect.maxX)
            )
            consider(
                EdgeInteraction(
                    axis: .resizeWidth,
                    grabber: CGPoint(x: rect.minX, y: point.y),
                    seamStart: CGPoint(x: rect.minX, y: rect.minY),
                    seamEnd: CGPoint(x: rect.minX, y: rect.maxY),
                    primaryID: zone.id,
                    primaryHandle: .w,
                    neighborID: nil,
                    neighborHandle: nil
                ),
                abs(point.x - rect.minX)
            )
        }
        if point.x >= rect.minX + cornerClearance, point.x <= rect.maxX - cornerClearance {
            consider(
                EdgeInteraction(
                    axis: .resizeHeight,
                    grabber: CGPoint(x: point.x, y: rect.maxY),
                    seamStart: CGPoint(x: rect.minX, y: rect.maxY),
                    seamEnd: CGPoint(x: rect.maxX, y: rect.maxY),
                    primaryID: zone.id,
                    primaryHandle: .n,
                    neighborID: nil,
                    neighborHandle: nil
                ),
                abs(point.y - rect.maxY)
            )
            consider(
                EdgeInteraction(
                    axis: .resizeHeight,
                    grabber: CGPoint(x: point.x, y: rect.minY),
                    seamStart: CGPoint(x: rect.minX, y: rect.minY),
                    seamEnd: CGPoint(x: rect.maxX, y: rect.minY),
                    primaryID: zone.id,
                    primaryHandle: .s,
                    neighborID: nil,
                    neighborHandle: nil
                ),
                abs(point.y - rect.minY)
            )
        }
    }

    private func edgeHandle(for zone: Zone, handle: Handle, pointer: CGPoint) -> EdgeInteraction? {
        let rect = viewRect(for: canvasRect(of: zone))
        guard !rect.isNull else { return nil }
        switch handle {
        case .e:
            let y = min(max(pointer.y, rect.minY + cornerClearance), rect.maxY - cornerClearance)
            return EdgeInteraction(
                axis: .resizeWidth,
                grabber: CGPoint(x: rect.maxX, y: y),
                seamStart: CGPoint(x: rect.maxX, y: rect.minY),
                seamEnd: CGPoint(x: rect.maxX, y: rect.maxY),
                primaryID: zone.id,
                primaryHandle: .e,
                neighborID: nil,
                neighborHandle: nil
            )
        case .w:
            let y = min(max(pointer.y, rect.minY + cornerClearance), rect.maxY - cornerClearance)
            return EdgeInteraction(
                axis: .resizeWidth,
                grabber: CGPoint(x: rect.minX, y: y),
                seamStart: CGPoint(x: rect.minX, y: rect.minY),
                seamEnd: CGPoint(x: rect.minX, y: rect.maxY),
                primaryID: zone.id,
                primaryHandle: .w,
                neighborID: nil,
                neighborHandle: nil
            )
        case .n:
            let x = min(max(pointer.x, rect.minX + cornerClearance), rect.maxX - cornerClearance)
            return EdgeInteraction(
                axis: .resizeHeight,
                grabber: CGPoint(x: x, y: rect.maxY),
                seamStart: CGPoint(x: rect.minX, y: rect.maxY),
                seamEnd: CGPoint(x: rect.maxX, y: rect.maxY),
                primaryID: zone.id,
                primaryHandle: .n,
                neighborID: nil,
                neighborHandle: nil
            )
        case .s:
            let x = min(max(pointer.x, rect.minX + cornerClearance), rect.maxX - cornerClearance)
            return EdgeInteraction(
                axis: .resizeHeight,
                grabber: CGPoint(x: x, y: rect.minY),
                seamStart: CGPoint(x: rect.minX, y: rect.minY),
                seamEnd: CGPoint(x: rect.maxX, y: rect.minY),
                primaryID: zone.id,
                primaryHandle: .s,
                neighborID: nil,
                neighborHandle: nil
            )
        case .ne, .nw, .se, .sw:
            return cornerHandle(for: zone, handle: handle, rect: rect)
        }
    }

    private func cornerHandle(for zone: Zone, handle: Handle, rect: CGRect) -> EdgeInteraction {
        let corner: CGPoint
        let axis: SplitAxis
        let outward: CGPoint
        switch handle {
        case .ne:
            corner = CGPoint(x: rect.maxX, y: rect.maxY)
            axis = .resizeDiagonalNESW
            outward = CGPoint(x: 1, y: 1)
        case .nw:
            corner = CGPoint(x: rect.minX, y: rect.maxY)
            axis = .resizeDiagonalNWSE
            outward = CGPoint(x: -1, y: 1)
        case .se:
            corner = CGPoint(x: rect.maxX, y: rect.minY)
            axis = .resizeDiagonalNWSE
            outward = CGPoint(x: 1, y: -1)
        case .sw:
            corner = CGPoint(x: rect.minX, y: rect.minY)
            axis = .resizeDiagonalNESW
            outward = CGPoint(x: -1, y: -1)
        default:
            corner = CGPoint(x: rect.midX, y: rect.midY)
            axis = .resizeWidth
            outward = CGPoint(x: 1, y: 0)
        }
        let len = max(hypot(outward.x, outward.y), 0.001)
        let dir = CGPoint(x: outward.x / len, y: outward.y / len)
        return EdgeInteraction(
            axis: axis,
            grabber: CGPoint(x: corner.x + dir.x * cornerOutset, y: corner.y + dir.y * cornerOutset),
            seamStart: corner,
            seamEnd: corner,
            primaryID: zone.id,
            primaryHandle: handle,
            neighborID: nil,
            neighborHandle: nil
        )
    }

    private func handle(at point: CGPoint, in rect: CGRect) -> Handle? {
        let spots: [(Handle, CGPoint)] = [
            (.nw, CGPoint(x: rect.minX, y: rect.maxY)),
            (.ne, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.sw, CGPoint(x: rect.minX, y: rect.minY)),
            (.se, CGPoint(x: rect.maxX, y: rect.minY)),
            (.n, CGPoint(x: rect.midX, y: rect.maxY)),
            (.s, CGPoint(x: rect.midX, y: rect.minY)),
            (.w, CGPoint(x: rect.minX, y: rect.midY)),
            (.e, CGPoint(x: rect.maxX, y: rect.midY)),
        ]
        return spots.first { hypot($0.1.x - point.x, $0.1.y - point.y) < 10 }?.0
    }

    private func resize(_ rect: NormalizedRect, handle: Handle, dx: Double, dy: Double, lockAspect: Bool) -> NormalizedRect {
        var r = rect
        switch handle {
        case .e: r.width += dx
        case .w: r.x += dx; r.width -= dx
        case .n: r.y += dy; r.height -= dy
        case .s: r.height += dy
        case .ne: r.y += dy; r.height -= dy; r.width += dx
        case .nw: r.x += dx; r.width -= dx; r.y += dy; r.height -= dy
        case .se: r.width += dx; r.height += dy
        case .sw: r.x += dx; r.width -= dx; r.height += dy
        }
        if lockAspect {
            let usingWidth: Bool
            switch handle {
            case .e, .w, .ne, .nw, .se, .sw:
                usingWidth = abs(dx) >= abs(dy)
            case .n, .s:
                usingWidth = false
            }
            r = ZonePixelMetrics.preservingAspect(from: rect, resized: r, usingWidth: usingWidth)
        }
        return r
    }

    private func zoomFactor(from delta: CGFloat) -> Double {
        max(0.85, min(1.18, 1 + Double(delta) * 0.004))
    }

    /// View is not flipped: origin bottom-left. NormalizedRect y=0 is the top of the work area.
    private func viewRect(for n: NormalizedRect) -> CGRect {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return .null }
        return CGRect(
            x: n.x * w,
            y: (1 - n.y - n.height) * h,
            width: n.width * w,
            height: n.height * h
        )
    }

    private func normalized(fromView rect: CGRect) -> NormalizedRect {
        let w = max(bounds.width, 1)
        let h = max(bounds.height, 1)
        return NormalizedRect(
            x: rect.minX / w,
            y: (h - rect.maxY) / h,
            width: rect.width / w,
            height: rect.height / h
        ).clamped()
    }

    private func rubberBand(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func closeButtonRect(for zoneRect: CGRect) -> CGRect {
        CGRect(
            x: zoneRect.maxX - closeButtonInset - closeButtonSize,
            y: zoneRect.maxY - closeButtonInset - closeButtonSize,
            width: closeButtonSize,
            height: closeButtonSize
        )
    }

    private func drawSplitHandle(_ edge: EdgeInteraction) {
        switch edge.primaryHandle {
        case .ne, .nw, .se, .sw:
            if #available(macOS 15.0, *) {
                // AppKit supplies the exact system corner-resize cursor, including
                // its stroke, shadow, hot spot, and accessibility-scaled appearance.
                return
            }
            ResizeGlyph.drawCornerPair(at: edge.seamStart, outward: outwardUnit(for: edge.primaryHandle))
        default:
            if edge.isLinked {
                ResizeGlyph.drawSystemDivider(at: edge.grabber, verticalSeam: edge.axis == .resizeWidth)
            } else {
                ResizeGlyph.drawPairedTicks(at: edge.grabber, rotation: rotation(for: edge.axis))
            }
        }
    }

    private func drawCloseButton(in rect: CGRect, highlighted: Bool) {
        let circle = NSBezierPath(ovalIn: rect)
        NSColor.black.withAlphaComponent(highlighted ? 0.55 : 0.4).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        let inset = rect.insetBy(dx: 6, dy: 6)
        let xPath = NSBezierPath()
        xPath.move(to: CGPoint(x: inset.minX, y: inset.minY))
        xPath.line(to: CGPoint(x: inset.maxX, y: inset.maxY))
        xPath.move(to: CGPoint(x: inset.minX, y: inset.maxY))
        xPath.line(to: CGPoint(x: inset.maxX, y: inset.minY))
        xPath.lineWidth = 2
        xPath.lineCapStyle = .round
        NSColor.white.setStroke()
        xPath.stroke()
    }
}

/// macOS Sequoia-style tiling ticks: two small black triangles with a white rim.
private enum ResizeGlyph {
    static let tickLength: CGFloat = 6.2
    static let tickBase: CGFloat = 6.8
    static let pairSpacing: CGFloat = 6.5

    static func linkedHitRect(center: CGPoint, verticalSeam: Bool) -> CGRect {
        let along: CGFloat = 22
        let across: CGFloat = 28
        if verticalSeam {
            return CGRect(x: center.x - across / 2, y: center.y - along / 2, width: across, height: along)
        }
        return CGRect(x: center.x - along / 2, y: center.y - across / 2, width: along, height: across)
    }

    static func drawSystemDivider(at center: CGPoint, verticalSeam: Bool) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = true
        let pillWidth: CGFloat = verticalSeam ? 6 : 28
        let pillHeight: CGFloat = verticalSeam ? 28 : 6
        let pill = CGRect(
            x: center.x - pillWidth / 2,
            y: center.y - pillHeight / 2,
            width: pillWidth,
            height: pillHeight
        )
        let path = NSBezierPath(
            roundedRect: pill,
            xRadius: min(pillWidth, pillHeight) / 2,
            yRadius: min(pillWidth, pillHeight) / 2
        )
        NSColor.black.withAlphaComponent(0.22).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        NSColor.white.setFill()
        path.fill()
        let tickOffset: CGFloat = 13
        if verticalSeam {
            drawTick(at: CGPoint(x: center.x - tickOffset, y: center.y), pointing: CGPoint(x: -1, y: 0))
            drawTick(at: CGPoint(x: center.x + tickOffset, y: center.y), pointing: CGPoint(x: 1, y: 0))
        } else {
            drawTick(at: CGPoint(x: center.x, y: center.y - tickOffset), pointing: CGPoint(x: 0, y: -1))
            drawTick(at: CGPoint(x: center.x, y: center.y + tickOffset), pointing: CGPoint(x: 0, y: 1))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func drawPairedTicks(at center: CGPoint, rotation: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = true
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: rotation)
        transform.concat()
        drawTick(at: CGPoint(x: -pairSpacing, y: 0), pointing: CGPoint(x: -1, y: 0))
        drawTick(at: CGPoint(x: pairSpacing, y: 0), pointing: CGPoint(x: 1, y: 0))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Two ticks wrapping the outside of a rounded corner, each pointing radially out.
    /// NE (screenshot): one more to the right, one more to the top. Other corners are that
    /// same quarter-circle, rotated.
    static func drawCornerPair(at corner: CGPoint, outward: CGPoint) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = true
        let ox: CGFloat = outward.x >= 0 ? 1 : -1
        let oy: CGFloat = outward.y >= 0 ? 1 : -1
        let inset: CGFloat = 3
        let radius: CGFloat = 8
        let distance = radius + 5.5
        let body = CGPoint(x: corner.x - ox * inset, y: corner.y - oy * inset)
        let cx = body.x - ox * radius
        let cy = body.y - oy * radius

        // 0° = east, 90° = north. Two angles near the corner peak.
        let degrees: [CGFloat]
        switch (ox > 0, oy > 0) {
        case (true, true):   degrees = [CGFloat(34), CGFloat(56)]
        case (false, true):  degrees = [CGFloat(124), CGFloat(146)]
        case (true, false):  degrees = [CGFloat(-34), CGFloat(-56)]
        case (false, false): degrees = [CGFloat(214), CGFloat(236)]
        }

        for deg in degrees {
            let ang = deg * .pi / 180
            let pos = CGPoint(x: cx + cos(ang) * distance, y: cy + sin(ang) * distance)
            drawTick(at: pos, pointing: CGPoint(x: cos(ang), y: sin(ang)))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func drawTick(at center: CGPoint, pointing dir: CGPoint) {
        let len = max(hypot(dir.x, dir.y), 0.001)
        let d = CGPoint(x: dir.x / len, y: dir.y / len)
        let p = CGPoint(x: -d.y, y: d.x)
        let tip = CGPoint(x: center.x + d.x * tickLength * 0.62, y: center.y + d.y * tickLength * 0.62)
        let back = CGPoint(x: center.x - d.x * tickLength * 0.38, y: center.y - d.y * tickLength * 0.38)
        let a = CGPoint(x: back.x + p.x * tickBase * 0.5, y: back.y + p.y * tickBase * 0.5)
        let b = CGPoint(x: back.x - p.x * tickBase * 0.5, y: back.y - p.y * tickBase * 0.5)

        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: a)
        path.line(to: b)
        path.close()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        NSColor.white.setStroke()
        path.lineWidth = 1.4
        path.stroke()
        NSColor.black.setFill()
        path.fill()
    }
}
