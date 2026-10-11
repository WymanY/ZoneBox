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
    /// snappedAt of a snap whose AX apply has not finished. A same-window
    /// record keeps the previous original while this is current.
    private var pendingSnappedAt: [WindowIdentity: Date] = [:]

    public init(
        records: [WindowIdentity: UnsnapRecord] = [:],
        membership: [WindowIdentity: WindowCatalogMembership] = [:]
    ) {
        self.records = records
        self.membership = membership
    }

    public mutating func record(
        _ value: UnsnapRecord,
        displayID: UUID?,
        awaitingApply: Bool = false
    ) {
        var stored = value
        if let existing = records[value.identity] {
            if pendingSnappedAt[value.identity] == existing.snappedAt {
                stored.originalFrameAX = existing.originalFrameAX
            } else {
                stored.originalFrameAX = UnsnapCatalogPolicy.originalFrameAX(
                    existing: existing,
                    incomingOriginal: value.originalFrameAX
                )
            }
        }
        records[value.identity] = stored
        if awaitingApply {
            pendingSnappedAt[value.identity] = stored.snappedAt
        }
        if let zone = stored.zoneIDs.first, let displayID {
            membership[value.identity] = WindowCatalogMembership(
                zoneID: zone,
                displayID: displayID,
                snappedAt: stored.snappedAt
            )
        } else {
            membership[value.identity] = nil
        }
    }

    /// AX completion for a snap or restore. Restore drops only when the
    /// requested frame landed and this identity was not replaced. Snap stores
    /// the applied frame only while this write still owns the captured record.
    @discardableResult
    public mutating func completeApply(
        identity: WindowIdentity,
        requestedFrame: CGRect,
        appliedFrame: CGRect?,
        capturedDrop: UnsnapRecord?,
        capturedSnap: UnsnapRecord?
    ) -> Bool {
        if let dropIdentity = UnsnapCatalogPolicy.identityToDrop(
            capturedForThisWrite: capturedDrop,
            currentRecord: records[identity],
            requestedFrame: requestedFrame,
            appliedFrame: appliedFrame
        ) {
            drop(identity: dropIdentity)
            return true
        }
        if let capturedSnap,
           capturedSnap.identity == identity,
           pendingSnappedAt[identity] == capturedSnap.snappedAt,
           records[identity]?.snappedAt == capturedSnap.snappedAt {
            pendingSnappedAt[identity] = nil
        }
        guard let applied = UnsnapCatalogPolicy.appliedSnappedFrame(
            capturedSnap: capturedSnap,
            currentRecord: records[identity],
            requestedFrame: requestedFrame,
            appliedFrame: appliedFrame
        ), var record = records[identity], record.snappedFrameAX != applied else {
            return false
        }
        record.snappedFrameAX = applied
        records[identity] = record
        return true
    }

    public mutating func drop(pid: pid_t) {
        records = records.filter { $0.key.pid != pid }
        membership = membership.filter { $0.key.pid != pid }
        pendingSnappedAt = pendingSnappedAt.filter { $0.key.pid != pid }
    }

    public mutating func drop(identity: WindowIdentity) {
        records[identity] = nil
        membership[identity] = nil
        pendingSnappedAt[identity] = nil
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
