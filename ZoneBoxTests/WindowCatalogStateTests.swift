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
                originalFrameAX: CGRect(x: 0, y: 0, width: 500, height: 800),
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

    func testRecordingALaterSnapAfterLiveResizeStartsNewOriginal() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 9, windowNumber: 9)
        let firstOriginal = CGRect(x: 0, y: 31, width: 1440, height: 869)
        let resized = CGRect(x: 142, y: 154, width: 697, height: 697)
        let displayID = UUID()

        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: firstOriginal,
                snappedFrameAX: CGRect(x: 0, y: 31, width: 720, height: 869),
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: resized,
                snappedFrameAX: CGRect(x: 720, y: 31, width: 720, height: 869),
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )

        let record = try! XCTUnwrap(state.records[identity])
        XCTAssertEqual(record.originalFrameAX, resized)
        XCTAssertEqual(record.snappedFrameAX, CGRect(x: 720, y: 31, width: 720, height: 869))
    }

    func testDropThenRecordStartsANewOriginalFrameCycle() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 9, windowNumber: 9)
        let firstOriginal = CGRect(x: 8, y: 8, width: 200, height: 160)
        let restored = CGRect(x: 220, y: 180, width: 200, height: 160)
        let nextOriginal = CGRect(x: 220, y: 180, width: 200, height: 160)
        let displayID = UUID()

        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: firstOriginal,
                snappedFrameAX: CGRect(x: 0, y: 0, width: 500, height: 800),
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )
        state.drop(identity: identity)
        XCTAssertNil(state.records[identity])
        XCTAssertNil(state.membership[identity])

        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: nextOriginal,
                snappedFrameAX: CGRect(x: 500, y: 0, width: 500, height: 800),
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )

        let record = try! XCTUnwrap(state.records[identity])
        XCTAssertEqual(record.originalFrameAX, restored)
        XCTAssertEqual(record.snappedFrameAX, CGRect(x: 500, y: 0, width: 500, height: 800))
        XCTAssertNotEqual(record.originalFrameAX, firstOriginal)
    }

    func testConstrainedSnapCompletionStoresActualAndKeepsOriginal() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 21, windowNumber: 21)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 400, height: 300)
        let requested = CGRect(x: 0, y: 31, width: 720, height: 869)
        let nextRequested = CGRect(x: 720, y: 31, width: 720, height: 869)
        let writer = CatalogAXFrameWriter(frame: original)
        let applied = AXFrameMutation.apply(
            requested,
            maxSize: CGSize(width: 720, height: 400),
            using: writer
        )
        XCTAssertEqual(applied, CGRect(x: 0, y: 31, width: 720, height: 400))
        XCTAssertGreaterThan(RectMath.chebyshevSize(requested.size, applied!.size), UnsnapCatalogPolicy.sizeTolerance)

        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: requested,
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )
        let capturedSnap = state.records[identity]
        XCTAssertTrue(
            state.completeApply(
                identity: identity,
                requestedFrame: requested,
                appliedFrame: applied,
                capturedDrop: nil,
                capturedSnap: capturedSnap
            )
        )
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, applied)
        XCTAssertEqual(state.records[identity]?.originalFrameAX, original)

        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: applied!,
                snappedFrameAX: nextRequested,
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )
        XCTAssertEqual(state.records[identity]?.originalFrameAX, original)
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, nextRequested)
    }

    func testCompleteApplyManualResizeStartsNewOriginal() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 22, windowNumber: 22)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 400, height: 300)
        let requested = CGRect(x: 0, y: 31, width: 720, height: 869)
        let applied = CGRect(x: 0, y: 31, width: 720, height: 400)
        let resized = CGRect(x: 142, y: 154, width: 500, height: 500)
        let nextRequested = CGRect(x: 720, y: 31, width: 720, height: 869)

        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: requested,
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )
        let capturedSnap = state.records[identity]
        _ = state.completeApply(
            identity: identity,
            requestedFrame: requested,
            appliedFrame: applied,
            capturedDrop: nil,
            capturedSnap: capturedSnap
        )

        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: resized,
                snappedFrameAX: nextRequested,
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )
        XCTAssertEqual(state.records[identity]?.originalFrameAX, resized)
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, nextRequested)
    }

    func testRestoreCompletionDropsAfterAnotherWindowDrag() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 31, windowNumber: 31)
        let other = WindowIdentity(pid: 32, windowNumber: 32)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 500, height: 400)
        let snapped = CGRect(x: 0, y: 31, width: 720, height: 869)
        let restore = CGRect(x: 220, y: 180, width: 500, height: 400)
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: snapped,
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )
        let capturedDrop = state.records[identity]
        state.record(
            UnsnapRecord(
                identity: other,
                originalFrameAX: CGRect(x: 8, y: 8, width: 200, height: 160),
                snappedFrameAX: CGRect(x: 720, y: 31, width: 720, height: 869),
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )

        XCTAssertTrue(
            state.completeApply(
                identity: identity,
                requestedFrame: restore,
                appliedFrame: restore,
                capturedDrop: capturedDrop,
                capturedSnap: nil
            )
        )
        XCTAssertNil(state.records[identity])
        XCTAssertNotNil(state.records[other])
    }

    func testRestoreCompletionKeepsNewerSameWindowSnap() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 33, windowNumber: 33)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 500, height: 400)
        let firstSnap = CGRect(x: 0, y: 31, width: 720, height: 869)
        let nextSnap = CGRect(x: 720, y: 31, width: 720, height: 869)
        let restore = CGRect(x: 220, y: 180, width: 500, height: 400)
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: firstSnap,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 10)
            ),
            displayID: displayID
        )
        let capturedDrop = state.records[identity]
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: firstSnap,
                snappedFrameAX: nextSnap,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 20)
            ),
            displayID: displayID
        )

        XCTAssertFalse(
            state.completeApply(
                identity: identity,
                requestedFrame: restore,
                appliedFrame: restore,
                capturedDrop: capturedDrop,
                capturedSnap: nil
            )
        )
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, nextSnap)
        XCTAssertEqual(state.records[identity]?.originalFrameAX, original)
    }

    func testPartialRestoreKeepsRecordForRetry() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 34, windowNumber: 34)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 500, height: 400)
        let snapped = CGRect(x: 0, y: 31, width: 720, height: 869)
        let restore = original
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: snapped,
                zoneIDs: [UUID()]
            ),
            displayID: displayID
        )
        let capturedDrop = state.records[identity]
        let writer = CatalogAXFrameWriter(frame: snapped, ignoreWrites: true)
        let applied = AXFrameMutation.apply(restore, using: writer)
        XCTAssertEqual(applied, snapped)
        XCTAssertFalse(UnsnapCatalogPolicy.frameMatches(applied, requested: restore))

        XCTAssertFalse(
            state.completeApply(
                identity: identity,
                requestedFrame: restore,
                appliedFrame: applied,
                capturedDrop: capturedDrop,
                capturedSnap: nil
            )
        )
        XCTAssertEqual(state.records[identity], capturedDrop)
    }

    func testOlderSameTargetSnapDoesNotOverwriteNewerRecord() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 35, windowNumber: 35)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 400, height: 300)
        let requested = CGRect(x: 0, y: 31, width: 720, height: 869)
        let firstApplied = CGRect(x: 0, y: 31, width: 720, height: 400)
        let secondApplied = CGRect(x: 0, y: 31, width: 720, height: 420)
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: requested,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 10)
            ),
            displayID: displayID
        )
        let firstSnap = state.records[identity]
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: requested,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 20)
            ),
            displayID: displayID
        )
        let secondSnap = state.records[identity]
        XCTAssertNotEqual(firstSnap, secondSnap)

        XCTAssertFalse(
            state.completeApply(
                identity: identity,
                requestedFrame: requested,
                appliedFrame: firstApplied,
                capturedDrop: nil,
                capturedSnap: firstSnap
            )
        )
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, requested)

        XCTAssertTrue(
            state.completeApply(
                identity: identity,
                requestedFrame: requested,
                appliedFrame: secondApplied,
                capturedDrop: nil,
                capturedSnap: secondSnap
            )
        )
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, secondApplied)
        XCTAssertEqual(state.records[identity]?.originalFrameAX, original)
    }

    func testNewDragWhilePendingKeepsOriginalWhenOldApplyIsNil() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 36, windowNumber: 36)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 400, height: 300)
        let requested = CGRect(x: 0, y: 31, width: 720, height: 869)
        let constrained = CGRect(x: 0, y: 31, width: 720, height: 400)
        let nextRequested = CGRect(x: 720, y: 31, width: 720, height: 869)
        let nextActual = CGRect(x: 720, y: 31, width: 700, height: 420)
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: requested,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 10)
            ),
            displayID: displayID,
            awaitingApply: true
        )
        let firstSnap = state.records[identity]
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: constrained,
                snappedFrameAX: nextRequested,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 20)
            ),
            displayID: displayID,
            awaitingApply: true
        )
        XCTAssertEqual(state.records[identity]?.originalFrameAX, original)
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, nextRequested)
        let secondSnap = state.records[identity]

        XCTAssertFalse(
            state.completeApply(
                identity: identity,
                requestedFrame: requested,
                appliedFrame: nil,
                capturedDrop: nil,
                capturedSnap: firstSnap
            )
        )
        XCTAssertEqual(state.records[identity]?.originalFrameAX, original)
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, nextRequested)

        XCTAssertTrue(
            state.completeApply(
                identity: identity,
                requestedFrame: nextRequested,
                appliedFrame: nextActual,
                capturedDrop: nil,
                capturedSnap: secondSnap
            )
        )
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, nextActual)
        XCTAssertEqual(state.records[identity]?.originalFrameAX, original)
    }

    func testManualResizeAfterCompletedSnapStartsNewOriginal() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 37, windowNumber: 37)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 400, height: 300)
        let requested = CGRect(x: 0, y: 31, width: 720, height: 869)
        let applied = CGRect(x: 0, y: 31, width: 720, height: 400)
        let resized = CGRect(x: 142, y: 154, width: 500, height: 500)
        let nextRequested = CGRect(x: 720, y: 31, width: 720, height: 869)
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: requested,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 10)
            ),
            displayID: displayID,
            awaitingApply: true
        )
        let firstSnap = state.records[identity]
        XCTAssertTrue(
            state.completeApply(
                identity: identity,
                requestedFrame: requested,
                appliedFrame: applied,
                capturedDrop: nil,
                capturedSnap: firstSnap
            )
        )
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: resized,
                snappedFrameAX: nextRequested,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 20)
            ),
            displayID: displayID,
            awaitingApply: true
        )
        XCTAssertEqual(state.records[identity]?.originalFrameAX, resized)
        _ = state.completeApply(
            identity: identity,
            requestedFrame: requested,
            appliedFrame: applied,
            capturedDrop: nil,
            capturedSnap: firstSnap
        )
        XCTAssertEqual(state.records[identity]?.originalFrameAX, resized)
        XCTAssertEqual(state.records[identity]?.snappedFrameAX, nextRequested)
    }

    func testSameWindowInteractionWithoutReplacementKeepsRestoreRecord() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 41, windowNumber: 41)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 500, height: 400)
        let snapped = CGRect(x: 0, y: 31, width: 720, height: 869)
        let restore = CGRect(x: 220, y: 180, width: 500, height: 400)
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: snapped,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 41)
            ),
            displayID: displayID
        )
        let firstDrag = state.beginInteraction(identity: identity)
        let capturedDrop = state.records[identity]
        let secondDrag = state.beginInteraction(identity: identity)

        XCTAssertNotEqual(firstDrag, secondDrag)
        XCTAssertFalse(
            state.completeApply(
                identity: identity,
                requestedFrame: restore,
                appliedFrame: restore,
                capturedDrop: capturedDrop,
                capturedSnap: nil,
                capturedInteractionToken: firstDrag
            )
        )
        XCTAssertEqual(state.records[identity], capturedDrop)
        XCTAssertEqual(state.interactionToken(for: identity), secondDrag)
    }

    func testOtherWindowInteractionStillDropsCompletedRestore() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 42, windowNumber: 42)
        let other = WindowIdentity(pid: 43, windowNumber: 43)
        let displayID = UUID()
        let original = CGRect(x: 40, y: 40, width: 500, height: 400)
        let snapped = CGRect(x: 0, y: 31, width: 720, height: 869)
        let restore = CGRect(x: 220, y: 180, width: 500, height: 400)
        state.record(
            UnsnapRecord(
                identity: identity,
                originalFrameAX: original,
                snappedFrameAX: snapped,
                zoneIDs: [UUID()],
                snappedAt: Date(timeIntervalSince1970: 42)
            ),
            displayID: displayID
        )
        let firstDrag = state.beginInteraction(identity: identity)
        let capturedDrop = state.records[identity]
        _ = state.beginInteraction(identity: other)

        XCTAssertTrue(
            state.completeApply(
                identity: identity,
                requestedFrame: restore,
                appliedFrame: restore,
                capturedDrop: capturedDrop,
                capturedSnap: nil,
                capturedInteractionToken: firstDrag
            )
        )
        XCTAssertNil(state.records[identity])
        XCTAssertNil(state.interactionToken(for: identity))
        XCTAssertNotNil(state.interactionToken(for: other))
    }

    func testRebuiltWindowDoesNotReuseDroppedInteractionToken() {
        var state = WindowCatalogState()
        let identity = WindowIdentity(pid: 44, windowNumber: 44)
        let other = WindowIdentity(pid: 45, windowNumber: 45)
        let displayID = UUID()
        let record = UnsnapRecord(
            identity: identity,
            originalFrameAX: CGRect(x: 40, y: 40, width: 500, height: 400),
            snappedFrameAX: CGRect(x: 0, y: 31, width: 720, height: 869),
            zoneIDs: [UUID()],
            snappedAt: Date(timeIntervalSince1970: 44)
        )
        let restore = CGRect(x: 220, y: 180, width: 500, height: 400)
        state.record(record, displayID: displayID)
        let stale = state.beginInteraction(identity: identity)
        let otherToken = state.beginInteraction(identity: other)
        state.drop(pid: identity.pid)
        XCTAssertNil(state.records[identity])
        XCTAssertNil(state.interactionToken(for: identity))
        XCTAssertEqual(state.interactionToken(for: other), otherToken)

        state.record(record, displayID: displayID)
        let rebuilt = state.beginInteraction(identity: identity)
        XCTAssertNotEqual(stale, rebuilt)
        XCTAssertFalse(
            state.completeApply(
                identity: identity,
                requestedFrame: restore,
                appliedFrame: restore,
                capturedDrop: record,
                capturedSnap: nil,
                capturedInteractionToken: stale
            )
        )
        XCTAssertEqual(state.records[identity], record)
    }
}

private final class CatalogAXFrameWriter: AXFrameWriting {
    var frame: CGRect
    var ignoreWrites: Bool

    init(frame: CGRect, ignoreWrites: Bool = false) {
        self.frame = frame
        self.ignoreWrites = ignoreWrites
    }

    func readFrame() -> CGRect? { frame }

    func setSize(_ size: CGSize) {
        guard !ignoreWrites else { return }
        frame.size = size
    }

    func setPoint(_ origin: CGPoint) {
        guard !ignoreWrites else { return }
        frame.origin = origin
    }

    func sleep(_ duration: TimeInterval) {}
}
