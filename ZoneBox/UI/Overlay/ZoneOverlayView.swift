import AppKit
import ZoneBoxCore

final class ZoneOverlayView: NSView {
    var zones: [ResolvedZone] = []
    var highlightID: UUID?
    var showNumbers = true
    var inactiveOpacity = 0.20
    var activeOpacity = 0.40
    var fillColor = NSColor.systemBlue
    var borderColor = NSColor.white
    var primaryFlipHeight: CGFloat = 0

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for zone in zones {
            let rect = CoordinateConverter.appKitRect(fromAX: zone.frameAX, primaryFlipHeight: primaryFlipHeight)
            let local = convertFromScreen(rect)
            let highlighted = zone.zoneID == highlightID
            let fill = fillColor.withAlphaComponent(highlighted ? activeOpacity : inactiveOpacity)
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
    }

    private func convertFromScreen(_ screenRect: CGRect) -> CGRect {
        guard let window else { return screenRect }
        let windowRect = window.convertFromScreen(screenRect)
        return convert(windowRect, from: nil)
    }
}
