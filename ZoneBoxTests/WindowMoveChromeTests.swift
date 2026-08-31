import XCTest
@testable import ZoneBoxCore

final class WindowMoveChromeTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 80, width: 800, height: 600)

    func testUnknownHitInTitleBandIsMoveChrome() {
        XCTAssertTrue(
            WindowMoveChrome.contains(
                axPoint: CGPoint(x: 180, y: 90),
                windowFrameAX: frame,
                hitRole: nil,
                hitSubrole: nil,
                ancestorRoles: []
            )
        )
    }

    func testUnknownHitInContentIsNotMoveChrome() {
        XCTAssertFalse(
            WindowMoveChrome.contains(
                axPoint: CGPoint(x: 180, y: 240),
                windowFrameAX: frame,
                hitRole: nil,
                hitSubrole: nil,
                ancestorRoles: []
            )
        )
    }

    func testTitleBarRoleIsMoveChrome() {
        XCTAssertTrue(
            WindowMoveChrome.contains(
                axPoint: CGPoint(x: 180, y: 90),
                windowFrameAX: frame,
                hitRole: WindowMoveChrome.titleBarRole,
                hitSubrole: nil,
                ancestorRoles: []
            )
        )
    }

    func testWebAreaInTitleBandStillAllowsWindowMove() {
        XCTAssertTrue(
            WindowMoveChrome.contains(
                axPoint: CGPoint(x: 180, y: 90),
                windowFrameAX: frame,
                hitRole: "AXWebArea",
                hitSubrole: nil,
                ancestorRoles: []
            )
        )
    }

    func testWebAreaBelowTitleBandIsNotMoveChrome() {
        XCTAssertFalse(
            WindowMoveChrome.contains(
                axPoint: CGPoint(x: 180, y: 240),
                windowFrameAX: frame,
                hitRole: "AXWebArea",
                hitSubrole: nil,
                ancestorRoles: []
            )
        )
    }

    func testScrollAreaAncestorIsNotMoveChrome() {
        XCTAssertFalse(
            WindowMoveChrome.contains(
                axPoint: CGPoint(x: 180, y: 240),
                windowFrameAX: frame,
                hitRole: "AXStaticText",
                hitSubrole: nil,
                ancestorRoles: ["AXGroup", "AXScrollArea"]
            )
        )
    }

    func testTrafficLightsAreNotMoveChrome() {
        XCTAssertFalse(
            WindowMoveChrome.contains(
                axPoint: CGPoint(x: 112, y: 90),
                windowFrameAX: frame,
                hitRole: "AXButton",
                hitSubrole: "AXCloseButton",
                ancestorRoles: [WindowMoveChrome.titleBarRole]
            )
        )
    }

    func testToolbarInTitleBandIsMoveChrome() {
        XCTAssertTrue(
            WindowMoveChrome.contains(
                axPoint: CGPoint(x: 300, y: 110),
                windowFrameAX: frame,
                hitRole: "AXToolbar",
                hitSubrole: nil,
                ancestorRoles: []
            )
        )
    }

    func testToolbarBelowTitleBandIsNotMoveChrome() {
        XCTAssertFalse(
            WindowMoveChrome.contains(
                axPoint: CGPoint(x: 300, y: 200),
                windowFrameAX: frame,
                hitRole: "AXToolbar",
                hitSubrole: nil,
                ancestorRoles: []
            )
        )
    }

    func testHoverBandUsesTopThirtySixPoints() {
        let band = WindowMoveChrome.titleBarBand(frame)

        XCTAssertEqual(band, CGRect(x: 100, y: 80, width: 800, height: 36))
        XCTAssertTrue(band.contains(CGPoint(x: 899, y: 115)))
        XCTAssertFalse(band.contains(CGPoint(x: 899, y: 116)))
    }

    func testHoverBandClampsToSmallWindowHeight() {
        let small = CGRect(x: 12, y: 24, width: 100, height: 20)

        XCTAssertEqual(WindowMoveChrome.titleBarBand(small), small)
    }
}
