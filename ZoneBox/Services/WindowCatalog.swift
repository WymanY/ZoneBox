import Foundation
import ZoneBoxCore

@MainActor
final class WindowCatalog {
    private var state = WindowCatalogState()

    func record(_ value: UnsnapRecord, displayID: UUID?) {
        state.record(value, displayID: displayID)
    }

    func record(for identity: WindowIdentity) -> UnsnapRecord? {
        state.records[identity]
    }

    func drop(pid: pid_t) {
        state.drop(pid: pid)
    }

    func drop(identity: WindowIdentity) {
        state.drop(identity: identity)
    }

    func zoneID(for identity: WindowIdentity, displayID: UUID) -> UUID? {
        state.zoneID(for: identity, displayID: displayID)
    }

    func identities(in zoneID: UUID, displayID: UUID) -> [WindowIdentity] {
        state.identities(in: zoneID, displayID: displayID)
    }

    func snappedMemberships(on displayID: UUID) -> [(identity: WindowIdentity, zoneID: UUID)] {
        state.snappedMemberships(on: displayID)
    }

    func updateSnappedFrame(
        _ frame: CGRect,
        for identity: WindowIdentity,
        zoneID: UUID,
        displayID: UUID
    ) {
        state.updateSnappedFrame(frame, for: identity, zoneID: zoneID, displayID: displayID)
    }
}
