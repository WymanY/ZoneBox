import CoreGraphics
import Foundation

public protocol AXFrameWriting: AnyObject {
    func readFrame() -> CGRect?
    func setSize(_ size: CGSize)
    func setPoint(_ origin: CGPoint)
    func sleep(_ duration: TimeInterval)
}

/// Writes AX position and size, then waits for apps that asynchronously
/// restyle the window after a size change. Raycast AI Chat accepts the
/// writes, then recenters; a trailing size write in the fast loop is what
/// undoes the origin. A matching read is confirmed after a short delay so
/// that restyle is not treated as success. Settle then writes origin last.
/// Apps that silently enforce an unadvertised minimum (Surge Dashboard) keep
/// that allowed size, then the origin is slid so the window still covers the
/// zone and stays inside the work area.
public enum AXFrameMutation: Sendable {
    public enum Outcome: Equatable, Sendable {
        case applied
        case sizeLimited
        case positionLimited
        case unavailable
    }

    public static let successTolerance: CGFloat = 2
    public static let fastRetryLimit = 3
    public static let fastRetryDelay: TimeInterval = 0.016
    public static let settleDelay: TimeInterval = 0.200
    public static let originRetryDelay: TimeInterval = 0.150

    /// Compare with the user's original target, not the target clamped to an
    /// application's limits. A readable frame alone does not mean it fitted.
    public static func outcome(actual: CGRect?, requested: CGRect) -> Outcome {
        guard let actual else { return .unavailable }
        if sizeError(actual, target: requested) > successTolerance { return .sizeLimited }
        if originError(actual, target: requested) > successTolerance { return .positionLimited }
        return .applied
    }

    public static func apply(
        _ frame: CGRect,
        minSize: CGSize? = nil,
        maxSize: CGSize? = nil,
        bounds: CGRect? = nil,
        using writer: AXFrameWriting
    ) -> CGRect? {
        let start = writer.readFrame()
        let sized = clamped(frame, minSize: minSize, maxSize: maxSize)
        let target = CGRect(origin: frame.origin, size: sized.size)

        for attempt in 0..<fastRetryLimit {
            writer.setSize(target.size)
            writer.setPoint(target.origin)
            writer.setSize(target.size)
            if let actual = confirmedFrame(target, using: writer) {
                return maybeFitOversized(actual, requested: frame, bounds: bounds, using: writer)
            }
            if attempt + 1 < fastRetryLimit {
                writer.sleep(fastRetryDelay)
            }
        }

        writer.sleep(settleDelay)
        if let actual = confirmedFrame(target, using: writer) {
            return maybeFitOversized(actual, requested: frame, bounds: bounds, using: writer)
        }

        if let current = writer.readFrame(), sizeError(current, target: target) > successTolerance {
            writer.setSize(target.size)
            writer.sleep(originRetryDelay)
        }
        writer.setPoint(target.origin)
        if let actual = writer.readFrame(), originError(actual, target: target) > successTolerance {
            writer.setPoint(target.origin)
        }
        if let actual = writer.readFrame(), chebyshevError(actual, target: target) <= successTolerance {
            return maybeFitOversized(actual, requested: frame, bounds: bounds, using: writer)
        }

        let current = writer.readFrame()
        let allowedSize = effectiveSize(
            requested: target.size,
            start: start?.size,
            actual: current?.size ?? target.size
        )
        if let current, sizeError(current, target: CGRect(origin: current.origin, size: allowedSize)) > successTolerance {
            writer.setSize(allowedSize)
        }
        writer.setPoint(target.origin)
        if let actual = writer.readFrame(), originError(actual, target: target) > successTolerance {
            writer.setPoint(target.origin)
        }
        return maybeFitOversized(writer.readFrame() ?? current, requested: frame, bounds: bounds, using: writer)
    }

    /// Slide an oversized window so it still covers the zone and stays in `bounds`
    /// when the allowed size fits that work area. If the app minimum is larger
    /// than the screen, keep that size and anchor top-left; do not shrink.
    public static func fitted(requested: CGRect, size: CGSize, bounds: CGRect?) -> CGRect {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        guard let bounds, bounds.width > 0, bounds.height > 0 else {
            return CGRect(x: requested.minX, y: requested.minY, width: width, height: height)
        }
        if width > bounds.width + successTolerance || height > bounds.height + successTolerance {
            return CGRect(x: bounds.minX, y: bounds.minY, width: width, height: height)
        }
        let minX = bounds.minX
        let maxX = bounds.maxX - width
        let minY = bounds.minY
        let maxY = bounds.maxY - height
        let x = min(max(requested.minX, minX), max(minX, maxX))
        let y = min(max(requested.minY, minY), max(minY, maxY))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Recover a writable size after an app silently rejects part of a frame.
    /// A dimension that grew past the request is treated as a minimum; an
    /// increase that never took is retried; a shrink that landed elsewhere is
    /// treated as a maximum.
    public static func effectiveSize(requested: CGSize, start: CGSize?, actual: CGSize) -> CGSize {
        CGSize(
            width: effectiveDimension(requested: requested.width, start: start?.width, actual: actual.width),
            height: effectiveDimension(requested: requested.height, start: start?.height, actual: actual.height)
        )
    }

    /// A window can echo the target frame immediately, then restyle a moment
    /// later. Treat a match as final only if it is still there after the short
    /// delay that follows a trailing size write.
    private static func confirmedFrame(_ target: CGRect, using writer: AXFrameWriting) -> CGRect? {
        guard let actual = writer.readFrame(), chebyshevError(actual, target: target) <= successTolerance else {
            return nil
        }
        writer.sleep(fastRetryDelay)
        guard let confirmed = writer.readFrame(), chebyshevError(confirmed, target: target) <= successTolerance else {
            return nil
        }
        return confirmed
    }

    public static func chebyshevError(_ actual: CGRect, target: CGRect) -> CGFloat {
        max(originError(actual, target: target), sizeError(actual, target: target))
    }

    public static func originError(_ actual: CGRect, target: CGRect) -> CGFloat {
        max(abs(actual.origin.x - target.origin.x), abs(actual.origin.y - target.origin.y))
    }

    public static func sizeError(_ actual: CGRect, target: CGRect) -> CGFloat {
        max(abs(actual.size.width - target.size.width), abs(actual.size.height - target.size.height))
    }

    public static func clamped(_ frame: CGRect, minSize: CGSize?, maxSize: CGSize?) -> CGRect {
        var target = frame
        if let minSize {
            target.size.width = max(target.size.width, minSize.width)
            target.size.height = max(target.size.height, minSize.height)
        }
        if let maxSize, maxSize.width > 0 {
            target.size.width = min(target.size.width, maxSize.width)
            target.size.height = min(target.size.height, maxSize.height)
        }
        return target
    }

    private static func effectiveDimension(requested: CGFloat, start: CGFloat?, actual: CGFloat) -> CGFloat {
        if abs(actual - requested) <= successTolerance { return requested }
        let unchanged = start.map { abs(actual - $0) <= successTolerance } ?? false
        if actual > requested + successTolerance {
            return actual
        }
        if unchanged {
            return requested
        }
        return actual
    }

    /// Origin correction only: requested geometry was fully on one work area, and
    /// an app minimum made the window larger than that request. Partially offscreen
    /// and spanning frames are left exactly as accepted.
    private static func maybeFitOversized(
        _ actual: CGRect?,
        requested: CGRect,
        bounds: CGRect?,
        using writer: AXFrameWriting
    ) -> CGRect? {
        guard let actual else { return nil }
        let grew = actual.width > requested.width + successTolerance
            || actual.height > requested.height + successTolerance
        guard grew, let bounds, fullyContains(bounds, requested) else {
            return actual
        }
        let retry = fitted(requested: requested, size: actual.size, bounds: bounds)
        if originError(actual, target: retry) <= successTolerance {
            return actual
        }
        writer.setPoint(retry.origin)
        return writer.readFrame() ?? actual
    }

    private static func fullyContains(_ bounds: CGRect, _ rect: CGRect) -> Bool {
        rect.minX >= bounds.minX - successTolerance
            && rect.minY >= bounds.minY - successTolerance
            && rect.maxX <= bounds.maxX + successTolerance
            && rect.maxY <= bounds.maxY + successTolerance
    }
}
