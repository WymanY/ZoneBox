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

    public enum AppOpenAction: Equatable, Sendable {
        case none
        case launch
        case reopen
    }

    /// A saved app with no usable window still needs an open action.
    /// If the process is already running, reopen its default window instead of
    /// treating the running app as already restored.
    public static func openAction(
        bundleID: String,
        missingBundleIDs: [String],
        runningBundleIDs: Set<String>,
        launchMissingApps: Bool
    ) -> AppOpenAction {
        guard launchMissingApps, missingBundleIDs.contains(bundleID) else { return .none }
        return runningBundleIDs.contains(bundleID) ? .reopen : .launch
    }

    /// Bundle IDs from sections whose display and layout are currently available.
    /// Skipped (disconnected) sections must not unhide or reopen their apps.
    public static func restorableBundleIDs(
        profile: WorkspaceProfile,
        availableDisplayIDs: Set<DisplayIdentity.ID>
    ) -> Set<String> {
        Set(
            profile.sections
                .filter { availableDisplayIDs.contains($0.space.displayID) }
                .flatMap(\.rules)
                .map(\.bundleID)
        )
    }

    /// Leftover AX windows that are neither minimized nor hidden live on another
    /// Space or in native full screen. Extra saved placements for that app must
    /// not reopen it.
    public static func isUnreachableLeftoverWindow(
        isMinimized: Bool,
        isHiddenApp: Bool,
        isFullscreen: Bool
    ) -> Bool {
        isFullscreen || !(isMinimized || isHiddenApp)
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
                let sample = queue.remove(at: preferredIndex(in: queue, zone: zone.frameAX, sectionZones: zones))
                queues[rule.bundleID] = queue
                placements.append(WindowOrganizePlacement(identity: sample.identity, targetFrameAX: zone.frameAX))
                zoneIDs[sample.identity] = zone.zoneID
            }
            sections.append(
                SectionPlan(
                    displayID: displayID,
                    layoutID: section.layoutID,
                    placements: placements,
                    zoneIDByIdentity: zoneIDs
                )
            )
        }

        return Outcome(
            sections: sections,
            missingBundleIDs: missing,
            staleRules: stale,
            skippedDisplayIDs: skipped
        )
    }

    /// Same-app windows are consumed front-to-back, but a window that already
    /// sits in the rule's zone keeps it, and a window on the section's display
    /// beats one on another display. Otherwise two browser windows swap places
    /// on every restore even though both were exactly where the profile wanted.
    static func preferredIndex(
        in queue: [ProfileCapture.WindowSample],
        zone: CGRect,
        sectionZones: [ResolvedZone]
    ) -> Int {
        var bestIndex = 0
        var bestScore = -1
        for (index, sample) in queue.enumerated() {
            let score: Int
            if ProfileCapture.occupies(sample.frameAX, zone: zone) {
                score = 2
            } else if sectionZones.contains(where: { intersectsInterior(sample.frameAX, $0.frameAX) }) {
                score = 1
            } else {
                score = 0
            }
            if score > bestScore {
                bestScore = score
                bestIndex = index
                if score == 2 { break }
            }
        }
        return bestIndex
    }

    private static func intersectsInterior(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = lhs.intersection(rhs)
        return !overlap.isNull && overlap.width > 0 && overlap.height > 0
    }
}
