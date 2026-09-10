import XCTest
@testable import ZoneBoxCore

final class AXFrameMutationTests: XCTestCase {
    func testMatchingWindowConfirmsAfterShortDelay() {
        let start = CGRect(x: 10, y: 20, width: 300, height: 200)
        let target = CGRect(x: 40, y: 80, width: 500, height: 320)
        let writer = FakeAXFrameWriter(frame: start)
        let actual = AXFrameMutation.apply(target, using: writer)
        XCTAssertEqual(actual, target)
        XCTAssertEqual(writer.sizeWriteCount, 2)
        XCTAssertEqual(writer.pointWriteCount, 1)
        XCTAssertEqual(writer.sleeps, [AXFrameMutation.fastRetryDelay])
    }

    func testImmediateMatchThatRecentersStillSettlesOrigin() {
        let start = CGRect(x: 296, y: -855, width: 1411, height: 839)
        let target = CGRect(x: -21, y: -944, width: 1536, height: 839)
        let recentered = CGPoint(x: 255, y: -866)
        let writer = FakeAXFrameWriter(frame: start, recenterOnSleep: recentered)
        let actual = AXFrameMutation.apply(target, using: writer)
        XCTAssertEqual(actual?.origin, target.origin)
        XCTAssertEqual(actual?.size, target.size)
        XCTAssertTrue(writer.sleeps.contains(AXFrameMutation.settleDelay))
        XCTAssertEqual(writer.frame.origin, target.origin)
    }

    func testSizeWriteDriftsOriginUntilSettleSetsPointLast() {
        let start = CGRect(x: 296, y: -855, width: 1411, height: 839)
        let target = CGRect(x: -21, y: -944, width: 1536, height: 839)
        let drifted = CGPoint(x: 255, y: -866)
        let writer = FakeAXFrameWriter(frame: start, driftOnSize: drifted)
        let actual = AXFrameMutation.apply(target, using: writer)
        XCTAssertEqual(actual?.origin, target.origin)
        XCTAssertEqual(actual?.size, target.size)
        XCTAssertEqual(writer.sleeps.first, AXFrameMutation.fastRetryDelay)
        XCTAssertEqual(writer.sleeps.last, AXFrameMutation.settleDelay)
        XCTAssertEqual(writer.pointWriteCount, AXFrameMutation.fastRetryLimit + 1)
        XCTAssertEqual(writer.frame.origin, target.origin)
    }

    func testSettleRetriesSizeWhenFastWritesAreIgnored() {
        let start = CGRect(x: 296, y: -855, width: 1411, height: 839)
        let target = CGRect(x: -213, y: -520, width: 955, height: 520)
        let writer = FakeAXFrameWriter(
            frame: start,
            driftOnSize: CGPoint(x: 590, y: -985),
            ignoreSizeUntilElapsed: AXFrameMutation.settleDelay
        )
        let actual = AXFrameMutation.apply(target, using: writer)
        XCTAssertEqual(actual?.origin, target.origin)
        XCTAssertEqual(actual?.size, target.size)
        XCTAssertTrue(writer.sleeps.contains(AXFrameMutation.settleDelay))
        XCTAssertTrue(writer.sleeps.contains(AXFrameMutation.originRetryDelay))
    }

    func testMinSizeIsHonored() {
        let writer = FakeAXFrameWriter(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let actual = AXFrameMutation.apply(
            CGRect(x: 10, y: 10, width: 100, height: 80),
            minSize: CGSize(width: 400, height: 300),
            using: writer
        )
        XCTAssertEqual(actual, CGRect(x: 10, y: 10, width: 400, height: 300))
        XCTAssertEqual(writer.sleeps, [AXFrameMutation.fastRetryDelay])
    }
}

private final class FakeAXFrameWriter: AXFrameWriting {
    var frame: CGRect
    var sleeps: [TimeInterval] = []
    var sizeWriteCount = 0
    var pointWriteCount = 0
    private let driftOnSize: CGPoint?
    private let recenterOnSleep: CGPoint?
    private let ignoreSizeUntilElapsed: TimeInterval
    private var elapsed: TimeInterval = 0

    init(
        frame: CGRect,
        driftOnSize: CGPoint? = nil,
        recenterOnSleep: CGPoint? = nil,
        ignoreSizeUntilElapsed: TimeInterval = 0
    ) {
        self.frame = frame
        self.driftOnSize = driftOnSize
        self.recenterOnSleep = recenterOnSleep
        self.ignoreSizeUntilElapsed = ignoreSizeUntilElapsed
    }

    func readFrame() -> CGRect? {
        frame
    }

    func setSize(_ size: CGSize) {
        sizeWriteCount += 1
        if ignoreSizeUntilElapsed > 0, elapsed < ignoreSizeUntilElapsed {
            return
        }
        frame.size = size
        if let driftOnSize {
            frame.origin = driftOnSize
        }
    }

    func setPoint(_ origin: CGPoint) {
        pointWriteCount += 1
        frame.origin = origin
    }

    func sleep(_ duration: TimeInterval) {
        sleeps.append(duration)
        elapsed += duration
        if let recenterOnSleep {
            frame.origin = recenterOnSleep
        }
    }
}
