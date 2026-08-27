import Foundation
import ZoneBoxCore

@MainActor
final class WindowCatalog {
    private var records: [WindowIdentity: UnsnapRecord] = [:]
    private var membership: [WindowIdentity: (zoneID: UUID, displayID: UUID, snappedAt: Date)] = [:]

    func record(_ value: UnsnapRecord, displayID: UUID?) {
        if records[value.identity] == nil {
            records[value.identity] = value
        }
        if let zone = value.zoneIDs.first, let displayID {
            membership[value.identity] = (zone, displayID, value.snappedAt)
        } else {
            membership[value.identity] = nil
        }
    }

    func record(for identity: WindowIdentity) -> UnsnapRecord? {
        records[identity]
    }

    func drop(pid: pid_t) {
        records = records.filter { $0.key.pid != pid }
        membership = membership.filter { $0.key.pid != pid }
    }

    func drop(identity: WindowIdentity) {
        records[identity] = nil
        membership[identity] = nil
    }

    func zoneID(for identity: WindowIdentity, displayID: UUID) -> UUID? {
        guard membership[identity]?.displayID == displayID else { return nil }
        return membership[identity]?.zoneID
    }

    func identities(in zoneID: UUID, displayID: UUID) -> [WindowIdentity] {
        membership.filter { $0.value.zoneID == zoneID && $0.value.displayID == displayID }
            .sorted { lhs, rhs in
                if lhs.value.snappedAt != rhs.value.snappedAt {
                    return lhs.value.snappedAt < rhs.value.snappedAt
                }
                return lhs.key.windowNumber < rhs.key.windowNumber
            }
            .map(\.key)
    }
}
