import XCTest
@testable import ZoneBoxCore

final class CoordinateConverterTests: XCTestCase {
    func testA_primaryOnly() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let h = CoordinateConverter.primaryFlipHeight(screenFramesAppKit: [primary])
        XCTAssertEqual(h, 900)
        XCTAssertEqual(
            CoordinateConverter.axPoint(fromAppKit: CGPoint(x: 100, y: 100), primaryFlipHeight: h),
            CGPoint(x: 100, y: 800)
        )
        XCTAssertEqual(
            CoordinateConverter.axRect(fromAppKit: primary, primaryFlipHeight: h),
            CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let visible = CGRect(x: 0, y: 80, width: 1440, height: 795)
        XCTAssertEqual(
            CoordinateConverter.axRect(fromAppKit: visible, primaryFlipHeight: h),
            CGRect(x: 0, y: 25, width: 1440, height: 795)
        )
    }

    func testB_externalLeft() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let h = CoordinateConverter.primaryFlipHeight(screenFramesAppKit: [primary, external])
        XCTAssertEqual(h, 900)
        XCTAssertEqual(
            CoordinateConverter.axPoint(fromAppKit: CGPoint(x: -1920, y: 0), primaryFlipHeight: h),
            CGPoint(x: -1920, y: 900)
        )
        XCTAssertEqual(
            CoordinateConverter.axPoint(fromAppKit: CGPoint(x: -1920, y: 1080), primaryFlipHeight: h),
            CGPoint(x: -1920, y: -180)
        )
    }

    func testC_externalAbove_notBoundingBox() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: 0, y: 900, width: 1440, height: 900)
        let h = CoordinateConverter.primaryFlipHeight(screenFramesAppKit: [primary, external])
        XCTAssertEqual(h, 900)
        XCTAssertEqual(
            CoordinateConverter.axPoint(fromAppKit: CGPoint(x: 0, y: 1800), primaryFlipHeight: h),
            CGPoint(x: 0, y: -900)
        )
        let naive = 1800 - 1800
        XCTAssertNotEqual(naive, -900)
    }

    func testD_notch() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 945)
        let h = CoordinateConverter.primaryFlipHeight(screenFramesAppKit: [frame])
        XCTAssertEqual(h, 982)
        XCTAssertEqual(
            CoordinateConverter.axRect(fromAppKit: visible, primaryFlipHeight: h),
            CGRect(x: 0, y: 37, width: 1512, height: 945)
        )
    }

    func testE_dockLeft() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 80, y: 0, width: 1360, height: 875)
        let h = CoordinateConverter.primaryFlipHeight(screenFramesAppKit: [frame])
        XCTAssertEqual(
            CoordinateConverter.axRect(fromAppKit: visible, primaryFlipHeight: h),
            CGRect(x: 80, y: 25, width: 1360, height: 875)
        )
    }
}
