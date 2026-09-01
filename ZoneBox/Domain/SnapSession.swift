import CoreGraphics
import Foundation

public struct UnsnapRecord: Sendable, Equatable {
    public var identity: WindowIdentity
    public var originalFrameAX: CGRect
    public var snappedFrameAX: CGRect
    public var zoneIDs: [UUID]
    public var snappedAt: Date

    public init(
        identity: WindowIdentity,
        originalFrameAX: CGRect,
        snappedFrameAX: CGRect,
        zoneIDs: [UUID],
        snappedAt: Date = Date()
    ) {
        self.identity = identity
        self.originalFrameAX = originalFrameAX
        self.snappedFrameAX = snappedFrameAX
        self.zoneIDs = zoneIDs
        self.snappedAt = snappedAt
    }
}

public enum SnapSessionPhase: Equatable, Sendable {
    case idle
    case mouseDown(WindowIdentity, originAX: CGRect)
    case dragging(WindowIdentity)
    case resizing
    case armed(WindowIdentity)
    case highlighting(WindowIdentity, SnapTarget)
}

public enum SnapEffect: Equatable, Sendable {
    case none
    case showOverlay(displayID: UUID)
    case hideOverlay
    case highlight(SnapTarget)
    case applyFrame(WindowIdentity, CGRect)
    case recordUnsnap(UnsnapRecord)
    case cancel
    case assignLayout(Layout.ID)
    case clearLockedTarget
    case selectCandidate(Int)
}

public struct SnapReducerInput: Equatable, Sendable {
    public var phase: SnapSessionPhase
    public var event: SnapMouseEvent
    public var workAreas: [WorkArea]
    public var primaryFlipHeight: CGFloat
    public var window: WindowIdentity?
    public var downFrameAX: CGRect?
    public var currentFrameAX: CGRect?
    public var downLocationAppKit: CGPoint?
    public var resolvedZones: [ResolvedZone]
    public var unsnapRecord: UnsnapRecord?
    public var trusted: Bool
    public var snapEnabled: Bool
    public var isEditorOpen: Bool
    public var restoreSizeOnUnsnap: Bool
    public var overlapPolicy: OverlapPolicy
    public var snapOnShiftDrag: Bool
    public var snapOnRightClickDrag: Bool
    public var shakeToSnapEnabled: Bool
    public var shakeIntensity: Int
    public var pointerTrace: [CGPoint]
    public var stickyArm: Bool
    public var armOriginAppKit: CGPoint?
    public var gridCells: [GridCell]
    public var gridGutter: CGFloat
    public var gridWorkAreaAX: CGRect
    public var magneticResizeEnabled: Bool
    public var magneticThreshold: CGFloat

    /// Zone chosen by overlay digit; hover must not replace it.
    public var lockedTarget: SnapTarget?

    /// True when the press started on window-move chrome (title bar).
    /// Content-area drags must not arm the zone overlay.
    public var startedOnMoveChrome: Bool

    /// Cross-layout zone candidates under the pointer, assigned layout first.
    public var candidates: [ZoneCandidate]
    /// Index into `candidates` chosen by scroll/Tab. Engine-owned, like `lockedTarget`.
    public var candidateIndex: Int
    /// Layout currently assigned to the cursor display, if any.
    public var assignedLayoutID: Layout.ID?
    /// Layout belonging to the highlighted candidate or strip target.
    public var sessionLayoutID: Layout.ID?
    /// True while the pointer is inside the layout strip. Zones under the strip do not win.
    public var pointerInLayoutStrip: Bool
    /// Mini-zone under the pointer, already mapped to a real `ResolvedZone`.
    public var forcedTarget: SnapTarget?

    public init(
        phase: SnapSessionPhase,
        event: SnapMouseEvent,
        workAreas: [WorkArea] = [],
        primaryFlipHeight: CGFloat = 0,
        window: WindowIdentity? = nil,
        downFrameAX: CGRect? = nil,
        currentFrameAX: CGRect? = nil,
        downLocationAppKit: CGPoint? = nil,
        resolvedZones: [ResolvedZone] = [],
        unsnapRecord: UnsnapRecord? = nil,
        trusted: Bool = true,
        snapEnabled: Bool = true,
        isEditorOpen: Bool = false,
        restoreSizeOnUnsnap: Bool = true,
        overlapPolicy: OverlapPolicy = .smallestArea,
        snapOnShiftDrag: Bool = true,
        snapOnRightClickDrag: Bool = true,
        shakeToSnapEnabled: Bool = true,
        shakeIntensity: Int = ShakeProfile.defaultIntensity,
        pointerTrace: [CGPoint] = [],
        stickyArm: Bool = false,
        armOriginAppKit: CGPoint? = nil,
        gridCells: [GridCell] = [],
        gridGutter: CGFloat = 0,
        gridWorkAreaAX: CGRect = .null,
        magneticResizeEnabled: Bool = true,
        magneticThreshold: CGFloat = MagneticResize.defaultThreshold,
        lockedTarget: SnapTarget? = nil,
        startedOnMoveChrome: Bool = true,
        candidates: [ZoneCandidate] = [],
        candidateIndex: Int = 0,
        assignedLayoutID: Layout.ID? = nil,
        sessionLayoutID: Layout.ID? = nil,
        pointerInLayoutStrip: Bool = false,
        forcedTarget: SnapTarget? = nil
    ) {
        self.phase = phase
        self.event = event
        self.workAreas = workAreas
        self.primaryFlipHeight = primaryFlipHeight
        self.window = window
        self.downFrameAX = downFrameAX
        self.currentFrameAX = currentFrameAX
        self.downLocationAppKit = downLocationAppKit
        self.resolvedZones = resolvedZones
        self.unsnapRecord = unsnapRecord
        self.trusted = trusted
        self.snapEnabled = snapEnabled
        self.isEditorOpen = isEditorOpen
        self.restoreSizeOnUnsnap = restoreSizeOnUnsnap
        self.overlapPolicy = overlapPolicy
        self.snapOnShiftDrag = snapOnShiftDrag
        self.snapOnRightClickDrag = snapOnRightClickDrag
        self.shakeToSnapEnabled = shakeToSnapEnabled
        self.shakeIntensity = shakeIntensity
        self.pointerTrace = pointerTrace
        self.stickyArm = stickyArm
        self.armOriginAppKit = armOriginAppKit
        self.gridCells = gridCells
        self.gridGutter = gridGutter
        self.gridWorkAreaAX = gridWorkAreaAX
        self.magneticResizeEnabled = magneticResizeEnabled
        self.magneticThreshold = magneticThreshold
        self.lockedTarget = lockedTarget
        self.startedOnMoveChrome = startedOnMoveChrome
        self.candidates = candidates
        self.candidateIndex = candidateIndex
        self.assignedLayoutID = assignedLayoutID
        self.sessionLayoutID = sessionLayoutID
        self.pointerInLayoutStrip = pointerInLayoutStrip
        self.forcedTarget = forcedTarget
    }
}

public struct SnapReducerOutput: Equatable, Sendable {
    public var phase: SnapSessionPhase
    public var effects: [SnapEffect]

    public init(phase: SnapSessionPhase, effects: [SnapEffect]) {
        self.phase = phase
        self.effects = effects
    }
}

public enum SnapLayoutSession {
    /// Crossing a display always adopts that display's assigned layout so an
    /// armed drag cannot keep resolving the previous screen's zones.
    public static func sessionLayoutID(
        previousDisplayID: DisplayIdentity.ID?,
        currentDisplayID: DisplayIdentity.ID?,
        assignedLayoutID: Layout.ID?,
        currentSessionLayoutID: Layout.ID?
    ) -> (layoutID: Layout.ID?, crossedDisplay: Bool) {
        guard let currentDisplayID else {
            return (currentSessionLayoutID, false)
        }
        if previousDisplayID != currentDisplayID {
            return (assignedLayoutID, true)
        }
        return (currentSessionLayoutID, false)
    }

    /// Crossing a display adopts that screen's assigned layout unless a digit
    /// lock is holding the previous session layout in place.
    public static func sessionLayoutID(
        previousDisplayID: DisplayIdentity.ID?,
        currentDisplayID: DisplayIdentity.ID?,
        assignedLayoutID: Layout.ID?,
        currentSessionLayoutID: Layout.ID?,
        lockedTarget: SnapTarget?
    ) -> (layoutID: Layout.ID?, crossedDisplay: Bool) {
        let crossed = sessionLayoutID(
            previousDisplayID: previousDisplayID,
            currentDisplayID: currentDisplayID,
            assignedLayoutID: assignedLayoutID,
            currentSessionLayoutID: currentSessionLayoutID
        )
        if crossed.crossedDisplay, lockedTarget != nil {
            return (currentSessionLayoutID, true)
        }
        return crossed
    }

    /// When the pointer leaves the previously cycled candidate, index 0 is the
    /// assigned-layout hit. Keep `sessionLayoutID` on that candidate so overlay
    /// zones and labels do not describe different layouts.
    public static func layoutIDAfterCandidateReset(
        candidates: [ZoneCandidate],
        candidateIndex: Int,
        currentSessionLayoutID: Layout.ID?
    ) -> Layout.ID? {
        if candidates.indices.contains(candidateIndex) {
            return candidates[candidateIndex].layoutID
        }
        return currentSessionLayoutID
    }

    /// A digit lock pins both the zone and its layout until the lock is cleared.
    public static func layoutIDAfterCandidateReset(
        candidates: [ZoneCandidate],
        candidateIndex: Int,
        currentSessionLayoutID: Layout.ID?,
        lockedTarget: SnapTarget?
    ) -> Layout.ID? {
        if lockedTarget != nil { return currentSessionLayoutID }
        return layoutIDAfterCandidateReset(
            candidates: candidates,
            candidateIndex: candidateIndex,
            currentSessionLayoutID: currentSessionLayoutID
        )
    }

    /// After leaving a strip mini-zone, follow the live candidate rather than
    /// keeping the strip's layout. Index 0 is the assigned-layout hit.
    public static func sessionLayoutIDForPointer(
        forcedLayoutID: Layout.ID?,
        candidates: [ZoneCandidate],
        candidateIndex: Int,
        currentSessionLayoutID: Layout.ID?,
        assignedLayoutID: Layout.ID?
    ) -> Layout.ID? {
        if let forcedLayoutID { return forcedLayoutID }
        if candidates.indices.contains(candidateIndex) {
            return candidates[candidateIndex].layoutID
        }
        return currentSessionLayoutID ?? assignedLayoutID
    }

    public static func sessionLayoutIDForPointer(
        forcedLayoutID: Layout.ID?,
        candidates: [ZoneCandidate],
        candidateIndex: Int,
        currentSessionLayoutID: Layout.ID?,
        assignedLayoutID: Layout.ID?,
        lockedTarget: SnapTarget?
    ) -> Layout.ID? {
        if lockedTarget != nil { return currentSessionLayoutID }
        return sessionLayoutIDForPointer(
            forcedLayoutID: forcedLayoutID,
            candidates: candidates,
            candidateIndex: candidateIndex,
            currentSessionLayoutID: currentSessionLayoutID,
            assignedLayoutID: assignedLayoutID
        )
    }
}

public enum SnapLayoutAssignmentPolicy {
    /// Persist a cross-layout assignment only after the snapped frame is known
    /// to have been applied. A failed AX write must leave settings unchanged.
    public static func shouldPersist(afterFrameApplied succeeded: Bool) -> Bool {
        succeeded
    }

    /// An AX frame write may only commit the assignment captured for that write.
    /// A later, unrelated `.applyFrame` must not inherit a previous pending value.
    public static func assignmentToCommit(
        capturedForThisWrite: Layout.ID?,
        frameApplied: Bool
    ) -> Layout.ID? {
        guard frameApplied else { return nil }
        return capturedForThisWrite
    }
}
