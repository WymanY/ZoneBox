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
        var occupiedZoneIDs = Set<UUID>()
        var occupiedZoneNumbers = Set<Int>()
        let indexed = windows.enumerated().compactMap { index, sample -> (Int, ResolvedZone, String)? in
            guard let bundleID = sample.identity.bundleID, !bundleID.isEmpty,
                  let zone = matchingZone(for: sample.frameAX, zones: zones),
                  !occupiedZoneIDs.contains(zone.zoneID),
                  !occupiedZoneNumbers.contains(zone.number)
            else { return nil }
            occupiedZoneIDs.insert(zone.zoneID)
            occupiedZoneNumbers.insert(zone.number)
            return (index, zone, bundleID)
        }
        return indexed.sorted { lhs, rhs in
            if lhs.1.number != rhs.1.number { return lhs.1.number < rhs.1.number }
            return lhs.0 < rhs.0
        }.map { _, zone, bundleID in
            AppPlacementRule(bundleID: bundleID, zoneID: zone.zoneID, zoneNumber: zone.number)
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

    private static func matchingZone(for frame: CGRect, zones: [ResolvedZone]) -> ResolvedZone? {
        if let exact = zones.first(where: {
            WindowOrganize.didApply(frame, to: $0.frameAX, sizeTolerance: 28, originTolerance: 28)
        }) {
            return exact
        }
        let area = max(frame.width, 0) * max(frame.height, 0)
        guard area > 0 else { return nil }
        return zones.enumerated().compactMap { index, zone -> (Int, ResolvedZone, CGFloat)? in
            let intersection = frame.intersection(zone.frameAX)
            guard !intersection.isNull else { return nil }
            let ratio = max(intersection.width, 0) * max(intersection.height, 0) / area
            guard ratio >= 0.5 else { return nil }
            return (index, zone, ratio)
        }.max { lhs, rhs in
            if abs(lhs.2 - rhs.2) > 0.000_001 { return lhs.2 < rhs.2 }
            return lhs.0 > rhs.0
        }?.1
    }

    private static func isFullyVisible(_ frame: CGRect, behind occluders: [CGRect]) -> Bool {
        !occluders.contains { occluder in
            guard isUsable(occluder) else { return false }
            let overlap = frame.intersection(occluder)
            return !overlap.isNull && overlap.width * overlap.height > 0.5
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
