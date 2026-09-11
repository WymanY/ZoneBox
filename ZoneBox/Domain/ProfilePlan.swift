import CoreGraphics
import Foundation

public enum ProfilePlan {
    public struct SectionPlan: Equatable, Sendable {
        public var displayID: DisplayIdentity.ID
        public var workAreaAX: CGRect
        public var placements: [WindowOrganizePlacement]
        /// Every saved frame on this display, including ones whose app has no
        /// window yet, so the confirmation flash shows the whole arrangement.
        public var targetFramesAX: [CGRect]

        public init(
            displayID: DisplayIdentity.ID,
            workAreaAX: CGRect,
            placements: [WindowOrganizePlacement],
            targetFramesAX: [CGRect]
        ) {
            self.displayID = displayID
            self.workAreaAX = workAreaAX
            self.placements = placements
            self.targetFramesAX = targetFramesAX
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var sections: [SectionPlan]
        public var missingBundleIDs: [String]
        public var skippedDisplayIDs: [DisplayIdentity.ID]

        public init(
            sections: [SectionPlan],
            missingBundleIDs: [String],
            skippedDisplayIDs: [DisplayIdentity.ID]
        ) {
            self.sections = sections
            self.missingBundleIDs = missingBundleIDs
            self.skippedDisplayIDs = skippedDisplayIDs
        }
    }

    public enum AppOpenAction: Equatable, Sendable {
        case none
        case launch
        case reopen
    }

    /// A saved app with no usable window still needs an open action.
    /// If the process is already running, activate its existing windows instead of
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

    /// Bundle IDs from sections whose display is currently available.
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

    /// Native full screen is the only leftover window restore must not yank
    /// the user toward. Minimized, hidden, and ordinary AX windows are claimed
    /// by activating the already-running app.
    public static func isUnreachableLeftoverWindow(
        isMinimized: Bool,
        isHiddenApp: Bool,
        isFullscreen: Bool
    ) -> Bool {
        isFullscreen
    }

    /// Saved frames are relative to each display's work area, so a section
    /// restores proportionally when the same display comes back at another
    /// resolution and exactly when it does not.
    public static func make(
        profile: WorkspaceProfile,
        workAreasBySection: [DisplayIdentity.ID: CGRect],
        candidates: [ProfileCapture.WindowSample]
    ) -> Outcome {
        var queues: [String: [ProfileCapture.WindowSample]] = [:]
        for candidate in candidates {
            guard let bundleID = candidate.identity.bundleID, !bundleID.isEmpty else { continue }
            queues[bundleID, default: []].append(candidate)
        }

        var sections: [SectionPlan] = []
        var missing: [String] = []
        var skipped: [DisplayIdentity.ID] = []

        for section in profile.sections {
            let displayID = section.space.displayID
            guard let workAreaAX = workAreasBySection[displayID] else {
                if !skipped.contains(displayID) { skipped.append(displayID) }
                continue
            }
            var placements: [WindowOrganizePlacement] = []
            var targets: [CGRect] = []
            for rule in section.rules {
                let target = rule.frame.denormalize(in: workAreaAX)
                targets.append(target)
                guard var queue = queues[rule.bundleID], !queue.isEmpty else {
                    if !missing.contains(rule.bundleID) { missing.append(rule.bundleID) }
                    continue
                }
                let sample = queue.remove(at: preferredIndex(in: queue, target: target, workAreaAX: workAreaAX))
                queues[rule.bundleID] = queue
                placements.append(WindowOrganizePlacement(identity: sample.identity, targetFrameAX: target))
            }
            sections.append(
                SectionPlan(
                    displayID: displayID,
                    workAreaAX: workAreaAX,
                    placements: placements,
                    targetFramesAX: targets
                )
            )
        }

        return Outcome(
            sections: sections,
            missingBundleIDs: missing,
            skippedDisplayIDs: skipped
        )
    }

    /// Same-app windows are consumed front-to-back, but a window that already
    /// sits at the rule's frame keeps it, and a window on the section's display
    /// beats one on another display. Otherwise two browser windows swap places
    /// on every restore even though both were exactly where the profile wanted.
    static func preferredIndex(
        in queue: [ProfileCapture.WindowSample],
        target: CGRect,
        workAreaAX: CGRect
    ) -> Int {
        var bestIndex = 0
        var bestScore = -1
        for (index, sample) in queue.enumerated() {
            let score: Int
            if ProfileCapture.occupies(sample.frameAX, zone: target) {
                score = 2
            } else if intersectsInterior(sample.frameAX, workAreaAX) {
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
