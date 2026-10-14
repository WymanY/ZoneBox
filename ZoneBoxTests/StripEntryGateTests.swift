import XCTest
@testable import ZoneBoxCore

final class StripEntryGateTests: XCTestCase {
    private let layoutA = UUID()
    private let layoutB = UUID()

    func testSpawnUnderPointerDoesNotStartCandidate() {
        var gate = StripEntryGate()
        let first = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 1, suppress: false)
        XCTAssertFalse(first.isConfirmed)
        XCTAssertNil(first.candidateZoneNumber)
        XCTAssertNil(first.acceptedZoneNumber)
        XCTAssertNil(first.remainingDwell)

        let stillThere = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 1.5, suppress: false)
        XCTAssertFalse(stillThere.isConfirmed)
        XCTAssertNil(stillThere.candidateZoneNumber)
        XCTAssertNil(stillThere.acceptedZoneNumber)
    }

    func testEnteringAfterEmptyContentStartsDwell() {
        var gate = StripEntryGate()
        _ = gate.advance(miniZone: nil, overflow: nil, now: 1, suppress: false)
        let entered = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 1.01, suppress: false)
        XCTAssertEqual(entered.candidateLayoutID, layoutA)
        XCTAssertEqual(entered.candidateZoneNumber, 2)
        XCTAssertEqual(entered.remainingDwell, StripEntryGate.dwellDuration)
        XCTAssertFalse(entered.isConfirmed)
        XCTAssertNil(entered.acceptedZoneNumber)
    }

    func testLeavingBeforeDwellCancelsCandidate() {
        var gate = StripEntryGate()
        _ = gate.advance(miniZone: nil, overflow: nil, now: 1, suppress: false)
        _ = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 1.01, suppress: false)
        let left = gate.advance(miniZone: nil, overflow: nil, now: 1.1, suppress: false)
        XCTAssertFalse(left.isConfirmed)
        XCTAssertNil(left.candidateZoneNumber)
        XCTAssertNil(left.acceptedZoneNumber)
        XCTAssertNil(left.remainingDwell)
    }

    func testDwellConfirmsAndKeepsLayoutOnStillPointer() {
        var gate = StripEntryGate()
        _ = gate.advance(miniZone: nil, overflow: nil, now: 1, suppress: false)
        _ = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 1.0, suppress: false)
        let confirmed = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 1.21, suppress: false)
        XCTAssertTrue(confirmed.isConfirmed)
        XCTAssertEqual(confirmed.acceptedLayoutID, layoutA)
        XCTAssertEqual(confirmed.acceptedZoneNumber, 2)
        XCTAssertNil(confirmed.candidateZoneNumber)
        XCTAssertNil(confirmed.remainingDwell)
    }

    func testConfirmedMiniZoneSwitchesImmediately() {
        var gate = StripEntryGate()
        confirm(zone: zone(layoutA, 2), on: &gate, at: 1)
        let switched = gate.advance(miniZone: zone(layoutB, 1), overflow: nil, now: 2, suppress: false)
        XCTAssertTrue(switched.isConfirmed)
        XCTAssertEqual(switched.acceptedLayoutID, layoutB)
        XCTAssertEqual(switched.acceptedZoneNumber, 1)
        XCTAssertNil(switched.remainingDwell)
    }

    func testOverflowRequiresDwellEvenAfterZoneConfirm() {
        var gate = StripEntryGate()
        confirm(zone: zone(layoutA, 2), on: &gate, at: 1)
        let hover = gate.advance(miniZone: nil, overflow: 1, now: 3, suppress: false)
        XCTAssertTrue(hover.isConfirmed)
        XCTAssertEqual(hover.candidateOverflow, 1)
        XCTAssertNil(hover.confirmedOverflow)
        XCTAssertEqual(hover.remainingDwell, StripEntryGate.dwellDuration)

        let paged = gate.advance(miniZone: nil, overflow: 1, now: 3.21, suppress: false)
        XCTAssertTrue(paged.isConfirmed)
        XCTAssertEqual(paged.confirmedOverflow, 1)
        XCTAssertNil(paged.remainingDwell)
    }

    func testSpawnOverflowDoesNotPage() {
        var gate = StripEntryGate()
        let first = gate.advance(miniZone: nil, overflow: 1, now: 1, suppress: false)
        XCTAssertNil(first.candidateOverflow)
        XCTAssertNil(first.confirmedOverflow)
        let held = gate.advance(miniZone: nil, overflow: 1, now: 1.4, suppress: false)
        XCTAssertNil(held.confirmedOverflow)
    }

    func testSuppressResetsGate() {
        var gate = StripEntryGate()
        confirm(zone: zone(layoutA, 2), on: &gate, at: 1)
        let suppressed = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 4, suppress: true)
        XCTAssertEqual(suppressed, .empty)
        _ = gate.advance(miniZone: nil, overflow: nil, now: 4.1, suppress: false)
        let reentered = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 4.2, suppress: false)
        XCTAssertFalse(reentered.isConfirmed)
        XCTAssertEqual(reentered.candidateZoneNumber, 2)
    }

    func testChromeAndLingerNeverStartCandidate() {
        var gate = StripEntryGate()
        _ = gate.advance(miniZone: nil, overflow: nil, now: 1, suppress: false)
        let chrome = gate.advance(miniZone: nil, overflow: nil, now: 1.1, suppress: false)
        XCTAssertEqual(chrome, .empty)
    }

    func testMovingToAnotherMiniZoneRestartsDwell() {
        var gate = StripEntryGate()
        _ = gate.advance(miniZone: nil, overflow: nil, now: 1, suppress: false)
        _ = gate.advance(miniZone: zone(layoutA, 1), overflow: nil, now: 1.0, suppress: false)
        let switched = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 1.1, suppress: false)
        XCTAssertEqual(switched.candidateZoneNumber, 2)
        XCTAssertEqual(switched.remainingDwell, StripEntryGate.dwellDuration)
        XCTAssertFalse(switched.isConfirmed)
    }

    func testMouseUpAfterThresholdBeforeRefreshDoesNotConfirm() {
        var gate = pendingZone()
        var refresh = gate
        let confirmedByRefresh = refresh.advance(
            miniZone: zone(layoutA, 2),
            overflow: nil,
            now: pendingConfirmTime,
            suppress: false
        )
        XCTAssertTrue(confirmedByRefresh.isConfirmed)
        XCTAssertEqual(confirmedByRefresh.acceptedZoneNumber, 2)

        gate.prepare(.mouseUp)
        let released = gate.advance(
            miniZone: zone(layoutA, 2),
            overflow: nil,
            now: pendingConfirmTime,
            suppress: false
        )
        XCTAssertFalse(released.isConfirmed)
        XCTAssertNil(released.acceptedLayoutID)
        XCTAssertNil(released.acceptedZoneNumber)
        XCTAssertEqual(released.candidateZoneNumber, 2)
        XCTAssertEqual(released.remainingDwell, StripEntryGate.dwellDuration)
    }

    func testMouseUpKeepsAlreadyConfirmedSelection() {
        var gate = StripEntryGate()
        confirm(zone: zone(layoutA, 2), on: &gate, at: 1)
        gate.prepare(.mouseUp)
        let released = gate.advance(miniZone: zone(layoutA, 2), overflow: nil, now: 2, suppress: false)
        XCTAssertTrue(released.isConfirmed)
        XCTAssertEqual(released.acceptedLayoutID, layoutA)
        XCTAssertEqual(released.acceptedZoneNumber, 2)
        XCTAssertNil(released.candidateZoneNumber)
        XCTAssertNil(released.remainingDwell)
    }

    func testDigitResetBlocksRearmUntilPointerLeaves() {
        var gate = pendingZone()
        var refresh = gate
        let confirmedByRefresh = refresh.advance(
            miniZone: zone(layoutA, 2),
            overflow: nil,
            now: pendingConfirmTime,
            suppress: false
        )
        XCTAssertTrue(confirmedByRefresh.isConfirmed)
        XCTAssertEqual(confirmedByRefresh.acceptedZoneNumber, 2)

        gate.prepare(.digit)
        let sameCellPolls = [0.0, 0.05, StripEntryGate.dwellDuration, 0.5]
        for offset in sameCellPolls {
            let poll = gate.advance(
                miniZone: zone(layoutA, 2),
                overflow: nil,
                now: pendingConfirmTime + offset,
                suppress: false
            )
            XCTAssertFalse(poll.isConfirmed)
            XCTAssertNil(poll.candidateZoneNumber)
            XCTAssertNil(poll.acceptedZoneNumber)
            XCTAssertNil(poll.remainingDwell)
        }

        let left = gate.advance(miniZone: nil, overflow: nil, now: pendingConfirmTime + 0.6, suppress: false)
        XCTAssertFalse(left.isConfirmed)
        let reentered = gate.advance(
            miniZone: zone(layoutA, 2),
            overflow: nil,
            now: pendingConfirmTime + 0.61,
            suppress: false
        )
        XCTAssertFalse(reentered.isConfirmed)
        XCTAssertEqual(reentered.candidateZoneNumber, 2)
        XCTAssertEqual(reentered.remainingDwell, StripEntryGate.dwellDuration)
    }

    func testCycleLayoutAfterThresholdBeforeRefreshDoesNotConfirmOrRearm() {
        var refresh = pendingZone(layoutB, zoneNumber: 1)
        let confirmedByRefresh = refresh.advance(
            miniZone: zone(layoutB, 1),
            overflow: nil,
            now: pendingConfirmTime,
            suppress: false
        )
        XCTAssertTrue(confirmedByRefresh.isConfirmed)
        XCTAssertEqual(confirmedByRefresh.acceptedLayoutID, layoutB)

        var gate = pendingZone(layoutB, zoneNumber: 1)
        gate.prepare(.cycleLayout)
        let sameCellPolls = [0.0, 0.05, StripEntryGate.dwellDuration, 0.5]
        for offset in sameCellPolls {
            let poll = gate.advance(
                miniZone: zone(layoutB, 1),
                overflow: nil,
                now: pendingConfirmTime + offset,
                suppress: false
            )
            XCTAssertFalse(poll.isConfirmed)
            XCTAssertNil(poll.candidateLayoutID)
            XCTAssertNil(poll.acceptedLayoutID)
            XCTAssertNil(poll.remainingDwell)
        }

        let left = gate.advance(miniZone: nil, overflow: nil, now: pendingConfirmTime + 0.6, suppress: false)
        XCTAssertFalse(left.isConfirmed)
        let reentered = gate.advance(
            miniZone: zone(layoutB, 1),
            overflow: nil,
            now: pendingConfirmTime + 0.61,
            suppress: false
        )
        XCTAssertFalse(reentered.isConfirmed)
        XCTAssertEqual(reentered.candidateLayoutID, layoutB)
        XCTAssertEqual(reentered.remainingDwell, StripEntryGate.dwellDuration)
    }

    func testCycleLayoutKeepsAlreadyConfirmedSelection() {
        var gate = StripEntryGate()
        confirm(zone: zone(layoutB, 1), on: &gate, at: 1)
        gate.prepare(.cycleLayout)
        let kept = gate.advance(miniZone: zone(layoutB, 1), overflow: nil, now: 2, suppress: false)
        XCTAssertTrue(kept.isConfirmed)
        XCTAssertEqual(kept.acceptedLayoutID, layoutB)
        XCTAssertEqual(kept.acceptedZoneNumber, 1)
        XCTAssertNil(kept.candidateLayoutID)
        XCTAssertNil(kept.remainingDwell)
    }

    func testCycleLayoutDuringPendingOverflowKeepsConfirmedSelection() {
        let lateTime = 2 + StripEntryGate.dwellDuration + 0.005
        for delta in [1, -1] {
            var early = StripEntryGate()
            confirm(zone: zone(layoutB, 1), on: &early, at: 1)
            let pending = early.advance(miniZone: nil, overflow: delta, now: 2, suppress: false)
            XCTAssertTrue(pending.isConfirmed)
            XCTAssertEqual(pending.candidateOverflow, delta)
            XCTAssertNil(pending.confirmedOverflow)
            early.prepare(.cycleLayout)
            let canceledEarly = early.advance(miniZone: nil, overflow: delta, now: 2.05, suppress: false)
            XCTAssertTrue(canceledEarly.isConfirmed)
            XCTAssertNil(canceledEarly.confirmedOverflow)
            XCTAssertEqual(canceledEarly.candidateOverflow, delta)
            XCTAssertEqual(canceledEarly.remainingDwell, StripEntryGate.dwellDuration)

            var late = StripEntryGate()
            confirm(zone: zone(layoutB, 1), on: &late, at: 1)
            _ = late.advance(miniZone: nil, overflow: delta, now: 2, suppress: false)
            var raced = late
            let paged = raced.advance(miniZone: nil, overflow: delta, now: lateTime, suppress: false)
            XCTAssertEqual(paged.confirmedOverflow, delta)
            late.prepare(.cycleLayout)
            let canceledLate = late.advance(miniZone: nil, overflow: delta, now: lateTime, suppress: false)
            XCTAssertTrue(canceledLate.isConfirmed)
            XCTAssertNil(canceledLate.confirmedOverflow)
            XCTAssertEqual(canceledLate.candidateOverflow, delta)
            XCTAssertEqual(canceledLate.remainingDwell, StripEntryGate.dwellDuration)
        }
    }

    private func zone(_ layoutID: UUID, _ number: Int) -> (layoutID: Layout.ID, zoneNumber: Int) {
        (layoutID, number)
    }

    /// Past the 0.20 confirm threshold and before the engine refresh at remaining + 0.015.
    private var pendingConfirmTime: TimeInterval { 1.01 + StripEntryGate.dwellDuration + 0.005 }

    private func pendingZone(_ layoutID: Layout.ID? = nil, zoneNumber: Int = 2) -> StripEntryGate {
        let layoutID = layoutID ?? layoutA
        var gate = StripEntryGate()
        _ = gate.advance(miniZone: nil, overflow: nil, now: 1, suppress: false)
        let pending = gate.advance(miniZone: zone(layoutID, zoneNumber), overflow: nil, now: 1.01, suppress: false)
        XCTAssertEqual(pending.candidateLayoutID, layoutID)
        XCTAssertEqual(pending.candidateZoneNumber, zoneNumber)
        XCTAssertEqual(pending.remainingDwell, StripEntryGate.dwellDuration)
        XCTAssertFalse(pending.isConfirmed)
        return gate
    }

    private func confirm(
        zone: (layoutID: Layout.ID, zoneNumber: Int),
        on gate: inout StripEntryGate,
        at now: TimeInterval
    ) {
        _ = gate.advance(miniZone: nil, overflow: nil, now: now, suppress: false)
        _ = gate.advance(miniZone: zone, overflow: nil, now: now, suppress: false)
        let confirmed = gate.advance(
            miniZone: zone,
            overflow: nil,
            now: now + 0.21,
            suppress: false
        )
        XCTAssertTrue(confirmed.isConfirmed)
        XCTAssertEqual(confirmed.acceptedZoneNumber, zone.zoneNumber)
    }
}
