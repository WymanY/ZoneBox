import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class WorkspaceLayoutPreviewTests: XCTestCase {
    func testZoneIDWinsWhenNumberPointsAtAnotherPane() {
        let left = UUID()
        let right = UUID()
        let layout = canvas(
            Zone(id: left, number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
            Zone(id: right, number: 2, canvasRect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(
            layout: layout,
            rules: [AppPlacementRule(bundleID: "safari", zoneID: right, zoneNumber: 1)]
        )

        XCTAssertEqual(bundle(snapshot, left), nil)
        XCTAssertEqual(bundle(snapshot, right), "safari")
        XCTAssertEqual(snapshot.panes.first { $0.zoneID == right }?.number, 2)
    }

    func testZoneNumberFallbackWhenZoneIDIsGone() {
        let live = UUID()
        let layout = canvas(
            Zone(id: live, number: 2, canvasRect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)),
            Zone(id: UUID(), number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(
            layout: layout,
            rules: [AppPlacementRule(bundleID: "mail", zoneID: UUID(), zoneNumber: 2)]
        )

        XCTAssertEqual(bundle(snapshot, live), "mail")
    }

    func testMissingZoneLeavesPaneUnbound() {
        let zone = UUID()
        let layout = canvas(
            Zone(id: zone, number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(
            layout: layout,
            rules: [AppPlacementRule(bundleID: "notes", zoneID: UUID(), zoneNumber: 9)]
        )

        XCTAssertEqual(snapshot.panes.count, 1)
        XCTAssertNil(snapshot.panes[0].bundleID)
        XCTAssertFalse(snapshot.panes[0].showsIcon)
    }

    func testMissingLayoutIsUnavailableWithoutPanes() {
        let snapshot = WorkspaceLayoutPreview.snapshot(
            layout: nil,
            rules: [AppPlacementRule(bundleID: "safari", zoneID: UUID(), zoneNumber: 1)]
        )
        XCTAssertTrue(snapshot.isUnavailable)
        XCTAssertTrue(snapshot.panes.isEmpty)
    }

    func testZeroSizePaneIsDropped() {
        let live = UUID()
        let layout = canvas(
            Zone(id: live, number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1)),
            Zone(id: UUID(), number: 2, canvasRect: NormalizedRect(x: 0.2, y: 0.2, width: 0, height: 0.4))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(layout: layout, rules: [])
        XCTAssertEqual(snapshot.panes.map { $0.zoneID }, [live])
    }

    func testOverlappingCanvasGeometryIsPreserved() {
        let back = UUID()
        let front = UUID()
        let layout = canvas(
            Zone(id: back, number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.6, height: 0.6)),
            Zone(id: front, number: 2, canvasRect: NormalizedRect(x: 0.4, y: 0.4, width: 0.6, height: 0.6))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(layout: layout, rules: [])
        XCTAssertEqual(snapshot.panes.count, 2)
        XCTAssertEqual(snapshot.panes[0].rect.width, 0.6, accuracy: 0.0001)
        XCTAssertEqual(snapshot.panes[1].rect.x, 0.4, accuracy: 0.0001)
        XCTAssertTrue(rects(snapshot.panes[0].rect).intersects(rects(snapshot.panes[1].rect)))
        XCTAssertFalse(
            rects(snapshot.panes[0].labelRect).intersects(rects(snapshot.panes[1].labelRect)),
            "overlapping panes must not stack numbers on top of each other"
        )
    }

    func testTinyBoundPaneHidesIconAndKeepsNumber() {
        let zone = UUID()
        let layout = canvas(
            Zone(id: zone, number: 3, canvasRect: NormalizedRect(x: 0.01, y: 0.01, width: 0.08, height: 0.08))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(
            layout: layout,
            rules: [AppPlacementRule(bundleID: "x.y", zoneID: zone, zoneNumber: 3)]
        )
        XCTAssertEqual(snapshot.panes[0].bundleID, "x.y")
        XCTAssertEqual(snapshot.panes[0].number, 3)
        XCTAssertFalse(snapshot.panes[0].showsIcon)
    }

    func testWideBoundPaneShowsIcon() {
        let zone = UUID()
        let layout = canvas(
            Zone(id: zone, number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(
            layout: layout,
            rules: [AppPlacementRule(bundleID: "safari", zoneID: zone, zoneNumber: 1)]
        )
        XCTAssertEqual(snapshot.panes[0].bundleID, "safari")
        XCTAssertTrue(snapshot.panes[0].showsIcon)
    }

    func testPreviewFollowsCurrentLayoutGeometryNotHistoricalNumbersAlone() {
        let zone = UUID()
        var layout = canvas(
            Zone(id: zone, number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.25, height: 1))
        )
        let rules = [AppPlacementRule(bundleID: "code", zoneID: zone, zoneNumber: 1)]
        let before = WorkspaceLayoutPreview.snapshot(layout: layout, rules: rules)
        layout.zones[0].canvasRect = NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let after = WorkspaceLayoutPreview.snapshot(layout: layout, rules: rules)

        XCTAssertEqual(before.panes[0].rect.width, 0.25, accuracy: 0.0001)
        XCTAssertEqual(after.panes[0].rect.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(after.panes[0].rect.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(after.panes[0].bundleID, "code")
    }

    func testFirstRuleWinsWhenTwoRulesResolveToTheSameLiveZone() {
        let zone = UUID()
        let layout = canvas(
            Zone(id: zone, number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(
            layout: layout,
            rules: [
                AppPlacementRule(bundleID: "front", zoneID: zone, zoneNumber: 2),
                AppPlacementRule(bundleID: "back", zoneID: UUID(), zoneNumber: 1),
            ]
        )
        XCTAssertEqual(snapshot.panes[0].bundleID, "front")
    }

    func testCreatingZoneIsExcludedFromGeometry() {
        let live = UUID()
        let layout = canvas(
            Zone(id: live, number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
            Zone(id: UUID(), number: 2, name: "__creating", canvasRect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(layout: layout, rules: [])
        XCTAssertEqual(snapshot.panes.map { $0.zoneID }, [live])
    }

    func testGridTemplateBindsByPreservedZoneID() {
        let layout = LayoutTemplates.columns(2)
        let first = layout.zones[0]
        let snapshot = WorkspaceLayoutPreview.snapshot(
            layout: layout,
            rules: [AppPlacementRule(bundleID: "finder", zoneID: first.id, zoneNumber: 99)]
        )
        XCTAssertEqual(snapshot.panes.count, 2)
        XCTAssertEqual(bundle(snapshot, first.id), "finder")
        XCTAssertLessThan(snapshot.panes[0].rect.x, snapshot.panes[1].rect.x)
    }

    func testLabelRectStaysInsidePane() {
        let layout = canvas(
            Zone(id: UUID(), number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.3, height: 0.4)),
            Zone(id: UUID(), number: 2, canvasRect: NormalizedRect(x: 0.7, y: 0.6, width: 0.3, height: 0.4))
        )
        let snapshot = WorkspaceLayoutPreview.snapshot(layout: layout, rules: [])
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

    private func canvas(_ zones: Zone...) -> Layout {
        Layout(name: "Desk", kind: .canvas, zones: zones)
    }

    private func bundle(_ snapshot: WorkspaceLayoutPreview.Snapshot, _ zoneID: UUID) -> String? {
        snapshot.panes.first { $0.zoneID == zoneID }?.bundleID
    }

    private func rects(_ rect: NormalizedRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
