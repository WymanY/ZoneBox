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
        case .digit(let number):
            return reduceDigit(input, number: number)
        case .cycleCandidate(let delta):
            return reduceCycleCandidate(input, delta: delta)
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
            if input.startedOnMoveChrome,
               input.restoreSizeOnUnsnap,
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
            let target: SnapTarget
            if input.forcedTarget != nil || input.pointerInLayoutStrip {
                target = currentTarget(input)
            } else if let locked = lockedTarget(input) {
                target = locked
            } else if case .highlighting(_, let highlighted) = input.phase, highlighted.frameAX != nil {
                target = highlighted
            } else {
                target = currentTarget(input)
            }
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
            if let layoutID = layoutID(for: target, input: input) {
                if let applyIndex = effects.firstIndex(of: .applyFrame(window, frame)) {
                    effects.insert(.assignLayout(layoutID), at: applyIndex)
                } else {
                    effects.append(.assignLayout(layoutID))
                }
            }
            return SnapReducerOutput(phase: .idle, effects: effects)
        }
    }

    private static func reduceArm(_ input: SnapReducerInput, sticky: Bool) -> SnapReducerOutput {
        _ = sticky
        guard input.snapOnRightClickDrag, input.startedOnMoveChrome else {
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
        case .mouseDown(let window, let originAX)
            where shift && input.snapOnShiftDrag && input.startedOnMoveChrome && !isResize(input) && hasMoved(input, originAX: originAX):
            return arm(window, input: input)
        case .dragging(let window) where shift && input.snapOnShiftDrag && input.startedOnMoveChrome:
            return arm(window, input: input)
        case .armed, .highlighting:
            if !shift && !input.stickyArm && input.lockedTarget == nil {
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
        if input.lockedTarget != nil, let frame = target.frameAX {
            effects.append(.applyFrame(window, frame))
        }
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
        if let forced = input.forcedTarget {
            return forced
        }
        if input.pointerInLayoutStrip {
            return .none
        }
        if let locked = lockedTarget(input) {
            return locked
        }
        let point = CoordinateConverter.axPoint(
            fromAppKit: input.event.locationAppKit,
            primaryFlipHeight: input.primaryFlipHeight
        )
        if input.event.modifiers.contains(.control),
           let gridTarget = gridTarget(input, currentAX: point) {
            return gridTarget
        }
        if input.candidateIndex != 0, let candidate = selectedCandidate(input) {
            return .zone(candidate.zone)
        }
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

    private static func reduceDigit(_ input: SnapReducerInput, number: Int) -> SnapReducerOutput {
        guard (1...9).contains(number) else {
            return SnapReducerOutput(phase: input.phase, effects: [])
        }
        guard let window = currentWindow(input.phase) else {
            return SnapReducerOutput(phase: input.phase, effects: [])
        }
        switch input.phase {
        case .armed, .highlighting:
            guard let zone = input.resolvedZones.first(where: { $0.number == number }) else {
                return SnapReducerOutput(phase: input.phase, effects: [])
            }
            let target = SnapTarget.zone(zone)
            var effects: [SnapEffect] = []
            if let displayID = cursorDisplayID(input) {
                effects.append(.showOverlay(displayID: displayID))
            }
            effects.append(.highlight(target))
            effects.append(.applyFrame(window, zone.frameAX))
            if input.unsnapRecord == nil, let original = input.downFrameAX {
                effects.append(
                    .recordUnsnap(
                        UnsnapRecord(
                            identity: window,
                            originalFrameAX: original,
                            snappedFrameAX: zone.frameAX,
                            zoneIDs: [zone.zoneID]
                        )
                    )
                )
            }
            return SnapReducerOutput(phase: .highlighting(window, target), effects: effects)
        default:
            return SnapReducerOutput(phase: input.phase, effects: [])
        }
    }

    private static func reduceCycleCandidate(_ input: SnapReducerInput, delta: Int) -> SnapReducerOutput {
        switch input.phase {
        case .armed, .highlighting:
            break
        default:
            return SnapReducerOutput(phase: input.phase, effects: [])
        }
        guard let window = currentWindow(input.phase), !input.candidates.isEmpty else {
            return SnapReducerOutput(phase: input.phase, effects: [])
        }
        let nextIndex = ZoneCandidateResolver.wrappingIndex(
            current: input.candidateIndex,
            delta: delta,
            count: input.candidates.count
        )
        let candidate = input.candidates[nextIndex]
        let target = SnapTarget.zone(candidate.zone)
        var effects: [SnapEffect] = [.selectCandidate(nextIndex), .clearLockedTarget]
        if let displayID = cursorDisplayID(input) {
            effects.append(.showOverlay(displayID: displayID))
        }
        effects.append(.highlight(target))
        return SnapReducerOutput(phase: .highlighting(window, target), effects: effects)
    }

    private static func selectedCandidate(_ input: SnapReducerInput) -> ZoneCandidate? {
        guard input.candidates.indices.contains(input.candidateIndex) else { return nil }
        return input.candidates[input.candidateIndex]
    }

    private static func layoutID(for target: SnapTarget, input: SnapReducerInput) -> Layout.ID? {
        if let forced = input.forcedTarget, forced == target {
            return input.sessionLayoutID
        }
        if case .zone(let zone) = target {
            if let candidate = input.candidates.first(where: { $0.zone.zoneID == zone.zoneID }) {
                return candidate.layoutID
            }
            if input.resolvedZones.contains(where: { $0.zoneID == zone.zoneID }) {
                return input.sessionLayoutID ?? input.assignedLayoutID
            }
        }
        if case .span = target {
            return input.sessionLayoutID ?? input.assignedLayoutID
        }
        return input.sessionLayoutID ?? input.assignedLayoutID
    }

    private static func lockedTarget(_ input: SnapReducerInput) -> SnapTarget? {
        guard case .zone(let locked) = input.lockedTarget else { return input.lockedTarget }
        if let current = input.resolvedZones.first(where: { $0.number == locked.number }) {
            return .zone(current)
        }
        return input.lockedTarget
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
        // CG vs AX chrome and snap rounding can jitter a few points. A real
        // resize is a clear size change, not a 2–8 pt shadow/title-bar mismatch.
        return RectMath.chebyshevSize(down.size, current.size) > 8
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
        guard input.startedOnMoveChrome else { return false }
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
