import AppKit
import ZoneBoxCore

enum LayoutThumbnailRenderer {
    static func image(
        for layout: Layout,
        size: NSSize,
        fill: NSColor,
        stroke: NSColor,
        gutterPoints: CGFloat = 0,
        showNumbers: Bool = false
    ) -> NSImage {
        let zones = LayoutTemplates.thumbnailGeometry(for: layout)
        let image = NSImage(size: size, flipped: false) { rect in
            let canvas = rect.insetBy(dx: 0.5, dy: 0.5)
            guard canvas.width > 1, canvas.height > 1, !zones.isEmpty else { return true }
            let panes = zones.map { zone in
                CGRect(
                    x: canvas.minX + zone.rect.x * canvas.width,
                    y: canvas.minY + (1 - zone.rect.y - zone.rect.height) * canvas.height,
                    width: zone.rect.width * canvas.width,
                    height: zone.rect.height * canvas.height
                )
            }
            // Keep tiny menu thumbnails legible while preserving the configured gap proportion.
            let maximumGutter = min(canvas.width, canvas.height) * 0.20
            let effectiveGutter = min(max(0, gutterPoints), maximumGutter)
            let gutteredPanes = Gutter.apply(panes, gutter: effectiveGutter, workAreaAX: canvas)
            for (zone, gutteredPane) in zip(zones, gutteredPanes) {
                let pane = gutteredPane.insetBy(dx: 0.4, dy: 0.4)
                guard pane.width > 0.5, pane.height > 0.5 else { continue }
                let path = NSBezierPath(roundedRect: pane, xRadius: 1.6, yRadius: 1.6)
                fill.setFill()
                path.fill()
                stroke.setStroke()
                path.lineWidth = 0.7
                path.stroke()
                guard showNumbers else { continue }
                let label = "\(zone.number)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: max(5, min(pane.width, pane.height) * 0.32), weight: .semibold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                ]
                let size = label.size(withAttributes: attrs)
                label.draw(
                    at: CGPoint(
                        x: pane.midX - size.width / 2,
                        y: pane.midY - size.height / 2
                    ),
                    withAttributes: attrs
                )
            }
            return true
        }
        image.resizingMode = .stretch
        return image
    }

    static func menuImage(for layout: Layout, gutterPoints: CGFloat = 0) -> NSImage {
        let image = self.image(
            for: layout,
            size: NSSize(width: 20, height: 12),
            fill: NSColor.black,
            stroke: NSColor.black.withAlphaComponent(0.35),
            gutterPoints: gutterPoints
        )
        image.isTemplate = true
        return image
    }
}
