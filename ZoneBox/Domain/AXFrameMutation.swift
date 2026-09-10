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
/// writes, then recenters; a trailing `setSize` in the fast loop is what
/// undoes the origin. Settle waits for that adjustment and sets origin last.
public enum AXFrameMutation: Sendable {
    public static let successTolerance: CGFloat = 2
    public static let fastRetryLimit = 3
    public static let fastRetryDelay: TimeInterval = 0.016
    public static let settleDelay: TimeInterval = 0.200
    public static let originRetryDelay: TimeInterval = 0.150

    public static func apply(
        _ frame: CGRect,
        minSize: CGSize? = nil,
        maxSize: CGSize? = nil,
        using writer: AXFrameWriting
    ) -> CGRect? {
        let target = clamped(frame, minSize: minSize, maxSize: maxSize)

        for attempt in 0..<fastRetryLimit {
            writer.setSize(target.size)
            writer.setPoint(target.origin)
            writer.setSize(target.size)
            if let actual = writer.readFrame(), chebyshevError(actual, target: target) <= successTolerance {
                return actual
            }
            if attempt + 1 < fastRetryLimit {
                writer.sleep(fastRetryDelay)
            }
        }

        writer.sleep(settleDelay)
        if let actual = writer.readFrame(), chebyshevError(actual, target: target) <= successTolerance {
            return actual
        }

        if let current = writer.readFrame(), sizeError(current, target: target) > successTolerance {
            writer.setSize(target.size)
            writer.sleep(originRetryDelay)
        }
        writer.setPoint(target.origin)
        if let actual = writer.readFrame(), originError(actual, target: target) > successTolerance {
            writer.setPoint(target.origin)
        }
        return writer.readFrame()
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
}
