import CoreGraphics

/// Pointer-sample shake detector used by snap-to-zone overlay arming.
///
/// Oscillation is inferred from direction reversals on a single axis plus
/// path-versus-net displacement. A one-direction drag of similar length does
/// not qualify. Samples are AppKit points in chronological order.
public enum ShakeDetector {
    public static let minimumReversals = 4
    public static let minimumPathLength: CGFloat = 96
    public static let maxNetToPathRatio: CGFloat = 0.42
    public static let sampleEpsilon: CGFloat = 6
    public static let reversalDistance: CGFloat = 20

    public static func isShake(_ points: [CGPoint]) -> Bool {
        guard points.count >= 8 else { return false }

        var path: CGFloat = 0
        var dxs: [CGFloat] = []
        var dys: [CGFloat] = []
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            let step = hypot(dx, dy)
            if step < sampleEpsilon { continue }
            path += step
            dxs.append(dx)
            dys.append(dy)
        }

        let first = points[0]
        let last = points[points.count - 1]
        let net = hypot(last.x - first.x, last.y - first.y)
        let reversals = max(signChanges(dxs), signChanges(dys))
        guard reversals >= minimumReversals else { return false }
        guard path >= minimumPathLength else { return false }
        guard path > 0, net / path <= maxNetToPathRatio else { return false }
        return true
    }

    /// Count direction reversals, ignoring opposite blips shorter than `reversalDistance`.
    private static func signChanges(_ deltas: [CGFloat]) -> Int {
        var last: CGFloat = 0
        var accumulated: CGFloat = 0
        var count = 0
        for delta in deltas {
            if last == 0 {
                if abs(delta) >= 1 {
                    last = delta
                    accumulated = delta
                }
                continue
            }
            if delta * last < 0 {
                if abs(accumulated) >= reversalDistance {
                    count += 1
                    last = delta
                    accumulated = delta
                } else {
                    accumulated += delta
                    if abs(accumulated) < 1 {
                        last = 0
                        accumulated = 0
                    }
                }
            } else {
                accumulated += delta
                last = delta
            }
        }
        return count
    }
}
