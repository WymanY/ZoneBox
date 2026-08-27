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

    public init(
        schemaVersion: Int = 1,
        layouts: [Layout] = LayoutTemplates.all(),
        displays: [DisplayIdentity] = [],
        assignments: [LayoutAssignment] = []
    ) {
        self.schemaVersion = schemaVersion
        self.layouts = layouts
        self.displays = displays
        self.assignments = assignments
    }

    public func layout(for displayID: DisplayIdentity.ID) -> Layout? {
        let assigned = assignments.first { $0.space.displayID == displayID }?.layoutID
        if let assigned, let layout = layouts.first(where: { $0.id == assigned }) {
            return layout
        }
        return layouts.first
    }

    public mutating func assign(layoutID: Layout.ID, to displayID: DisplayIdentity.ID) {
        assignments.removeAll { $0.space.displayID == displayID }
        assignments.append(LayoutAssignment(space: SpaceKey(displayID: displayID), layoutID: layoutID))
    }

    public mutating func upsertAndAssign(_ layout: Layout, to displayID: DisplayIdentity.ID) {
        if let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[index] = layout
        } else {
            layouts.append(layout)
        }
        assign(layoutID: layout.id, to: displayID)
    }
}
