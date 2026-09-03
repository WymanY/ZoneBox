import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class WindowCatalogStateTests: XCTestCase {
    func testUpdateSnappedFrameKeepsOriginalAndMembershipTimestamp() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 11, windowNumber: 22)
        let original = CGRect(x: 10, y: 20, width: 300, height: 200)
        let firstSnap = CGRect(x: 0, y: 0, width: 500, height: 800)
        let nextSnap = CGRect(x: 0, y: 0, width: 350, height: 800)
        let zoneID = UUID()
        let displayID = UUID()
        let snappedAt = Date(timeIntervalSince1970: 1_700_000_000)

        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: firstSnap,
                zoneIDs: [zoneID],
                snappedAt: snappedAt
            ),
            displayID: displayID
        )
        state.updateSnappedFrame(nextSnap, for: identity, zoneID: zoneID, displayID: displayID)

        let record = try! XCTUnwrap(state.records[identity])
        XCTAssertEqual(record.originalFrameAX, original)
        XCTAssertEqual(record.snappedFrameAX, nextSnap)
        XCTAssertEqual(record.zoneIDs, [zoneID])
        XCTAssertEqual(record.snappedAt, snappedAt)
        XCTAssertEqual(state.membership[identity]?.snappedAt, snappedAt)
        XCTAssertEqual(state.membership[identity]?.zoneID, zoneID)
        XCTAssertEqual(state.membership[identity]?.displayID, displayID)
    }

    func testSnappedMembershipsOnlyReturnsTheRequestedDisplay() {
        var state = WindowCatalogState()
        let displayA = UUID()
        let displayB = UUID()
        let zoneA = UUID()
        let zoneB = UUID()
        let first = WindowIdentity(pid: 1, windowNumber: 1)
        let second = WindowIdentity(pid: 2, windowNumber: 2)
        let other = WindowIdentity(pid: 3, windowNumber: 3)

        state.record(
            UnsnapRecord(
                identity: first,
                originalFrameAX: .zero,
                snappedFrameAX: CGRect(x: 0, y: 0, width: 100, height: 100),
                zoneIDs: [zoneA],
                snappedAt: Date(timeIntervalSince1970: 10)
            ),
            displayID: displayA
        )
        state.record(
            UnsnapRecord(
                identity: second,
                originalFrameAX: .zero,
                snappedFrameAX: CGRect(x: 100, y: 0, width: 100, height: 100),
                zoneIDs: [zoneB],
                snappedAt: Date(timeIntervalSince1970: 20)
            ),
            displayID: displayA
        )
        state.record(
            UnsnapRecord(
                identity: other,
                originalFrameAX: .zero,
                snappedFrameAX: CGRect(x: 0, y: 0, width: 200, height: 200),
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 30)
            ),
            displayID: displayB
        )

        let memberships = state.snappedMemberships(on: displayA)
        XCTAssertEqual(memberships.map(\.identity), [first, second])
        XCTAssertEqual(memberships.map(\.zoneID), [zoneA, zoneB])
        XCTAssertEqual(state.snappedMemberships(on: displayB).map(\.identity), [other])
    }

    func testRecordingALaterSnapUpdatesMembershipAndKeepsOriginalFrame() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 9, windowNumber: 9)
        let original = CGRect(x: 8, y: 8, width: 200, height: 160)
        let firstZone = UUID()
        let secondZone = UUID()
        let displayID = UUID()

        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: CGRect(x: 0, y: 0, width: 500, height: 800),
                zoneIDs: [firstZone],
                snappedAt: Date(timeIntervalSince1970: 10)
            ),
            displayID: displayID
        )
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: CGRect(x: 40, y: 40, width: 180, height: 140),
                snappedFrameAX: CGRect(x: 500, y: 0, width: 500, height: 800),
                zoneIDs: [secondZone],
                snappedAt: Date(timeIntervalSince1970: 20)
            ),
            displayID: displayID
        )

        let record = try! XCTUnwrap(state.records[identity])
        XCTAssertEqual(record.originalFrameAX, original)
        XCTAssertEqual(record.snappedFrameAX, CGRect(x: 500, y: 0, width: 500, height: 800))
        XCTAssertEqual(record.zoneIDs, [secondZone])
        XCTAssertEqual(state.membership[identity]?.zoneID, secondZone)
        XCTAssertEqual(state.zoneID(for: identity, displayID: displayID), secondZone)
    }
}
