import XCTest
@testable import ZoneBoxCore

final class SnapEngineTests: XCTestCase {
    private let window = WindowIdentity(pid: 42, windowNumber: 7, bundleID: "com.apple.Terminal")
    private let frame = CGRect(x: 10, y: 10, width: 400, height: 300)

    func testUntrustedFailsClosed() {
        let input = SnapReducerInput(
            phase: .dragging(window),
            event: SnapMouseEvent(kind: .leftDragged, locationAppKit: .zero, modifiers: [.shift]),
            trusted: false
        )
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .idle)
        XCTAssertTrue(out.effects.contains(.hideOverlay))
    }

    func testEditorOpenFailsClosed() {
        let input = SnapReducerInput(
            phase: .dragging(window),
            event: SnapMouseEvent(kind: .leftDragged, locationAppKit: .zero, modifiers: [.shift]),
            isEditorOpen: true
        )
        XCTAssertEqual(SnapSessionReducer.reduce(input).phase, .idle)
    }

    func testClickWithoutMoveStaysIdleOnUp() {
        var input = base(phase: .idle, kind: .leftDown)
        input.window = window
        input.currentFrameAX = frame
        let down = SnapSessionReducer.reduce(input)
        guard case .mouseDown = down.phase else {
            return XCTFail("expected mouseDown")
        }
        var up = input
        up.phase = down.phase
        up.event.kind = .leftUp
        XCTAssertEqual(SnapSessionReducer.reduce(up).phase, .idle)
    }

    func testResizeNeverArms() {
        var input = base(phase: .mouseDown(window, originAX: frame), kind: .leftDragged)
        input.downFrameAX = frame
        input.currentFrameAX = CGRect(x: 10, y: 10, width: 500, height: 300)
        input.event.modifiers = [.shift]
        XCTAssertEqual(SnapSessionReducer.reduce(input).phase, .resizing)
    }

    func testShiftArmsWhileDragging() {
        var input = base(phase: .dragging(window), kind: .flagsChanged)
        input.event.modifiers = [.shift]
        input.event.locationAppKit = CGPoint(x: 100, y: 100)
        input.workAreas = [sampleWorkArea()]
        input.resolvedZones = [
            ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 700, height: 900)),
        ]
        input.primaryFlipHeight = 900
        let out = SnapSessionReducer.reduce(input)
        XCTAssertTrue(out.effects.contains { if case .showOverlay = $0 { return true }; return false })
    }

    func testEscapeCancels() {
        let input = base(phase: .armed(window), kind: .escape)
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .idle)
        XCTAssertTrue(out.effects.contains(.cancel))
    }

    private func base(phase: SnapSessionPhase, kind: SnapMouseEvent.Kind) -> SnapReducerInput {
        SnapReducerInput(
            phase: phase,
            event: SnapMouseEvent(kind: kind, locationAppKit: CGPoint(x: 50, y: 50), modifiers: []),
            downFrameAX: frame,
            currentFrameAX: frame,
            downLocationAppKit: .zero
        )
    }

    private func sampleWorkArea() -> WorkArea {
        WorkArea(
            display: DisplayIdentity(
                localizedName: "Built-in",
                visibleWidth: 1440,
                visibleHeight: 900,
                backingScale: 2
            ),
            frameAppKit: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrameAppKit: CGRect(x: 0, y: 0, width: 1440, height: 875),
            backingScale: 2
        )
    }
}
