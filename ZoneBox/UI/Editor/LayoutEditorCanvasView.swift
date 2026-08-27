import AppKit
import ZoneBoxCore

final class LayoutEditorCanvasView: NSView {
    var layout: Layout {
        didSet {
            if let selectedID, !layout.zones.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
            needsDisplay = true
        }
    }
    var primaryFlipHeight: CGFloat
    var workAreaAX: CGRect
    var selectedID: UUID? {
        didSet { needsDisplay = true }
    }
    var onChange: ((Layout) -> Void)?
    var onCancel: (() -> Void)?
    var onInteractionChange: ((Bool) -> Void)?

    private enum DragKind {
        case create(start: CGPoint)
        case move(id: UUID, startRect: NormalizedRect, start: CGPoint)
        case resize(id: UUID, startRect: NormalizedRect, start: CGPoint, handle: Handle)
        case split(
            axis: SplitAxis,
            firstID: UUID,
            firstRect: NormalizedRect,
            secondID: UUID,
            secondRect: NormalizedRect,
            start: CGPoint
        )
        case close
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
    private let closeButtonSize: CGFloat = 22
    private let closeButtonInset: CGFloat = 8
    private let edgeSlop: CGFloat = 12
    /// Wider than a single-edge hit so the always-visible linked sash is easy to grab.
    private let linkedEdgeSlop: CGFloat = 20
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
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func cursorUpdate(with event: NSEvent) {
        applyCursor()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()

        let zones = layout.zones.sorted(by: { $0.number < $1.number })
        for zone in zones {
            let rect = viewRect(for: canvasRect(of: zone))
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
            let selected = zone.id == selectedID
            let body = rect.insetBy(dx: 3, dy: 3)
            NSColor.systemBlue.withAlphaComponent(selected ? 0.35 : 0.18).setFill()
            let path = NSBezierPath(roundedRect: body, xRadius: 8, yRadius: 8)
            path.fill()
            NSColor.white.withAlphaComponent(selected ? 0.95 : 0.6).setStroke()
            path.lineWidth = selected ? 3 : 1.5
            path.stroke()

            let label = "\(zone.number)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 36, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attrs
            )
        }

        if let edge = visibleSplitHandle() {
            drawSplitHandle(edge)
        }

        for zone in zones {
            let rect = viewRect(for: canvasRect(of: zone))
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
            drawCloseButton(in: closeButtonRect(for: rect), highlighted: zone.id == selectedID)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if let zone = hitZone(at: point), closeButtonRect(for: viewRect(for: canvasRect(of: zone))).contains(point) {
            deleteZone(id: zone.id)
            drag = .close
            hoverEdge = nil
            setInteracting(false)
            return
        }

        if let edge = edgeInteraction(at: point) {
            selectedID = edge.primaryID
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
            setInteracting(true)
            applyCursor()
            needsDisplay = true
            return
        }

        if let zone = hitZone(at: point) {
            selectedID = zone.id
            let rect = canvasRect(of: zone)
            if let handle = handle(at: point, in: viewRect(for: rect)) {
                drag = .resize(id: zone.id, startRect: rect, start: point, handle: handle)
            } else {
                drag = .move(id: zone.id, startRect: rect, start: point)
            }
        } else {
            selectedID = nil
            drag = .create(start: point)
        }
        hoverEdge = nil
        setInteracting(true)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .create(let start):
            let rect = rubberBand(from: start, to: point)
            guard rect.width >= 24, rect.height >= 24 else { return }
            upsertCreatingZone(normalized(fromView: rect))
        case .move(let id, let startRect, let start):
            let dx = Double((point.x - start.x) / max(bounds.width, 1))
            let dy = Double(-(point.y - start.y) / max(bounds.height, 1))
            updateZone(id) { zone in
                var r = startRect
                r.x += dx
                r.y += dy
                zone.canvasRect = r.clamped()
            }
        case .resize(let id, let startRect, let start, let handle):
            let dx = Double((point.x - start.x) / max(bounds.width, 1))
            let dy = Double(-(point.y - start.y) / max(bounds.height, 1))
            updateZone(id) { zone in
                zone.canvasRect = resize(startRect, handle: handle, dx: dx, dy: dy).clamped()
            }
            if let zone = layout.zones.first(where: { $0.id == id }) {
                hoverEdge = edgeHandle(for: zone, handle: handle, pointer: point)
            }
        case .split(let axis, let firstID, let firstRect, let secondID, let secondRect, let start):
            applySplitDrag(
                axis: axis,
                firstID: firstID,
                firstRect: firstRect,
                secondID: secondID,
                secondRect: secondRect,
                start: start,
                point: point
            )
        case .close, nil:
            break
        }
        commit()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if case .create(let start) = drag {
            let traveled = hypot(point.x - start.x, point.y - start.y)
            if let last = layout.zones.last, last.name == "__creating" {
                layout.zones[layout.zones.count - 1].name = nil
                selectedID = last.id
            } else if traveled < 8 {
                createDefaultZone(at: start)
            }
        }
        drag = nil
        setInteracting(false)
        ensureCanvas()
        refreshHover(at: point)
        commit()
    }

    override func scrollWheel(with event: NSEvent) {
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

        // Axis from modifiers only. Do not inspect deltaX to decide width —
        // vertical trackpad swipes always leak a horizontal component, and a
        // decaying gesture often ends with |dx| > |dy|.
        let axes = ZoneScrollZoom.axes(
            option: event.modifierFlags.contains(.option),
            shift: event.modifierFlags.contains(.shift)
        )
        let widthFactor: Double?
        let heightFactor: Double?
        switch axes {
        case .both:
            let delta = abs(dy) >= abs(dx) ? dy : dx
            guard abs(delta) >= 0.01 else { return }
            let factor = zoomFactor(from: delta)
            widthFactor = factor
            heightFactor = factor
        case .width:
            let delta = dy + dx
            guard abs(delta) >= 0.01 else { return }
            widthFactor = zoomFactor(from: delta)
            heightFactor = nil
        case .height:
            guard abs(dy) >= 0.01 else { return }
            widthFactor = nil
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
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        if event.keyCode == 48 {
            cycleSelection(forward: !event.modifierFlags.contains(.shift))
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            if let selectedID {
                deleteZone(id: selectedID)
            }
            return
        }
        super.keyDown(with: event)
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

    func cycleSelection(forward: Bool) {
        guard drag == nil else { return }
        window?.makeFirstResponder(self)
        selectedID = layout.cycledZoneID(from: selectedID, forward: forward)
    }

    private func createDefaultZone(at point: CGPoint) {
        ensureCanvas()
        let width = min(280, max(140, bounds.width * 0.28))
        let height = min(200, max(110, bounds.height * 0.24))
        var rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        rect.origin.x = min(max(0, rect.origin.x), max(0, bounds.width - rect.width))
        rect.origin.y = min(max(0, rect.origin.y), max(0, bounds.height - rect.height))
        let number = (layout.zones.map(\.number).max() ?? 0) + 1
        let zone = Zone(number: number, canvasRect: normalized(fromView: rect))
        layout.zones.append(zone)
        selectedID = zone.id
    }

    private func upsertCreatingZone(_ rect: NormalizedRect) {
        ensureCanvas()
        if let last = layout.zones.last, last.name == "__creating" {
            layout.zones[layout.zones.count - 1].canvasRect = rect
        } else {
            let number = (layout.zones.map(\.number).max() ?? 0) + 1
            layout.zones.append(Zone(number: number, name: "__creating", canvasRect: rect))
        }
    }

    private func deleteZone(id: UUID) {
        layout.zones.removeAll { $0.id == id }
        layout = layout.packedNumbers()
        if selectedID == id { selectedID = nil }
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

    private func commit() {
        onChange?(layout)
        needsDisplay = true
    }

    private func ensureCanvas() {
        if layout.kind == .grid {
            layout = (try? layout.convertingGridToCanvas(workAreaAX: workAreaAX)) ?? layout
        }
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
        if let rect = zone.canvasRect { return rect }
        if let resolved = try? resolveLayout(layout, workAreaAX: workAreaAX, gutter: 0),
           let match = resolved.first(where: { $0.zoneID == zone.id }) {
            return NormalizedRect.normalize(match.frameAX, in: workAreaAX)
        }
        return NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
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
        let next = edgeInteraction(at: point)
        if next != hoverEdge {
            hoverEdge = next
            needsDisplay = true
        }
        applyCursor()
    }

    private func applyCursor() {
        if visibleSplitHandle() != nil {
            Self.hiddenCursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func visibleSplitHandle() -> EdgeInteraction? {
        switch drag {
        case .create, .move, .close: return nil
        case .resize, .split, nil: return hoverEdge
        }
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

    private func resize(_ rect: NormalizedRect, handle: Handle, dx: Double, dy: Double) -> NormalizedRect {
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
            ResizeGlyph.drawCornerPair(at: edge.seamStart, outward: outwardUnit(for: edge.primaryHandle))
        default:
            ResizeGlyph.drawPairedTicks(at: edge.grabber, rotation: rotation(for: edge.axis))
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
