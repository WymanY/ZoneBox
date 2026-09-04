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
}
