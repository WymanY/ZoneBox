import XCTest
@testable import ZoneBoxCore

final class QuickSnapperTests: XCTestCase {
    private let terminal = WindowIdentity(pid: 42, windowNumber: 7, bundleID: "com.apple.Terminal")
    private let zoneBox = WindowIdentity(pid: 99, windowNumber: 1, bundleID: "com.fancyzone.app")

    func testInvokeShowsOverlayAndCapturesFocus() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(
                phase: .hidden,
                event: .invoke,
                zoneNumbers: [1, 2, 3],
                focusedWindow: terminal
            )
        )
        XCTAssertEqual(out.phase, .showing(target: terminal))
        XCTAssertEqual(out.effects, [.showOverlay])
        XCTAssertFalse(out.effects.contains { if case .snap = $0 { return true }; return false })
    }

    func testDigitSnapsExistingZone() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(
                phase: .showing(target: terminal),
                event: .digit(3),
                zoneNumbers: [1, 2, 3]
            )
        )
        XCTAssertEqual(out.phase, .hidden)
        XCTAssertEqual(out.effects, [.snap(terminal, zoneNumber: 3), .hideOverlay])
    }

    func testDigitSnapsInvokeSnapshotNotLaterFocus() {
        let invoked = QuickSnapperReducer.reduce(
            QuickSnapperInput(
                phase: .hidden,
                event: .invoke,
                zoneNumbers: [1, 2],
                focusedWindow: terminal
            )
        )
        guard case .showing(let target) = invoked.phase else {
            return XCTFail("invoke must enter showing with a snapshot")
        }
        XCTAssertEqual(target, terminal)

        let stolenFocus = QuickSnapperReducer.reduce(
            QuickSnapperInput(
                phase: invoked.phase,
                event: .digit(1),
                zoneNumbers: [1, 2],
                focusedWindow: zoneBox
            )
        )
        XCTAssertEqual(stolenFocus.phase, .hidden)
        XCTAssertEqual(stolenFocus.effects, [.snap(terminal, zoneNumber: 1), .hideOverlay])
        XCTAssertFalse(
            stolenFocus.effects.contains(.snap(zoneBox, zoneNumber: 1)),
            "HUD key-sink / ZoneBox activation must not become the snap target"
        )
    }

    func testDigitWithoutSnapshotIsNoOp() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(
                phase: .showing(target: nil),
                event: .digit(1),
                zoneNumbers: [1],
                focusedWindow: zoneBox
            )
        )
        XCTAssertEqual(out.phase, .showing(target: nil))
        XCTAssertEqual(out.effects, [])
        XCTAssertFalse(out.effects.contains { if case .snap = $0 { return true }; return false })
    }

    func testMissingDigitIsNoOp() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(
                phase: .showing(target: terminal),
                event: .digit(9),
                zoneNumbers: [1, 2, 3],
                focusedWindow: zoneBox
            )
        )
        XCTAssertEqual(out.phase, .showing(target: terminal))
        XCTAssertEqual(out.effects, [])
    }

    func testDismissLeavesWindowUnmoved() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(
                phase: .showing(target: terminal),
                event: .dismiss,
                zoneNumbers: [1, 2, 3],
                focusedWindow: zoneBox
            )
        )
        XCTAssertEqual(out.phase, .hidden)
        XCTAssertEqual(out.effects, [.hideOverlay])
        XCTAssertFalse(out.effects.contains { if case .snap = $0 { return true }; return false })
    }

    func testDigitWhileHiddenIsNoOp() {
        let out = QuickSnapperReducer.reduce(
            QuickSnapperInput(
                phase: .hidden,
                event: .digit(1),
                zoneNumbers: [1],
                focusedWindow: terminal
            )
        )
        XCTAssertEqual(out.phase, .hidden)
        XCTAssertEqual(out.effects, [])
    }

    func testFailClosedWhenUntrustedOrEditorOpen() {
        var input = QuickSnapperInput(
            phase: .showing(target: terminal),
            event: .digit(1),
            zoneNumbers: [1],
            trusted: false
        )
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
