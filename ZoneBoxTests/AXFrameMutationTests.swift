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
        XCTAssertEqual(
            AXFrameMutation.outcome(actual: actual, requested: CGRect(x: 10, y: 10, width: 100, height: 80)),
            .sizeLimited
        )
    }

    func testUnadvertisedSizeLimitReturnsActualFrameAndReportsPartialSnap() {
        let target = CGRect(x: 0, y: 31, width: 771, height: 869)
        let writer = FakeAXFrameWriter(
            frame: CGRect(x: 57, y: 89, width: 1100, height: 782),
            minimumSize: CGSize(width: 1100, height: 0)
        )
        let actual = AXFrameMutation.apply(target, using: writer)
        XCTAssertEqual(actual, CGRect(x: 0, y: 31, width: 1100, height: 869))
        XCTAssertEqual(AXFrameMutation.outcome(actual: actual, requested: target), .sizeLimited)
        XCTAssertLessThanOrEqual(writer.sizeWriteCount, AXFrameMutation.fastRetryLimit * 2 + 1)
    }

    func testUnadvertisedMinWidthFitsRightZoneOntoWorkArea() {
        let requested = CGRect(x: 772.984, y: 31, width: 667.016, height: 869)
        let bounds = CGRect(x: 0, y: 31, width: 1440, height: 869)
        let writer = FakeAXFrameWriter(
            frame: CGRect(x: 0, y: 31, width: 1100, height: 869),
            minimumSize: CGSize(width: 1100, height: 0)
        )
        let actual = AXFrameMutation.apply(requested, bounds: bounds, using: writer)
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual!.width, 1100, accuracy: 0.5)
        XCTAssertEqual(actual!.height, 869, accuracy: 0.5)
        XCTAssertEqual(actual!.minX, 340, accuracy: 1)
        XCTAssertEqual(actual!.minY, 31, accuracy: 1)
        XCTAssertLessThanOrEqual(actual!.maxX, bounds.maxX + 1)
        XCTAssertEqual(AXFrameMutation.outcome(actual: actual, requested: requested), .sizeLimited)
    }

    func testUnadvertisedMinHeightFitsBottomZoneAndKeepsRequestedWidth() {
        let requested = CGRect(x: 0, y: 611.3623, width: 1440, height: 288.6377)
        let bounds = CGRect(x: 0, y: 31, width: 1440, height: 869)
        let writer = FakeAXFrameWriter(
            frame: CGRect(x: 0, y: 31, width: 1100, height: 869),
            minimumSize: CGSize(width: 0, height: 600)
        )
        let actual = AXFrameMutation.apply(requested, bounds: bounds, using: writer)
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual!.width, 1440, accuracy: 1)
        XCTAssertEqual(actual!.height, 600, accuracy: 0.5)
        XCTAssertEqual(actual!.minX, 0, accuracy: 1)
        XCTAssertEqual(actual!.minY, 300, accuracy: 1)
        XCTAssertLessThanOrEqual(actual!.maxY, bounds.maxY + 1)
        XCTAssertEqual(AXFrameMutation.outcome(actual: actual, requested: requested), .sizeLimited)
    }

    func testFittedKeepsRequestedOriginWhenAllowedSizeFitsTheZone() {
        let requested = CGRect(x: 100, y: 40, width: 500, height: 400)
        let bounds = CGRect(x: 0, y: 31, width: 1440, height: 869)
        XCTAssertEqual(
            AXFrameMutation.fitted(requested: requested, size: requested.size, bounds: bounds),
            requested
        )
    }

    func testApplyPreservesPartiallyOffscreenExactSizeEvenWhenBoundsArePassed() {
        let requested = CGRect(x: -80, y: 40, width: 400, height: 300)
        let bounds = CGRect(x: 0, y: 31, width: 1440, height: 869)
        let writer = FakeAXFrameWriter(frame: CGRect(x: 200, y: 100, width: 400, height: 300))
        let actual = AXFrameMutation.apply(requested, bounds: bounds, using: writer)
        XCTAssertEqual(actual, requested)
        XCTAssertEqual(AXFrameMutation.outcome(actual: actual, requested: requested), .applied)
    }

    func testApplyPreservesSpanningExactSizeEvenWhenBoundsArePassed() {
        let requested = CGRect(x: 1000, y: 31, width: 800, height: 500)
        let bounds = CGRect(x: 0, y: 31, width: 1440, height: 869)
        let writer = FakeAXFrameWriter(frame: CGRect(x: 100, y: 31, width: 800, height: 500))
        let actual = AXFrameMutation.apply(requested, bounds: bounds, using: writer)
        XCTAssertEqual(actual, requested)
        XCTAssertEqual(AXFrameMutation.outcome(actual: actual, requested: requested), .applied)
    }

    func testMinLargerThanScreenKeepsActualSizeAndAnchorsTopLeft() {
        let requested = CGRect(x: 773, y: 31, width: 667, height: 869)
        let bounds = CGRect(x: 0, y: 31, width: 1440, height: 869)
        let allowed = CGSize(width: 1600, height: 869)
        let fitted = AXFrameMutation.fitted(requested: requested, size: allowed, bounds: bounds)
        XCTAssertEqual(fitted.width, 1600)
        XCTAssertEqual(fitted.height, 869)
        XCTAssertEqual(fitted.origin, CGPoint(x: 0, y: 31))

        let writer = FakeAXFrameWriter(
            frame: CGRect(x: 200, y: 100, width: 1600, height: 869),
            minimumSize: allowed
        )
        let actual = AXFrameMutation.apply(requested, bounds: bounds, using: writer)
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual!.width, 1600, accuracy: 0.5)
        XCTAssertEqual(actual!.height, 869, accuracy: 0.5)
        XCTAssertEqual(actual!.minX, 0, accuracy: 1)
        XCTAssertEqual(actual!.minY, 31, accuracy: 1)
        XCTAssertEqual(AXFrameMutation.outcome(actual: actual, requested: requested), .sizeLimited)
    }

    func testEffectiveSizeRetriesIgnoredWidthIncreaseAndKeepsDiscoveredMinHeight() {
        XCTAssertEqual(
            AXFrameMutation.effectiveSize(
                requested: CGSize(width: 1440, height: 289),
                start: CGSize(width: 1100, height: 869),
                actual: CGSize(width: 1440, height: 600)
            ),
            CGSize(width: 1440, height: 600)
        )
        XCTAssertEqual(
            AXFrameMutation.effectiveSize(
                requested: CGSize(width: 1440, height: 289),
                start: CGSize(width: 1100, height: 869),
                actual: CGSize(width: 1100, height: 600)
            ),
            CGSize(width: 1440, height: 600)
        )
    }

    func testSnapOutcomeAllowsPixelRoundingButReportsSizeOrPositionMismatch() {
        let target = CGRect(x: 0, y: 31, width: 770.984, height: 869)
        XCTAssertEqual(
            AXFrameMutation.outcome(actual: CGRect(x: 1, y: 32, width: 771, height: 868), requested: target),
            .applied
        )
        XCTAssertEqual(
            AXFrameMutation.outcome(actual: CGRect(x: 0, y: 31, width: 771, height: 819), requested: target),
            .sizeLimited
        )
        XCTAssertEqual(AXFrameMutation.outcome(actual: target.offsetBy(dx: 20, dy: 0), requested: target), .positionLimited)
        XCTAssertEqual(AXFrameMutation.outcome(actual: nil, requested: target), .unavailable)
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
    private let minimumSize: CGSize
    private var elapsed: TimeInterval = 0

    init(
        frame: CGRect,
        driftOnSize: CGPoint? = nil,
        recenterOnSleep: CGPoint? = nil,
        ignoreSizeUntilElapsed: TimeInterval = 0,
        minimumSize: CGSize = .zero
    ) {
        self.frame = frame
        self.driftOnSize = driftOnSize
        self.recenterOnSleep = recenterOnSleep
        self.ignoreSizeUntilElapsed = ignoreSizeUntilElapsed
        self.minimumSize = minimumSize
    }

    func readFrame() -> CGRect? {
        frame
    }

    func setSize(_ size: CGSize) {
        sizeWriteCount += 1
        if ignoreSizeUntilElapsed > 0, elapsed < ignoreSizeUntilElapsed {
            return
        }
        frame.size = CGSize(width: max(size.width, minimumSize.width), height: max(size.height, minimumSize.height))
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
