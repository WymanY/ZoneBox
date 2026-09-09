import XCTest
@testable import ZoneBoxCore

final class OverlayPresentationTests: XCTestCase {
    func testEmptyPresentationHasNoLayoutName() {
        XCTAssertNil(OverlayPresentation.empty.layoutName)
        XCTAssertNil(OverlayPresentation.empty.strip)
    }

    func testLayoutNamePreviewDoesNotCarryStrip() {
        let presentation = OverlayPresentation(layoutName: "Focus")
        XCTAssertEqual(presentation.layoutName, "Focus")
        XCTAssertNil(presentation.strip)
    }

    func testSnapSessionOmitsCandidateChrome() {
        let presentation = OverlayPresentation.snapSession()
        XCTAssertNil(presentation.strip)
        XCTAssertNil(presentation.layoutName)
    }

    func testStripHoverTooltipStateIsPartOfPresentation() {
        let geometry = LayoutStripGeometry(
            frameAppKit: CGRect(x: 0, y: 0, width: 100, height: 40),
            cards: [],
            overflowFrameAppKit: CGRect(x: 80, y: 0, width: 20, height: 40),
            leadingOverflowFrameAppKit: CGRect(x: 0, y: 0, width: 20, height: 40)
        )
        let idle = OverlayStripRenderModel(geometry: geometry)
        let hovered = OverlayStripRenderModel(geometry: geometry, hoveredOverflow: .next)
        XCTAssertNil(idle.hoveredOverflow)
        XCTAssertEqual(hovered.hoveredOverflow, .next)
        XCTAssertNotEqual(idle, hovered)
    }
}
