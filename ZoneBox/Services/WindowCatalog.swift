import Foundation
import ZoneBoxCore

@MainActor
final class WindowCatalog {
    private var records: [WindowIdentity: UnsnapRecord] = [:]
    private var membership: [WindowIdentity: (zoneID: UUID, snappedAt: Date)] = [:]

    func record(_ value: UnsnapRecord) {
        if records[value.identity] == nil {
            records[value.identity] = value
        }
        if let zone = value.zoneIDs.first {
            membership[value.identity] = (zone, value.snappedAt)
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

    func zoneID(for identity: WindowIdentity) -> UUID? {
        membership[identity]?.zoneID
    }

    func identities(in zoneID: UUID) -> [WindowIdentity] {
        membership.filter { $0.value.zoneID == zoneID }
            .sorted { lhs, rhs in
                if lhs.value.snappedAt != rhs.value.snappedAt {
                    return lhs.value.snappedAt < rhs.value.snappedAt
                }
                return lhs.key.windowNumber < rhs.key.windowNumber
            }
            .map(\.key)
    }
}
