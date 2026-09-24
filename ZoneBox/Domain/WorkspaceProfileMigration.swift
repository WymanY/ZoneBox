import Foundation

/// Workspaces saved before frame capture stored bundleID-to-zone rules plus
/// the layout they pointed at. store.json is decoded through these lenient
/// records so a later launch can still read the original zone mapping.
///
/// Geometry is resolved only when a layout, work area, and gutter are all
/// available. Until then the zone fields stay on the profile and are written
/// back unchanged, so a missing layout or an early persist cannot bake the
/// wrong frames or drop a rule the old app could still restore.
public enum WorkspaceProfileMigration {
    public struct StoredRule: Codable, Equatable, Sendable {
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

        private enum CodingKeys: String, CodingKey {
            case bundleID
            case frame
            case zoneID
            case zoneNumber
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(bundleID, forKey: .bundleID)
            try container.encodeIfPresent(frame, forKey: .frame)
            try container.encodeIfPresent(zoneID, forKey: .zoneID)
            try container.encodeIfPresent(zoneNumber, forKey: .zoneNumber)
        }
    }

    public struct StoredSection: Codable, Equatable, Sendable {
        public var space: SpaceKey
        public var layoutID: Layout.ID?
        public var rules: [StoredRule]

        public init(space: SpaceKey, layoutID: Layout.ID? = nil, rules: [StoredRule]) {
            self.space = space
            self.layoutID = layoutID
            self.rules = rules
        }

        private enum CodingKeys: String, CodingKey {
            case space
            case layoutID
            case rules
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(space, forKey: .space)
            try container.encodeIfPresent(layoutID, forKey: .layoutID)
            try container.encode(rules, forKey: .rules)
        }
    }

    public struct StoredProfile: Codable, Equatable, Sendable {
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

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case sections
            case launchMissingApps
            case createdAt
            case updatedAt
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(sections, forKey: .sections)
            try container.encodeIfPresent(launchMissingApps, forKey: .launchMissingApps)
            try container.encodeIfPresent(createdAt, forKey: .createdAt)
            try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        }
    }

    /// Decode-time mapping. Zone-only rules keep their zone fields; frames are
    /// filled later by resolving(_:layouts:workAreasByDisplay:gutter:).
    public static func profiles(from stored: [StoredProfile], layouts: [Layout]) -> [WorkspaceProfile] {
        let layoutsByID = Dictionary(uniqueKeysWithValues: layouts.map { ($0.id, $0) })
        return stored.map { profile in
            let now = Date()
            return WorkspaceProfile(
                id: profile.id,
                name: profile.name,
                sections: profile.sections.compactMap { section in
                    let layout = section.layoutID.flatMap { layoutsByID[$0] }
                    let rules = migratedRules(section.rules, layout: layout)
                    guard !rules.isEmpty else { return nil }
                    return ProfileSection(space: section.space, layoutID: section.layoutID, rules: rules)
                },
                launchMissingApps: profile.launchMissingApps ?? true,
                createdAt: profile.createdAt ?? now,
                updatedAt: profile.updatedAt ?? profile.createdAt ?? now
            )
        }
    }

    public static func stored(from profiles: [WorkspaceProfile]) -> [StoredProfile] {
        profiles.map { profile in
            StoredProfile(
                id: profile.id,
                name: profile.name,
                sections: profile.sections.map { section in
                    StoredSection(
                        space: section.space,
                        layoutID: section.layoutID,
                        rules: section.rules.map(storedRule(from:))
                    )
                },
                launchMissingApps: profile.launchMissingApps,
                createdAt: profile.createdAt,
                updatedAt: profile.updatedAt
            )
        }
    }

    /// Fill frames for legacy zone rules when the live work area and gutter
    /// are known. Zone fields stay so the next save can still write the old
    /// mapping. Captured frame-only rules are left alone.
    public static func resolving(
        _ profile: WorkspaceProfile,
        layouts: [Layout],
        workAreasByDisplay: [DisplayIdentity.ID: CGRect],
        gutter: CGFloat
    ) -> WorkspaceProfile {
        let layoutsByID = Dictionary(uniqueKeysWithValues: layouts.map { ($0.id, $0) })
        var copy = profile
        copy.sections = profile.sections.map { section in
            var section = section
            let layout = section.layoutID.flatMap { layoutsByID[$0] }
            let workAreaAX = workAreasByDisplay[section.space.displayID]
            section.rules = section.rules.map { rule in
                var rule = rule
                rule.frame = resolvedFrame(rule, layout: layout, workAreaAX: workAreaAX, gutter: gutter)
                return rule
            }
            return section
        }
        return copy
    }

    public static func resolving(
        _ profiles: [WorkspaceProfile],
        layouts: [Layout],
        workAreasByDisplay: [DisplayIdentity.ID: CGRect],
        gutter: CGFloat
    ) -> [WorkspaceProfile] {
        profiles.map {
            resolving($0, layouts: layouts, workAreasByDisplay: workAreasByDisplay, gutter: gutter)
        }
    }

    /// Same pane-first order legacy restore used, then one rule per pane so
    /// duplicate-zone captures keep the frontmost app.
    static func migratedRules(_ stored: [StoredRule], layout: Layout?) -> [AppPlacementRule] {
        var seenPanes = Set<UUID>()
        var rules: [AppPlacementRule] = []
        for stored in stored {
            guard !stored.bundleID.isEmpty else { continue }
            if !isLegacyZoneRule(stored) {
                guard let frame = stored.frame else { continue }
                rules.append(AppPlacementRule(bundleID: stored.bundleID, frame: frame))
                continue
            }
            if let paneID = paneID(for: stored, layout: layout) {
                guard seenPanes.insert(paneID).inserted else { continue }
                rules.append(
                    AppPlacementRule(
                        bundleID: stored.bundleID,
                        frame: stored.frame,
                        zoneID: stored.zoneID ?? paneID,
                        zoneNumber: stored.zoneNumber ?? layout?.zones.first(where: { $0.id == paneID })?.number
                    )
                )
                continue
            }
            rules.append(
                AppPlacementRule(
                    bundleID: stored.bundleID,
                    frame: stored.frame,
                    zoneID: stored.zoneID,
                    zoneNumber: stored.zoneNumber
                )
            )
        }
        return rules
    }

    static func resolvedFrame(
        _ rule: AppPlacementRule,
        layout: Layout?,
        workAreaAX: CGRect?,
        gutter: CGFloat
    ) -> NormalizedRect? {
        if !isLegacyZoneRule(rule) {
            return rule.frame
        }
        guard let layout,
              let workAreaAX,
              workAreaAX.width > 0,
              workAreaAX.height > 0,
              let zones = try? resolveLayout(layout, workAreaAX: workAreaAX, gutter: gutter)
        else {
            return rule.frame
        }
        let zone = zones.first(where: { $0.zoneID == rule.zoneID })
            ?? zones.first(where: { $0.number == rule.zoneNumber })
        guard let zone else { return rule.frame }
        return NormalizedRect.normalize(zone.frameAX, in: workAreaAX)
    }

    static func paneID(for stored: StoredRule, layout: Layout?) -> UUID? {
        guard let layout else { return nil }
        if let zoneID = stored.zoneID, layout.zones.contains(where: { $0.id == zoneID }) {
            return zoneID
        }
        if let number = stored.zoneNumber {
            return layout.zones.first(where: { $0.number == number })?.id
        }
        return nil
    }

    static func isLegacyZoneRule(_ rule: StoredRule) -> Bool {
        rule.zoneID != nil || rule.zoneNumber != nil
    }

    static func isLegacyZoneRule(_ rule: AppPlacementRule) -> Bool {
        rule.zoneID != nil || rule.zoneNumber != nil
    }

    static func storedRule(from rule: AppPlacementRule) -> StoredRule {
        if isLegacyZoneRule(rule) {
            return StoredRule(
                bundleID: rule.bundleID,
                frame: nil,
                zoneID: rule.zoneID,
                zoneNumber: rule.zoneNumber
            )
        }
        return StoredRule(bundleID: rule.bundleID, frame: rule.frame)
    }
}
