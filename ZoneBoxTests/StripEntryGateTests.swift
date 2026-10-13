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

    private func zone(_ layoutID: UUID, _ number: Int) -> (layoutID: Layout.ID, zoneNumber: Int) {
        (layoutID, number)
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
