import CoreGraphics
import Foundation

public enum ProfilePlan {
    public struct SectionPlan: Equatable, Sendable {
        public var displayID: DisplayIdentity.ID
        public var layoutID: Layout.ID
        public var placements: [WindowOrganizePlacement]
        public var zoneIDByIdentity: [WindowIdentity: UUID]

        public init(
            displayID: DisplayIdentity.ID,
            layoutID: Layout.ID,
            placements: [WindowOrganizePlacement],
            zoneIDByIdentity: [WindowIdentity: UUID]
        ) {
            self.displayID = displayID
            self.layoutID = layoutID
            self.placements = placements
            self.zoneIDByIdentity = zoneIDByIdentity
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var sections: [SectionPlan]
        public var missingBundleIDs: [String]
        public var staleRules: [AppPlacementRule]
        public var skippedDisplayIDs: [DisplayIdentity.ID]

        public init(
            sections: [SectionPlan],
            missingBundleIDs: [String],
            staleRules: [AppPlacementRule],
            skippedDisplayIDs: [DisplayIdentity.ID]
        ) {
            self.sections = sections
            self.missingBundleIDs = missingBundleIDs
            self.staleRules = staleRules
            self.skippedDisplayIDs = skippedDisplayIDs
        }
    }

    public static func make(
        profile: WorkspaceProfile,
        zonesBySection: [DisplayIdentity.ID: [ResolvedZone]],
        candidates: [ProfileCapture.WindowSample]
    ) -> Outcome {
        var queues: [String: [ProfileCapture.WindowSample]] = [:]
        for candidate in candidates {
            guard let bundleID = candidate.identity.bundleID, !bundleID.isEmpty else { continue }
            queues[bundleID, default: []].append(candidate)
        }

        var sections: [SectionPlan] = []
        var missing: [String] = []
        var stale: [AppPlacementRule] = []
        var skipped: [DisplayIdentity.ID] = []

        for section in profile.sections {
            let displayID = section.space.displayID
            guard let zones = zonesBySection[displayID] else {
                if !skipped.contains(displayID) { skipped.append(displayID) }
                continue
            }
            var placements: [WindowOrganizePlacement] = []
            var zoneIDs: [WindowIdentity: UUID] = [:]
            for rule in ProfileCapture.frontmostRulesPerZone(section.rules) {
                guard let zone = zones.first(where: { $0.zoneID == rule.zoneID })
                    ?? zones.first(where: { $0.number == rule.zoneNumber })
                else {
                    stale.append(rule)
                    continue
                }
                guard var queue = queues[rule.bundleID], !queue.isEmpty else {
                    if !missing.contains(rule.bundleID) { missing.append(rule.bundleID) }
                    continue
                }
                let sample = queue.removeFirst()
                queues[rule.bundleID] = queue
                placements.append(WindowOrganizePlacement(identity: sample.identity, targetFrameAX: zone.frameAX))
                zoneIDs[sample.identity] = zone.zoneID
            }
            if !placements.isEmpty {
                sections.append(
                    SectionPlan(
                        displayID: displayID,
                        layoutID: section.layoutID,
                        placements: placements,
                        zoneIDByIdentity: zoneIDs
                    )
                )
            }
        }

        return Outcome(
            sections: sections,
            missingBundleIDs: missing,
            staleRules: stale,
            skippedDisplayIDs: skipped
        )
    }
}
