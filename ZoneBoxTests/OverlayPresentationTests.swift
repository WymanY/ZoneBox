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

    func testSnapSessionKeepsOnlyTheActiveLayoutTriggerZones() {
        let current = ZoneCandidate(
            layoutID: UUID(),
            layoutName: "Priority 3",
            zone: ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 400, height: 800))
        )
        let otherLeft = ZoneCandidate(
            layoutID: UUID(),
            layoutName: "Columns 2",
            zone: ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 800))
        )
        let otherTop = ZoneCandidate(
            layoutID: UUID(),
            layoutName: "Rows 2",
            zone: ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 800, height: 400))
        )

        let presentation = OverlayPresentation.snapSession(
            candidates: [current, otherLeft, otherTop],
            candidateIndex: 0,
            localizedLayoutName: { name in "localized:\(name)" }
        )

        XCTAssertTrue(presentation.candidateOutlinesAX.isEmpty)
        XCTAssertEqual(presentation.candidateLabel?.text, "localized:Priority 3 · 1/3")
        XCTAssertEqual(presentation.candidateLabel?.anchorAX, current.zone.frameAX)
        XCTAssertNil(presentation.strip)
        XCTAssertNil(presentation.layoutName)
    }

    func testSnapSessionOmitsLabelWhenThereIsOnlyOneCandidate() {
        let only = ZoneCandidate(
            layoutID: UUID(),
            layoutName: "Focus",
            zone: ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 800, height: 800))
        )

        let presentation = OverlayPresentation.snapSession(
            candidates: [only],
            candidateIndex: 0
        )

        XCTAssertTrue(presentation.candidateOutlinesAX.isEmpty)
        XCTAssertNil(presentation.candidateLabel)
    }
}
