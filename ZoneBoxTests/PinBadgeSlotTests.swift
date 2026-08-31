import XCTest
@testable import ZoneBoxCore

final class PinBadgeSlotTests: XCTestCase {
    func testButtonIsInsetAndCenteredInTitleBarBand() throws {
        let window = CGRect(x: 100, y: 80, width: 800, height: 600)
        let rect = try XCTUnwrap(PinBadgeSlot.hoverButtonRect(windowFrameAX: window))

        XCTAssertEqual(rect, CGRect(x: 868, y: 120, width: 24, height: 24))
        XCTAssertGreaterThanOrEqual(rect.minY, window.minY + PinBadgeSlot.titleBarHeight)
        XCTAssertLessThan(rect.maxX, window.maxX)
    }

    func testNarrowWindowSuppressesHoverButton() {
        let window = CGRect(x: 100, y: 80, width: 119, height: 600)
        XCTAssertNil(PinBadgeSlot.hoverButtonRect(windowFrameAX: window))
    }

    func testBadgeSupportsNarrowPinnedWindow() {
        let window = CGRect(x: -300, y: -40, width: 90, height: 30)
        let rect = PinBadgeSlot.rect(windowFrameAX: window, size: 20, inset: 8)

        XCTAssertEqual(rect, CGRect(x: -238, y: -30, width: 20, height: 20))
    }

    func testAXAppKitRoundTripKeepsBadgeRect() {
        let window = CGRect(x: 100, y: 80, width: 800, height: 600)
        let badgeAX = PinBadgeSlot.rect(windowFrameAX: window, size: 20, inset: 8)
        let appKit = CoordinateConverter.appKitRect(fromAX: badgeAX, primaryFlipHeight: 900)
        let roundTrip = CoordinateConverter.axRect(fromAppKit: appKit, primaryFlipHeight: 900)

        XCTAssertEqual(roundTrip, badgeAX)
    }
}
