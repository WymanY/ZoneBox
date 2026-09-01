import XCTest
@testable import ZoneBoxCore

final class OverlayPresentationTests: XCTestCase {
    func testEmptyPresentationHasNoLayoutName() {
        XCTAssertNil(OverlayPresentation.empty.layoutName)
        XCTAssertTrue(OverlayPresentation.empty.candidateOutlinesAX.isEmpty)
        XCTAssertNil(OverlayPresentation.empty.candidateLabel)
        XCTAssertNil(OverlayPresentation.empty.strip)
    }

    func testLayoutNamePreviewDoesNotCarryStripOrCandidates() {
        let presentation = OverlayPresentation(layoutName: "Focus")
        XCTAssertEqual(presentation.layoutName, "Focus")
        XCTAssertTrue(presentation.candidateOutlinesAX.isEmpty)
        XCTAssertNil(presentation.candidateLabel)
        XCTAssertNil(presentation.strip)
    }
}
