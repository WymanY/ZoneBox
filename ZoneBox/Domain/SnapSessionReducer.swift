import CoreGraphics
import Foundation

public enum SnapSessionReducer {
    public static func reduce(_ input: SnapReducerInput) -> SnapReducerOutput {
        if !input.trusted || !input.snapEnabled || input.isEditorOpen {
            if input.phase == .idle {
                return SnapReducerOutput(phase: .idle, effects: [])
            }
            return SnapReducerOutput(phase: .idle, effects: [.hideOverlay, .cancel])
        }

        switch input.event.kind {
        case .escape:
            return SnapReducerOutput(phase: .idle, effects: [.hideOverlay, .cancel])
        case .leftDown:
            return reduceLeftDown(input)
        case .leftDragged:
            return reduceDragged(input)
        case .leftUp:
            return reduceLeftUp(input)
        case .rightDown:
            return reduceArm(input, sticky: true)
        case .flagsChanged:
            return reduceFlags(input)
        }
    }

    private static func reduceLeftDown(_ input: SnapReducerInput) -> SnapReducerOutput {
        guard let window = input.window, let frame = input.currentFrameAX ?? input.downFrameAX else {
            return SnapReducerOutput(phase: .idle, effects: [])
        }
        return SnapReducerOutput(phase: .mouseDown(window, originAX: frame), effects: [])
    }

    private static func reduceDragged(_ input: SnapReducerInput) -> SnapReducerOutput {
        switch input.phase {
        case .idle:
            return SnapReducerOutput(phase: .idle, effects: [])
        case .resizing:
            return SnapReducerOutput(phase: .resizing, effects: [])
        case .mouseDown(let window, let originAX):
            if isResize(input) {
                return SnapReducerOutput(phase: .resizing, effects: [])
            }
            if hasMoved(input, originAX: originAX) {
                if shouldArm(input) {
                    return arm(window, input: input)
                }
                return SnapReducerOutput(phase: .dragging(window), effects: [])
            }
            return SnapReducerOutput(phase: input.phase, effects: [])
        case .dragging(let window):
            if isResize(input) {
                return SnapReducerOutput(phase: .resizing, effects: [])
            }
            if shouldArm(input) {
                return arm(window, input: input)
            }
            return SnapReducerOutput(phase: .dragging(window), effects: [])
        case .armed, .highlighting:
            return highlight(input)
        }
    }

    private static func reduceLeftUp(_ input: SnapReducerInput) -> SnapReducerOutput {
        switch input.phase {
        case .idle, .mouseDown:
            return SnapReducerOutput(phase: .idle, effects: [.hideOverlay])
        case .resizing:
            return reduceResizeUp(input)
        case .dragging(let window):
            if input.restoreSizeOnUnsnap,
               let record = input.unsnapRecord,
               let down = input.downLocationAppKit,
               RectMath.chebyshev(input.event.locationAppKit, down) >= 30 {
                let frame = clamp(record.originalFrameAX, to: input.workAreas, flip: input.primaryFlipHeight)
                return SnapReducerOutput(
                    phase: .idle,
                    effects: [.applyFrame(window, frame), .hideOverlay]
                )
            }
            return SnapReducerOutput(phase: .idle, effects: [.hideOverlay])
        case .armed, .highlighting:
            let target = currentTarget(input)
            guard let frame = target.frameAX, let window = currentWindow(input.phase) else {
                return SnapReducerOutput(phase: .idle, effects: [.hideOverlay])
            }
            var effects: [SnapEffect] = [.applyFrame(window, frame), .hideOverlay]
            if input.unsnapRecord == nil, let original = input.downFrameAX {
                effects.insert(
                    .recordUnsnap(
                        UnsnapRecord(
                            identity: window,
                            originalFrameAX: original,
                            snappedFrameAX: frame,
                            zoneIDs: target.unsnapZoneIDs
                        )
                    ),
                    at: 0
                )
            }
            return SnapReducerOutput(phase: .idle, effects: effects)
        }
    }

    private static func reduceArm(_ input: SnapReducerInput, sticky: Bool) -> SnapReducerOutput {
        _ = sticky
        guard input.snapOnRightClickDrag else {
            return SnapReducerOutput(phase: input.phase, effects: [])
        }
        switch input.phase {
        case .dragging(let window), .armed(let window):
            return arm(window, input: input)
        case .highlighting(let window, _):
            return arm(window, input: input)
        default:
            return SnapReducerOutput(phase: input.phase, effects: [])
        }
    }

    private static func reduceFlags(_ input: SnapReducerInput) -> SnapReducerOutput {
        let shift = input.event.modifiers.contains(.shift)
        switch input.phase {
        case .dragging(let window) where shift && input.snapOnShiftDrag:
            return arm(window, input: input)
        case .armed, .highlighting:
            if !shift && !input.stickyArm {
                if let window = currentWindow(input.phase) {
                    return SnapReducerOutput(phase: .dragging(window), effects: [.hideOverlay])
                }
            } else {
                return highlight(input)
            }
            return SnapReducerOutput(phase: input.phase, effects: [])
        default:
            return SnapReducerOutput(phase: input.phase, effects: [])
        }
    }

    private static func reduceResizeUp(_ input: SnapReducerInput) -> SnapReducerOutput {
        var effects: [SnapEffect] = [.hideOverlay]
        if input.magneticResizeEnabled,
           let window = input.window,
           let original = input.downFrameAX,
           let current = input.currentFrameAX
        {
            let snapped = MagneticResize.snap(
                original: original,
                current: current,
                zoneFramesAX: input.resolvedZones.map(\.frameAX),
                threshold: input.magneticThreshold,
                workAreaAX: magneticWorkAreaAX(input)
            )
            if snapped != current {
                effects.insert(.applyFrame(window, snapped), at: 0)
            }
        }
        return SnapReducerOutput(phase: .idle, effects: effects)
    }

    private static func arm(_ window: WindowIdentity, input: SnapReducerInput) -> SnapReducerOutput {
        let target = currentTarget(input)
        let displayID = cursorDisplayID(input)
        var effects: [SnapEffect] = []
        if let displayID {
            effects.append(.showOverlay(displayID: displayID))
        }
        effects.append(.highlight(target))
        if case .none = target {
            return SnapReducerOutput(phase: .armed(window), effects: effects)
        }
        return SnapReducerOutput(phase: .highlighting(window, target), effects: effects)
    }

    private static func highlight(_ input: SnapReducerInput) -> SnapReducerOutput {
        guard let window = currentWindow(input.phase) else {
            return SnapReducerOutput(phase: .idle, effects: [.hideOverlay])
        }
        return arm(window, input: input)
    }

    private static func currentTarget(_ input: SnapReducerInput) -> SnapTarget {
        let point = CoordinateConverter.axPoint(
            fromAppKit: input.event.locationAppKit,
            primaryFlipHeight: input.primaryFlipHeight
        )
        if let gridTarget = gridTarget(input, currentAX: point) {
            return gridTarget
        }
        return HitTester(policy: input.overlapPolicy).target(at: point, zones: input.resolvedZones)
    }

    /// Grid layouts prefer the cell under the pointer. Traveling from the
    /// arm origin onto another cell is a hover, not a span; otherwise a
    /// window dragged onto a zone would union every cell along the path.
    /// Control-drag keeps the original grid-draw union for multi-zone spans.
    private static func gridTarget(_ input: SnapReducerInput, currentAX: CGPoint) -> SnapTarget? {
        guard !input.gridCells.isEmpty else { return nil }

        if input.event.modifiers.contains(.control), let originAppKit = input.armOriginAppKit {
            let originAX = CoordinateConverter.axPoint(
                fromAppKit: originAppKit,
                primaryFlipHeight: input.primaryFlipHeight
            )
            let drag = CGRect(
                x: min(originAX.x, currentAX.x),
                y: min(originAX.y, currentAX.y),
                width: abs(currentAX.x - originAX.x),
                height: abs(currentAX.y - originAX.y)
            )
            let dragCovered = GridCoverage.coveredCells(dragRectAX: drag, cells: input.gridCells)
            if zoneIndices(in: dragCovered).count > 1 {
                return target(fromCovered: dragCovered, input: input)
            }
        }

        let hoverCovered = GridCoverage.coveredCells(
            dragRectAX: CGRect(origin: currentAX, size: .zero),
            cells: input.gridCells
        )
        return target(fromCovered: hoverCovered, input: input)
    }

    private static func target(fromCovered covered: [GridCell], input: SnapReducerInput) -> SnapTarget {
        guard let union = GridCoverage.unionFrameAX(
            cells: covered,
            gutter: input.gridGutter,
            workAreaAX: input.gridWorkAreaAX
        ) else {
            return .none
        }
        if let zone = input.resolvedZones.first(where: { rectsApproximatelyEqual($0.frameAX, union) }) {
            return .zone(zone)
        }
        let ids = input.resolvedZones
            .filter { $0.frameAX.intersects(union) }
            .map(\.zoneID)
        return .span(frameAX: union, zoneIDs: ids)
    }

    private static func rectsApproximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5
            && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5
            && abs(a.height - b.height) < 0.5
    }

    private static func zoneIndices(in cells: [GridCell]) -> Set<Int> {
        Set(cells.map(\.zoneIndex))
    }


    private static func cursorDisplayID(_ input: SnapReducerInput) -> UUID? {
        input.workAreas.first { $0.containsAppKitPoint(input.event.locationAppKit) }?.display.id
    }

    private static func currentWindow(_ phase: SnapSessionPhase) -> WindowIdentity? {
        switch phase {
        case .mouseDown(let w, _), .dragging(let w), .armed(let w), .highlighting(let w, _):
            return w
        default:
            return nil
        }
    }

    private static func isResize(_ input: SnapReducerInput) -> Bool {
        guard let down = input.downFrameAX, let current = input.currentFrameAX else { return false }
        return RectMath.chebyshevSize(down.size, current.size) > 2
    }

    private static func hasMoved(_ input: SnapReducerInput, originAX: CGRect) -> Bool {
        let cursorMoved: Bool
        if let down = input.downLocationAppKit {
            cursorMoved = RectMath.chebyshev(input.event.locationAppKit, down) >= 4
        } else {
            cursorMoved = false
        }
        let originMoved: Bool
        if let current = input.currentFrameAX {
            originMoved = RectMath.chebyshev(current.origin, originAX.origin) >= 2
        } else {
            originMoved = false
        }
        return cursorMoved || originMoved
    }

    private static func shouldArm(_ input: SnapReducerInput) -> Bool {
        if input.snapOnShiftDrag && input.event.modifiers.contains(.shift) {
            return true
        }
        if input.shakeToSnapEnabled && ShakeDetector.isShake(input.pointerTrace, intensity: input.shakeIntensity) {
            return true
        }
        return false
    }

    private static func magneticWorkAreaAX(_ input: SnapReducerInput) -> CGRect? {
        let flip = input.primaryFlipHeight
        let pointAppKit: CGPoint
        if let current = input.currentFrameAX {
            pointAppKit = CoordinateConverter.appKitPoint(
                fromAX: CGPoint(x: current.midX, y: current.midY),
                primaryFlipHeight: flip
            )
        } else {
            pointAppKit = input.event.locationAppKit
        }
        let area = input.workAreas.first { $0.containsAppKitPoint(pointAppKit) } ?? input.workAreas.first
        guard let area else { return nil }
        return CoordinateConverter.axRect(fromAppKit: area.visibleFrameAppKit, primaryFlipHeight: flip)
    }

    private static func clamp(_ rect: CGRect, to workAreas: [WorkArea], flip: CGFloat) -> CGRect {
        guard let area = workAreas.first else { return rect }
        let workAX = CoordinateConverter.axRect(fromAppKit: area.visibleFrameAppKit, primaryFlipHeight: flip)
        return rect.intersection(workAX)
    }
}
