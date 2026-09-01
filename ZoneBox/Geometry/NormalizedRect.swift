import CoreGraphics

public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func clamped() -> NormalizedRect {
        var r = self
        r.width = min(max(r.width, 0.02), 1)
        r.height = min(max(r.height, 0.02), 1)
        r.x = min(max(r.x, 0), 1 - r.width)
        r.y = min(max(r.y, 0), 1 - r.height)
        return r
    }

    /// Scale one or both axes around a normalized anchor. Axes with a `nil`
    /// factor are left bitwise-unchanged — height-only zoom must not touch x/width.
    public func scaled(
        widthFactor: Double? = nil,
        heightFactor: Double? = nil,
        anchorX: Double,
        anchorY: Double,
        minSize: Double = 0.08
    ) -> NormalizedRect {
        var r = self
        if let factor = widthFactor {
            let t = width > 0.0001 ? min(1, max(0, (anchorX - x) / width)) : 0.5
            let newWidth = min(1, max(minSize, width * factor))
            r.width = newWidth
            r.x = min(max(0, anchorX - t * newWidth), 1 - newWidth)
        }
        if let factor = heightFactor {
            let t = height > 0.0001 ? min(1, max(0, (anchorY - y) / height)) : 0.5
            let newHeight = min(1, max(minSize, height * factor))
            r.height = newHeight
            r.y = min(max(0, anchorY - t * newHeight), 1 - newHeight)
        }
        return r
    }

    public func denormalize(in workAreaAX: CGRect) -> CGRect {
        let n = clamped()
        return CGRect(
            x: workAreaAX.minX + n.x * workAreaAX.width,
            y: workAreaAX.minY + n.y * workAreaAX.height,
            width: n.width * workAreaAX.width,
            height: n.height * workAreaAX.height
        )
    }

    public static func normalize(_ axRect: CGRect, in workAreaAX: CGRect) -> NormalizedRect {
        guard workAreaAX.width > 0, workAreaAX.height > 0 else {
            return NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        }
        return NormalizedRect(
            x: (axRect.minX - workAreaAX.minX) / workAreaAX.width,
            y: (axRect.minY - workAreaAX.minY) / workAreaAX.height,
            width: axRect.width / workAreaAX.width,
            height: axRect.height / workAreaAX.height
        ).clamped()
    }
}
