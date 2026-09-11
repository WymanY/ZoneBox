import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class WorkspaceLayoutPreviewTests: XCTestCase {
    func testPanesMirrorTheCapturedFramesBackToFront() {
        let snapshot = WorkspaceLayoutPreview.snapshot(rules: [
            AppPlacementRule(bundleID: "front", frame: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)),
            AppPlacementRule(bundleID: "back", frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
        ])

        XCTAssertEqual(snapshot.panes.map(\.bundleID), ["back", "front"])
        XCTAssertEqual(snapshot.panes[0].rect, NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(snapshot.panes[1].rect, NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
        XCTAssertTrue(snapshot.panes.allSatisfy(\.showsIcon))
    }

    func testEmptyRulesProduceNoPanes() {
        XCTAssertTrue(WorkspaceLayoutPreview.snapshot(rules: []).panes.isEmpty)
    }

    func testOverlappingWindowsKeepBothPanesWithSeparateLabels() {
        let snapshot = WorkspaceLayoutPreview.snapshot(rules: [
            AppPlacementRule(bundleID: "front", frame: NormalizedRect(x: 0.4, y: 0.4, width: 0.6, height: 0.6)),
            AppPlacementRule(bundleID: "back", frame: NormalizedRect(x: 0, y: 0, width: 0.6, height: 0.6)),
        ])

        XCTAssertEqual(snapshot.panes.count, 2)
        XCTAssertTrue(rects(snapshot.panes[0].rect).intersects(rects(snapshot.panes[1].rect)))
        XCTAssertFalse(
            rects(snapshot.panes[0].labelRect).intersects(rects(snapshot.panes[1].labelRect)),
            "overlapping windows must not stack icons on top of each other"
        )
        XCTAssertTrue(snapshot.panes.allSatisfy(\.showsIcon))
    }

    func testWindowHiddenBehindAFrontWindowDropsItsIcon() {
        let snapshot = WorkspaceLayoutPreview.snapshot(rules: [
            AppPlacementRule(bundleID: "front", frame: NormalizedRect(x: 0, y: 0, width: 1, height: 1)),
            AppPlacementRule(bundleID: "back", frame: NormalizedRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)),
        ])

        XCTAssertEqual(snapshot.panes.map(\.bundleID), ["back", "front"])
        XCTAssertFalse(snapshot.panes[0].showsIcon)
        XCTAssertTrue(snapshot.panes[1].showsIcon)
    }

    func testTinyWindowHidesIconButKeepsPane() {
        let snapshot = WorkspaceLayoutPreview.snapshot(rules: [
            AppPlacementRule(bundleID: "x.y", frame: NormalizedRect(x: 0.01, y: 0.01, width: 0.08, height: 0.08)),
        ])
        XCTAssertEqual(snapshot.panes.count, 1)
        XCTAssertEqual(snapshot.panes[0].bundleID, "x.y")
        XCTAssertFalse(snapshot.panes[0].showsIcon)
    }

    func testLabelRectStaysInsidePane() {
        let snapshot = WorkspaceLayoutPreview.snapshot(rules: [
            AppPlacementRule(bundleID: "a", frame: NormalizedRect(x: 0, y: 0, width: 0.3, height: 0.4)),
            AppPlacementRule(bundleID: "b", frame: NormalizedRect(x: 0.7, y: 0.6, width: 0.3, height: 0.4)),
        ])
        for pane in snapshot.panes {
            let paneRect = rects(pane.rect)
            let label = rects(pane.labelRect)
            XCTAssertFalse(label.isNull)
            XCTAssertGreaterThan(paneRect.intersection(label).width, 0)
            XCTAssertGreaterThan(paneRect.intersection(label).height, 0)
            XCTAssertEqual(paneRect.intersection(label).width, label.width, accuracy: 0.02)
            XCTAssertEqual(paneRect.intersection(label).height, label.height, accuracy: 0.02)
        }
    }

    private func rects(_ rect: NormalizedRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
