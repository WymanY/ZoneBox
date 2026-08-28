import AppKit
import ZoneBoxCore

enum LayoutThumbnailRenderer {
    static func image(
        for layout: Layout,
        size: NSSize,
        fill: NSColor,
        stroke: NSColor
    ) -> NSImage {
        let zones = LayoutTemplates.thumbnailGeometry(for: layout)
        let image = NSImage(size: size, flipped: false) { rect in
            let canvas = rect.insetBy(dx: 0.5, dy: 0.5)
            guard canvas.width > 1, canvas.height > 1, !zones.isEmpty else { return true }
            for zone in zones {
                let pane = CGRect(
                    x: canvas.minX + zone.rect.x * canvas.width,
                    y: canvas.minY + (1 - zone.rect.y - zone.rect.height) * canvas.height,
                    width: zone.rect.width * canvas.width,
                    height: zone.rect.height * canvas.height
                ).insetBy(dx: 0.4, dy: 0.4)
                guard pane.width > 0.5, pane.height > 0.5 else { continue }
                let path = NSBezierPath(roundedRect: pane, xRadius: 1.6, yRadius: 1.6)
                fill.setFill()
                path.fill()
                stroke.setStroke()
                path.lineWidth = 0.7
                path.stroke()
            }
            return true
        }
        image.resizingMode = .stretch
        return image
    }

    static func menuImage(for layout: Layout) -> NSImage {
        let image = self.image(
            for: layout,
            size: NSSize(width: 20, height: 12),
            fill: NSColor.black,
            stroke: NSColor.black.withAlphaComponent(0.35)
        )
        image.isTemplate = true
        return image
    }
}
