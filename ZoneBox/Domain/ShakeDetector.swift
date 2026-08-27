import CoreGraphics

/// How hard a title-bar wiggle must be before the zone overlay arms.
/// 1 = light (easy to trigger), 10 = firm (needs a bigger shake).
public struct ShakeProfile: Equatable, Sendable {
    public var minimumReversals: Int
    public var minimumPathLength: CGFloat
    public var maxNetToPathRatio: CGFloat
    public var sampleEpsilon: CGFloat
    public var reversalDistance: CGFloat
    public var lookbackCount: Int
    public var minimumSamples: Int

    public init(
        minimumReversals: Int,
        minimumPathLength: CGFloat,
        maxNetToPathRatio: CGFloat,
        sampleEpsilon: CGFloat,
        reversalDistance: CGFloat,
        lookbackCount: Int,
        minimumSamples: Int
    ) {
        self.minimumReversals = minimumReversals
        self.minimumPathLength = minimumPathLength
        self.maxNetToPathRatio = maxNetToPathRatio
        self.sampleEpsilon = sampleEpsilon
        self.reversalDistance = reversalDistance
        self.lookbackCount = lookbackCount
        self.minimumSamples = minimumSamples
    }

    public static let intensityRange = 1...10
    public static let defaultIntensity = 3

    public static func clampedIntensity(_ value: Int) -> Int {
        min(intensityRange.upperBound, max(intensityRange.lowerBound, value))
    }

    public static func profile(intensity: Int) -> ShakeProfile {
        let t = CGFloat(clampedIntensity(intensity) - 1) / 9
        let reversals = Int((2 + t * 3).rounded())
        return ShakeProfile(
            minimumReversals: reversals,
            minimumPathLength: 28 + t * 110,
            maxNetToPathRatio: 0.70 - t * 0.38,
            sampleEpsilon: 3 + t * 4,
            reversalDistance: 8 + t * 18,
            lookbackCount: Int((40 - t * 8).rounded()),
            minimumSamples: max(6, reversals * 2)
        )
    }
}

/// Pointer-sample shake detector used by snap-to-zone overlay arming.
///
/// Oscillation is inferred from direction reversals on a single axis plus
/// path-versus-net displacement on a *recent suffix* of the trace, so a
/// straight drag followed by a wiggle still qualifies. A one-direction drag
/// of similar length does not. Samples are AppKit points in chronological order.
public enum ShakeDetector {
    public static func isShake(
        _ points: [CGPoint],
        intensity: Int = ShakeProfile.defaultIntensity
    ) -> Bool {
        let profile = ShakeProfile.profile(intensity: intensity)
        guard points.count >= profile.minimumSamples else { return false }
        let suffixLengths = [
            profile.lookbackCount,
            min(24, profile.lookbackCount),
            min(16, profile.lookbackCount),
            min(12, profile.lookbackCount),
        ]
        var seen = Set<Int>()
        for raw in suffixLengths {
            let length = min(max(raw, profile.minimumSamples), points.count)
            if seen.contains(length) { continue }
            seen.insert(length)
            if matches(Array(points.suffix(length)), profile: profile) {
                return true
            }
        }
        return false
    }

    private static func matches(_ points: [CGPoint], profile: ShakeProfile) -> Bool {
        guard points.count >= profile.minimumSamples else { return false }

        var path: CGFloat = 0
        var dxs: [CGFloat] = []
        var dys: [CGFloat] = []
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            let step = hypot(dx, dy)
            if step < profile.sampleEpsilon { continue }
            path += step
            dxs.append(dx)
            dys.append(dy)
        }

        let first = points[0]
        let last = points[points.count - 1]
        let net = hypot(last.x - first.x, last.y - first.y)
        let reversals = max(
            signChanges(dxs, reversalDistance: profile.reversalDistance),
            signChanges(dys, reversalDistance: profile.reversalDistance)
        )
        guard reversals >= profile.minimumReversals else { return false }
        guard path >= profile.minimumPathLength else { return false }
        guard path > 0, net / path <= profile.maxNetToPathRatio else { return false }
        return true
    }

    /// Count direction reversals, ignoring opposite blips shorter than `reversalDistance`.
    private static func signChanges(_ deltas: [CGFloat], reversalDistance: CGFloat) -> Int {
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
