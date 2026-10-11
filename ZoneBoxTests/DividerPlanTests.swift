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

    func testOccupancyRecordsStackedWindowsSoTheHandleStaysHidden() {
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
                (windows[1], left),
                (windows[2], right),
            ]
        )
        XCTAssertEqual(occupancy[layout.zones[0].id], [windows[0], windows[1]])
        XCTAssertEqual(occupancy[layout.zones[1].id], [windows[2]])
        XCTAssertTrue(
            DividerPlan.handles(
                layout: layout,
                workAreaAX: work,
                resolvedFrames: [
                    layout.zones[0].id: left,
                    layout.zones[1].id: right,
                ],
                snapped: occupancy
            ).isEmpty
        )
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

    func testObservingMinSizeOnlyTightensWhenASuccessfulWriteRefusesToShrink() {
        let requested = CGRect(x: 10, y: 20, width: 120, height: 80)
        let actual = AXFrameMutation.clamped(
            requested,
            minSize: CGSize(width: 400, height: 300),
            maxSize: nil
        )
        XCTAssertEqual(actual, CGRect(x: 10, y: 20, width: 400, height: 300))
        let zoneID = UUID()
        let learned = DividerPlan.observingMinSize(
            [:],
            zoneID: zoneID,
            requested: requested,
            actual: actual,
            axis: .vertical
        )
        XCTAssertEqual(learned[zoneID]?.width, 400)
    }

    func testObservingMinSizeIgnoresWritesThatMatchedTheRequest() {
        let zoneID = UUID()
        let requested = CGRect(x: 10, y: 20, width: 200, height: 800)
        let matched = DividerPlan.observingMinSize(
            [:],
            zoneID: zoneID,
            requested: requested,
            actual: requested,
            axis: .vertical
        )
        XCTAssertTrue(matched.isEmpty)

        let learned = DividerPlan.observingMinSize(
            [:],
            zoneID: zoneID,
            requested: requested,
            actual: CGRect(x: 10, y: 20, width: 400, height: 800),
            axis: .vertical
        )
        XCTAssertEqual(learned[zoneID]?.width, 400)
        XCTAssertEqual(learned[zoneID]?.height, 0)

        let unchanged = DividerPlan.observingMinSize(
            learned,
            zoneID: zoneID,
            requested: CGRect(x: 10, y: 20, width: 500, height: 800),
            actual: CGRect(x: 10, y: 20, width: 500, height: 800),
            axis: .vertical
        )
        XCTAssertEqual(unchanged[zoneID]?.width, 400)

        let raised = DividerPlan.observingMinSize(
            learned,
            zoneID: zoneID,
            requested: requested,
            actual: CGRect(x: 10, y: 20, width: 420, height: 800),
            axis: .vertical
        )
        XCTAssertEqual(raised[zoneID]?.width, 420)
    }

    func testObservingMinSizeIgnoresTheUndraggedAxis() {
        let zoneID = UUID()
        let learned = DividerPlan.observingMinSize(
            [:],
            zoneID: zoneID,
            requested: CGRect(x: 0, y: 0, width: 500, height: 100),
            actual: CGRect(x: 0, y: 0, width: 500, height: 300),
            axis: .horizontal
        )
        XCTAssertEqual(learned[zoneID]?.height, 300)
        XCTAssertEqual(learned[zoneID]?.width, 0)
    }

    func testVerticalLeftMinSizeStopsLeftwardMoveAndAllowsRightward() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let minSizes = [layout.zones[0].id: CGSize(width: 400, height: 0)]
        let blocked = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.15,
                workAreaAX: work,
                gutter: 0,
                minSizes: minSizes
            )
        )
        let blockedLeft = try resolvedFrame(layout.zones[0].id, in: blocked, gutter: 0)
        XCTAssertEqual(blockedLeft.width, 400, accuracy: 2)
        let blockedLine = try XCTUnwrap(DividerPlan.normalizedLine(of: handle, in: blocked, workAreaAX: work))
        XCTAssertGreaterThan(blockedLine, 0.3)
        XCTAssertLessThan(blockedLine, 0.5)
        let unconstrained = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.15))
        XCTAssertLessThan(
            try resolvedFrame(layout.zones[0].id, in: unconstrained, gutter: 0).width,
            blockedLeft.width - 20
        )

        let reverse = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.7,
                workAreaAX: work,
                gutter: 0,
                minSizes: minSizes
            )
        )
        let reverseLeft = try resolvedFrame(layout.zones[0].id, in: reverse, gutter: 0)
        XCTAssertEqual(reverseLeft.width, 700, accuracy: 2)
    }

    func testVerticalRightMinSizeStopsRightwardMove() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let minSizes = [layout.zones[1].id: CGSize(width: 350, height: 0)]
        let blocked = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.9,
                workAreaAX: work,
                gutter: 0,
                minSizes: minSizes
            )
        )
        let blockedRight = try resolvedFrame(layout.zones[1].id, in: blocked, gutter: 0)
        XCTAssertEqual(blockedRight.width, 350, accuracy: 2)
    }

    func testHorizontalTopMinSizeStopsTowardTheTopAndAllowsTheBottom() throws {
        let layout = LayoutTemplates.rows(2)
        let handle = try horizontalHandle(for: layout)
        let minSizes = [layout.zones[0].id: CGSize(width: 0, height: 300)]
        let blocked = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.1,
                workAreaAX: work,
                gutter: 0,
                minSizes: minSizes
            )
        )
        let blockedTop = try resolvedFrame(layout.zones[0].id, in: blocked, gutter: 0)
        XCTAssertEqual(blockedTop.height, 300, accuracy: 2)
        let blockedLine = try XCTUnwrap(DividerPlan.normalizedLine(of: handle, in: blocked, workAreaAX: work))
        XCTAssertGreaterThan(blockedLine, 0.2)
        XCTAssertLessThan(blockedLine, 0.5)
        let unconstrained = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.1))
        XCTAssertLessThan(
            try resolvedFrame(layout.zones[0].id, in: unconstrained, gutter: 0).height,
            blockedTop.height - 20
        )

        let reverse = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.6,
                workAreaAX: work,
                gutter: 0,
                minSizes: minSizes
            )
        )
        let reverseTop = try resolvedFrame(layout.zones[0].id, in: reverse, gutter: 0)
        XCTAssertEqual(reverseTop.height, 480, accuracy: 2)
    }

    func testGutterIsIncludedWhenStoppingAtMinWidth() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let gutter: CGFloat = 16
        let minSizes = [layout.zones[0].id: CGSize(width: 400, height: 0)]
        let blocked = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.1,
                workAreaAX: work,
                gutter: gutter,
                minSizes: minSizes
            )
        )
        let blockedLeft = try resolvedFrame(layout.zones[0].id, in: blocked, gutter: gutter)
        XCTAssertGreaterThanOrEqual(blockedLeft.width + 0.5, 400)
        XCTAssertEqual(blockedLeft.width, 400, accuracy: 2)
    }

    func testBothSidesMinSizesClampTheReachableRange() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let minSizes: [UUID: CGSize] = [
            layout.zones[0].id: CGSize(width: 300, height: 0),
            layout.zones[1].id: CGSize(width: 250, height: 0),
        ]
        let leftStop = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.05,
                workAreaAX: work,
                gutter: 0,
                minSizes: minSizes
            )
        )
        XCTAssertEqual(try resolvedFrame(layout.zones[0].id, in: leftStop, gutter: 0).width, 300, accuracy: 2)
        let rightStop = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.95,
                workAreaAX: work,
                gutter: 0,
                minSizes: minSizes
            )
        )
        XCTAssertEqual(try resolvedFrame(layout.zones[1].id, in: rightStop, gutter: 0).width, 250, accuracy: 2)
    }

    func testCanvasVerticalMinSizeStopsTheSeam() throws {
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
            lineAX: work.minX + 500,
            spanAX: work.minY...work.maxY,
            slots: [
                DividerHandleSlot(zoneID: layout.zones[0].id, identity: identities(count: 1)[0]),
                DividerHandleSlot(zoneID: layout.zones[1].id, identity: WindowIdentity(pid: 2, windowNumber: 2)),
            ]
        )
        let minSizes = [layout.zones[0].id: CGSize(width: 400, height: 0)]
        let blocked = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.1,
                workAreaAX: work,
                gutter: 0,
                minSizes: minSizes
            )
        )
        XCTAssertEqual(try resolvedFrame(layout.zones[0].id, in: blocked, gutter: 0).width, 400, accuracy: 2)
    }

    func testLayoutMatchingActualFramesUsesTheContactLine() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let left = CGRect(x: work.minX, y: work.minY, width: 400, height: work.height)
        let right = CGRect(x: work.minX + 400, y: work.minY, width: 600, height: work.height)
        let matched = try XCTUnwrap(
            DividerPlan.layoutMatchingActualFrames(
                layout,
                handle: handle,
                actualFrames: [
                    layout.zones[0].id: left,
                    layout.zones[1].id: right,
                ],
                workAreaAX: work
            )
        )
        XCTAssertEqual(DividerPlan.normalizedLine(of: handle, in: matched, workAreaAX: work) ?? 0, 0.4, accuracy: 0.002)
        XCTAssertEqual(try resolvedFrame(layout.zones[0].id, in: matched, gutter: 0).width, 400, accuracy: 2)
    }

    func testLayoutMatchingActualFramesRejectsASplitGap() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let left = CGRect(x: work.minX, y: work.minY, width: 400, height: work.height)
        let right = CGRect(x: work.minX + 500, y: work.minY, width: 500, height: work.height)
        XCTAssertNil(
            DividerPlan.layoutMatchingActualFrames(
                layout,
                handle: handle,
                actualFrames: [
                    layout.zones[0].id: left,
                    layout.zones[1].id: right,
                ],
                workAreaAX: work
            )
        )
    }

    func testLayoutMatchingActualFramesUsesNearestNeighborNotFarSlot() throws {
        let layout = LayoutTemplates.grid2x2()
        let handle = try verticalHandle(for: layout)
        XCTAssertEqual(handle.slots.count, 4)
        let leftTop = CGRect(x: work.minX, y: work.minY, width: 400, height: 400)
        let leftBottom = CGRect(x: work.minX, y: work.minY + 400, width: 400, height: 400)
        let rightTop = CGRect(x: work.minX + 400, y: work.minY, width: 600, height: 400)
        let rightBottomLagged = CGRect(x: work.minX + 700, y: work.minY + 400, width: 300, height: 400)
        let matched = try XCTUnwrap(
            DividerPlan.layoutMatchingActualFrames(
                layout,
                handle: handle,
                actualFrames: [
                    layout.zones[0].id: leftTop,
                    layout.zones[1].id: rightTop,
                    layout.zones[2].id: leftBottom,
                    layout.zones[3].id: rightBottomLagged,
                ],
                workAreaAX: work
            )
        )
        XCTAssertEqual(
            DividerPlan.normalizedLine(of: handle, in: matched, workAreaAX: work) ?? 0,
            0.4,
            accuracy: 0.002
        )
    }

    func testClampingPendingLayoutDoesNotPassObservedMins() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let overshot = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.12))
        let clamped = DividerPlan.clamping(
            overshot,
            toHandle: handle,
            from: layout,
            workAreaAX: work,
            gutter: 0,
            minSizes: [layout.zones[0].id: CGSize(width: 400, height: 0)]
        )
        XCTAssertEqual(try resolvedFrame(layout.zones[0].id, in: clamped, gutter: 0).width, 400, accuracy: 2)
    }

    func testMinSizeStopExplainsOnlyAShrinkTheWindowRefused() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let requested = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.2))
        let applied = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.2,
                workAreaAX: work,
                gutter: 0,
                minSizes: [layout.zones[0].id: CGSize(width: 400, height: 0)]
            )
        )
        let requestedFrames = try frames(of: requested)
        var actuals = try frames(of: applied)
        actuals[layout.zones[0].id] = CGRect(x: work.minX, y: work.minY, width: 400, height: work.height)

        let stop = try XCTUnwrap(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: requested,
                appliedLayout: applied,
                requestedFrames: requestedFrames,
                actualFrames: actuals,
                workAreaAX: work,
                gutter: 0
            )
        )
        XCTAssertEqual(stop.axis, .vertical)
        XCTAssertEqual(stop.windows.map(\.identity), [handle.slots[0].identity])
        XCTAssertEqual(stop.windows[0].limit, 400, accuracy: 0.5)
    }

    func testMinSizeStopIgnoresAWriteThatNeverReturned() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let requested = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.2))
        XCTAssertNil(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: requested,
                appliedLayout: layout,
                requestedFrames: try frames(of: requested),
                actualFrames: [:],
                workAreaAX: work,
                gutter: 0
            )
        )
    }

    func testMinSizeStopIgnoresAPointerThatDidNotReachTheLimit() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let requested = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.45))
        let actual = CGRect(x: work.minX, y: work.minY, width: 450, height: work.height)
        XCTAssertNil(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: requested,
                appliedLayout: requested,
                requestedFrames: try frames(of: requested),
                actualFrames: [layout.zones[0].id: actual, layout.zones[1].id: try frames(of: requested)[layout.zones[1].id]!],
                workAreaAX: work,
                gutter: 0
            )
        )
    }

    func testMinSizeStopUsesTheRawPointerAfterWritesWereClamped() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let raw = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.2))
        let clampedWrite = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.2,
                workAreaAX: work,
                gutter: 0,
                minSizes: [layout.zones[0].id: CGSize(width: 400, height: 0)]
            )
        )
        let earlierRequest = try frames(of: try XCTUnwrap(
            DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.35)
        ))
        var earlierActual = earlierRequest
        earlierActual[layout.zones[0].id] = CGRect(
            x: work.minX, y: work.minY, width: 400, height: work.height
        )
        let learned = DividerPlan.observingMinSize(
            [:],
            zoneID: layout.zones[0].id,
            requested: earlierRequest[layout.zones[0].id]!,
            actual: earlierActual[layout.zones[0].id]!,
            axis: .vertical
        )

        XCTAssertNil(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: clampedWrite,
                appliedLayout: clampedWrite,
                requestedFrames: try frames(of: clampedWrite),
                actualFrames: try frames(of: clampedWrite),
                workAreaAX: work,
                gutter: 0
            )
        )
        let kept = DividerPlan.retainedMinSizeRefusals(
            learned,
            handle: handle,
            pointerLayout: raw,
            appliedLayout: clampedWrite,
            workAreaAX: work
        )
        let stop = try XCTUnwrap(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: raw,
                appliedLayout: clampedWrite,
                refusals: kept,
                workAreaAX: work,
                gutter: 0
            )
        )
        XCTAssertEqual(stop.windows.map(\.identity), [handle.slots[0].identity])
        XCTAssertTrue(stop.windows[0].observed)
        XCTAssertEqual(stop.windows[0].limit, 400, accuracy: 0.5)
    }

    func testRetainedRefusalDropsWhenThePointerBacksAway() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let backedAway = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.45))
        let held = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.4))
        let refusal = [layout.zones[0].id: CGSize(width: 400, height: 0)]

        XCTAssertTrue(
            DividerPlan.retainedMinSizeRefusals(
                refusal,
                handle: handle,
                pointerLayout: backedAway,
                appliedLayout: held,
                workAreaAX: work
            ).isEmpty
        )
        XCTAssertNil(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: backedAway,
                appliedLayout: held,
                refusals: [:],
                workAreaAX: work,
                gutter: 0
            )
        )
    }

    func testGridRightRefusalStaysUntilThePointerBacksAway() throws {
        let layout = LayoutTemplates.columns(2)
        let handle = try verticalHandle(for: layout)
        let raw = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.8))
        let applied = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.8,
                workAreaAX: work,
                gutter: 0,
                minSizes: [layout.zones[1].id: CGSize(width: 350, height: 0)]
            )
        )
        XCTAssertEqual(try resolvedFrame(layout.zones[1].id, in: applied, gutter: 0).width, 350, accuracy: 2)
        let refusals = [layout.zones[1].id: CGSize(width: 350, height: 0)]
        let right = try XCTUnwrap(handle.slots.first { $0.zoneID == layout.zones[1].id })

        let kept = DividerPlan.retainedMinSizeRefusals(
            refusals,
            handle: handle,
            pointerLayout: raw,
            appliedLayout: applied,
            workAreaAX: work
        )
        XCTAssertEqual(kept[layout.zones[1].id]?.width, 350)
        let stop = try XCTUnwrap(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: raw,
                appliedLayout: applied,
                refusals: kept,
                workAreaAX: work,
                gutter: 0
            )
        )
        XCTAssertEqual(stop.axis, .vertical)
        XCTAssertEqual(stop.windows.map { $0.identity }, [right.identity])
        XCTAssertEqual(stop.windows[0].limit, 350, accuracy: 0.5)

        let backedAway = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.55))
        XCTAssertTrue(
            DividerPlan.retainedMinSizeRefusals(
                refusals,
                handle: handle,
                pointerLayout: backedAway,
                appliedLayout: applied,
                workAreaAX: work
            ).isEmpty
        )
        XCTAssertNil(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: backedAway,
                appliedLayout: applied,
                refusals: [:],
                workAreaAX: work,
                gutter: 0
            )
        )
    }

    func testGridBottomRefusalStaysUntilThePointerBacksAway() throws {
        let layout = LayoutTemplates.rows(2)
        let handle = try horizontalHandle(for: layout)
        let raw = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.8))
        let applied = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                layout,
                handle: handle,
                toNormalized: 0.8,
                workAreaAX: work,
                gutter: 0,
                minSizes: [layout.zones[1].id: CGSize(width: 0, height: 350)]
            )
        )
        XCTAssertEqual(try resolvedFrame(layout.zones[1].id, in: applied, gutter: 0).height, 350, accuracy: 2)
        let refusals = [layout.zones[1].id: CGSize(width: 0, height: 350)]
        let bottom = try XCTUnwrap(handle.slots.first { $0.zoneID == layout.zones[1].id })

        let kept = DividerPlan.retainedMinSizeRefusals(
            refusals,
            handle: handle,
            pointerLayout: raw,
            appliedLayout: applied,
            workAreaAX: work
        )
        XCTAssertEqual(kept[layout.zones[1].id]?.height, 350)
        let stop = try XCTUnwrap(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: raw,
                appliedLayout: applied,
                refusals: kept,
                workAreaAX: work,
                gutter: 0
            )
        )
        XCTAssertEqual(stop.axis, .horizontal)
        XCTAssertEqual(stop.windows.map { $0.identity }, [bottom.identity])
        XCTAssertEqual(stop.windows[0].limit, 350, accuracy: 0.5)

        let backedAway = try XCTUnwrap(DividerPlan.movedLayout(layout, handle: handle, toNormalized: 0.4))
        XCTAssertTrue(
            DividerPlan.retainedMinSizeRefusals(
                refusals,
                handle: handle,
                pointerLayout: backedAway,
                appliedLayout: applied,
                workAreaAX: work
            ).isEmpty
        )
        XCTAssertNil(
            DividerPlan.minSizeStop(
                handle: handle,
                requestedLayout: backedAway,
                appliedLayout: applied,
                refusals: [:],
                workAreaAX: work,
                gutter: 0
            )
        )
    }

    func testMergingReadableAXMinSizeRaisesTheBound() {
        let zoneID = UUID()
        let merged = DividerPlan.mergingMinSize(
            [zoneID: CGSize(width: 120, height: 0)],
            zoneID: zoneID,
            minSize: CGSize(width: 180, height: 90)
        )
        XCTAssertEqual(merged[zoneID]?.width, 180)
        XCTAssertEqual(merged[zoneID]?.height, 90)
    }

    /// A snapped seam can already be narrower than the learned minimum. Dragging
    /// further into that side used to search only back to the invalid base and
    /// return it. The feasible seam is past the base, including when the two
    /// mins leave only a narrow interval.
    func testClampSearchesPastAnUndersizedBase() throws {
        let columns = LayoutTemplates.columns(2)
        let vertical = try verticalHandle(for: columns)
        let narrowLeft = try XCTUnwrap(DividerPlan.movedLayout(columns, handle: vertical, toNormalized: 0.30))
        let leftMin = [columns.zones[0].id: CGSize(width: 350, height: 0)]
        let expandedLeft = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                narrowLeft,
                handle: vertical,
                toNormalized: 0.10,
                workAreaAX: work,
                gutter: 0,
                minSizes: leftMin
            )
        )
        XCTAssertEqual(try resolvedFrame(columns.zones[0].id, in: expandedLeft, gutter: 0).width, 350, accuracy: 2)
        let reversedLeft = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                narrowLeft,
                handle: vertical,
                toNormalized: 0.70,
                workAreaAX: work,
                gutter: 0,
                minSizes: leftMin
            )
        )
        XCTAssertEqual(try resolvedFrame(columns.zones[0].id, in: reversedLeft, gutter: 0).width, 700, accuracy: 2)

        let narrowRight = try XCTUnwrap(DividerPlan.movedLayout(columns, handle: vertical, toNormalized: 0.70))
        let expandedRight = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                narrowRight,
                handle: vertical,
                toNormalized: 0.90,
                workAreaAX: work,
                gutter: 0,
                minSizes: [columns.zones[1].id: CGSize(width: 350, height: 0)]
            )
        )
        XCTAssertEqual(try resolvedFrame(columns.zones[1].id, in: expandedRight, gutter: 0).width, 350, accuracy: 2)

        let rows = LayoutTemplates.rows(2)
        let horizontal = try horizontalHandle(for: rows)
        let narrowTop = try XCTUnwrap(DividerPlan.movedLayout(rows, handle: horizontal, toNormalized: 0.375))
        let expandedTop = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                narrowTop,
                handle: horizontal,
                toNormalized: 0.10,
                workAreaAX: work,
                gutter: 0,
                minSizes: [rows.zones[0].id: CGSize(width: 0, height: 350)]
            )
        )
        XCTAssertEqual(try resolvedFrame(rows.zones[0].id, in: expandedTop, gutter: 0).height, 350, accuracy: 2)

        let narrowBottom = try XCTUnwrap(DividerPlan.movedLayout(rows, handle: horizontal, toNormalized: 0.625))
        let expandedBottom = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                narrowBottom,
                handle: horizontal,
                toNormalized: 0.90,
                workAreaAX: work,
                gutter: 0,
                minSizes: [rows.zones[1].id: CGSize(width: 0, height: 350)]
            )
        )
        XCTAssertEqual(try resolvedFrame(rows.zones[1].id, in: expandedBottom, gutter: 0).height, 350, accuracy: 2)

        let tight = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                narrowLeft,
                handle: vertical,
                toNormalized: 0.10,
                workAreaAX: work,
                gutter: 0,
                minSizes: [
                    columns.zones[0].id: CGSize(width: 490, height: 0),
                    columns.zones[1].id: CGSize(width: 505, height: 0),
                ]
            )
        )
        XCTAssertEqual(try resolvedFrame(columns.zones[0].id, in: tight, gutter: 0).width, 490, accuracy: 2)
        XCTAssertGreaterThanOrEqual(try resolvedFrame(columns.zones[1].id, in: tight, gutter: 0).width + 0.5, 505)

        let opposite = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                narrowLeft,
                handle: vertical,
                toNormalized: 0.05,
                workAreaAX: work,
                gutter: 0,
                minSizes: [
                    columns.zones[0].id: CGSize(width: 350, height: 0),
                    columns.zones[1].id: CGSize(width: 600, height: 0),
                ]
            )
        )
        XCTAssertEqual(try resolvedFrame(columns.zones[0].id, in: opposite, gutter: 0).width, 350, accuracy: 2)
        XCTAssertGreaterThanOrEqual(try resolvedFrame(columns.zones[1].id, in: opposite, gutter: 0).width + 0.5, 600)

        let canvas = Layout(
            name: "Narrow Canvas",
            kind: .canvas,
            zones: [
                Zone(number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 0.30, height: 1)),
                Zone(number: 2, canvasRect: NormalizedRect(x: 0.30, y: 0, width: 0.70, height: 1)),
            ]
        )
        let canvasHandle = DividerHandleSpec(
            axis: .vertical,
            afterIndex: 0,
            lineAX: work.minX + 300,
            spanAX: work.minY...work.maxY,
            slots: [
                DividerHandleSlot(zoneID: canvas.zones[0].id, identity: identities(count: 1)[0]),
                DividerHandleSlot(zoneID: canvas.zones[1].id, identity: WindowIdentity(pid: 2, windowNumber: 2)),
            ]
        )
        let canvasExpanded = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                canvas,
                handle: canvasHandle,
                toNormalized: 0.10,
                workAreaAX: work,
                gutter: 0,
                minSizes: [canvas.zones[0].id: CGSize(width: 350, height: 0)]
            )
        )
        XCTAssertEqual(try resolvedFrame(canvas.zones[0].id, in: canvasExpanded, gutter: 0).width, 350, accuracy: 2)

        let canvasRows = Layout(
            name: "Narrow Canvas Rows",
            kind: .canvas,
            zones: [
                Zone(number: 1, canvasRect: NormalizedRect(x: 0, y: 0, width: 1, height: 0.375)),
                Zone(number: 2, canvasRect: NormalizedRect(x: 0, y: 0.375, width: 1, height: 0.625)),
            ]
        )
        let canvasRowHandle = DividerHandleSpec(
            axis: .horizontal,
            afterIndex: 0,
            lineAX: work.minY + 300,
            spanAX: work.minX...work.maxX,
            slots: [
                DividerHandleSlot(zoneID: canvasRows.zones[0].id, identity: identities(count: 1)[0]),
                DividerHandleSlot(zoneID: canvasRows.zones[1].id, identity: WindowIdentity(pid: 2, windowNumber: 2)),
            ]
        )
        let canvasBottom = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                canvasRows,
                handle: canvasRowHandle,
                toNormalized: 0.10,
                workAreaAX: work,
                gutter: 0,
                minSizes: [canvasRows.zones[0].id: CGSize(width: 0, height: 350)]
            )
        )
        XCTAssertEqual(try resolvedFrame(canvasRows.zones[0].id, in: canvasBottom, gutter: 0).height, 350, accuracy: 2)

        let impossible = try XCTUnwrap(
            DividerPlan.clampedMovedLayout(
                narrowLeft,
                handle: vertical,
                toNormalized: 0.10,
                workAreaAX: work,
                gutter: 0,
                minSizes: [
                    columns.zones[0].id: CGSize(width: 700, height: 0),
                    columns.zones[1].id: CGSize(width: 400, height: 0),
                ]
            )
        )
        XCTAssertEqual(try resolvedFrame(columns.zones[0].id, in: impossible, gutter: 0).width, 300, accuracy: 2)
        let impossibleAgain = DividerPlan.clamping(
            impossible,
            toHandle: vertical,
            from: narrowLeft,
            workAreaAX: work,
            gutter: 0,
            minSizes: [
                columns.zones[0].id: CGSize(width: 700, height: 0),
                columns.zones[1].id: CGSize(width: 400, height: 0),
            ]
        )
        XCTAssertEqual(try resolvedFrame(columns.zones[0].id, in: impossibleAgain, gutter: 0).width, 300, accuracy: 2)
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

    private func verticalHandle(for layout: Layout) throws -> DividerHandleSpec {
        let windows = identities(count: layout.zones.count)
        let snapped = Dictionary(uniqueKeysWithValues: zip(layout.zones.map(\.id), windows.map { [$0] }))
        return try XCTUnwrap(try handles(for: layout, snapped: snapped).first { $0.axis == .vertical })
    }

    private func horizontalHandle(for layout: Layout) throws -> DividerHandleSpec {
        let windows = identities(count: layout.zones.count)
        let snapped = Dictionary(uniqueKeysWithValues: zip(layout.zones.map(\.id), windows.map { [$0] }))
        return try XCTUnwrap(try handles(for: layout, snapped: snapped).first { $0.axis == .horizontal })
    }

    private func resolvedFrame(_ zoneID: UUID, in layout: Layout, gutter: CGFloat) throws -> CGRect {
        let resolved = try resolveLayout(layout, workAreaAX: work, gutter: gutter)
        return try XCTUnwrap(resolved.first { $0.zoneID == zoneID }?.frameAX)
    }

    private func frames(of layout: Layout, gutter: CGFloat = 0) throws -> [UUID: CGRect] {
        let resolved = try resolveLayout(layout, workAreaAX: work, gutter: gutter)
        return Dictionary(uniqueKeysWithValues: resolved.map { ($0.zoneID, $0.frameAX) })
    }
}
