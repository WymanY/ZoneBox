import CoreGraphics
import Foundation

/// One captured window: the app that owned it and where it sat, relative to
/// its display's work area. Restore writes that frame back, so a workspace
/// reproduces the desk as it was captured rather than the zones of whichever
/// layout happened to be active.
public struct AppPlacementRule: Codable, Hashable, Sendable {
    public var bundleID: String
    public var frame: NormalizedRect

    public init(bundleID: String, frame: NormalizedRect) {
        self.bundleID = bundleID
        self.frame = frame
    }

    /// Two captures of the same desk differ by a few points once a window has
    /// been nudged. Frames within this fraction of the work area count as the
    /// same place.
    public static let matchTolerance: Double = 0.02

    public func matches(_ other: AppPlacementRule, tolerance: Double = matchTolerance) -> Bool {
        bundleID == other.bundleID && frame.isClose(to: other.frame, tolerance: tolerance)
    }

    /// Left-to-right, then top-to-bottom, so lists and generated names read the
    /// way the desk looks. Rules are stored front-to-back for restore.
    public static func readingOrder(_ rules: [AppPlacementRule]) -> [AppPlacementRule] {
        func bucket(_ value: Double) -> Int { Int((value * 50).rounded()) }
        return rules.enumerated().sorted { lhs, rhs in
            let left = (bucket(lhs.element.frame.x), bucket(lhs.element.frame.y), lhs.element.bundleID, lhs.offset)
            let right = (bucket(rhs.element.frame.x), bucket(rhs.element.frame.y), rhs.element.bundleID, rhs.offset)
            return left < right
        }.map(\.element)
    }
}

public struct ProfileSection: Codable, Hashable, Sendable {
    public var space: SpaceKey
    /// Captured windows front-to-back.
    public var rules: [AppPlacementRule]

    public init(space: SpaceKey, rules: [AppPlacementRule]) {
        self.space = space
        self.rules = rules
    }
}

public struct WorkspaceProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sections: [ProfileSection]
    public var launchMissingApps: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        sections: [ProfileSection],
        launchMissingApps: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sections = sections
        self.launchMissingApps = launchMissingApps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var applicationCount: Int {
        Set(sections.flatMap(\.rules).map(\.bundleID)).count
    }

    /// Join unique app names with "+" so the save sheet can offer ChatGPT+Notes
    /// instead of a generic "Workspace". Callers pass names in reading order.
    public static func suggestedName(appNames: [String], fallback: String) -> String {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in appNames {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(name)
        }
        return ordered.isEmpty ? fallback : ordered.joined(separator: "+")
    }

    /// Arrangement equality ignores rule order and section order and tolerates
    /// small frame drift. Empty profiles never match, including against another
    /// empty profile.
    public func hasSameArrangement(as other: WorkspaceProfile) -> Bool {
        Self.sameArrangement(sections, other.sections)
    }

    public func hasSameArrangement(as sections: [ProfileSection]) -> Bool {
        Self.sameArrangement(self.sections, sections)
    }

    public static func sameArrangement(_ lhs: [ProfileSection], _ rhs: [ProfileSection]) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty, lhs.count == rhs.count else { return false }
        let left = lhs.sorted { $0.space.displayID.uuidString < $1.space.displayID.uuidString }
        let right = rhs.sorted { $0.space.displayID.uuidString < $1.space.displayID.uuidString }
        return zip(left, right).allSatisfy { lhs, rhs in
            lhs.space.displayID == rhs.space.displayID && sameRules(lhs.rules, rhs.rules)
        }
    }

    static func sameRules(_ lhs: [AppPlacementRule], _ rhs: [AppPlacementRule]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var unmatched = rhs
        for rule in lhs {
            guard let index = unmatched.firstIndex(where: { rule.matches($0) }) else { return false }
            unmatched.remove(at: index)
        }
        return true
    }
}

public struct WorkspaceApplyFeedback: Equatable, Sendable {
    public var titleKey: L10nKey
    public var detail: String
    public var isError: Bool

    public init(titleKey: L10nKey, detail: String, isError: Bool) {
        self.titleKey = titleKey
        self.detail = detail
        self.isError = isError
    }

    public static func make(
        moved: [WindowIdentity],
        issues: [WindowOrganizeIssue],
        skipped: [WindowIdentity],
        missingCount: Int,
        launchingCount: Int = 0,
        disconnectedCount: Int,
        applicationName: (WindowIdentity) -> String,
        language: AppLanguage = LanguageCenter.language
    ) -> WorkspaceApplyFeedback {
        let movedSet = Set(moved)
        let constrained = issues.filter {
            $0.behavior == .sizeConstrained && movedSet.contains($0.identity)
        }
        let constrainedSet = Set(constrained.map(\.identity))
        let fullyPlacedCount = movedSet.subtracting(constrainedSet).count

        var failedSet = Set(skipped)
        for issue in issues where !constrainedSet.contains(issue.identity) {
            failedSet.insert(issue.identity)
        }
        failedSet.subtract(movedSet)

        var parts: [String] = []
        if fullyPlacedCount > 0 {
            parts.append(
                String(
                    format: L10n.text(.workspaceMovedDetail, language: language),
                    locale: language.locale,
                    fullyPlacedCount
                )
            )
        }

        var namedApplications = Set<String>()
        for issue in constrained {
            let name = applicationName(issue.identity)
            guard namedApplications.insert(name).inserted else { continue }
            parts.append(L10n.workspaceSizeConstrained(name, language: language))
        }

        if missingCount > 0 {
            parts.append(
                String(
                    format: L10n.text(.workspaceMissingDetail, language: language),
                    locale: language.locale,
                    missingCount
                )
            )
        }
        if disconnectedCount > 0 {
            parts.append(
                String(
                    format: L10n.text(.workspaceDisplaysSkippedDetail, language: language),
                    locale: language.locale,
                    disconnectedCount
                )
            )
        }
        if !failedSet.isEmpty {
            parts.append(
                String(
                    format: L10n.text(.workspaceWindowsSkippedDetail, language: language),
                    locale: language.locale,
                    failedSet.count
                )
            )
        }

        let isPartial = !constrainedSet.isEmpty
            || !failedSet.isEmpty
            || missingCount > 0
            || disconnectedCount > 0
        return WorkspaceApplyFeedback(
            titleKey: isPartial ? .workspaceApplyPartialTitle : .workspaceAppliedTitle,
            detail: parts.joined(separator: " "),
            isError: movedSet.isEmpty
        )
    }
}
