import XCTest
@testable import ZoneBoxCore

final class OwnWindowFrameMutationTests: XCTestCase {
    func testOwnProcessUsesMainThreadAppKit() {
        XCTAssertTrue(OwnWindowFrameMutation.usesMainThreadAppKit(pid: 99, ownPID: 99))
        XCTAssertFalse(OwnWindowFrameMutation.usesMainThreadAppKit(pid: 42, ownPID: 99))
    }

    func testNegativeAppKitWindowNumberDoesNotConvert() {
        XCTAssertNil(OwnWindowFrameMutation.cgWindowID(fromAppKitWindowNumber: -1))
    }

    func testValidAppKitWindowNumberConverts() {
        XCTAssertEqual(OwnWindowFrameMutation.cgWindowID(fromAppKitWindowNumber: 42), 42)
    }

    func testAppKitFrameFlipsAXOrigin() {
        let ax = CGRect(x: 100, y: 50, width: 400, height: 300)
        XCTAssertEqual(
            OwnWindowFrameMutation.appKitFrame(fromAX: ax, primaryFlipHeight: 900),
            CGRect(x: 100, y: 550, width: 400, height: 300)
        )
    }

    func testFixedSizeWindowKeepsAppliedLimits() {
        let applied = CGSize(width: 400, height: 300)
        let limits = OwnWindowFrameMutation.sizeLimits(
            applied: applied,
            previousMin: CGSize(width: 760, height: 560),
            previousMax: CGSize(width: 760, height: 560)
        )
        XCTAssertEqual(limits.min, applied)
        XCTAssertEqual(limits.max, applied)
    }

    func testFlexibleWindowKeepsExistingLimits() {
        let applied = CGSize(width: 400, height: 300)
        let minSize = CGSize(width: 200, height: 150)
        let maxSize = CGSize(width: 2000, height: 1500)
        let limits = OwnWindowFrameMutation.sizeLimits(
            applied: applied,
            previousMin: minSize,
            previousMax: maxSize
        )
        XCTAssertEqual(limits.min, minSize)
        XCTAssertEqual(limits.max, maxSize)
    }
}
