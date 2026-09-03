import CoreGraphics
import XCTest
@testable import ZoneBoxCore

final class DividerPlanTests: XCTestCase {
    private let work = CGRect(x: 10, y: 20, width: 1000, height: 800)

    func testColumnsTwoProducesOneVerticalHandleAtWeightPrefix() throws {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 2)
        let handles = try handles(for: layout, snapped: [
            layout.zones[0].id: [windows[0]],
            layout.zones[1].id: [windows[1]],
        ])
        XCTAssertEqual(handles.count, 1)
        let handle = try XCTUnwrap(handles.first)
        XCTAssertEqual(handle.axis, .vertical)
        XCTAssertEqual(handle.afterIndex, 0)
        XCTAssertEqual(handle.lineAX, work.minX + work.width * 0.5, accuracy: 0.001)
        XCTAssertEqual(handle.spanAX.lowerBound, work.minY, accuracy: 0.001)
        XCTAssertEqual(handle.spanAX.upperBound, work.maxY, accuracy: 0.001)
        XCTAssertEqual(Set(handle.slots.map(\.zoneID)), Set(layout.zones.map(\.id)))
        XCTAssertEqual(handle.slots.count, 2)
    }

    func testColumnsThreeProducesAHandleOnEachInnerSeam() throws {
        let layout = LayoutTemplates.columns(3)
        let windows = identities(count: 3)
        let snapped = Dictionary(uniqueKeysWithValues: zip(layout.zones.map(\.id), windows.map { [$0] }))
        let handles = try handles(for: layout, snapped: snapped)
        XCTAssertEqual(handles.map(\.axis), [.vertical, .vertical])
        XCTAssertEqual(handles.map(\.afterIndex), [0, 1])
        XCTAssertEqual(handles[0].lineAX, work.minX + work.width * 1.0 / 3.0, accuracy: 0.6)
        XCTAssertEqual(handles[1].lineAX, work.minX + work.width * 2.0 / 3.0, accuracy: 0.6)
        XCTAssertEqual(Set(handles[0].slots.map(\.zoneID)), Set([layout.zones[0].id, layout.zones[1].id]))
        XCTAssertEqual(Set(handles[1].slots.map(\.zoneID)), Set([layout.zones[1].id, layout.zones[2].id]))
    }

    func testPriorityThreeVerticalHandleMovesThreeWindows() throws {
        let layout = LayoutTemplates.priority3()
        let windows = identities(count: 3)
        let handles = try handles(for: layout, snapped: [
            layout.zones[0].id: [windows[0]],
            layout.zones[1].id: [windows[1]],
            layout.zones[2].id: [windows[2]],
        ])
        let vertical = try XCTUnwrap(handles.first(where: { $0.axis == .vertical }))
        XCTAssertEqual(vertical.afterIndex, 0)
        XCTAssertEqual(Set(vertical.slots.map(\.zoneID)), Set(layout.zones.map(\.id)))
        XCTAssertEqual(vertical.slots.count, 3)
        XCTAssertEqual(vertical.spanAX.lowerBound, work.minY, accuracy: 0.001)
        XCTAssertEqual(vertical.spanAX.upperBound, work.maxY, accuracy: 0.001)
        XCTAssertEqual(vertical.lineAX, work.minX + work.width * 0.5, accuracy: 0.001)
    }

    func testPriorityThreeHorizontalHandleCoversOnlyTheRightColumn() throws {
        let layout = LayoutTemplates.priority3()
        let windows = identities(count: 3)
        let handles = try handles(for: layout, snapped: [
            layout.zones[0].id: [windows[0]],
            layout.zones[1].id: [windows[1]],
            layout.zones[2].id: [windows[2]],
        ])
        let horizontal = try XCTUnwrap(handles.first(where: { $0.axis == .horizontal }))
        XCTAssertEqual(horizontal.afterIndex, 0)
        XCTAssertEqual(Set(horizontal.slots.map(\.zoneID)), Set([layout.zones[1].id, layout.zones[2].id]))
        XCTAssertEqual(horizontal.slots.count, 2)
        XCTAssertEqual(horizontal.spanAX.lowerBound, work.minX + work.width * 0.5, accuracy: 0.001)
        XCTAssertEqual(horizontal.spanAX.upperBound, work.maxX, accuracy: 0.001)
        XCTAssertEqual(horizontal.lineAX, work.minY + work.height * 0.5, accuracy: 0.001)
    }

    func testMergedZoneCoveringASeamProducesNoHandle() throws {
        let layout = LayoutTemplates.columns(1)
        XCTAssertTrue(try handles(for: layout, snapped: [layout.zones[0].id: [identities(count: 1)[0]]]).isEmpty)
    }

    func testEmptyOrStackedZoneSuppressesTheHandle() throws {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 3)
        XCTAssertTrue(try handles(for: layout, snapped: [
            layout.zones[0].id: [windows[0]],
        ]).isEmpty)
        XCTAssertTrue(try handles(for: layout, snapped: [
            layout.zones[0].id: [windows[0]],
            layout.zones[1].id: [windows[1], windows[2]],
        ]).isEmpty)
    }

    func testCanvasLayoutProducesNoHandles() throws {
        let layout = LayoutTemplates.focus()
        XCTAssertTrue(try handles(for: layout, snapped: [:]).isEmpty)
    }

    func testCanvasColumnsProduceAVerticalHandleOnTheSharedSeam() throws {
        let layout = Layout(
            name: "Canvas Columns",
            kind: .canvas,
            zones: [
                Zone(number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
                Zone(number: 2, canvasRect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)),
            ]
        )
        let windows = identities(count: 2)
        let handles = try handles(for: layout, snapped: [
            layout.zones[0].id: [windows[0]],
            layout.zones[1].id: [windows[1]],
        ])
        XCTAssertEqual(handles.count, 1)
        let handle = try XCTUnwrap(handles.first)
        XCTAssertEqual(handle.axis, .vertical)
        XCTAssertEqual(handle.lineAX, work.minX + work.width * 0.5, accuracy: 0.6)
        XCTAssertEqual(Set(handle.slots.map { $0.zoneID }), Set(layout.zones.map { $0.id }))
    }

    func testOccupancyBindsWindowsByLiveFrameInsteadOfCatalogZoneIDs() {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 2)
        let left = CGRect(x: work.minX, y: work.minY, width: 500, height: work.height)
        let right = CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height)
        let occupancy = DividerPlan.occupancy(
            resolvedFrames: [
                layout.zones[0].id: left,
                layout.zones[1].id: right,
            ],
            windows: [
                (windows[0], right),
                (windows[1], left),
            ]
        )
        XCTAssertEqual(occupancy[layout.zones[0].id], [windows[1]])
        XCTAssertEqual(occupancy[layout.zones[1].id], [windows[0]])
    }

    func testOccupancyPrefersCatalogMembershipWhenAStrayWindowOverlapsTheSameZone() {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 3)
        let left = CGRect(x: work.minX, y: work.minY, width: 500, height: work.height)
        let right = CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height)
        let occupancy = DividerPlan.occupancy(
            resolvedFrames: [
                layout.zones[0].id: left,
                layout.zones[1].id: right,
            ],
            windows: [
                (windows[0], left),
                (windows[1], right),
                (windows[2], left.insetBy(dx: 40, dy: 80)),
            ],
            preferred: [
                windows[0]: layout.zones[0].id,
                windows[1]: layout.zones[1].id,
            ]
        )
        XCTAssertEqual(occupancy[layout.zones[0].id], [windows[0]])
        XCTAssertEqual(occupancy[layout.zones[1].id], [windows[1]])
    }

    func testOccupancyKeepsAnInPlaceCatalogWindowWhenCoverageIsSoft() {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 2)
        let left = CGRect(x: work.minX, y: work.minY, width: 500, height: work.height)
        let right = CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height)
        let slightlyShort = CGRect(x: left.minX + 12, y: left.minY + 16, width: left.width - 24, height: left.height - 32)
        let occupancy = DividerPlan.occupancy(
            resolvedFrames: [
                layout.zones[0].id: left,
                layout.zones[1].id: right,
            ],
            windows: [
                (windows[0], slightlyShort),
                (windows[1], right),
            ],
            preferred: [
                windows[0]: layout.zones[0].id,
                windows[1]: layout.zones[1].id,
            ]
        )
        XCTAssertEqual(occupancy[layout.zones[0].id], [windows[0]])
        XCTAssertEqual(occupancy[layout.zones[1].id], [windows[1]])
    }

    func testOccupancyIgnoresTinyOrOffscreenChrome() {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 3)
        let left = CGRect(x: work.minX, y: work.minY, width: 500, height: work.height)
        let right = CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height)
        let occupancy = DividerPlan.occupancy(
            resolvedFrames: [
                layout.zones[0].id: left,
                layout.zones[1].id: right,
            ],
            windows: [
                (windows[0], left),
                (windows[1], right),
                (windows[2], CGRect(x: left.midX - 8, y: left.minY, width: 16, height: 16)),
            ]
        )
        XCTAssertEqual(occupancy[layout.zones[0].id], [windows[0]])
        XCTAssertEqual(occupancy[layout.zones[1].id], [windows[1]])
    }

    func testPreferredOverflowingWindowStillOccupiesItsZone() {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 3)
        let left = CGRect(x: work.minX, y: work.minY, width: 500, height: work.height)
        let right = CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height)
        let overflowingRight = CGRect(x: work.minX + 499, y: work.minY, width: 760, height: work.height)
        let occupancy = DividerPlan.occupancy(
            resolvedFrames: [
                layout.zones[0].id: left,
                layout.zones[1].id: right,
            ],
            windows: [
                (windows[0], left),
                (windows[1], overflowingRight),
                (windows[2], CGRect(x: work.minX + 220, y: work.minY + 80, width: 720, height: 520)),
            ],
            preferred: [
                windows[0]: layout.zones[0].id,
                windows[1]: layout.zones[1].id,
            ],
            workAreaAX: work
        )
        XCTAssertEqual(occupancy[layout.zones[0].id], [windows[0]])
        XCTAssertEqual(occupancy[layout.zones[1].id], [windows[1]])
        let handle = DividerPlan.handles(
            layout: layout,
            workAreaAX: work,
            resolvedFrames: [
                layout.zones[0].id: left,
                layout.zones[1].id: overflowingRight.intersection(work),
            ],
            snapped: occupancy
        )
        XCTAssertEqual(handle.count, 1)
        XCTAssertEqual(handle.first?.axis, .vertical)
    }

    func testUncataloguedFullscreenWindowDoesNotOccupyAHalfZone() {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 1)
        let left = CGRect(x: work.minX, y: work.minY, width: 500, height: work.height)
        let right = CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height)
        let occupancy = DividerPlan.occupancy(
            resolvedFrames: [
                layout.zones[0].id: left,
                layout.zones[1].id: right,
            ],
            windows: [
                (windows[0], work),
            ],
            workAreaAX: work
        )
        XCTAssertTrue(occupancy.isEmpty)
    }

    func testHandleUsesLiveWindowContactInsteadOfLaggedResolvedFrames() throws {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 2)
        let left = CGRect(x: work.minX, y: work.minY, width: 420, height: work.height)
        let right = CGRect(x: work.minX + 436, y: work.minY, width: 564, height: work.height)
        let occupancy = DividerPlan.occupancy(
            resolvedFrames: [
                layout.zones[0].id: CGRect(x: work.minX, y: work.minY, width: 500, height: work.height),
                layout.zones[1].id: CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height),
            ],
            windows: [
                (windows[0], left),
                (windows[1], right),
            ],
            preferred: [
                windows[0]: layout.zones[0].id,
                windows[1]: layout.zones[1].id,
            ]
        )
        var frames = [
            layout.zones[0].id: CGRect(x: work.minX, y: work.minY, width: 500, height: work.height),
            layout.zones[1].id: CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height),
        ]
        frames[layout.zones[0].id] = left
        frames[layout.zones[1].id] = right
        let handle = try XCTUnwrap(
            DividerPlan.handles(
                layout: layout,
                workAreaAX: work,
                resolvedFrames: frames,
                snapped: occupancy
            ).first
        )
        XCTAssertEqual(handle.lineAX, (left.maxX + right.minX) / 2, accuracy: 0.6)
    }

    func testMovingACanvasSeamKeepsOuterEdges() {
        let layout = Layout(
            name: "Canvas Columns",
            kind: .canvas,
            zones: [
                Zone(number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
                Zone(number: 2, canvasRect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)),
            ]
        )
        let handle = DividerHandleSpec(
            axis: .vertical,
            afterIndex: 0,
            lineAX: 0.5,
            spanAX: 0...1,
            slots: [
                DividerHandleSlot(zoneID: layout.zones[0].id, identity: identities(count: 1)[0]),
                DividerHandleSlot(zoneID: layout.zones[1].id, identity: WindowIdentity(pid: 2, windowNumber: 2)),
            ]
        )
        let moved = try! XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.3))
        XCTAssertEqual(moved.zones[0].canvasRect?.x ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(moved.zones[0].canvasRect?.width ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(moved.zones[1].canvasRect?.x ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(moved.zones[1].canvasRect?.width ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertTrue(DividerPlan.geometryChanged(from: layout, to: moved))
    }

    func testGutterKeepsTheHandleOnTheUngutteredWeightLine() throws {
        let layout = LayoutTemplates.columns(2)
        let windows = identities(count: 2)
        let handles = try handles(
            for: layout,
            snapped: [
                layout.zones[0].id: [windows[0]],
                layout.zones[1].id: [windows[1]],
            ],
            gutter: 16
        )
        XCTAssertEqual(handles.count, 1)
        XCTAssertEqual(handles[0].lineAX, work.minX + 500, accuracy: 0.6)
    }

    func testMovingAVerticalLineMovesTheHandleWithTheSeam() throws {
        let start = LayoutTemplates.columns(2)
        let windows = identities(count: 2)
        let snapped = [
            start.zones[0].id: [windows[0]],
            start.zones[1].id: [windows[1]],
        ]
        let before = try XCTUnwrap(try handles(for: start, snapped: snapped).first)
        let moved = try XCTUnwrap(GridEditing.moveLine(start, axis: .vertical, afterIndex: 0, toNormalized: 0.3))
        let after = try XCTUnwrap(try handles(for: moved, snapped: snapped).first)
        XCTAssertEqual(after.axis, .vertical)
        XCTAssertEqual(after.afterIndex, 0)
        XCTAssertEqual(after.lineAX, work.minX + work.width * 0.3, accuracy: 0.6)
        XCTAssertGreaterThan(abs(before.lineAX - after.lineAX), 50)
        XCTAssertEqual(after.spanAX.lowerBound, work.minY, accuracy: 0.001)
        XCTAssertEqual(after.spanAX.upperBound, work.maxY, accuracy: 0.001)
    }

    func testHandleStaysOnTheActualWindowContactWhenFramesLagTheLayout() throws {
        let start = LayoutTemplates.columns(2)
        let moved = try XCTUnwrap(GridEditing.moveLine(start, axis: .vertical, afterIndex: 0, toNormalized: 0.3))
        let windows = identities(count: 2)
        let laggedFrames = [
            start.zones[0].id: CGRect(x: work.minX, y: work.minY, width: 500, height: work.height),
            start.zones[1].id: CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height),
        ]
        let handle = try XCTUnwrap(
            DividerPlan.handles(
                layout: moved,
                workAreaAX: work,
                resolvedFrames: laggedFrames,
                snapped: [
                    start.zones[0].id: [windows[0]],
                    start.zones[1].id: [windows[1]],
                ]
            ).first
        )
        XCTAssertEqual(handle.lineAX, work.minX + 500, accuracy: 0.6)
        XCTAssertGreaterThan(abs(handle.lineAX - (work.minX + work.width * 0.3)), 20)
    }

    private func handles(
        for layout: Layout,
        snapped: [UUID: [WindowIdentity]],
        gutter: CGFloat = 0
    ) throws -> [DividerHandleSpec] {
        let resolved = try resolveLayout(layout, workAreaAX: work, gutter: gutter)
        let frames = Dictionary(uniqueKeysWithValues: resolved.map { ($0.zoneID, $0.frameAX) })
        return DividerPlan.handles(
            layout: layout,
            workAreaAX: work,
            resolvedFrames: frames,
            snapped: snapped
        )
    }

    private func identities(count: Int) -> [WindowIdentity] {
        (1...count).map { WindowIdentity(pid: pid_t($0), windowNumber: UInt32($0)) }
    }
}
