import CoreGraphics
import Foundation

/// Read-only restore schematic for a workspace section: every captured window
/// drawn where restore will put it, relative to the display's work area.
public enum WorkspaceLayoutPreview {
    public static let suggestedSize = CGSize(width: 160, height: 90)
    public static let iconMinimumWidth: CGFloat = 28
    public static let iconMinimumHeight: CGFloat = 22

    public struct Pane: Equatable, Sendable {
        public var bundleID: String
        public var rect: NormalizedRect
        /// False when the window is too small, or too covered by windows in
        /// front, for an icon to mean anything. The pane is still drawn.
        public var showsIcon: Bool
        public var labelRect: NormalizedRect
    }

    public struct Snapshot: Equatable, Sendable {
        /// Back-to-front, so drawing in order puts the frontmost window on top.
        public var panes: [Pane]
    }

    public static func snapshot(
        rules: [AppPlacementRule],
        canvasSize: CGSize = suggestedSize
    ) -> Snapshot {
        let drafts = rules.reversed().compactMap { rule -> Draft? in
            let rect = rule.frame.clamped()
            let frame = pixelRect(rect, in: canvasSize)
            guard frame.width > 0, frame.height > 0 else { return nil }
            return Draft(
                bundleID: rule.bundleID,
                rect: rect,
                frame: frame,
                showsIcon: frame.width >= iconMinimumWidth && frame.height >= iconMinimumHeight
            )
        }
        let labels = placeLabels(drafts, canvasSize: canvasSize)
        let panes = zip(drafts, labels).map { draft, placement in
            Pane(
                bundleID: draft.bundleID,
                rect: draft.rect,
                showsIcon: placement.showsIcon,
                labelRect: normalize(placement.frame, in: canvasSize)
            )
        }
        return Snapshot(panes: panes)
    }

    private struct Draft {
        var bundleID: String
        var rect: NormalizedRect
        var frame: CGRect
        var showsIcon: Bool
    }

    private struct LabelPlacement {
        var frame: CGRect
        var showsIcon: Bool
    }

    private static func placeLabels(_ drafts: [Draft], canvasSize: CGSize) -> [LabelPlacement] {
        var placed: [CGRect] = []
        var result: [LabelPlacement] = []
        result.reserveCapacity(drafts.count)
        for (index, draft) in drafts.enumerated() {
            let occluders = drafts.enumerated().compactMap { otherIndex, other -> CGRect? in
                guard otherIndex > index, other.frame.intersects(draft.frame) else { return nil }
                return other.frame
            }
            let frame = bestLabelRect(
                in: draft.frame,
                size: labelSize(pane: draft.frame),
                occluders: occluders,
                avoiding: placed,
                canvasSize: canvasSize
            )
            var showsIcon = draft.showsIcon
            if showsIcon,
               occluders.contains(where: { $0.contains(frame) })
               || placed.contains(where: { $0.intersects(frame) })
            {
                showsIcon = false
            }
            if showsIcon {
                placed.append(frame)
            }
            result.append(LabelPlacement(frame: frame, showsIcon: showsIcon))
        }
        return result
    }

    private static func labelSize(pane: CGRect) -> CGSize {
        let requested = CGSize(width: 18, height: 18)
        return CGSize(
            width: min(requested.width, max(8, pane.width - 2)),
            height: min(requested.height, max(8, pane.height - 2))
        )
    }

    private static func bestLabelRect(
        in pane: CGRect,
        size: CGSize,
        occluders: [CGRect],
        avoiding: [CGRect],
        canvasSize: CGSize
    ) -> CGRect {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let clippedPane = pane.intersection(canvas)
        guard clippedPane.width > 0.5, clippedPane.height > 0.5 else {
            return pane
        }
        let fitted = CGSize(
            width: min(size.width, max(1, clippedPane.width)),
            height: min(size.height, max(1, clippedPane.height))
        )
        let preferred = uniqueAnchor(in: clippedPane, occluders: occluders)
        let candidates = labelCandidates(in: clippedPane, size: fitted, preferred: preferred)
        return candidates.min { lhs, rhs in
            score(lhs, pane: clippedPane, occluders: occluders, avoiding: avoiding, preferred: preferred)
                < score(rhs, pane: clippedPane, occluders: occluders, avoiding: avoiding, preferred: preferred)
        } ?? CGRect(
            x: clippedPane.midX - fitted.width / 2,
            y: clippedPane.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private static func labelCandidates(in pane: CGRect, size: CGSize, preferred: CGPoint) -> [CGRect] {
        let inset: CGFloat = 2
        let xs = [
            pane.minX + inset,
            preferred.x - size.width / 2,
            pane.midX - size.width / 2,
            pane.maxX - size.width - inset,
        ]
        let ys = [
            pane.minY + inset,
            preferred.y - size.height / 2,
            pane.midY - size.height / 2,
            pane.maxY - size.height - inset,
        ]
        var rects: [CGRect] = []
        for y in ys {
            for x in xs {
                var rect = CGRect(x: x, y: y, width: size.width, height: size.height)
                if rect.minX < pane.minX { rect.origin.x = pane.minX }
                if rect.minY < pane.minY { rect.origin.y = pane.minY }
                if rect.maxX > pane.maxX { rect.origin.x = pane.maxX - size.width }
                if rect.maxY > pane.maxY { rect.origin.y = pane.maxY - size.height }
                rects.append(rect)
            }
        }
        return rects
    }

    private static func uniqueAnchor(in pane: CGRect, occluders: [CGRect]) -> CGPoint {
        let columns = 5
        let rows = 5
        var best = CGPoint(x: pane.midX, y: pane.midY)
        var bestCount = -1
        for row in 0..<rows {
            for column in 0..<columns {
                let point = CGPoint(
                    x: pane.minX + pane.width * (CGFloat(column) + 0.5) / CGFloat(columns),
                    y: pane.minY + pane.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                )
                guard !occluders.contains(where: { $0.contains(point) }) else { continue }
                let visibleNeighbors = (-1...1).reduce(0) { count, dy in
                    (-1...1).reduce(count) { inner, dx in
                        let neighbor = CGPoint(
                            x: point.x + CGFloat(dx) * pane.width / CGFloat(columns),
                            y: point.y + CGFloat(dy) * pane.height / CGFloat(rows)
                        )
                        guard pane.contains(neighbor),
                              !occluders.contains(where: { $0.contains(neighbor) })
                        else { return inner }
                        return inner + 1
                    }
                }
                if visibleNeighbors > bestCount {
                    bestCount = visibleNeighbors
                    best = point
                }
            }
        }
        return best
    }

    private static func score(
        _ rect: CGRect,
        pane: CGRect,
        occluders: [CGRect],
        avoiding: [CGRect],
        preferred: CGPoint
    ) -> CGFloat {
        let overlapPenalty: CGFloat = avoiding.contains(where: { $0.intersects(rect) }) ? 10_000 : 0
        let occluded = occluders.reduce(CGFloat(0)) { $0 + $1.intersection(rect).area }
        let outside = max(0, rect.area - rect.intersection(pane).area) * 50
        let distance = hypot(rect.midX - preferred.x, rect.midY - preferred.y)
        return overlapPenalty + occluded * 8 + outside + distance
    }

    private static func pixelRect(_ rect: NormalizedRect, in canvas: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(rect.x) * canvas.width,
            y: CGFloat(rect.y) * canvas.height,
            width: CGFloat(rect.width) * canvas.width,
            height: CGFloat(rect.height) * canvas.height
        )
    }

    private static func normalize(_ frame: CGRect, in canvas: CGSize) -> NormalizedRect {
        guard canvas.width > 0, canvas.height > 0 else {
            return NormalizedRect(x: 0, y: 0, width: 0, height: 0)
        }
        return NormalizedRect(
            x: Double(frame.minX / canvas.width),
            y: Double(frame.minY / canvas.height),
            width: Double(frame.width / canvas.width),
            height: Double(frame.height / canvas.height)
        )
    }
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
