import Foundation

public struct AppPlacementRule: Codable, Hashable, Sendable {
    public var bundleID: String
    public var zoneID: UUID
    public var zoneNumber: Int

    public init(bundleID: String, zoneID: UUID, zoneNumber: Int) {
        self.bundleID = bundleID
        self.zoneID = zoneID
        self.zoneNumber = zoneNumber
    }
}

public struct ProfileSection: Codable, Hashable, Sendable {
    public var space: SpaceKey
    public var layoutID: Layout.ID
    public var rules: [AppPlacementRule]

    public init(space: SpaceKey, layoutID: Layout.ID, rules: [AppPlacementRule]) {
        self.space = space
        self.layoutID = layoutID
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
        staleCount: Int,
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
        if staleCount > 0 {
            parts.append(
                String(
                    format: L10n.text(.workspaceStaleDetail, language: language),
                    locale: language.locale,
                    staleCount
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
            || staleCount > 0
            || disconnectedCount > 0
        return WorkspaceApplyFeedback(
            titleKey: isPartial ? .workspaceApplyPartialTitle : .workspaceAppliedTitle,
            detail: parts.joined(separator: " "),
            isError: movedSet.isEmpty
        )
    }
}
