import CoreGraphics
import Foundation

public struct CanvasSnapCandidates: Equatable, Sendable {
    public var x: [Double]
    public var y: [Double]

    public init(x: [Double], y: [Double]) {
        self.x = x
        self.y = y
    }

    public static func from(rects: [NormalizedRect]) -> CanvasSnapCandidates {
        var xs: [Double] = [0, 0.5, 1]
        var ys: [Double] = [0, 0.5, 1]
        for rect in rects {
            xs.append(contentsOf: [rect.x, rect.midX, rect.maxX])
            ys.append(contentsOf: [rect.y, rect.midY, rect.maxY])
        }
        return CanvasSnapCandidates(x: xs, y: ys)
    }
}

public struct CanvasSnapResult: Equatable, Sendable {
    public var rect: NormalizedRect
    public var hitX: [Double]
    public var hitY: [Double]

    public init(rect: NormalizedRect, hitX: [Double] = [], hitY: [Double] = []) {
        self.rect = rect
        self.hitX = hitX
        self.hitY = hitY
    }
}

public enum CanvasSnapping {
    public static let thresholdPoints: CGFloat = 8

    public enum Intent: Equatable, Sendable {
        case move
        case edges(left: Bool, right: Bool, top: Bool, bottom: Bool)
    }

    public static func snapping(
        _ rect: NormalizedRect,
        intent: Intent,
        candidates: CanvasSnapCandidates,
        thresholdX: Double,
        thresholdY: Double,
        minSize: Double = ZoneSplit.minSize
    ) -> CanvasSnapResult {
        if thresholdX <= 0, thresholdY <= 0 {
            return CanvasSnapResult(rect: rect, hitX: [], hitY: [])
        }
        switch intent {
        case .move:
            return snappingMove(
                rect,
                candidates: candidates,
                thresholdX: thresholdX,
                thresholdY: thresholdY
            )
        case .edges(let left, let right, let top, let bottom):
            return snappingEdges(
                rect,
                left: left,
                right: right,
                top: top,
                bottom: bottom,
                candidates: candidates,
                thresholdX: thresholdX,
                thresholdY: thresholdY,
                minSize: minSize
            )
        }
    }

    /// Snap one moving edge, then restore the locked aspect around the opposite corner.
    public static func snappingPreservingAspect(
        from start: NormalizedRect,
        resized: NormalizedRect,
        intent: Intent,
        candidates: CanvasSnapCandidates,
        thresholdX: Double,
        thresholdY: Double,
        usingWidth: Bool,
        minSize: Double = ZoneSplit.minSize
    ) -> CanvasSnapResult {
        let snapped = snappingClosestAxis(
            resized,
            intent: intent,
            candidates: candidates,
            thresholdX: thresholdX,
            thresholdY: thresholdY,
            minSize: minSize
        )
        let restored = ZonePixelMetrics.preservingAspect(
            from: start,
            resized: snapped.rect,
            usingWidth: usingWidth
        )
        let hits = snapping(
            restored,
            intent: intent,
            candidates: candidates,
            thresholdX: 1e-9,
            thresholdY: 1e-9,
            minSize: minSize
        )
        return CanvasSnapResult(rect: restored, hitX: hits.hitX, hitY: hits.hitY)
    }

    public static func snappingClosestAxis(
        _ rect: NormalizedRect,
        intent: Intent,
        candidates: CanvasSnapCandidates,
        thresholdX: Double,
        thresholdY: Double,
        minSize: Double = ZoneSplit.minSize
    ) -> CanvasSnapResult {
        let full = snapping(
            rect,
            intent: intent,
            candidates: candidates,
            thresholdX: thresholdX,
            thresholdY: thresholdY,
            minSize: minSize
        )
        guard !full.hitX.isEmpty, !full.hitY.isEmpty else { return full }
        let dx = abs(full.rect.x - rect.x) + abs(full.rect.maxX - rect.maxX)
        let dy = abs(full.rect.y - rect.y) + abs(full.rect.maxY - rect.maxY)
        if dx <= dy {
            return snapping(
                rect,
                intent: disablingVertical(intent),
                candidates: candidates,
                thresholdX: thresholdX,
                thresholdY: 0,
                minSize: minSize
            )
        }
        return snapping(
            rect,
            intent: disablingHorizontal(intent),
            candidates: candidates,
            thresholdX: 0,
            thresholdY: thresholdY,
            minSize: minSize
        )
    }

    private static func disablingVertical(_ intent: Intent) -> Intent {
        switch intent {
        case .move:
            return .edges(left: true, right: true, top: false, bottom: false)
        case .edges(let left, let right, _, _):
            return .edges(left: left, right: right, top: false, bottom: false)
        }
    }

    private static func disablingHorizontal(_ intent: Intent) -> Intent {
        switch intent {
        case .move:
            return .edges(left: false, right: false, top: true, bottom: true)
        case .edges(_, _, let top, let bottom):
            return .edges(left: false, right: false, top: top, bottom: bottom)
        }
    }

    private static func snappingMove(
        _ rect: NormalizedRect,
        candidates: CanvasSnapCandidates,
        thresholdX: Double,
        thresholdY: Double
    ) -> CanvasSnapResult {
        var next = rect
        if let xSnap = bestTranslation(
            values: [rect.x, rect.midX, rect.maxX],
            candidates: candidates.x,
            threshold: thresholdX
        ) {
            next.x += xSnap.delta
        }
        if let ySnap = bestTranslation(
            values: [rect.y, rect.midY, rect.maxY],
            candidates: candidates.y,
            threshold: thresholdY
        ) {
            next.y += ySnap.delta
        }
        return CanvasSnapResult(
            rect: next,
            hitX: alignedValues([next.x, next.midX, next.maxX], candidates: candidates.x),
            hitY: alignedValues([next.y, next.midY, next.maxY], candidates: candidates.y)
        )
    }

    private static func snappingEdges(
        _ rect: NormalizedRect,
        left: Bool,
        right: Bool,
        top: Bool,
        bottom: Bool,
        candidates: CanvasSnapCandidates,
        thresholdX: Double,
        thresholdY: Double,
        minSize: Double
    ) -> CanvasSnapResult {
        var next = rect
        var hitX: [Double] = []
        var hitY: [Double] = []

        if left, let snap = nearest(rect.x, in: candidates.x, threshold: thresholdX) {
            let maxX = rect.maxX
            let width = maxX - snap
            if width >= minSize {
                next.x = snap
                next.width = width
                hitX.append(snap)
            }
        }
        if right, let snap = nearest(rect.maxX, in: candidates.x, threshold: thresholdX) {
            let width = snap - next.x
            if width >= minSize {
                next.width = width
                hitX.append(snap)
            }
        }
        if top, let snap = nearest(rect.y, in: candidates.y, threshold: thresholdY) {
            let maxY = rect.maxY
            let height = maxY - snap
            if height >= minSize {
                next.y = snap
                next.height = height
                hitY.append(snap)
            }
        }
        if bottom, let snap = nearest(rect.maxY, in: candidates.y, threshold: thresholdY) {
            let height = snap - next.y
            if height >= minSize {
                next.height = height
                hitY.append(snap)
            }
        }

        return CanvasSnapResult(
            rect: next,
            hitX: uniqueSorted(hitX),
            hitY: uniqueSorted(hitY)
        )
    }

    private static func bestTranslation(
        values: [Double],
        candidates: [Double],
        threshold: Double
    ) -> (delta: Double, hit: Double)? {
        var best: (delta: Double, hit: Double)?
        for value in values {
            guard let snap = nearest(value, in: candidates, threshold: threshold) else { continue }
            let delta = snap - value
            if let current = best {
                if abs(delta) < abs(current.delta) {
                    best = (delta, snap)
                }
            } else {
                best = (delta, snap)
            }
        }
        return best
    }

    private static func nearest(_ value: Double, in candidates: [Double], threshold: Double) -> Double? {
        guard threshold > 0 else { return nil }
        var best: (candidate: Double, distance: Double)?
        for candidate in candidates {
            let distance = abs(candidate - value)
            guard distance <= threshold else { continue }
            if let current = best {
                if distance < current.distance {
                    best = (candidate, distance)
                }
            } else {
                best = (candidate, distance)
            }
        }
        return best?.candidate
    }

    private static func alignedValues(_ values: [Double], candidates: [Double]) -> [Double] {
        uniqueSorted(values.compactMap { value in
            candidates.first { abs($0 - value) <= 1e-9 }
        })
    }

    private static func uniqueSorted(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        for value in values.sorted() {
            if result.last.map({ abs($0 - value) <= 1e-9 }) == true { continue }
            result.append(value)
        }
        return result
    }
}
