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

    func testShakeTraceArmsOverlayWithoutShift() {
        var input = armedReadyInput(phase: .dragging(window), kind: .leftDragged)
        input.pointerTrace = ShakeDetectorTests.shakeTrace()
        input.shakeToSnapEnabled = true
        input.event.modifiers = []
        input.event.locationAppKit = ShakeDetectorTests.shakeTrace().last!
        let out = SnapSessionReducer.reduce(input)
        XCTAssertTrue(out.effects.contains { if case .showOverlay = $0 { return true }; return false })
        switch out.phase {
        case .armed, .highlighting:
            break
        default:
            XCTFail("expected armed/highlighting, got \(out.phase)")
        }
    }

    func testLinearTraceDoesNotArmWithoutShift() {
        var input = armedReadyInput(phase: .dragging(window), kind: .leftDragged)
        input.pointerTrace = ShakeDetectorTests.linearTrace(length: 640)
        input.shakeToSnapEnabled = true
        input.event.modifiers = []
        input.event.locationAppKit = ShakeDetectorTests.linearTrace(length: 640).last!
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .dragging(window))
        XCTAssertFalse(out.effects.contains { if case .showOverlay = $0 { return true }; return false })
    }

    func testShakeArmedDropAppliesZoneFrame() {
        let zone = ResolvedZone(
            zoneID: UUID(),
            number: 1,
            frameAX: CGRect(x: 16, y: 16, width: 668, height: 768)
        )
        var input = armedReadyInput(phase: .highlighting(window, .zone(zone)), kind: .leftUp)
        input.resolvedZones = [zone]
        input.event.locationAppKit = CoordinateConverter.appKitPoint(
            fromAX: CGPoint(x: 100, y: 100),
            primaryFlipHeight: input.primaryFlipHeight
        )
        input.downFrameAX = frame
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .idle)
        XCTAssertTrue(out.effects.contains(.applyFrame(window, zone.frameAX)))
        XCTAssertTrue(out.effects.contains(.hideOverlay))
    }

    func testGridDrawCoversOneCell() {
        let coverage = sampleGrid()
        var input = armedReadyInput(phase: .highlighting(window, .none), kind: .leftUp)
        input.primaryFlipHeight = 875
        input.gridCells = coverage.cells
        input.gridGutter = coverage.gutter
        input.gridWorkAreaAX = coverage.workAX
        input.armOriginAppKit = CGPoint(x: 80, y: 700)
        input.event.locationAppKit = CGPoint(x: 180, y: 620)
        input.downFrameAX = frame
        let out = SnapSessionReducer.reduce(input)
        let expected = expectedGridUnion(input)
        XCTAssertNotNil(expected)
        XCTAssertTrue(out.effects.contains(.applyFrame(window, expected!)))
    }

    func testGridDrawCoversTwoCellSpan() {
        let coverage = sampleGrid()
        var input = armedReadyInput(phase: .highlighting(window, .none), kind: .leftUp)
        input.primaryFlipHeight = 875
        input.gridCells = coverage.cells
        input.gridGutter = coverage.gutter
        input.gridWorkAreaAX = coverage.workAX
        input.armOriginAppKit = CGPoint(x: 80, y: 700)
        input.event.locationAppKit = CGPoint(x: 900, y: 620)
        input.downFrameAX = frame
        let out = SnapSessionReducer.reduce(input)
        let expected = expectedGridUnion(input)
        XCTAssertNotNil(expected)
        XCTAssertTrue(out.effects.contains(.applyFrame(window, expected!)))
        XCTAssertGreaterThan(expected!.width, 900)
    }

    func testGridZeroAreaOutsideCellsDoesNotSnap() {
        let coverage = sampleGrid()
        var input = armedReadyInput(phase: .highlighting(window, .none), kind: .leftUp)
        input.primaryFlipHeight = 875
        input.gridCells = coverage.cells
        input.gridGutter = coverage.gutter
        input.gridWorkAreaAX = coverage.workAX
        input.armOriginAppKit = CGPoint(x: 1800, y: 20)
        input.event.locationAppKit = CGPoint(x: 1900, y: 80)
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .idle)
        XCTAssertFalse(out.effects.contains { if case .applyFrame = $0 { return true }; return false })
        XCTAssertTrue(out.effects.contains(.hideOverlay))
    }

    func testMagneticResizeOnMouseUpNearEdge() {
        let zone = ResolvedZone(
            zoneID: UUID(),
            number: 1,
            frameAX: CGRect(x: 0, y: 0, width: 500, height: 800)
        )
        var input = armedReadyInput(phase: .resizing, kind: .leftUp)
        input.window = window
        input.workAreas = []
        input.downFrameAX = CGRect(x: 100, y: 100, width: 300, height: 300)
        input.currentFrameAX = CGRect(x: 100, y: 100, width: 405, height: 300)
        input.resolvedZones = [zone]
        input.magneticResizeEnabled = true
        input.magneticThreshold = 12
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .idle)
        let snapped = MagneticResize.snap(
            original: input.downFrameAX!,
            current: input.currentFrameAX!,
            zoneFramesAX: [zone.frameAX],
            threshold: 12
        )
        XCTAssertTrue(out.effects.contains(.applyFrame(window, snapped)))
        XCTAssertFalse(out.effects.contains { if case .showOverlay = $0 { return true }; return false })
    }

    func testMagneticResizeFarEdgeKeepsUserFrame() {
        let zone = ResolvedZone(
            zoneID: UUID(),
            number: 1,
            frameAX: CGRect(x: 0, y: 0, width: 500, height: 800)
        )
        var input = armedReadyInput(phase: .resizing, kind: .leftUp)
        input.window = window
        input.workAreas = []
        input.downFrameAX = CGRect(x: 100, y: 100, width: 300, height: 300)
        input.currentFrameAX = CGRect(x: 100, y: 100, width: 450, height: 300)
        input.resolvedZones = [zone]
        input.magneticResizeEnabled = true
        let out = SnapSessionReducer.reduce(input)
        XCTAssertFalse(out.effects.contains { if case .applyFrame = $0 { return true }; return false })
    }

    func testResizeWithShiftStillDoesNotArmOverlay() {
        var input = base(phase: .mouseDown(window, originAX: frame), kind: .leftDragged)
        input.downFrameAX = frame
        input.currentFrameAX = CGRect(x: 10, y: 10, width: 500, height: 300)
        input.event.modifiers = [.shift]
        input.pointerTrace = ShakeDetectorTests.shakeTrace()
        input.shakeToSnapEnabled = true
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .resizing)
        XCTAssertFalse(out.effects.contains { if case .showOverlay = $0 { return true }; return false })
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

    private func armedReadyInput(phase: SnapSessionPhase, kind: SnapMouseEvent.Kind) -> SnapReducerInput {
        var input = base(phase: phase, kind: kind)
        input.workAreas = [sampleWorkArea()]
        input.resolvedZones = [
            ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 16, y: 16, width: 668, height: 768)),
        ]
        input.primaryFlipHeight = 900
        return input
    }

    private func expectedGridUnion(_ input: SnapReducerInput) -> CGRect? {
        guard let origin = input.armOriginAppKit else { return nil }
        let originAX = CoordinateConverter.axPoint(
            fromAppKit: origin,
            primaryFlipHeight: input.primaryFlipHeight
        )
        let currentAX = CoordinateConverter.axPoint(
            fromAppKit: input.event.locationAppKit,
            primaryFlipHeight: input.primaryFlipHeight
        )
        let drag = CGRect(
            x: min(originAX.x, currentAX.x),
            y: min(originAX.y, currentAX.y),
            width: abs(currentAX.x - originAX.x),
            height: abs(currentAX.y - originAX.y)
        )
        return GridCoverage.unionFrameAX(
            dragRectAX: drag,
            cells: input.gridCells,
            gutter: input.gridGutter,
            workAreaAX: input.gridWorkAreaAX
        )
    }

    private func sampleGrid() -> (cells: [GridCell], gutter: CGFloat, workAX: CGRect) {
        let workAX = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let spec = GridSpec(
            rows: 1,
            columns: 2,
            rowWeights: [10_000],
            columnWeights: [5_000, 5_000],
            cellMap: [[0, 1]]
        )
        return (GridCoverage.cells(spec: spec, workAreaAX: workAX), 16, workAX)
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
