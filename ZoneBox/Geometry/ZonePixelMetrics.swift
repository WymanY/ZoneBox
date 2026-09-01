import CoreGraphics
import Foundation

public struct ZonePixelSize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum ZoneAspectPreset: Equatable, Sendable {
    case free
    case square
    case wide16x9
    case photo4x3
    case custom(width: Int, height: Int)

    public var ratio: Double? {
        switch self {
        case .free:
            return nil
        case .square:
            return 1
        case .wide16x9:
            return 16.0 / 9.0
        case .photo4x3:
            return 4.0 / 3.0
        case .custom(let width, let height):
            guard width > 0, height > 0 else { return nil }
            return Double(width) / Double(height)
        }
    }
}

public enum ZonePixelMetrics {
    public static let minPixels = 40

    public static func pixelSize(of rect: NormalizedRect, workAreaAX: CGRect) -> ZonePixelSize {
        let frame = rect.denormalize(in: workAreaAX)
        return ZonePixelSize(
            width: max(1, Int(frame.width.rounded())),
            height: max(1, Int(frame.height.rounded()))
        )
    }

    public static func resizing(
        _ rect: NormalizedRect,
        toWidth width: Int?,
        height: Int?,
        workAreaAX: CGRect,
        lockAspect: Bool
    ) -> NormalizedRect {
        let current = pixelSize(of: rect, workAreaAX: workAreaAX)
        var nextWidth = max(minPixels, width ?? current.width)
        var nextHeight = max(minPixels, height ?? current.height)
        if lockAspect, current.height > 0 {
            let ratio = Double(current.width) / Double(current.height)
            if width != nil, height == nil {
                nextHeight = max(minPixels, Int((Double(nextWidth) / ratio).rounded()))
            } else if height != nil, width == nil {
                nextWidth = max(minPixels, Int((Double(nextHeight) * ratio).rounded()))
            }
        }
        return applying(
            pixelWidth: nextWidth,
            pixelHeight: nextHeight,
            to: rect,
            workAreaAX: workAreaAX
        )
    }

    /// When aspect is locked, keep the unchanged side nil so it can be derived.
    public static func lockedFields(
        current: ZonePixelSize,
        width: Int?,
        height: Int?,
        lockAspect: Bool
    ) -> (width: Int?, height: Int?) {
        guard lockAspect else { return (width, height) }
        let nextWidth = width ?? current.width
        let nextHeight = height ?? current.height
        if nextWidth != current.width, nextHeight == current.height {
            return (nextWidth, nil)
        }
        if nextHeight != current.height, nextWidth == current.width {
            return (nil, nextHeight)
        }
        if nextWidth != current.width {
            return (nextWidth, nil)
        }
        if nextHeight != current.height {
            return (nil, nextHeight)
        }
        return (nextWidth, nextHeight)
    }

    public static func preservingAspect(
        from start: NormalizedRect,
        resized: NormalizedRect,
        usingWidth: Bool
    ) -> NormalizedRect {
        guard start.height > 0.0001 else { return resized.clamped() }
        let ratio = start.width / start.height
        var next = resized
        if usingWidth {
            next.height = max(0.02, next.width / ratio)
            let movedTop = abs(resized.y - start.y) > abs((resized.y + resized.height) - (start.y + start.height))
            if movedTop {
                next.y = (start.y + start.height) - next.height
            } else {
                next.y = start.y
            }
        } else {
            next.width = max(0.02, next.height * ratio)
            let movedLeft = abs(resized.x - start.x) > abs((resized.x + resized.width) - (start.x + start.width))
            if movedLeft {
                next.x = (start.x + start.width) - next.width
            } else {
                next.x = start.x
            }
        }
        return next.clamped()
    }

    public static func applying(
        aspect: ZoneAspectPreset,
        to rect: NormalizedRect,
        workAreaAX: CGRect
    ) -> NormalizedRect {
        guard let ratio = aspect.ratio, ratio > 0 else { return rect.clamped() }
        let current = pixelSize(of: rect, workAreaAX: workAreaAX)
        let currentRatio = current.height > 0 ? Double(current.width) / Double(current.height) : ratio
        var width = current.width
        var height = current.height
        if currentRatio >= ratio {
            width = max(minPixels, Int((Double(height) * ratio).rounded()))
        } else {
            height = max(minPixels, Int((Double(width) / ratio).rounded()))
        }
        return applying(
            pixelWidth: width,
            pixelHeight: height,
            to: rect,
            workAreaAX: workAreaAX
        )
    }

    public static func applying(
        pixelWidth: Int,
        pixelHeight: Int,
        to rect: NormalizedRect,
        workAreaAX: CGRect
    ) -> NormalizedRect {
        guard workAreaAX.width > 0, workAreaAX.height > 0 else { return rect.clamped() }
        let width = min(max(CGFloat(max(minPixels, pixelWidth)), 1), workAreaAX.width)
        let height = min(max(CGFloat(max(minPixels, pixelHeight)), 1), workAreaAX.height)
        let current = rect.denormalize(in: workAreaAX)
        let x = min(max(current.minX, workAreaAX.minX), workAreaAX.maxX - width)
        let y = min(max(current.minY, workAreaAX.minY), workAreaAX.maxY - height)
        return NormalizedRect.normalize(
            CGRect(x: x, y: y, width: width, height: height),
            in: workAreaAX
        )
    }

    /// Move a zone by pixel origin. X/Y are work-area coordinates with y growing downward,
    /// matching NormalizedRect and the on-canvas size labels.
    public static func moving(
        _ rect: NormalizedRect,
        toX x: Int?,
        y: Int?,
        workAreaAX: CGRect
    ) -> NormalizedRect {
        guard workAreaAX.width > 0, workAreaAX.height > 0 else { return rect.clamped() }
        let current = rect.denormalize(in: workAreaAX)
        let width = min(max(current.width, CGFloat(minPixels)), workAreaAX.width)
        let height = min(max(current.height, CGFloat(minPixels)), workAreaAX.height)
        let nextX: CGFloat
        if let x {
            nextX = workAreaAX.minX + CGFloat(x)
        } else {
            nextX = current.minX
        }
        let nextY: CGFloat
        if let y {
            nextY = workAreaAX.minY + CGFloat(y)
        } else {
            nextY = current.minY
        }
        let clampedX = min(max(nextX, workAreaAX.minX), workAreaAX.maxX - width)
        let clampedY = min(max(nextY, workAreaAX.minY), workAreaAX.maxY - height)
        return NormalizedRect.normalize(
            CGRect(x: clampedX, y: clampedY, width: width, height: height),
            in: workAreaAX
        )
    }

    public static func origin(
        of rect: NormalizedRect,
        workAreaAX: CGRect
    ) -> (x: Int, y: Int) {
        let frame = rect.denormalize(in: workAreaAX)
        return (
            Int((frame.minX - workAreaAX.minX).rounded()),
            Int((frame.minY - workAreaAX.minY).rounded())
        )
    }
}
