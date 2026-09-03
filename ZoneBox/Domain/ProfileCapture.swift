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

    public static func rules(
        windows: [WindowSample],
        zones: [ResolvedZone]
    ) -> [AppPlacementRule] {
        var used = Set<WindowIdentity>()
        return zones.sorted { lhs, rhs in
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.zoneID.uuidString < rhs.zoneID.uuidString
        }.compactMap { zone in
            guard let sample = windows.first(where: { candidate in
                guard !used.contains(candidate.identity),
                      let bundleID = candidate.identity.bundleID, !bundleID.isEmpty
                else { return false }
                return occupies(candidate.frameAX, zone: zone.frameAX)
            }), let bundleID = sample.identity.bundleID else { return nil }
            used.insert(sample.identity)
            return AppPlacementRule(bundleID: bundleID, zoneID: zone.zoneID, zoneNumber: zone.number)
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

    /// Keeps the frontmost captured assignment when older profile data contains
    /// more than one application for the same zone. Such duplicates were created
    /// when a partly exposed background window was mistaken for foreground
    /// content and would otherwise be restored on top of the intended window.
    public static func frontmostRulesPerZone(_ rules: [AppPlacementRule]) -> [AppPlacementRule] {
        var zoneIDs = Set<UUID>()
        var zoneNumbers = Set<Int>()
        return rules.filter { rule in
            guard !zoneIDs.contains(rule.zoneID), !zoneNumbers.contains(rule.zoneNumber) else {
                return false
            }
            zoneIDs.insert(rule.zoneID)
            zoneNumbers.insert(rule.zoneNumber)
            return true
        }
    }

    private static func occupies(_ frame: CGRect, zone: CGRect) -> Bool {
        WindowOrganize.didApply(frame, to: zone, sizeTolerance: 28, originTolerance: 28)
            || fills(frame, zone: zone)
    }

    /// A window owns a zone only when it still covers most of that zone.
    /// Background full-screen windows can fill a zone too, but each zone is
    /// assigned to the frontmost occupant so ChatGPT+Notes beat aDrive behind them.
    private static func fills(_ frame: CGRect, zone: CGRect) -> Bool {
        let intersection = frame.intersection(zone)
        guard !intersection.isNull, !intersection.isInfinite else { return false }
        let overlap = max(intersection.width, 0) * max(intersection.height, 0)
        let zoneArea = max(zone.width * zone.height, 1)
        return overlap / zoneArea >= 0.62
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
