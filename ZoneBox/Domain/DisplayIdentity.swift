import Foundation

public struct DisplayIdentity: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var uuid: UUID?
    public var lastCGDisplayID: UInt32
    public var vendorNumber: UInt32
    public var productNumber: UInt32
    public var serialNumber: UInt32
    public var localizedName: String
    public var visibleWidth: Double
    public var visibleHeight: Double
    public var backingScale: Double

    public init(
        id: UUID = UUID(),
        uuid: UUID? = nil,
        lastCGDisplayID: UInt32 = 0,
        vendorNumber: UInt32 = 0,
        productNumber: UInt32 = 0,
        serialNumber: UInt32 = 0,
        localizedName: String,
        visibleWidth: Double,
        visibleHeight: Double,
        backingScale: Double
    ) {
        self.id = id
        self.uuid = uuid
        self.lastCGDisplayID = lastCGDisplayID
        self.vendorNumber = vendorNumber
        self.productNumber = productNumber
        self.serialNumber = serialNumber
        self.localizedName = localizedName
        self.visibleWidth = visibleWidth
        self.visibleHeight = visibleHeight
        self.backingScale = backingScale
    }

    public func score(against other: DisplayIdentity) -> Int {
        if let a = uuid, let b = other.uuid, a == b { return 100 }
        if vendorNumber == other.vendorNumber,
           productNumber == other.productNumber,
           serialNumber != 0,
           serialNumber == other.serialNumber {
            return 90
        }
        if vendorNumber == other.vendorNumber, productNumber == other.productNumber {
            return 70
        }
        if localizedName == other.localizedName,
           abs(visibleWidth - other.visibleWidth) <= 2,
           abs(visibleHeight - other.visibleHeight) <= 2 {
            return 55
        }
        if abs(visibleWidth - other.visibleWidth) <= 2,
           abs(visibleHeight - other.visibleHeight) <= 2,
           abs(backingScale - other.backingScale) < 0.01 {
            return 25
        }
        return 0
    }

    public static func bestMatch(
        probe: DisplayIdentity,
        candidates: [DisplayIdentity]
    ) -> (DisplayIdentity, Int)? {
        let scored = candidates.map { ($0, probe.score(against: $0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        guard let best = scored.first else { return nil }
        let close = scored.filter { best.1 - $0.1 <= 10 && $0.1 >= 55 }
        if close.count >= 2, best.1 >= 55 { return (best.0, best.1) }
        if best.1 >= 70 { return best }
        if best.1 >= 25 { return best }
        return nil
    }
}

public struct SpaceKey: Codable, Hashable, Sendable {
    public var displayID: DisplayIdentity.ID
    public var spaceUUID: String?

    public init(displayID: DisplayIdentity.ID, spaceUUID: String? = nil) {
        self.displayID = displayID
        self.spaceUUID = spaceUUID
    }
}

public struct LayoutAssignment: Codable, Hashable, Sendable {
    public var space: SpaceKey
    public var layoutID: Layout.ID

    public init(space: SpaceKey, layoutID: Layout.ID) {
        self.space = space
        self.layoutID = layoutID
    }
}

public struct StoreDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var layouts: [Layout]
    public var displays: [DisplayIdentity]
    public var assignments: [LayoutAssignment]
    /// Most-recently-used layout IDs, newest first. Missing from legacy store.json.
    public var recentLayoutIDs: [Layout.ID]
    public var profiles: [WorkspaceProfile]
    public var activeProfileID: WorkspaceProfile.ID?

    public init(
        schemaVersion: Int = 1,
        layouts: [Layout] = LayoutTemplates.all(),
        displays: [DisplayIdentity] = [],
        assignments: [LayoutAssignment] = [],
        recentLayoutIDs: [Layout.ID] = [],
        profiles: [WorkspaceProfile] = [],
        activeProfileID: WorkspaceProfile.ID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.layouts = layouts
        self.displays = displays
        self.assignments = assignments
        self.recentLayoutIDs = recentLayoutIDs
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        normalizeReferences()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case layouts
        case displays
        case assignments
        case recentLayoutIDs
        case profiles
        case activeProfileID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        layouts = try container.decode([Layout].self, forKey: .layouts)
        displays = try container.decode([DisplayIdentity].self, forKey: .displays)
        assignments = try container.decode([LayoutAssignment].self, forKey: .assignments)
        recentLayoutIDs = try container.decodeIfPresent([Layout.ID].self, forKey: .recentLayoutIDs) ?? []
        profiles = try container.decodeIfPresent([WorkspaceProfile].self, forKey: .profiles) ?? []
        activeProfileID = try container.decodeIfPresent(WorkspaceProfile.ID.self, forKey: .activeProfileID)
        normalizeReferences()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(layouts, forKey: .layouts)
        try container.encode(displays, forKey: .displays)
        try container.encode(assignments, forKey: .assignments)
        try container.encode(recentLayoutIDs, forKey: .recentLayoutIDs)
        try container.encode(profiles, forKey: .profiles)
        try container.encodeIfPresent(activeProfileID, forKey: .activeProfileID)
    }

    public func layout(for displayID: DisplayIdentity.ID) -> Layout? {
        let assigned = assignments.first { $0.space.displayID == displayID }?.layoutID
        if let assigned, let layout = layouts.first(where: { $0.id == assigned }) {
            return layout
        }
        return layouts.first
    }

    public static let recentLayoutLimit = 20

    /// Newest-first MRU, with the assigned layout forced to the front when present.
    public func orderedLayouts(assignedID: Layout.ID?) -> [Layout] {
        var ordered: [Layout] = []
        if let assignedID, let assigned = layouts.first(where: { $0.id == assignedID }) {
            ordered.append(assigned)
        }
        for id in recentLayoutIDs {
            guard !ordered.contains(where: { $0.id == id }),
                  let layout = layouts.first(where: { $0.id == id })
            else { continue }
            ordered.append(layout)
        }
        for layout in layouts where !ordered.contains(where: { $0.id == layout.id }) {
            ordered.append(layout)
        }
        return ordered
    }

    public mutating func markLayoutUsed(_ id: Layout.ID) {
        guard layouts.contains(where: { $0.id == id }) else { return }
        recentLayoutIDs.removeAll { $0 == id }
        recentLayoutIDs.insert(id, at: 0)
        if recentLayoutIDs.count > Self.recentLayoutLimit {
            recentLayoutIDs.removeLast(recentLayoutIDs.count - Self.recentLayoutLimit)
        }
    }

    public mutating func assign(layoutID: Layout.ID, to displayID: DisplayIdentity.ID) {
        assignments.removeAll { $0.space.displayID == displayID }
        assignments.append(LayoutAssignment(space: SpaceKey(displayID: displayID), layoutID: layoutID))
    }

    public mutating func upsertAndAssign(_ layout: Layout, to displayID: DisplayIdentity.ID) {
        if let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[index] = layout
        } else {
            layouts.insert(layout, at: 0)
        }
        assign(layoutID: layout.id, to: displayID)
    }

    /// Removes a saved layout. The last remaining layout is kept so snapping always
    /// has somewhere to go. Displays that pointed at the deleted layout fall back to
    /// the first layout still in the document.
    @discardableResult
    public mutating func deleteLayout(id: Layout.ID) -> Bool {
        guard layouts.count > 1,
              let index = layouts.firstIndex(where: { $0.id == id })
        else { return false }
        layouts.remove(at: index)
        guard let fallbackID = layouts.first?.id else { return false }
        for assignmentIndex in assignments.indices where assignments[assignmentIndex].layoutID == id {
            assignments[assignmentIndex].layoutID = fallbackID
        }
        recentLayoutIDs.removeAll { $0 == id }
        for profileIndex in profiles.indices {
            profiles[profileIndex].sections.removeAll { $0.layoutID == id }
        }
        profiles.removeAll { $0.sections.isEmpty }
        if let activeProfileID, !profiles.contains(where: { $0.id == activeProfileID }) {
            self.activeProfileID = nil
        }
        return true
    }

    public mutating func upsertProfile(_ profile: WorkspaceProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        normalizeReferences()
    }

    @discardableResult
    public mutating func deleteProfile(id: WorkspaceProfile.ID) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: index)
        if activeProfileID == id { activeProfileID = nil }
        return true
    }

    public mutating func normalizeReferences() {
        pruneRecentLayoutIDs()
        let knownLayouts = Set(layouts.map(\.id))
        var seenProfiles = Set<WorkspaceProfile.ID>()
        profiles = profiles.compactMap { profile in
            guard !seenProfiles.contains(profile.id) else { return nil }
            seenProfiles.insert(profile.id)
            var copy = profile
            copy.sections.removeAll { !knownLayouts.contains($0.layoutID) || $0.rules.isEmpty }
            return copy.sections.isEmpty ? nil : copy
        }
        if let activeProfileID, !profiles.contains(where: { $0.id == activeProfileID }) {
            self.activeProfileID = nil
        }
    }

    private mutating func pruneRecentLayoutIDs() {
        let known = Set(layouts.map(\.id))
        var seen = Set<Layout.ID>()
        recentLayoutIDs.removeAll { id in
            if !known.contains(id) || seen.contains(id) { return true }
            seen.insert(id)
            return false
        }
    }
}
