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
        case .idle, .mouseDown, .resizing:
            return SnapReducerOutput(phase: .idle, effects: [.hideOverlay])
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
            if case .zone(let zone) = currentTarget(input), let window = currentWindow(input.phase) {
                var effects: [SnapEffect] = [.applyFrame(window, zone.frameAX), .hideOverlay]
                if input.unsnapRecord == nil, let original = input.downFrameAX {
                    effects.insert(
                        .recordUnsnap(
                            UnsnapRecord(
                                identity: window,
                                originalFrameAX: original,
                                snappedFrameAX: zone.frameAX,
                                zoneIDs: [zone.zoneID]
                            )
                        ),
                        at: 0
                    )
                }
                return SnapReducerOutput(phase: .idle, effects: effects)
            }
            return SnapReducerOutput(phase: .idle, effects: [.hideOverlay])
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
            if !shift {
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

    private static func arm(_ window: WindowIdentity, input: SnapReducerInput) -> SnapReducerOutput {
        let target = currentTarget(input)
        let displayID = cursorDisplayID(input)
        var effects: [SnapEffect] = []
        if let displayID {
            effects.append(.showOverlay(displayID: displayID))
        }
        effects.append(.highlight(target))
        if case .zone = target {
            return SnapReducerOutput(phase: .highlighting(window, target), effects: effects)
        }
        return SnapReducerOutput(phase: .armed(window), effects: effects)
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
        return HitTester(policy: input.overlapPolicy).target(at: point, zones: input.resolvedZones)
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
        (input.snapOnShiftDrag && input.event.modifiers.contains(.shift))
    }

    private static func clamp(_ rect: CGRect, to workAreas: [WorkArea], flip: CGFloat) -> CGRect {
        guard let area = workAreas.first else { return rect }
        let workAX = CoordinateConverter.axRect(fromAppKit: area.visibleFrameAppKit, primaryFlipHeight: flip)
        return rect.intersection(workAX)
    }
}
