import CoreGraphics
import Foundation

public struct StripDropLatch: Equatable, Sendable {
    public var layoutID: Layout.ID
    public var zone: ResolvedZone

    public init(layoutID: Layout.ID, zone: ResolvedZone) {
        self.layoutID = layoutID
        self.zone = zone
    }
}

/// Remembers how long each strip target was held so a drop can fall back to
/// the mini-zone the user actually rested on. Lifting fingers off a trackpad
/// or releasing a mouse button drags the pointer 15-25pt over the last few
/// frames; on a 37pt-wide thumbnail column that lands on the neighbor.
public struct StripDropLatchHistory: Equatable, Sendable {
    /// A target held at least this long counts as a deliberate choice.
    public static let settleDuration: TimeInterval = 0.2
    /// Target changes this close to mouse-up are treated as release drift.
    public static let releaseDriftWindow: TimeInterval = 0.12

    public private(set) var current: StripDropLatch?
    public private(set) var currentSince: TimeInterval
    public private(set) var settled: StripDropLatch?
    public private(set) var settledEndedAt: TimeInterval?

    public init() {
        current = nil
        currentSince = 0
        settled = nil
        settledEndedAt = nil
    }

    public mutating func record(_ latch: StripDropLatch?, at now: TimeInterval) {
        guard latch != current else { return }
        if let current, now - currentSince >= Self.settleDuration {
            settled = current
            settledEndedAt = now
        }
        if latch == nil {
            settled = nil
            settledEndedAt = nil
        }
        current = latch
        currentSince = now
    }

    /// The target a mouse-up should commit. `candidate` is the target the
    /// release frame itself computed; it only wins when the previous target
    /// was not a deliberate rest that ended within the drift window.
    public mutating func committed(candidate: StripDropLatch?, at now: TimeInterval) -> StripDropLatch? {
        record(candidate, at: now)
        guard let current else { return nil }
        if now - currentSince >= Self.releaseDriftWindow { return current }
        guard let settled, let settledEndedAt, now - settledEndedAt < Self.releaseDriftWindow else {
            return current
        }
        return settled
    }
}

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
    case dropUnsnap(WindowIdentity)
    case cancel
    case assignLayout(Layout.ID)
    case clearLockedTarget
    case selectLayout(Layout.ID)
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

    /// Adjacent layouts on the cursor display, current session layout first.
    public var layoutIDs: [Layout.ID]
    /// Layout currently assigned to the cursor display, if any.
    public var assignedLayoutID: Layout.ID?
    /// Layout currently shown by the overlay or strip target.
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
        layoutIDs: [Layout.ID] = [],
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
        self.layoutIDs = layoutIDs
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

    /// Tab / scroll walk adjacent layouts in display order.
    public static func wrappingIndex(current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let step = delta == 0 ? 0 : (delta > 0 ? 1 : -1)
        let next = current + step
        return ((next % count) + count) % count
    }

    public static func nextLayoutID(
        layoutIDs: [Layout.ID],
        currentSessionLayoutID: Layout.ID?,
        delta: Int
    ) -> Layout.ID? {
        guard !layoutIDs.isEmpty else { return currentSessionLayoutID }
        let current = currentSessionLayoutID.flatMap { layoutIDs.firstIndex(of: $0) } ?? 0
        return layoutIDs[wrappingIndex(current: current, delta: delta, count: layoutIDs.count)]
    }

    /// Trigger-zone hits under the pointer must not change the selected layout.
    /// An explicit Tab/scroll selection stays selected even while the pointer
    /// remains over a strip mini-zone; dropping still uses the strip target.
    public static func sessionLayoutIDForPointer(
        forcedLayoutID: Layout.ID?,
        currentSessionLayoutID: Layout.ID?,
        assignedLayoutID: Layout.ID?,
        preferForcedLayout: Bool = true
    ) -> Layout.ID? {
        if preferForcedLayout, let forcedLayoutID { return forcedLayoutID }
        return currentSessionLayoutID ?? assignedLayoutID
    }

    public static func sessionLayoutIDForPointer(
        forcedLayoutID: Layout.ID?,
        currentSessionLayoutID: Layout.ID?,
        assignedLayoutID: Layout.ID?,
        lockedTarget: SnapTarget?,
        preferForcedLayout: Bool = true
    ) -> Layout.ID? {
        if lockedTarget != nil { return currentSessionLayoutID }
        return sessionLayoutIDForPointer(
            forcedLayoutID: forcedLayoutID,
            currentSessionLayoutID: currentSessionLayoutID,
            assignedLayoutID: assignedLayoutID,
            preferForcedLayout: preferForcedLayout
        )
    }

    /// Linger-band probes may keep a mini-zone already chosen on the strip,
    /// but they must not start a selection. Cards sit in the top center, so
    /// shaking a window a few points below the bar would otherwise switch
    /// layouts without ever entering a card.
    public static func acceptedStripHit(
        hit: StripDropLatch?,
        previous _: StripDropLatch?,
        pointerOnStrip: Bool
    ) -> StripDropLatch? {
        return pointerOnStrip ? hit : nil
    }

    /// Only a real strip-card hover may highlight another layout. Projecting
    /// a linger-band point onto a card must not change the selected layout.
    public static func acceptedHighlight(
        pointerOnStrip: Bool,
        hitCard: Layout.ID?
    ) -> Layout.ID? {
        pointerOnStrip ? hitCard : nil
    }

    /// A strip mini-zone stays selected until the pointer leaves both the strip
    /// and that layout's real zones. A new mini-zone hit replaces it. Pointers
    /// that only slip a little below the strip keep the mini-zone so a card
    /// sitting over the wrong half of the screen cannot retarget the drop.
    public static func stripDropLatch(
        pointerInStrip: Bool,
        hit: StripDropLatch?,
        previous: StripDropLatch?,
        liveZoneInLatchedLayout: ResolvedZone?,
        lingerNearStrip: Bool = false
    ) -> StripDropLatch? {
        if let hit { return hit }
        if pointerInStrip || lingerNearStrip { return previous }
        guard let previous, let live = liveZoneInLatchedLayout else { return nil }
        return StripDropLatch(layoutID: previous.layoutID, zone: live)
    }

    /// Overlay panes and the highlight rect must come from the same layout.
    /// A leftover highlight from the previous strip card would otherwise draw
    /// that card's zone on top of the newly selected layout.
    public static func previewHighlight(
        _ highlight: SnapTarget,
        zones: [ResolvedZone],
        latch: StripDropLatch? = nil
    ) -> SnapTarget {
        if belongs(highlight, in: zones) { return highlight }
        if let latch, zones.contains(where: { $0.zoneID == latch.zone.zoneID }) {
            return .zone(latch.zone)
        }
        return .none
    }

    private static func belongs(_ highlight: SnapTarget, in zones: [ResolvedZone]) -> Bool {
        switch highlight {
        case .none:
            return true
        case .zone(let zone):
            return zones.contains { $0.zoneID == zone.zoneID }
        case .span(_, let zoneIDs):
            guard !zoneIDs.isEmpty else { return false }
            return zoneIDs.allSatisfy { id in
                zones.contains { $0.zoneID == id }
            }
        }
    }

    /// A successful overlay digit replaces the strip drop target. Keep the
    /// latched layout as the session layout so later numbers stay on it.
    public static func stripDropLatchAfterDigit(
        previous: StripDropLatch?,
        currentSessionLayoutID: Layout.ID?
    ) -> (latch: StripDropLatch?, sessionLayoutID: Layout.ID?) {
        (nil, previous?.layoutID ?? currentSessionLayoutID)
    }

    /// After a digit or Tab/scroll selection, ignore strip hits until the
    /// pointer leaves the strip so overlay refresh cannot rebuild the latch.
    public static func acceptingStripHit(
        suppressStripLatch: Bool,
        pointerInStrip: Bool
    ) -> (acceptHit: Bool, suppressStripLatch: Bool) {
        if !suppressStripLatch {
            return (true, false)
        }
        if pointerInStrip {
            return (false, true)
        }
        return (true, false)
    }

    public struct ExplicitLayoutPreview: Equatable, Sendable {
        public var selectedLayoutID: Layout.ID
        public var zones: [ResolvedZone]
        public var highlight: SnapTarget
        public var strip: LayoutStripGeometry?
        public var presentation: OverlayPresentation
        public var stripWindowStartID: Layout.ID?

        public init(
            selectedLayoutID: Layout.ID,
            zones: [ResolvedZone],
            highlight: SnapTarget,
            strip: LayoutStripGeometry?,
            presentation: OverlayPresentation,
            stripWindowStartID: Layout.ID?
        ) {
            self.selectedLayoutID = selectedLayoutID
            self.zones = zones
            self.highlight = highlight
            self.strip = strip
            self.presentation = presentation
            self.stripWindowStartID = stripWindowStartID
        }
    }

    /// Zones and the strip card for a Tab or Shift+Tab selection on this frame.
    /// The zone highlight stays empty so a pointer still resting on the previous
    /// card cannot paint that card's pane onto the newly selected layout.
    public static func projectExplicitSelection(
        selectedLayoutID: Layout.ID,
        zones: [ResolvedZone],
        layouts: [(layout: Layout, zones: [ResolvedZone])],
        workAreaAppKit: CGRect,
        workAreaAX: CGRect,
        assignedLayoutID: Layout.ID?,
        previousStartLayoutID: Layout.ID?,
        showLayoutStrip: Bool
    ) -> ExplicitLayoutPreview {
        guard showLayoutStrip else {
            return ExplicitLayoutPreview(
                selectedLayoutID: selectedLayoutID,
                zones: zones,
                highlight: .none,
                strip: nil,
                presentation: .snapSession(strip: nil),
                stripWindowStartID: previousStartLayoutID
            )
        }
        let strip = LayoutStripGeometry.make(
            workAreaAppKit: workAreaAppKit,
            layouts: layouts,
            assignedLayoutID: assignedLayoutID,
            workAreaAX: workAreaAX,
            focusedLayoutID: selectedLayoutID,
            previousStartLayoutID: previousStartLayoutID
        )
        let model = OverlayStripRenderModel(
            geometry: strip,
            highlightedLayoutID: selectedLayoutID,
            highlightedZoneNumber: nil
        )
        return ExplicitLayoutPreview(
            selectedLayoutID: selectedLayoutID,
            zones: zones,
            highlight: .none,
            strip: strip,
            presentation: .snapSession(strip: model),
            stripWindowStartID: strip.cards.first?.layoutID ?? previousStartLayoutID
        )
    }

    /// Layout used to resolve the next sample. suppressStripLatch is the flag
    /// after acceptingStripHit; this does not run that gate again. While
    /// suppression holds, a hovered card cannot replace the selection, including
    /// after the pointer has left the strip.
    public static func layoutIDAfterExplicitSelection(
        selectedLayoutID: Layout.ID?,
        pointerLayoutID: Layout.ID?,
        suppressStripLatch: Bool,
        pointerInStrip: Bool
    ) -> Layout.ID? {
        if suppressStripLatch {
            return selectedLayoutID
        }
        if pointerInStrip || pointerLayoutID != nil {
            return pointerLayoutID ?? selectedLayoutID
        }
        return selectedLayoutID
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

    /// A delayed AX completion must not mutate a newer drag session.
    public static func shouldUpdateSession(
        completionGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        completionGeneration == currentGeneration
    }

    /// Normal post-drop cleanup must keep the drop's generation so its AX write
    /// can still persist the assignment. Only a newer drag or cancel bumps it.
    public static func generationAfterSessionReset(
        current: Int,
        startingNewDrag: Bool
    ) -> Int {
        startingNewDrag ? current + 1 : current
    }
}

public enum UnsnapCatalogPolicy {
    public static let sizeTolerance: CGFloat = 8

    public static func frameMatches(_ actual: CGRect?, requested: CGRect) -> Bool {
        guard let actual else { return false }
        return max(
            RectMath.chebyshev(actual.origin, requested.origin),
            RectMath.chebyshevSize(actual.size, requested.size)
        ) <= sizeTolerance
    }

    /// A failed, partial, or superseded restore must not clear the current snap
    /// cycle. Another window's drag is not supersession; only a newer record
    /// for this identity replaces the captured restore.
    public static func identityToDrop(
        capturedForThisWrite: UnsnapRecord?,
        currentRecord: UnsnapRecord?,
        requestedFrame: CGRect,
        appliedFrame: CGRect?
    ) -> WindowIdentity? {
        guard let capturedForThisWrite,
              currentRecord == capturedForThisWrite,
              frameMatches(appliedFrame, requested: requestedFrame)
        else { return nil }
        return capturedForThisWrite.identity
    }

    /// Drag snaps record the requested zone before AX returns. Store the live
    /// frame only while this write still owns the captured catalog record.
    public static func appliedSnappedFrame(
        capturedSnap: UnsnapRecord?,
        currentRecord: UnsnapRecord?,
        requestedFrame: CGRect,
        appliedFrame: CGRect?
    ) -> CGRect? {
        guard let capturedSnap,
              let currentRecord,
              capturedSnap.identity == currentRecord.identity,
              capturedSnap.snappedAt == currentRecord.snappedAt,
              capturedSnap.zoneIDs == currentRecord.zoneIDs,
              capturedSnap.snappedFrameAX == currentRecord.snappedFrameAX,
              capturedSnap.snappedFrameAX == requestedFrame,
              let appliedFrame
        else { return nil }
        return appliedFrame
    }

    /// Mouse-down CG can briefly report a work-area-sized frame. Prefer the
    /// refreshed live size when it disagrees, keeping the down origin.
    public static func capturedOriginalFrame(downFrameAX: CGRect?, currentFrameAX: CGRect?) -> CGRect? {
        switch (downFrameAX, currentFrameAX) {
        case (nil, nil):
            return nil
        case (let down?, nil):
            return down
        case (nil, let current?):
            return current
        case (let down?, let current?):
            guard RectMath.chebyshevSize(down.size, current.size) > sizeTolerance else {
                return down
            }
            return CGRect(x: down.minX, y: down.minY, width: current.width, height: current.height)
        }
    }

    /// Keep the first original only while the window is still at the last
    /// snapped size. A live resize starts a new restore cycle.
    public static func originalFrameAX(existing: UnsnapRecord?, incomingOriginal: CGRect) -> CGRect {
        guard let existing else { return incomingOriginal }
        if RectMath.chebyshevSize(incomingOriginal.size, existing.snappedFrameAX.size) <= sizeTolerance {
            return existing.originalFrameAX
        }
        return incomingOriginal
    }
}
