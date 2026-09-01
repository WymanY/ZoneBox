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
        drawCandidateOutlines()
        drawCandidateLabel()
        drawStrip()
        drawLayoutName()
    }

    private func drawCandidateOutlines() {
        for frameAX in presentation.candidateOutlinesAX {
            let rect = CoordinateConverter.appKitRect(fromAX: frameAX, primaryFlipHeight: primaryFlipHeight)
            let local = convertFromScreen(rect).insetBy(dx: 3, dy: 3)
            guard local.width > 4, local.height > 4 else { continue }
            let path = NSBezierPath(roundedRect: local, xRadius: 10, yRadius: 10)
            NSColor.white.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 1.5
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
        }
    }

    private func drawCandidateLabel() {
        guard let label = presentation.candidateLabel else { return }
        let rect = CoordinateConverter.appKitRect(fromAX: label.anchorAX, primaryFlipHeight: primaryFlipHeight)
        let local = convertFromScreen(rect)
        let text = label.text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pad = NSSize(width: 8, height: 5)
        let bubble = CGRect(
            x: local.minX + 10,
            y: local.maxY - size.height - pad.height * 2 - 10,
            width: size.width + pad.width * 2,
            height: size.height + pad.height * 2
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 6, yRadius: 6).fill()
        text.draw(
            at: NSPoint(x: bubble.minX + pad.width, y: bubble.minY + pad.height),
            withAttributes: attrs
        )
    }

    private func drawStrip() {
        guard let strip = presentation.strip else { return }
        let geometry = strip.geometry
        let chrome = convertFromScreen(geometry.frameAppKit)
        NSColor.black.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: chrome, xRadius: 14, yRadius: 14).fill()

        for card in geometry.cards {
            let cardLocal = convertFromScreen(card.frameAppKit)
            let selected = card.layoutID == strip.highlightedLayoutID || (card.isAssigned && strip.highlightedLayoutID == nil)
            NSColor.white.withAlphaComponent(selected ? 0.18 : 0.10).setFill()
            let cardPath = NSBezierPath(roundedRect: cardLocal, xRadius: LayoutStripGeometry.cardCorner, yRadius: LayoutStripGeometry.cardCorner)
            cardPath.fill()
            if selected {
                NSColor.white.withAlphaComponent(0.9).setStroke()
                cardPath.lineWidth = 2
                cardPath.stroke()
            } else {
                NSColor.white.withAlphaComponent(0.35).setStroke()
                cardPath.lineWidth = 1
                cardPath.stroke()
            }

            for zone in card.zones {
                var pane = convertFromScreen(zone.frameAppKit).insetBy(dx: 1, dy: 1)
                let highlighted = selected && strip.highlightedZoneNumber == zone.number
                if highlighted {
                    let cx = pane.midX
                    let cy = pane.midY
                    pane = pane.insetBy(dx: -pane.width * 0.05, dy: -pane.height * 0.05)
                    pane.origin.x = cx - pane.width / 2
                    pane.origin.y = cy - pane.height / 2
                }
                fillColor.withAlphaComponent(highlighted ? 0.85 : 0.45).setFill()
                let zonePath = NSBezierPath(roundedRect: pane, xRadius: 3, yRadius: 3)
                zonePath.fill()
                NSColor.white.withAlphaComponent(highlighted ? 0.95 : 0.55).setStroke()
                zonePath.lineWidth = highlighted ? 1.6 : 0.8
                zonePath.stroke()
            }

            let name = L10n.layoutDisplayName(card.layoutName) as NSString
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
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
            let local = convertFromScreen(overflow)
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: local, xRadius: 8, yRadius: 8).fill()
            let dots = "⋯" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
            let size = dots.size(withAttributes: attrs)
            dots.draw(
                at: NSPoint(x: local.midX - size.width / 2, y: local.midY - size.height / 2),
                withAttributes: attrs
            )
        }
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
