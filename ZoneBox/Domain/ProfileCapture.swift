import CoreGraphics
import Foundation

public enum ProfileCapture {
    public struct VisibilitySample: Equatable, Sendable {
        public var identity: WindowIdentity
        public var frameAX: CGRect
        public var opacity: Double
        public var isOpaqueOccluder: Bool

        public init(
            identity: WindowIdentity,
            frameAX: CGRect,
            opacity: Double = 1,
            isOpaqueOccluder: Bool = true
        ) {
            self.identity = identity
            self.frameAX = frameAX
            self.opacity = opacity
            self.isOpaqueOccluder = isOpaqueOccluder
        }
    }

    public struct WindowSample: Equatable, Sendable {
        public var identity: WindowIdentity
        public var frameAX: CGRect

        public init(identity: WindowIdentity, frameAX: CGRect) {
            self.identity = identity
            self.frameAX = frameAX
        }
    }

    /// One rule per captured window, kept front-to-back, holding the frame
    /// relative to the display's work area. There is no zone matching: a
    /// window that spans two zones or ignores the layout entirely is saved
    /// exactly where it was.
    public static func rules(
        windows: [WindowSample],
        workAreaAX: CGRect
    ) -> [AppPlacementRule] {
        guard workAreaAX.width > 0, workAreaAX.height > 0 else { return [] }
        return windows.compactMap { sample in
            guard let bundleID = sample.identity.bundleID, !bundleID.isEmpty else { return nil }
            return AppPlacementRule(
                bundleID: bundleID,
                frame: NormalizedRect.rawNormalized(sample.frameAX, in: workAreaAX)
            )
        }
    }

    /// WindowServer returns on-screen windows front-to-back, including windows
    /// behind other windows. Divider occupancy hides a window when a single
    /// opaque window in front covers a meaningful fraction of its surface.
    public static func visibleWindowIdentities(
        frontToBack windows: [VisibilitySample]
    ) -> Set<WindowIdentity> {
        identities(frontToBack: windows, isVisible: isMostlyUncovered(_:behind:))
    }

    /// Workspace snapshot. Keeps a window while a usable region remains
    /// uncovered by opaque windows in front. Completely covered windows,
    /// including those jointly covered by several front windows, stay out
    /// unless `includeFullyOccluded` is on. A remaining sliver counts only if
    /// it can fit more than an 8x8 pt square (candidate inset 4 pt, opaque
    /// occluders outset 4 pt), so a 6 pt snap seam is not treated as visible.
    /// `includeFullyOccluded` skips that inset/outset and keeps every window
    /// that still passes the opacity and usable-frame filters. Saved frames
    /// are not shrunk. When supplied, `displayFramesAX` limits visibility to
    /// the union of physical displays; even the opt-in needs an intersection.
    /// Nil leaves geometry unbounded for callers without a display snapshot.
    /// Other capture filters still apply.
    public static func capturableWindowIdentities(
        frontToBack windows: [VisibilitySample],
        includeFullyOccluded: Bool = false,
        displayFramesAX: [CGRect]? = nil
    ) -> Set<WindowIdentity> {
        let displays = displayFramesAX?.map(\.standardized).filter(isUsable)
        return identities(
            frontToBack: windows,
            isVisible: { frame, occluders in
                if let displays,
                   !displays.contains(where: { isUsable(frame.intersection($0)) }) {
                    return false
                }
                return includeFullyOccluded || isStillVisible(frame, behind: occluders, displays: displays)
            }
        )
    }

    /// AX enumeration is batched by process. Recover the original CG order
    /// using the matched CG ref's index, even when AX reports a different ID.
    /// Windows discovered only through AX stay after on-screen matches, in
    /// their original order; minimized/hidden windows are appended separately.
    public static func orderedCandidates<T>(
        _ candidates: [T],
        windowServerIndex: (T) -> Int?
    ) -> [T] {
        let ranked: [(offset: Int, candidate: T, index: Int)] = candidates.enumerated().map { offset, candidate in
            (offset: offset, candidate: candidate, index: windowServerIndex(candidate) ?? Int.max)
        }
        return ranked.sorted {
            $0.index == $1.index ? $0.offset < $1.offset : $0.index < $1.index
        }.map { $0.candidate }
    }

    /// Whether a window currently counts as sitting at `target`: either placed
    /// there within tolerance or covering most of it.
    public static func occupies(_ frame: CGRect, zone: CGRect) -> Bool {
        ZoneOccupancy.occupies(frame, zone: zone)
    }

    /// "Only this display" is offered when at least two displays would be
    /// saved and the pointer sits on one of those displays. An empty pointer
    /// display would otherwise produce a zero-window capture.
    public static func offersThisDisplayScope(
        sections: [ProfileSection],
        pointerDisplayID: DisplayIdentity.ID?
    ) -> Bool {
        guard sections.count >= 2, let pointerDisplayID else { return false }
        return sections.contains { $0.space.displayID == pointerDisplayID }
    }

    /// A new workspace keeps every display that holds captured windows unless
    /// the user asked for the pointer's display only.
    public static func sections(
        _ sections: [ProfileSection],
        limitedTo displayID: DisplayIdentity.ID?
    ) -> [ProfileSection] {
        guard let displayID else { return sections }
        return sections.filter { $0.space.displayID == displayID }
    }

    /// Recapture refreshes connected displays only. A section whose display is
    /// unplugged stays as saved, so updating a laptop-only desk cannot erase the
    /// docked half. Returns nil when nothing was captured so a failed recapture
    /// cannot wipe the profile.
    public static func mergedRecaptureSections(
        existing: [ProfileSection],
        captured: [ProfileSection],
        availableDisplayIDs: Set<DisplayIdentity.ID>
    ) -> [ProfileSection]? {
        guard !captured.isEmpty else { return nil }
        var capturedByDisplay: [DisplayIdentity.ID: ProfileSection] = [:]
        for section in captured where capturedByDisplay[section.space.displayID] == nil {
            capturedByDisplay[section.space.displayID] = section
        }
        var result: [ProfileSection] = []
        var seen = Set<DisplayIdentity.ID>()
        for section in existing {
            let id = section.space.displayID
            seen.insert(id)
            if availableDisplayIDs.contains(id) {
                if let fresh = capturedByDisplay[id] {
                    result.append(fresh)
                }
            } else {
                result.append(section)
            }
        }
        for section in captured where seen.insert(section.space.displayID).inserted {
            result.append(section)
        }
        return result.isEmpty ? nil : result
    }

    /// Adjacent snapped windows commonly share a 1pt seam. That is not occlusion.
    /// Divider occupancy hides a window when one opaque front window covers a
    /// meaningful fraction of it. Workspace capture treats a remaining region
    /// as visible only when it can fit more than an 8x8 pt square.
    private static let occupancyOcclusionCoverage: CGFloat = 0.25
    /// Remaining uncovered area must fit a square larger than this to count.
    private static let captureSeamTolerance: CGFloat = 8

    private static func identities(
        frontToBack windows: [VisibilitySample],
        isVisible: (CGRect, [CGRect]) -> Bool
    ) -> Set<WindowIdentity> {
        var opaqueFrames: [CGRect] = []
        var visible = Set<WindowIdentity>()
        for window in windows {
            let frame = window.frameAX.standardized
            guard window.opacity > 0.01, isUsable(frame) else { continue }
            if isVisible(frame, opaqueFrames) {
                visible.insert(window.identity)
            }
            if window.isOpaqueOccluder {
                opaqueFrames.append(frame)
            }
        }
        return visible
    }

    private static func isMostlyUncovered(_ frame: CGRect, behind occluders: [CGRect]) -> Bool {
        let area = max(frame.width * frame.height, 1)
        return !occluders.contains { occluder in
            guard isUsable(occluder) else { return false }
            let overlap = frame.intersection(occluder)
            guard !overlap.isNull, !overlap.isInfinite else { return false }
            return (overlap.width * overlap.height) / area >= occupancyOcclusionCoverage
        }
    }

    private static func isStillVisible(
        _ frame: CGRect,
        behind occluders: [CGRect],
        displays: [CGRect]?
    ) -> Bool {
        // Guard stored size before inset. A CGRect with width/height <= 8 would
        // produce a zero or negative size; minX/width can then be read via
        // standardized geometry and look like a valid rectangle.
        guard frame.width > captureSeamTolerance, frame.height > captureSeamTolerance else {
            return false
        }
        let insetFrame = insetRect(frame, by: captureSeamTolerance / 2)
        guard isUsable(insetFrame) else { return false }
        // Subtract the union of physical displays before testing visibility.
        // Off-screen pieces are holes, just like opaque occluders. Expanding
        // those holes instead of insetting each display preserves continuous
        // visible regions across adjacent displays, without filling their gaps.
        var offscreen: [CGRect] = displays == nil ? [] : [frame]
        for display in displays ?? [] {
            offscreen = offscreen.flatMap { subtract($0, minus: display) }
        }
        let expanded = (occluders + offscreen).map { outsetRect($0, by: captureSeamTolerance / 2) }
        return remainingVisibleArea(of: insetFrame, subtracting: expanded) > 0
    }

    private static func insetRect(_ frame: CGRect, by amount: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX + amount,
            y: frame.minY + amount,
            width: frame.width - amount * 2,
            height: frame.height - amount * 2
        )
    }

    private static func outsetRect(_ frame: CGRect, by amount: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX - amount,
            y: frame.minY - amount,
            width: frame.width + amount * 2,
            height: frame.height + amount * 2
        )
    }

    private static func remainingVisibleArea(of frame: CGRect, subtracting occluders: [CGRect]) -> CGFloat {
        var uncovered: [CGRect] = [frame]
        for occluder in occluders {
            guard isUsable(occluder) else { continue }
            uncovered = uncovered.flatMap { subtract($0, minus: occluder) }
            if uncovered.isEmpty { return 0 }
        }
        return uncovered.reduce(0) { $0 + $1.width * $1.height }
    }

    private static func subtract(_ rect: CGRect, minus hole: CGRect) -> [CGRect] {
        let clip = rect.intersection(hole)
        guard !clip.isNull, !clip.isInfinite, clip.width > 0, clip.height > 0 else { return [rect] }
        var pieces: [CGRect] = []
        if clip.minX > rect.minX {
            pieces.append(CGRect(x: rect.minX, y: rect.minY, width: clip.minX - rect.minX, height: rect.height))
        }
        if clip.maxX < rect.maxX {
            pieces.append(CGRect(x: clip.maxX, y: rect.minY, width: rect.maxX - clip.maxX, height: rect.height))
        }
        if clip.minY > rect.minY {
            pieces.append(CGRect(x: clip.minX, y: rect.minY, width: clip.width, height: clip.minY - rect.minY))
        }
        if clip.maxY < rect.maxY {
            pieces.append(CGRect(x: clip.minX, y: clip.maxY, width: clip.width, height: rect.maxY - clip.maxY))
        }
        return pieces.filter(isUsable)
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        !frame.isNull
            && !frame.isInfinite
            && frame.minX.isFinite
            && frame.minY.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}
