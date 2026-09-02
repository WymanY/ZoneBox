import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class ZonePixelMetricsTests: XCTestCase {
    private let work = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testPixelSizeRoundsWorkAreaRect() {
        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.25, height: 0.4)
        let pixels = ZonePixelMetrics.pixelSize(of: rect, workAreaAX: work)
        XCTAssertEqual(pixels.width, 250)
        XCTAssertEqual(pixels.height, 320)
    }

    func testResizingWidthKeepsOriginWhenUnlocked() {
        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.2, height: 0.25)
        let next = ZonePixelMetrics.resizing(rect, toWidth: 400, height: nil, workAreaAX: work, lockAspect: false)
        let pixels = ZonePixelMetrics.pixelSize(of: next, workAreaAX: work)
        XCTAssertEqual(pixels.width, 400)
        XCTAssertEqual(pixels.height, 200)
        XCTAssertEqual(next.x, rect.x, accuracy: 0.0001)
        XCTAssertEqual(next.y, rect.y, accuracy: 0.0001)
    }

    func testLockingAspectAdjustsHeightFromWidth() {
        let rect = NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)
        let next = ZonePixelMetrics.resizing(rect, toWidth: 400, height: nil, workAreaAX: work, lockAspect: true)
        let pixels = ZonePixelMetrics.pixelSize(of: next, workAreaAX: work)
        XCTAssertEqual(pixels.width, 400)
        XCTAssertEqual(pixels.height, 160)
    }

    func testLockedFieldsKeepUnchangedSideNil() {
        let current = ZonePixelSize(width: 200, height: 100)
        let widthOnly = ZonePixelMetrics.lockedFields(current: current, width: 400, height: 100, lockAspect: true)
        XCTAssertEqual(widthOnly.width, 400)
        XCTAssertNil(widthOnly.height)

        let heightOnly = ZonePixelMetrics.lockedFields(current: current, width: 200, height: 80, lockAspect: true)
        XCTAssertNil(heightOnly.width)
        XCTAssertEqual(heightOnly.height, 80)

        let unlocked = ZonePixelMetrics.lockedFields(current: current, width: 400, height: 100, lockAspect: false)
        XCTAssertEqual(unlocked.width, 400)
        XCTAssertEqual(unlocked.height, 100)
    }

    func testPreservingAspectUsesWidthWhenDraggingEast() {
        let start = NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)
        let resized = NormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.1)
        let next = ZonePixelMetrics.preservingAspect(from: start, resized: resized, usingWidth: true)
        XCTAssertEqual(next.width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(next.height, 0.2, accuracy: 0.0001)
        XCTAssertEqual(next.x, start.x, accuracy: 0.0001)
        XCTAssertEqual(next.y, start.y, accuracy: 0.0001)
    }

    func testApplyingSixteenByNineShrinksToFit() {
        let rect = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let next = ZonePixelMetrics.applying(aspect: .wide16x9, to: rect, workAreaAX: work)
        let pixels = ZonePixelMetrics.pixelSize(of: next, workAreaAX: work)
        XCTAssertEqual(Double(pixels.width) / Double(pixels.height), 16.0 / 9.0, accuracy: 0.02)
        XCTAssertLessThanOrEqual(pixels.width, 500)
        XCTAssertLessThanOrEqual(pixels.height, 400)
    }

    func testPixelResizeClampsToWorkArea() {
        let rect = NormalizedRect(x: 0.8, y: 0.8, width: 0.15, height: 0.15)
        let next = ZonePixelMetrics.resizing(rect, toWidth: 900, height: 700, workAreaAX: work, lockAspect: false)
        let frame = next.denormalize(in: work)
        XCTAssertLessThanOrEqual(frame.maxX, work.maxX + 0.6)
        XCTAssertLessThanOrEqual(frame.maxY, work.maxY + 0.6)
        XCTAssertGreaterThanOrEqual(frame.minX, work.minX - 0.6)
        XCTAssertGreaterThanOrEqual(frame.minY, work.minY - 0.6)
    }

    func testMovingClampsAndLeavesUnspecifiedAxis() {
        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.2, height: 0.2)
        let movedX = ZonePixelMetrics.moving(rect, toX: -40, y: nil, workAreaAX: work)
        XCTAssertEqual(movedX.x, 0, accuracy: 0.0001)
        XCTAssertEqual(movedX.y, rect.y, accuracy: 0.0001)

        let movedY = ZonePixelMetrics.moving(rect, toX: nil, y: 900, workAreaAX: work)
        XCTAssertEqual(movedY.x, rect.x, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(movedY.maxY, 1.0001)

        let both = ZonePixelMetrics.moving(rect, toX: 100, y: 80, workAreaAX: work)
        let origin = ZonePixelMetrics.origin(of: both, workAreaAX: work)
        XCTAssertEqual(origin.x, 100)
        XCTAssertEqual(origin.y, 80)
    }

}
