import Foundation

/// Workspaces saved before frame capture stored `bundleID → zone` rules plus
/// the layout they pointed at. store.json is decoded through these lenient
/// records so each legacy zone becomes the frame it occupied in that layout
/// and old workspaces keep restoring to the same places.
public enum WorkspaceProfileMigration {
    public struct StoredRule: Decodable, Equatable, Sendable {
        public var bundleID: String
        public var frame: NormalizedRect?
        public var zoneID: UUID?
        public var zoneNumber: Int?

        public init(bundleID: String, frame: NormalizedRect? = nil, zoneID: UUID? = nil, zoneNumber: Int? = nil) {
            self.bundleID = bundleID
            self.frame = frame
            self.zoneID = zoneID
            self.zoneNumber = zoneNumber
        }
    }

    public struct StoredSection: Decodable, Equatable, Sendable {
        public var space: SpaceKey
        public var layoutID: Layout.ID?
        public var rules: [StoredRule]

        public init(space: SpaceKey, layoutID: Layout.ID? = nil, rules: [StoredRule]) {
            self.space = space
            self.layoutID = layoutID
            self.rules = rules
        }
    }

    public struct StoredProfile: Decodable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var sections: [StoredSection]
        public var launchMissingApps: Bool?
        public var createdAt: Date?
        public var updatedAt: Date?

        public init(
            id: UUID,
            name: String,
            sections: [StoredSection],
            launchMissingApps: Bool? = nil,
            createdAt: Date? = nil,
            updatedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.sections = sections
            self.launchMissingApps = launchMissingApps
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    public static func profiles(from stored: [StoredProfile], layouts: [Layout]) -> [WorkspaceProfile] {
        var panesByLayout: [Layout.ID: [(id: UUID, number: Int, rect: NormalizedRect)]] = [:]
        for layout in layouts {
            panesByLayout[layout.id] = LayoutTemplates.thumbnailPanes(for: layout)
        }
        return stored.map { profile in
            let now = Date()
            return WorkspaceProfile(
                id: profile.id,
                name: profile.name,
                sections: profile.sections.compactMap { section in
                    let rules = section.rules.compactMap { rule in
                        Self.rule(rule, panes: section.layoutID.flatMap { panesByLayout[$0] } ?? [])
                    }
                    guard !rules.isEmpty else { return nil }
                    return ProfileSection(space: section.space, rules: rules)
                },
                launchMissingApps: profile.launchMissingApps ?? true,
                createdAt: profile.createdAt ?? now,
                updatedAt: profile.updatedAt ?? profile.createdAt ?? now
            )
        }
    }

    /// Same resolution order legacy restore used: zoneID first, then number.
    /// A rule whose zone no longer exists has no place to go and is dropped.
    static func rule(
        _ stored: StoredRule,
        panes: [(id: UUID, number: Int, rect: NormalizedRect)]
    ) -> AppPlacementRule? {
        guard !stored.bundleID.isEmpty else { return nil }
        if let frame = stored.frame {
            return AppPlacementRule(bundleID: stored.bundleID, frame: frame)
        }
        let pane = panes.first(where: { $0.id == stored.zoneID })
            ?? panes.first(where: { $0.number == stored.zoneNumber })
        guard let pane else { return nil }
        return AppPlacementRule(bundleID: stored.bundleID, frame: pane.rect)
    }
}
