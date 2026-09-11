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
                frame: NormalizedRect.normalize(sample.frameAX, in: workAreaAX)
            )
        }
    }

    /// WindowServer returns on-screen windows front-to-back, including windows
    /// behind other windows. A workspace snapshot only keeps windows whose full
    /// rectangular surface is not covered by an opaque window in front.
    public static func visibleWindowIdentities(
        frontToBack windows: [VisibilitySample]
    ) -> Set<WindowIdentity> {
        var opaqueFrames: [CGRect] = []
        var visible = Set<WindowIdentity>()
        for window in windows {
            let frame = window.frameAX.standardized
            guard window.opacity > 0.01, isUsable(frame) else { continue }
            if isFullyVisible(frame, behind: opaqueFrames) {
                visible.insert(window.identity)
            }
            if window.isOpaqueOccluder {
                opaqueFrames.append(frame)
            }
        }
        return visible
    }

    /// Whether a window currently counts as sitting at `target`: either placed
    /// there within tolerance or covering most of it.
    public static func occupies(_ frame: CGRect, zone: CGRect) -> Bool {
        ZoneOccupancy.occupies(frame, zone: zone)
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
    /// A window is hidden only when a front opaque window covers a meaningful
    /// fraction of its surface.
    private static let occlusionCoverage: CGFloat = 0.25

    private static func isFullyVisible(_ frame: CGRect, behind occluders: [CGRect]) -> Bool {
        let area = max(frame.width * frame.height, 1)
        return !occluders.contains { occluder in
            guard isUsable(occluder) else { return false }
            let overlap = frame.intersection(occluder)
            guard !overlap.isNull, !overlap.isInfinite else { return false }
            return (overlap.width * overlap.height) / area >= occlusionCoverage
        }
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
