import XCTest
@testable import ZoneBoxCore

@MainActor
final class RuntimeOwnershipTests: XCTestCase {
    private let left = WindowIdentity(pid: 11, windowNumber: 1, bundleID: "com.example.left")
    private let right = WindowIdentity(pid: 12, windowNumber: 2, bundleID: "com.example.right")

    func testEditorModeBlocksDividerPinAndWorkspace() {
        var gate = RuntimeModeGate()
        XCTAssertTrue(gate.begin(.edit))
        XCTAssertEqual(gate.mode, .editing)
        XCTAssertFalse(gate.begin(.divide))
        XCTAssertFalse(gate.begin(.pinFollow))
        XCTAssertFalse(gate.begin(.organize))
        XCTAssertFalse(gate.begin(.snap))
        XCTAssertFalse(gate.allows(.presentDivider))
        XCTAssertFalse(gate.allows(.presentPinHover))
        XCTAssertFalse(gate.allows(.followPinnedWindows))
        XCTAssertFalse(gate.allows(.raisePinnedWindows))
        XCTAssertFalse(gate.allows(.censusWindows))
        XCTAssertFalse(gate.allows(.capturePointer))
        XCTAssertFalse(gate.allows(.mutateWindows))
    }

    func testSnapModeBlocksDividerAndPinFollow() {
        var gate = RuntimeModeGate()
        XCTAssertTrue(gate.begin(.snap))
        XCTAssertFalse(gate.begin(.divide))
        XCTAssertFalse(gate.begin(.pinFollow))
        XCTAssertFalse(gate.begin(.organize))
        XCTAssertFalse(gate.begin(.edit))
        XCTAssertFalse(gate.allows(.presentDivider))
        XCTAssertFalse(gate.allows(.presentPinHover))
        XCTAssertFalse(gate.allows(.followPinnedWindows))
        XCTAssertFalse(gate.allows(.censusWindows))
        XCTAssertTrue(gate.allows(.capturePointer))
        XCTAssertTrue(gate.allows(.mutateWindows))
    }

    func testDividerModeBlocksSnapAndCensus() {
        var gate = RuntimeModeGate()
        XCTAssertTrue(gate.begin(.divide))
        XCTAssertFalse(gate.begin(.snap))
        XCTAssertFalse(gate.allows(.capturePointer))
        XCTAssertFalse(gate.allows(.censusWindows))
        XCTAssertTrue(gate.allows(.presentDivider))
        XCTAssertTrue(gate.allows(.mutateWindows))
    }

    func testApplyKeepsLatestGeneration() async {
        let mutator = FakeWindowMutator(frames: [left: CGRect(x: 0, y: 0, width: 400, height: 300)])
        mutator.delayNanoseconds = 30_000_000
        let engine = WindowMutationEngine(mutator: mutator)
        XCTAssertTrue(engine.begin(.snap))
        let session = UUID()
        async let stale = engine.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 300),
            of: left,
            sessionID: session,
            generation: 1
        )
        try? await Task.sleep(nanoseconds: 5_000_000)
        let latest = await engine.applyFrame(
            CGRect(x: 0, y: 0, width: 500, height: 300),
            of: left,
            sessionID: session,
            generation: 2
        )
        let staleResult = await stale
        XCTAssertNil(staleResult)
        XCTAssertEqual(latest, CGRect(x: 0, y: 0, width: 500, height: 300))
        XCTAssertEqual(mutator.frame(of: left), CGRect(x: 0, y: 0, width: 500, height: 300))
        XCTAssertEqual(mutator.appliedFrames.last?.frameAX, CGRect(x: 0, y: 0, width: 500, height: 300))
    }

    func testDividerMouseUpKeepsFinalFrame() async {
        var windows = FakeWindowList(windows: [
            left: CGRect(x: 0, y: 0, width: 400, height: 800),
            right: CGRect(x: 400, y: 0, width: 400, height: 800),
        ])
        let mutator = FakeWindowMutator(frames: windows.windows)
        mutator.delayNanoseconds = 20_000_000
        let engine = WindowMutationEngine(mutator: mutator)
        XCTAssertTrue(engine.begin(.divide))
        let session = UUID()
        async let dragWrite = engine.applyFrame(
            CGRect(x: 0, y: 0, width: 360, height: 800),
            of: left,
            sessionID: session,
            generation: 1
        )
        let finalLeft = CGRect(x: 0, y: 0, width: 520, height: 800)
        let committed = await engine.applyFrame(
            finalLeft,
            of: left,
            sessionID: session,
            generation: 2
        )
        _ = await dragWrite
        windows.apply(committed ?? .zero, of: left)
        XCTAssertEqual(committed, finalLeft)
        XCTAssertEqual(windows.frame(of: left), finalLeft)
        XCTAssertEqual(mutator.frame(of: left), finalLeft)
        engine.end(.divide)
        XCTAssertEqual(engine.mode, .idle)
    }

    func testEditingBlocksMutationQueue() async {
        let mutator = FakeWindowMutator(frames: [left: CGRect(x: 0, y: 0, width: 100, height: 100)])
        let engine = WindowMutationEngine(mutator: mutator)
        XCTAssertTrue(engine.begin(.edit))
        let applied = await engine.applyFrame(
            CGRect(x: 10, y: 10, width: 200, height: 200),
            of: left,
            sessionID: UUID(),
            generation: 1
        )
        XCTAssertNil(applied)
        XCTAssertTrue(mutator.appliedFrames.isEmpty)
    }

    func testCancelledSessionDoesNotWrite() async {
        let mutator = FakeWindowMutator(frames: [left: CGRect(x: 0, y: 0, width: 100, height: 100)])
        mutator.delayNanoseconds = 40_000_000
        let engine = WindowMutationEngine(mutator: mutator)
        XCTAssertTrue(engine.begin(.snap))
        let session = UUID()
        async let write = engine.applyFrame(
            CGRect(x: 0, y: 0, width: 300, height: 100),
            of: left,
            sessionID: session,
            generation: 1
        )
        engine.cancel(sessionID: session)
        let result = await write
        XCTAssertNil(result)
    }
}
