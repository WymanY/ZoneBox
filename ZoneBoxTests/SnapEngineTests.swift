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

    func testOverlayDigitAppliesMatchingZone() {
        let zone1 = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 400, height: 800))
        let zone3 = ResolvedZone(zoneID: UUID(), number: 3, frameAX: CGRect(x: 800, y: 0, width: 400, height: 800))
        var input = overlayDigitInput(phase: .highlighting(window, .zone(zone1)), number: 3)
        input.resolvedZones = [zone1, zone3]
        input.downFrameAX = frame
        input.event.modifiers = [.shift]
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .highlighting(window, .zone(zone3)))
        XCTAssertTrue(out.effects.contains(.applyFrame(window, zone3.frameAX)))
        XCTAssertTrue(out.effects.contains(.highlight(.zone(zone3))))
        let recorded = out.effects.contains {
            if case .recordUnsnap(let record) = $0 {
                return record.identity == window
                    && record.originalFrameAX == frame
                    && record.snappedFrameAX == zone3.frameAX
                    && record.zoneIDs == [zone3.zoneID]
            }
            return false
        }
        XCTAssertTrue(recorded)
    }

    func testOverlayDigitMissingZoneIsNoOp() {
        let zone1 = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 400, height: 800))
        var input = overlayDigitInput(phase: .armed(window), number: 9)
        input.resolvedZones = [zone1]
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .armed(window))
        XCTAssertEqual(out.effects, [])
    }

    func testOverlayDigitWhileIdleOrUnarmedIsNoOp() {
        var idle = overlayDigitInput(phase: .idle, number: 1)
        idle.window = window
        idle.resolvedZones = [
            ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 400, height: 800)),
        ]
        XCTAssertEqual(SnapSessionReducer.reduce(idle).effects, [])

        var dragging = overlayDigitInput(phase: .dragging(window), number: 1)
        dragging.resolvedZones = idle.resolvedZones
        XCTAssertEqual(SnapSessionReducer.reduce(dragging).phase, .dragging(window))
        XCTAssertEqual(SnapSessionReducer.reduce(dragging).effects, [])
    }

    func testLockedDigitIgnoresLaterHover() {
        let zone1 = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 400, height: 800))
        let zone2 = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 400, height: 800))
        var input = armedReadyInput(phase: .highlighting(window, .zone(zone2)), kind: .leftDragged)
        input.resolvedZones = [zone1, zone2]
        input.lockedTarget = .zone(zone1)
        input.event.locationAppKit = CGPoint(x: 700, y: 400)
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .highlighting(window, .zone(zone1)))
        XCTAssertTrue(out.effects.contains(.highlight(.zone(zone1))))
        XCTAssertTrue(out.effects.contains(.applyFrame(window, zone1.frameAX)))
        XCTAssertFalse(out.effects.contains(.highlight(.zone(zone2))))
    }

    func testLockedDigitDropAppliesLockedZone() {
        let zone1 = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 16, y: 16, width: 400, height: 768))
        let zone2 = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 16, width: 400, height: 768))
        var input = armedReadyInput(phase: .highlighting(window, .zone(zone2)), kind: .leftUp)
        input.resolvedZones = [zone1, zone2]
        input.lockedTarget = .zone(zone1)
        input.downFrameAX = frame
        input.event.locationAppKit = CGPoint(x: 700, y: 400)
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .idle)
        XCTAssertTrue(out.effects.contains(.applyFrame(window, zone1.frameAX)))
        XCTAssertFalse(out.effects.contains(.applyFrame(window, zone2.frameAX)))
    }

    func testLockedDigitKeepsOverlayAfterShiftRelease() {
        let zone = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 400, y: 0, width: 400, height: 800))
        var input = armedReadyInput(phase: .highlighting(window, .zone(zone)), kind: .flagsChanged)
        input.resolvedZones = [zone]
        input.lockedTarget = .zone(zone)
        input.stickyArm = false
        input.event.modifiers = []
        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .highlighting(window, .zone(zone)))
        XCTAssertTrue(out.effects.contains(.highlight(.zone(zone))))
        XCTAssertFalse(out.effects.contains(.hideOverlay))
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

    func testLinearThenShakeArmsOverlay() {
        let trace = ShakeDetectorTests.appendingShake(
            ShakeDetectorTests.linearTrace(length: 400),
            amplitude: 28,
            cycles: 3
        )
        var input = armedReadyInput(phase: .dragging(window), kind: .leftDragged)
        input.pointerTrace = trace
        input.shakeToSnapEnabled = true
        input.shakeIntensity = ShakeProfile.defaultIntensity
        input.event.modifiers = []
        input.event.locationAppKit = trace.last!
        let out = SnapSessionReducer.reduce(input)
        XCTAssertTrue(out.effects.contains { if case .showOverlay = $0 { return true }; return false })
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
        input.event.modifiers = [.control]
        input.downFrameAX = frame
        let out = SnapSessionReducer.reduce(input)
        let expected = expectedGridUnion(input)
        XCTAssertNotNil(expected)
        XCTAssertTrue(out.effects.contains(.applyFrame(window, expected!)))
        XCTAssertGreaterThan(expected!.width, 900)
    }

    func testGridHoverAppliesCellUnderCursorNotArmOriginSpan() throws {
        let workAX = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let spec = GridSpec(
            rows: 1,
            columns: 2,
            rowWeights: [10_000],
            columnWeights: [5_000, 5_000],
            cellMap: [[0, 1]]
        )
        let zones = (1...2).map { Zone(number: $0) }
        let resolved = try GridResolver.resolve(spec: spec, zones: zones, workAreaAX: workAX, gutter: 16)
        let rightZone = try XCTUnwrap(resolved.first(where: { $0.number == 2 }))

        var input = armedReadyInput(phase: .highlighting(window, .none), kind: .leftUp)
        input.primaryFlipHeight = 800
        input.workAreas = [
            WorkArea(
                display: DisplayIdentity(localizedName: "Columns", visibleWidth: 1000, visibleHeight: 800, backingScale: 2),
                frameAppKit: workAX,
                visibleFrameAppKit: workAX,
                backingScale: 2
            ),
        ]
        input.resolvedZones = resolved
        input.gridCells = GridCoverage.cells(spec: spec, workAreaAX: workAX)
        input.gridGutter = 16
        input.gridWorkAreaAX = workAX
        input.armOriginAppKit = CGPoint(x: 100, y: 400)
        input.event.locationAppKit = CGPoint(x: 780, y: 400)
        input.downFrameAX = frame

        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.effects.filter {
            if case .applyFrame = $0 { return true }
            return false
        }, [.applyFrame(window, rightZone.frameAX)], "effects=\(out.effects) phase=\(out.phase) right=\(rightZone.frameAX)")
    }

    func testGridHoverHighlightUsesCellUnderCursor() throws {
        let workAX = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let spec = GridSpec(
            rows: 1,
            columns: 2,
            rowWeights: [10_000],
            columnWeights: [5_000, 5_000],
            cellMap: [[0, 1]]
        )
        let zones = (1...2).map { Zone(number: $0) }
        let resolved = try GridResolver.resolve(spec: spec, zones: zones, workAreaAX: workAX, gutter: 16)
        let rightZone = try XCTUnwrap(resolved.first(where: { $0.number == 2 }))

        var input = armedReadyInput(phase: .armed(window), kind: .leftDragged)
        input.primaryFlipHeight = 800
        input.workAreas = [
            WorkArea(
                display: DisplayIdentity(localizedName: "Columns", visibleWidth: 1000, visibleHeight: 800, backingScale: 2),
                frameAppKit: workAX,
                visibleFrameAppKit: workAX,
                backingScale: 2
            ),
        ]
        input.resolvedZones = resolved
        input.gridCells = GridCoverage.cells(spec: spec, workAreaAX: workAX)
        input.gridGutter = 16
        input.gridWorkAreaAX = workAX
        input.armOriginAppKit = CGPoint(x: 100, y: 400)
        input.event.locationAppKit = CGPoint(x: 780, y: 400)

        let out = SnapSessionReducer.reduce(input)
        XCTAssertEqual(out.phase, .highlighting(window, .zone(rightZone)), "effects=\(out.effects)")
        XCTAssertTrue(out.effects.contains(.highlight(.zone(rightZone))), "effects=\(out.effects)")
    }

    func testGridControlDragSpansAdjacentZones() throws {
        let workAX = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let spec = GridSpec(
            rows: 1,
            columns: 2,
            rowWeights: [10_000],
            columnWeights: [5_000, 5_000],
            cellMap: [[0, 1]]
        )
        let zones = (1...2).map { Zone(number: $0) }
        let resolved = try GridResolver.resolve(spec: spec, zones: zones, workAreaAX: workAX, gutter: 16)
        let expected = try XCTUnwrap(
            GridCoverage.unionFrameAX(
                dragRectAX: CGRect(x: 100, y: 400, width: 680, height: 0),
                cells: GridCoverage.cells(spec: spec, workAreaAX: workAX),
                gutter: 16,
                workAreaAX: workAX
            )
        )

        var input = armedReadyInput(phase: .highlighting(window, .none), kind: .leftUp)
        input.primaryFlipHeight = 800
        input.workAreas = [
            WorkArea(
                display: DisplayIdentity(localizedName: "Columns", visibleWidth: 1000, visibleHeight: 800, backingScale: 2),
                frameAppKit: workAX,
                visibleFrameAppKit: workAX,
                backingScale: 2
            ),
        ]
        input.resolvedZones = resolved
        input.gridCells = GridCoverage.cells(spec: spec, workAreaAX: workAX)
        input.gridGutter = 16
        input.gridWorkAreaAX = workAX
        input.armOriginAppKit = CGPoint(x: 100, y: 400)
        input.event.locationAppKit = CGPoint(x: 780, y: 400)
        input.event.modifiers = [.control]
        input.downFrameAX = frame

        let out = SnapSessionReducer.reduce(input)
        XCTAssertTrue(out.effects.contains(.applyFrame(window, expected)), "effects=\(out.effects) expected=\(expected)")
    }

    func testGridDragInsideMergedZoneAppliesCompleteLayoutZone() throws {
        let workAX = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let spec = GridSpec(
            rows: 2,
            columns: 2,
            rowWeights: [5_000, 5_000],
            columnWeights: [5_000, 5_000],
            cellMap: [[0, 1], [0, 2]]
        )
        let zones = (1...3).map { Zone(number: $0) }
        let resolved = try GridResolver.resolve(spec: spec, zones: zones, workAreaAX: workAX, gutter: 16)
        let leftZone = try XCTUnwrap(resolved.first(where: { $0.number == 1 }))

        var input = armedReadyInput(phase: .highlighting(window, .zone(leftZone)), kind: .leftUp)
        input.primaryFlipHeight = 800
        input.workAreas = [
            WorkArea(
                display: DisplayIdentity(localizedName: "Priority Grid", visibleWidth: 1000, visibleHeight: 800, backingScale: 2),
                frameAppKit: workAX,
                visibleFrameAppKit: workAX,
                backingScale: 2
            ),
        ]
        input.resolvedZones = resolved
        input.gridCells = GridCoverage.cells(spec: spec, workAreaAX: workAX)
        input.gridGutter = 16
        input.gridWorkAreaAX = workAX
        input.armOriginAppKit = CGPoint(x: 100, y: 700)
        input.event.locationAppKit = CGPoint(x: 180, y: 620)
        input.downFrameAX = frame

        let out = SnapSessionReducer.reduce(input)

        XCTAssertTrue(out.effects.contains(.applyFrame(window, leftZone.frameAX)))
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

    private func overlayDigitInput(phase: SnapSessionPhase, number: Int) -> SnapReducerInput {
        var input = armedReadyInput(phase: phase, kind: .digit(number))
        input.event.locationAppKit = CGPoint(x: 100, y: 100)
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

final class DisplayTargetResolverTests: XCTestCase {
    private let leftID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let rightID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let upperID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!

    func testWindowUsesDisplayWithLargestIntersection() throws {
        let target = try XCTUnwrap(
            DisplayTargetResolver.workArea(
                containingWindowFrameAX: CGRect(x: 80, y: 10, width: 80, height: 80),
                from: workAreas,
                primaryFlipHeight: 100
            )
        )

        XCTAssertEqual(target.display.id, rightID)
    }

    func testEvenlySpanningWindowIsAmbiguous() {
        let target = DisplayTargetResolver.workArea(
            containingWindowFrameAX: CGRect(x: 50, y: 10, width: 100, height: 80),
            from: workAreas,
            primaryFlipHeight: 100
        )

        XCTAssertNil(target)
    }

    func testDisplayAbovePrimaryUsesAXCoordinateSpace() throws {
        let upper = area(
            id: upperID,
            name: "Upper",
            frame: CGRect(x: 0, y: 100, width: 100, height: 100)
        )
        let target = try XCTUnwrap(
            DisplayTargetResolver.workArea(
                containingWindowFrameAX: CGRect(x: 10, y: -90, width: 60, height: 60),
                from: [workAreas[0], upper],
                primaryFlipHeight: 100
            )
        )

        XCTAssertEqual(target.display.id, upperID)
    }

    func testOffscreenWindowDoesNotFallBackToFirstDisplay() {
        let target = DisplayTargetResolver.workArea(
            containingWindowFrameAX: CGRect(x: 300, y: 10, width: 50, height: 50),
            from: workAreas,
            primaryFlipHeight: 100
        )

        XCTAssertNil(target)
    }

    func testMissingDisplaysFailClosed() {
        let target = DisplayTargetResolver.workArea(
            containingWindowFrameAX: CGRect(x: 10, y: 10, width: 50, height: 50),
            from: [],
            primaryFlipHeight: 100
        )

        XCTAssertNil(target)
    }

    private var workAreas: [WorkArea] {
        [
            area(id: leftID, name: "Left", frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            area(id: rightID, name: "Right", frame: CGRect(x: 100, y: 0, width: 100, height: 100)),
        ]
    }

    private func area(id: UUID, name: String, frame: CGRect) -> WorkArea {
        WorkArea(
            display: DisplayIdentity(
                id: id,
                localizedName: name,
                visibleWidth: frame.width,
                visibleHeight: frame.height,
                backingScale: 1
            ),
            frameAppKit: frame,
            visibleFrameAppKit: frame,
            backingScale: 1
        )
    }
}
