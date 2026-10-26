import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class OverlayStackingPolicyTests: XCTestCase {
    func testLiveSnapSitsJustAboveDraggingWindowNotScreensaver() {
        let live = OverlayStackingPolicy.windowLevel(.liveSnap)
        let dragging = CGWindowLevelForKey(.draggingWindow)
        let screensaver = CGWindowLevelForKey(.screenSaverWindow)
        XCTAssertEqual(live, dragging + 1)
        XCTAssertLessThan(live, screensaver)
        XCTAssertEqual(
            OverlayStackingPolicy.windowLevel(.preview),
            screensaver
        )
    }

    func testLivePointerSampleDoesNotRestackOrFlush() {
        let decision = OverlayStackingPolicy.present(
            isPreview: false,
            alreadyVisible: true,
            stackingMatches: true
        )
        XCTAssertEqual(decision.kind, .liveSnap)
        XCTAssertFalse(decision.restack)
        XCTAssertFalse(decision.flushDisplay)
    }

    func testLiveFirstShowRestacksOnce() {
        let decision = OverlayStackingPolicy.present(
            isPreview: false,
            alreadyVisible: false,
            stackingMatches: false
        )
        XCTAssertEqual(decision.kind, .liveSnap)
        XCTAssertTrue(decision.restack)
        XCTAssertTrue(decision.flushDisplay)
    }

    func testPreviewKeepsRestackingSoItCoversConsole() {
        let decision = OverlayStackingPolicy.present(
            isPreview: true,
            alreadyVisible: true,
            stackingMatches: true
        )
        XCTAssertEqual(decision.kind, .preview)
        XCTAssertTrue(decision.restack)
        XCTAssertTrue(decision.flushDisplay)
    }

    func testPreviewToLiveOnVisiblePanelRestacksToLowerLevel() {
        let decision = OverlayStackingPolicy.present(
            isPreview: false,
            alreadyVisible: true,
            stackingMatches: false
        )
        XCTAssertEqual(decision.kind, .liveSnap)
        XCTAssertTrue(decision.restack)
        XCTAssertFalse(decision.flushDisplay)
    }

    func testKindMapsPreviewFlag() {
        XCTAssertEqual(OverlayStackingPolicy.kind(isPreview: false), .liveSnap)
        XCTAssertEqual(OverlayStackingPolicy.kind(isPreview: true), .preview)
    }
}
