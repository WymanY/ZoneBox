import AppKit
import ZoneBoxCore

@MainActor
final class DividerOverlayView: NSView {
    var handles: [DividerHandleSpec] = [] {
        didSet {
            needsDisplay = true
            updateTrackingAreas()
        }
    }
    var primaryFlipHeight: CGFloat = 0
    var highlightedIndex: Int?
    var onBeginDrag: ((DividerHandleSpec) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onEndDrag: (() -> Void)?
    var onCancelDrag: (() -> Void)?

    private var trackingAreasStorage: [NSTrackingArea] = []
    private var dragging = false

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreasStorage {
            removeTrackingArea(area)
        }
        trackingAreasStorage.removeAll()
        guard !handles.isEmpty else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreasStorage.append(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        applyCursor(at: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        applyCursor(at: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        applyCursor(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        guard !dragging else { return }
        highlightedIndex = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let screenPoint = convertPointToScreen(event.locationInWindow)
        guard let index = handleIndex(atAppKit: screenPoint) else { return }
        dragging = true
        highlightedIndex = index
        needsDisplay = true
        applyCursor(for: handles[index])
        onBeginDrag?(handles[index])
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        onDrag?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        onEndDrag?()
        applyCursor(at: event.locationInWindow)
    }

    override func cancelOperation(_ sender: Any?) {
        guard dragging else { return }
        resetInteraction()
        onCancelDrag?()
    }

    func resetInteraction() {
        dragging = false
        highlightedIndex = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !handles.isEmpty else { return }
        for (index, handle) in handles.enumerated() {
            let emphasized = highlightedIndex == index || dragging
            DividerGlyph.drawSystemDivider(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                verticalSeam: handle.isVertical,
                emphasized: emphasized
            )
        }
    }

    func handleIndex(atAppKit point: NSPoint) -> Int? {
        guard !handles.isEmpty else { return nil }
        let screenRect = window?.convertToScreen(convert(bounds, to: nil)) ?? bounds
        return screenRect.contains(point) ? 0 : nil
    }

    private func applyCursor(at windowPoint: NSPoint) {
        let screenPoint = convertPointToScreen(windowPoint)
        guard let index = handleIndex(atAppKit: screenPoint) else {
            highlightedIndex = dragging ? highlightedIndex : nil
            if !dragging { NSCursor.arrow.set() }
            needsDisplay = true
            return
        }
        highlightedIndex = index
        applyCursor(for: handles[index])
        needsDisplay = true
    }

    private func applyCursor(for handle: DividerHandleSpec) {
        (handle.isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
    }

    private func convertPointToScreen(_ windowPoint: NSPoint) -> NSPoint {
        window?.convertToScreen(NSRect(origin: windowPoint, size: .zero)).origin ?? windowPoint
    }
}

private enum DividerGlyph {
    static let tickLength: CGFloat = 6.2
    static let tickBase: CGFloat = 6.8

    static func drawSystemDivider(at center: CGPoint, verticalSeam: Bool, emphasized: Bool) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = true
        let pillWidth: CGFloat = verticalSeam ? (emphasized ? 8 : 6) : (emphasized ? 36 : 28)
        let pillHeight: CGFloat = verticalSeam ? (emphasized ? 36 : 28) : (emphasized ? 8 : 6)
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
        NSColor.black.withAlphaComponent(emphasized ? 0.28 : 0.22).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        NSColor.white.withAlphaComponent(emphasized ? 1 : 0.92).setFill()
        path.fill()
        // Keep the emphasized ticks inside the handle-sized panel. Window-level
        // hit testing is rectangular, so growing the panel would steal clicks
        // outside the advertised hit target.
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
