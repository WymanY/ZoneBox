import XCTest
@testable import ZoneBoxCore

final class QuickSnapperTests: XCTestCase {
    func testInvokeShowsOverlay() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(phase: .hidden, event: .invoke, zoneNumbers: [1, 2, 3])
        )
        XCTAssertEqual(out.phase, .showing)
        XCTAssertEqual(out.effects, [.showOverlay])
    }

    func testDigitSnapsExistingZone() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(phase: .showing, event: .digit(3), zoneNumbers: [1, 2, 3])
        )
        XCTAssertEqual(out.phase, .hidden)
        XCTAssertEqual(out.effects, [.snap(zoneNumber: 3), .hideOverlay])
    }

    func testMissingDigitIsNoOp() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(phase: .showing, event: .digit(9), zoneNumbers: [1, 2, 3])
        )
        XCTAssertEqual(out.phase, .showing)
        XCTAssertEqual(out.effects, [])
    }

    func testDismissLeavesWindowUnmoved() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(phase: .showing, event: .dismiss, zoneNumbers: [1, 2, 3])
        )
        XCTAssertEqual(out.phase, .hidden)
        XCTAssertEqual(out.effects, [.hideOverlay])
        XCTAssertFalse(out.effects.contains { if case .snap = $0 { return true }; return false })
    }

    func testDigitWhileHiddenIsNoOp() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(phase: .hidden, event: .digit(1), zoneNumbers: [1])
        )
        XCTAssertEqual(out.phase, .hidden)
        XCTAssertEqual(out.effects, [])
    }

    func testFailClosedWhenUntrustedOrEditorOpen() {
        var input = QuickSnapperInput(phase: .showing, event: .digit(1), zoneNumbers: [1], trusted: false)
        XCTAssertEqual(QuickSnapperReducer.reduce(input).phase, .hidden)
        input.trusted = true
        input.isEditorOpen = true
        XCTAssertEqual(QuickSnapperReducer.reduce(input).phase, .hidden)
        input.isEditorOpen = false
        input.enabled = false
        XCTAssertEqual(QuickSnapperReducer.reduce(input).phase, .hidden)
        input.enabled = true
        input.snapEnabled = false
        XCTAssertEqual(QuickSnapperReducer.reduce(input).phase, .hidden)
    }

    func testZoneNumberMapsHardwareKeysOneThroughNine() {
        XCTAssertEqual(QuickSnapperReducer.zoneNumber(forKeyCode: 18), 1)
        XCTAssertEqual(QuickSnapperReducer.zoneNumber(forKeyCode: 23), 5)
        XCTAssertEqual(QuickSnapperReducer.zoneNumber(forKeyCode: 25), 9)
        XCTAssertNil(QuickSnapperReducer.zoneNumber(forKeyCode: 29))
    }
}
