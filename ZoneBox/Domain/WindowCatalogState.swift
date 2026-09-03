import CoreGraphics
import Foundation

public struct WindowCatalogMembership: Equatable, Sendable {
    public var zoneID: UUID
    public var displayID: UUID
    public var snappedAt: Date

    public init(zoneID: UUID, displayID: UUID, snappedAt: Date) {
        self.zoneID = zoneID
        self.displayID = displayID
        self.snappedAt = snappedAt
    }
}

public struct WindowCatalogState: Equatable, Sendable {
    public var records: [WindowIdentity: UnsnapRecord] = [:]
    public var membership: [WindowIdentity: WindowCatalogMembership] = [:]

    public init(
        records: [WindowIdentity: UnsnapRecord] = [:],
        membership: [WindowIdentity: WindowCatalogMembership] = [:]
    ) {
        self.records = records
        self.membership = membership
    }

    public mutating func record(_ value: UnsnapRecord, displayID: UUID?) {
        if let existing = records[value.identity] {
            var updated = value
            updated.originalFrameAX = existing.originalFrameAX
            records[value.identity] = updated
        } else {
            records[value.identity] = value
        }
        if let zone = value.zoneIDs.first, let displayID {
            membership[value.identity] = WindowCatalogMembership(
                zoneID: zone,
                displayID: displayID,
                snappedAt: value.snappedAt
            )
        } else {
            membership[value.identity] = nil
        }
    }

    public mutating func drop(pid: pid_t) {
        records = records.filter { $0.key.pid != pid }
        membership = membership.filter { $0.key.pid != pid }
    }

    public mutating func drop(identity: WindowIdentity) {
        records[identity] = nil
        membership[identity] = nil
    }

    public func zoneID(for identity: WindowIdentity, displayID: UUID) -> UUID? {
        guard membership[identity]?.displayID == displayID else { return nil }
        return membership[identity]?.zoneID
    }

    public func identities(in zoneID: UUID, displayID: UUID) -> [WindowIdentity] {
        membership.filter { $0.value.zoneID == zoneID && $0.value.displayID == displayID }
            .sorted { lhs, rhs in
                if lhs.value.snappedAt != rhs.value.snappedAt {
                    return lhs.value.snappedAt < rhs.value.snappedAt
                }
                return lhs.key.windowNumber < rhs.key.windowNumber
            }
            .map(\.key)
    }

    public func snappedMemberships(on displayID: UUID) -> [(identity: WindowIdentity, zoneID: UUID)] {
        membership
            .filter { $0.value.displayID == displayID }
            .sorted { lhs, rhs in
                if lhs.value.snappedAt != rhs.value.snappedAt {
                    return lhs.value.snappedAt < rhs.value.snappedAt
                }
                return lhs.key.windowNumber < rhs.key.windowNumber
            }
            .map { ($0.key, $0.value.zoneID) }
    }

    /// Divider-driven frame updates keep the original unsnap origin and the
    /// membership timestamp so zone rotation order stays put.
    public mutating func updateSnappedFrame(
        _ frame: CGRect,
        for identity: WindowIdentity,
        zoneID: UUID,
        displayID: UUID
    ) {
        if var record = records[identity] {
            record.snappedFrameAX = frame
            record.zoneIDs = [zoneID]
            records[identity] = record
        }
        if let existing = membership[identity] {
            membership[identity] = WindowCatalogMembership(
                zoneID: zoneID,
                displayID: displayID,
                snappedAt: existing.snappedAt
            )
        } else {
            membership[identity] = WindowCatalogMembership(
                zoneID: zoneID,
                displayID: displayID,
                snappedAt: Date()
            )
        }
    }
}
