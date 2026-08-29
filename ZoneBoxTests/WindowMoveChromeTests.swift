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
}
