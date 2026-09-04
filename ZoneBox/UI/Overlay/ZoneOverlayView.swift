import AppKit
import ZoneBoxCore

final class ZoneOverlayView: NSView {
    var zones: [ResolvedZone] = []
    var highlightID: UUID? {
        didSet { startHighlightTransition() }
    }
    var highlightFrameAX: CGRect? {
        didSet { startHighlightTransition() }
    }
    var showNumbers = true
    var inactiveOpacity = 0.20
    var activeOpacity = 0.40
    var fillColor = NSColor.systemBlue
    var borderColor = NSColor.white
    var primaryFlipHeight: CGFloat = 0
    var presentation = OverlayPresentation.empty
    private var displayedHighlightFrame: CGRect?
    private var highlightAnimation: Timer?
    private var committedHighlightFrame: CGRect?

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for zone in zones {
            let rect = CoordinateConverter.appKitRect(fromAX: zone.frameAX, primaryFlipHeight: primaryFlipHeight)
            let local = convertFromScreen(rect)
            let highlighted = displayedHighlightFrame == nil && zone.zoneID == highlightID
            let fill = fillColor.withAlphaComponent(highlighted ? previewActiveOpacity : previewInactiveOpacity)
            fill.setFill()
            let path = NSBezierPath(roundedRect: local.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
            path.fill()
            borderColor.withAlphaComponent(highlighted ? 0.9 : 0.5).setStroke()
            path.lineWidth = highlighted ? 4 : 2
            path.stroke()
            if showNumbers {
                let label = "\(zone.number)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                ]
                let size = label.size(withAttributes: attrs)
                label.draw(at: NSPoint(x: local.midX - size.width / 2, y: local.midY - size.height / 2), withAttributes: attrs)
            }
        }
        if let highlightAX = displayedHighlightFrame ?? highlightFrameAX {
            let rect = CoordinateConverter.appKitRect(fromAX: highlightAX, primaryFlipHeight: primaryFlipHeight)
            let local = convertFromScreen(rect)
            fillColor.withAlphaComponent(activeOpacity).setFill()
            let path = NSBezierPath(roundedRect: local.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
            path.fill()
            borderColor.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 4
            path.stroke()
        }
        drawStrip()
        drawLayoutName()
    }

    private func drawStrip() {
        guard let strip = presentation.strip else { return }
        let geometry = strip.geometry
        let chrome = convertFromScreen(geometry.frameAppKit)
        NSColor.black.withAlphaComponent(0.58).setFill()
        let chromePath = NSBezierPath(roundedRect: chrome, xRadius: 16, yRadius: 16)
        chromePath.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        chromePath.lineWidth = 1
        chromePath.stroke()

        for card in geometry.cards {
            let cardLocal = convertFromScreen(card.frameAppKit)
            let selected = card.layoutID == strip.highlightedLayoutID || (card.isAssigned && strip.highlightedLayoutID == nil)
            if selected {
                fillColor.withAlphaComponent(0.28).setFill()
            } else {
                NSColor.white.withAlphaComponent(0.08).setFill()
            }
            let cardPath = NSBezierPath(roundedRect: cardLocal, xRadius: LayoutStripGeometry.cardCorner, yRadius: LayoutStripGeometry.cardCorner)
            cardPath.fill()
            if selected {
                fillColor.withAlphaComponent(0.98).setStroke()
                cardPath.lineWidth = 3
                cardPath.stroke()
                NSColor.white.withAlphaComponent(0.95).setStroke()
                let inner = NSBezierPath(
                    roundedRect: cardLocal.insetBy(dx: 2.5, dy: 2.5),
                    xRadius: max(4, LayoutStripGeometry.cardCorner - 2),
                    yRadius: max(4, LayoutStripGeometry.cardCorner - 2)
                )
                inner.lineWidth = 1.4
                inner.stroke()
            } else {
                NSColor.white.withAlphaComponent(0.22).setStroke()
                cardPath.lineWidth = 1
                cardPath.stroke()
            }

            for zone in card.zones {
                var pane = convertFromScreen(zone.frameAppKit).insetBy(dx: 1, dy: 1)
                let highlighted = selected && strip.highlightedZoneNumber == zone.number
                if highlighted {
                    let cx = pane.midX
                    let cy = pane.midY
                    pane = pane.insetBy(dx: -pane.width * 0.08, dy: -pane.height * 0.08)
                    pane.origin.x = cx - pane.width / 2
                    pane.origin.y = cy - pane.height / 2
                }
                if highlighted {
                    fillColor.withAlphaComponent(1).setFill()
                } else if selected {
                    fillColor.withAlphaComponent(0.42).setFill()
                } else {
                    fillColor.withAlphaComponent(0.32).setFill()
                }
                let zonePath = NSBezierPath(roundedRect: pane, xRadius: 3, yRadius: 3)
                zonePath.fill()
                if highlighted {
                    NSColor.white.setStroke()
                    zonePath.lineWidth = 2.4
                } else {
                    NSColor.white.withAlphaComponent(selected ? 0.42 : 0.28).setStroke()
                    zonePath.lineWidth = 0.8
                }
                zonePath.stroke()
            }

            let name = L10n.layoutDisplayName(card.layoutName) as NSString
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: selected ? .semibold : .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(selected ? 1 : 0.72),
            ]
            let nameSize = name.size(withAttributes: nameAttrs)
            name.draw(
                at: NSPoint(
                    x: cardLocal.midX - nameSize.width / 2,
                    y: cardLocal.minY + 3
                ),
                withAttributes: nameAttrs
            )
        }

        if let overflow = geometry.overflowFrameAppKit {
            drawOverflow(overflow, symbol: "›")
        }
        if let overflow = geometry.leadingOverflowFrameAppKit {
            drawOverflow(overflow, symbol: "‹")
        }
    }

    private func drawOverflow(_ frameAppKit: CGRect, symbol: String) {
        let local = convertFromScreen(frameAppKit)
        NSColor.white.withAlphaComponent(0.18).setFill()
        let path = NSBezierPath(roundedRect: local, xRadius: 8, yRadius: 8)
        path.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
        let label = symbol as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(x: local.midX - size.width / 2, y: local.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private func drawLayoutName() {
        guard let name = presentation.layoutName, !name.isEmpty else { return }
        let text = name as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pad = NSSize(width: 18, height: 10)
        let bubble = CGRect(
            x: ((bounds.width - size.width) / 2 - pad.width).rounded(),
            y: (bounds.midY - (size.height + pad.height * 2) / 2).rounded(),
            width: size.width + pad.width * 2,
            height: size.height + pad.height * 2
        )
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 14, yRadius: 14).fill()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        let stroke = NSBezierPath(roundedRect: bubble, xRadius: 14, yRadius: 14)
        stroke.lineWidth = 1.2
        stroke.stroke()
        text.draw(
            at: NSPoint(x: bubble.minX + pad.width, y: bubble.minY + pad.height),
            withAttributes: attrs
        )
    }

    private func convertFromScreen(_ screenRect: CGRect) -> CGRect {
        guard let window else { return screenRect }
        let windowRect = window.convertFromScreen(screenRect)
        return convert(windowRect, from: nil)
    }

    private var previewInactiveOpacity: CGFloat {
        presentation.layoutName == nil ? inactiveOpacity : max(inactiveOpacity, 0.34)
    }

    private var previewActiveOpacity: CGFloat {
        presentation.layoutName == nil ? activeOpacity : max(activeOpacity, 0.52)
    }

    private func currentHighlightFrameAX() -> CGRect? {
        if let highlightFrameAX { return highlightFrameAX }
        if let highlightID, let zone = zones.first(where: { $0.zoneID == highlightID }) {
            return zone.frameAX
        }
        return nil
    }

    private func startHighlightTransition() {
        let target = currentHighlightFrameAX()
        highlightAnimation?.invalidate()
        highlightAnimation = nil
        defer { committedHighlightFrame = target }
        guard let from = committedHighlightFrame, let to = target, from != to else {
            displayedHighlightFrame = nil
            needsDisplay = true
            return
        }
        let duration: TimeInterval = 0.012
        let started = Date()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let t = min(1, Date().timeIntervalSince(started) / duration)
            self.displayedHighlightFrame = CGRect(
                x: from.minX + (to.minX - from.minX) * t,
                y: from.minY + (to.minY - from.minY) * t,
                width: from.width + (to.width - from.width) * t,
                height: from.height + (to.height - from.height) * t
            )
            self.needsDisplay = true
            if t >= 1 {
                timer.invalidate()
                self.highlightAnimation = nil
                self.displayedHighlightFrame = nil
                self.committedHighlightFrame = to
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        highlightAnimation = timer
    }
}
