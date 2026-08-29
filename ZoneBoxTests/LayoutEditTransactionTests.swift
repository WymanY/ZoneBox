import XCTest
@testable import ZoneBoxCore

final class LayoutEditTransactionTests: XCTestCase {
    private let displayID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let copyID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let workArea = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testNewLayoutDoesNotMutateDocumentUntilCommit() {
        var document = StoreDocument()
        let before = document
        let draft = LayoutTemplates.emptyCanvas(name: "Canvas 8")
        var transaction = LayoutEditTransaction(original: nil, draft: draft, targetDisplayID: displayID)

        XCTAssertEqual(document, before)
        XCTAssertFalse(transaction.canCommit)
        XCTAssertNil(transaction.layoutForCommit(existingNames: document.layouts.map(\.name)))

        var populatedDraft = LayoutTemplates.focus()
        populatedDraft.id = draft.id
        populatedDraft.name = draft.name
        populatedDraft.createdAt = draft.createdAt
        transaction.updateDraft(populatedDraft)
        let committed = transaction.layoutForCommit(
            existingNames: document.layouts.map(\.name),
            now: now
        )
        XCTAssertNotNil(committed)
        document.upsertAndAssign(committed!, to: transaction.targetDisplayID)

        XCTAssertEqual(document.layouts.count, before.layouts.count + 1)
        XCTAssertEqual(committed?.id, draft.id)
        XCTAssertEqual(committed?.name, draft.name)
        XCTAssertEqual(document.layout(for: displayID)?.id, committed?.id)
    }

    func testDeletingEveryZoneCannotCommit() {
        let original = LayoutTemplates.focus()
        var empty = original
        empty.zones = []
        var transaction = LayoutEditTransaction(original: original, draft: original, targetDisplayID: displayID)
        transaction.updateDraft(empty)

        XCTAssertFalse(transaction.canCommit)
        XCTAssertNil(transaction.layoutForCommit(existingNames: [original.name]))
    }

    func testUnchangedGridCommitIsNoOp() throws {
        let original = LayoutTemplates.columns(2)
        let transaction = LayoutEditTransaction(original: original, draft: original, targetDisplayID: displayID)

        XCTAssertFalse(transaction.hasChanges)
        XCTAssertNil(transaction.layoutForCommit(existingNames: [original.name]))
        XCTAssertEqual(original.kind, .grid)
    }

    func testExplicitlyNamedUnchangedGridCreatesGridCopy() throws {
        let original = LayoutTemplates.columns(2)
        let transaction = LayoutEditTransaction(original: original, draft: original, targetDisplayID: displayID)

        let committed = try XCTUnwrap(
            transaction.layoutForCommit(
                existingNames: [original.name],
                newID: copyID,
                now: now,
                requestedName: "Desk",
                createsCopy: true
            )
        )

        XCTAssertEqual(committed.id, copyID)
        XCTAssertEqual(committed.name, "Desk")
        XCTAssertEqual(committed.kind, .grid)
        XCTAssertEqual(committed.createdAt, now)
    }

    func testChangedGridUpdatesInPlace() throws {
        let original = LayoutTemplates.columns(2)
        var editable = original
        var transaction = LayoutEditTransaction(original: original, draft: editable, targetDisplayID: displayID)
        editable = try XCTUnwrap(GridEditing.moveLine(editable, axis: .vertical, afterIndex: 0, toNormalized: 0.4))
        transaction.updateDraft(editable)

        let committed = try XCTUnwrap(
            transaction.layoutForCommit(
                existingNames: [original.name, "Columns 2 Copy"],
                newID: copyID,
                now: now
            )
        )

        XCTAssertEqual(committed.id, original.id)
        XCTAssertEqual(committed.name, original.name)
        XCTAssertEqual(committed.kind, .grid)
        XCTAssertEqual(committed.grid?.columnWeights[0], 4_000)
        XCTAssertEqual(committed.createdAt, original.createdAt)
        XCTAssertEqual(committed.updatedAt, now)
        XCTAssertEqual(original.kind, .grid)
        XCTAssertEqual(original.id, transaction.original?.id)
    }

    func testChangedGridCommitUsesProvidedCopyName() throws {
        let original = LayoutTemplates.columns(2)
        var editable = original
        var transaction = LayoutEditTransaction(original: original, draft: editable, targetDisplayID: displayID)
        editable = try XCTUnwrap(GridEditing.moveLine(editable, axis: .vertical, afterIndex: 0, toNormalized: 0.4))
        transaction.updateDraft(editable)

        XCTAssertEqual(
            transaction.suggestedCopyName(existingNames: [original.name]),
            "Columns 2 Copy"
        )
        XCTAssertEqual(
            transaction.suggestedCopyName(
                sourceName: LayoutTemplates.columns(3).name,
                existingNames: [original.name]
            ),
            "Columns 3 Copy"
        )
        let committed = try XCTUnwrap(
            transaction.layoutForCommit(
                existingNames: [original.name, "Desk"],
                newID: copyID,
                now: now,
                requestedName: "  Desk  ",
                createsCopy: true
            )
        )
        XCTAssertEqual(committed.name, "Desk 2")
        XCTAssertEqual(committed.kind, .grid)
    }

    func testNewLayoutCommitUsesProvidedUniqueName() throws {
        let draft = LayoutTemplates.focus()
        let transaction = LayoutEditTransaction(original: nil, draft: draft, targetDisplayID: displayID)

        let committed = try XCTUnwrap(
            transaction.layoutForCommit(
                existingNames: ["Desk"],
                now: now,
                requestedName: "  Desk  "
            )
        )

        XCTAssertEqual(committed.id, draft.id)
        XCTAssertEqual(committed.name, "Desk 2")
        XCTAssertEqual(committed.updatedAt, now)
    }

    func testSuggestedCopyNameDoesNotStackCopySuffix() {
        XCTAssertEqual(LayoutEditTransaction.copyBaseName(from: "Priority 3 Copy 2 Copy"), "Priority 3 Copy")
        XCTAssertEqual(LayoutEditTransaction.copyBaseName(from: "Columns 2"), "Columns 2 Copy")
        XCTAssertEqual(
            LayoutEditTransaction.uniqueName(
                base: LayoutEditTransaction.copyBaseName(from: "Priority 3 Copy"),
                existingNames: ["Priority 3", "Priority 3 Copy"]
            ),
            "Priority 3 Copy 2"
        )
    }

    func testExistingCanvasUpdatesInPlace() throws {
        let original = LayoutTemplates.focus()
        var changed = original
        changed.zones[0].canvasRect?.width = 0.7
        var transaction = LayoutEditTransaction(original: original, draft: original, targetDisplayID: displayID)
        transaction.updateDraft(changed)

        let committed = try XCTUnwrap(
            transaction.layoutForCommit(existingNames: [original.name], newID: copyID, now: now)
        )

        XCTAssertEqual(committed.id, original.id)
        XCTAssertEqual(committed.createdAt, original.createdAt)
        XCTAssertEqual(committed.updatedAt, now)
        XCTAssertEqual(committed.zones[0].canvasRect?.width, 0.7)
    }

    func testExistingCanvasCanSaveAsNamedCopy() throws {
        let original = LayoutTemplates.focus()
        let transaction = LayoutEditTransaction(
            original: original,
            draft: original,
            targetDisplayID: displayID
        )

        let committed = try XCTUnwrap(
            transaction.layoutForCommit(
                existingNames: [original.name, "Focus Copy"],
                newID: copyID,
                now: now,
                requestedName: "Focus Copy",
                createsCopy: true
            )
        )

        XCTAssertEqual(committed.id, copyID)
        XCTAssertEqual(committed.name, "Focus Copy 2")
        XCTAssertEqual(committed.createdAt, now)
        XCTAssertEqual(committed.kind, .canvas)
        XCTAssertEqual(transaction.original?.id, original.id)
    }

    func testDocumentUpsertAssignsCapturedDisplay() {
        var document = StoreDocument()
        let layout = LayoutTemplates.focus()

        document.upsertAndAssign(layout, to: displayID)

        XCTAssertEqual(document.layout(for: displayID)?.id, layout.id)
        XCTAssertEqual(document.layouts.filter { $0.id == layout.id }.count, 1)
    }

    func testDeleteLayoutReassignsDisplaysAndKeepsLastLayout() {
        var document = StoreDocument(layouts: [
            LayoutTemplates.columns(2),
            LayoutTemplates.focus(),
        ])
        let first = document.layouts[0]
        let second = document.layouts[1]
        document.assign(layoutID: second.id, to: displayID)

        XCTAssertTrue(document.deleteLayout(id: second.id))
        XCTAssertEqual(document.layouts.map { $0.id }, [first.id])
        XCTAssertEqual(document.layout(for: displayID)?.id, first.id)
        XCTAssertFalse(document.deleteLayout(id: first.id))
        XCTAssertEqual(document.layouts.map { $0.id }, [first.id])
    }

    func testThumbnailGeometryMatchesSavedCanvasPanes() {
        let layout = Layout(
            name: "cool 2",
            kind: .canvas,
            zones: [
                Zone(number: 1, canvasRect: NormalizedRect(x: 0, y: 0.12, width: 0.49, height: 0.77)),
                Zone(number: 2, canvasRect: NormalizedRect(x: 0.49, y: 0.12, width: 0.21, height: 0.77)),
                Zone(number: 3, canvasRect: NormalizedRect(x: 0.70, y: 0.12, width: 0.29, height: 0.77)),
            ]
        )
        let geometry = LayoutTemplates.thumbnailGeometry(for: layout)
        XCTAssertEqual(geometry.map { $0.number }, [1, 2, 3])
        XCTAssertEqual(geometry[0].rect.x, 0, accuracy: 0.0001)
        XCTAssertEqual(geometry[1].rect.x, 0.49, accuracy: 0.0001)
        XCTAssertEqual(geometry[2].rect.x, 0.70, accuracy: 0.0001)
        XCTAssertEqual(geometry[0].rect.width, 0.49, accuracy: 0.0001)
        XCTAssertEqual(geometry[1].rect.width, 0.21, accuracy: 0.0001)
        XCTAssertEqual(geometry[2].rect.width, 0.29, accuracy: 0.0001)
    }

    func testColumnsThumbnailUsesVerticalPanes() {
        let geometry = LayoutTemplates.thumbnailGeometry(for: LayoutTemplates.columns(3))
        XCTAssertEqual(geometry.map { $0.number }, [1, 2, 3])
        XCTAssertEqual(geometry[0].rect.x, 0, accuracy: 0.001)
        XCTAssertLessThan(geometry[0].rect.x, geometry[1].rect.x)
        XCTAssertLessThan(geometry[1].rect.x, geometry[2].rect.x)
        XCTAssertEqual(geometry[0].rect.y, 0, accuracy: 0.001)
        XCTAssertEqual(geometry[0].rect.height, 1, accuracy: 0.001)
    }

    func testGridConversionNumbersFollowReadingOrder() throws {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let columns = try LayoutTemplates.columns(3).convertingGridToCanvas(workAreaAX: work)
        let columnZones = columns.zones.sorted { $0.number < $1.number }
        XCTAssertEqual(columnZones.map(\.number), [1, 2, 3])
        XCTAssertLessThan(columnZones[0].canvasRect!.x, columnZones[1].canvasRect!.x)
        XCTAssertLessThan(columnZones[1].canvasRect!.x, columnZones[2].canvasRect!.x)

        let rows = try LayoutTemplates.rows(2).convertingGridToCanvas(workAreaAX: work)
        let rowZones = rows.zones.sorted { $0.number < $1.number }
        XCTAssertLessThan(rowZones[0].canvasRect!.y, rowZones[1].canvasRect!.y)

        let grid = try LayoutTemplates.grid2x2().convertingGridToCanvas(workAreaAX: work)
        let byNumber = Dictionary(uniqueKeysWithValues: grid.zones.map { ($0.number, $0.canvasRect!) })
        XCTAssertLessThan(byNumber[1]!.x, byNumber[2]!.x)
        XCTAssertLessThan(byNumber[1]!.y, byNumber[3]!.y)
        XCTAssertLessThan(byNumber[2]!.y, byNumber[4]!.y)
        XCTAssertLessThan(byNumber[3]!.x, byNumber[4]!.x)
    }

    func testEditorPresetSelectionMatchesGridAndSavedCanvasCopyByGeometry() throws {
        let grid = LayoutTemplates.columns(3)
        XCTAssertEqual(LayoutTemplates.matchingEditorPresetIndex(for: grid, workAreaAX: workArea), 1)

        var copy = try grid.convertingGridToCanvas(workAreaAX: workArea)
        copy.name = "My Desk"
        XCTAssertEqual(LayoutTemplates.matchingEditorPresetIndex(for: copy, workAreaAX: workArea), 1)

        copy.zones[0].canvasRect?.width = 0.2
        XCTAssertNil(LayoutTemplates.matchingEditorPresetIndex(for: copy, workAreaAX: workArea))
    }

    func testEditorToolbarOffersSavedLayoutOnlyWhenItIsNotAPreset() throws {
        XCTAssertNil(
            LayoutTemplates.editorToolbarSavedLayout(
                original: LayoutTemplates.columns(3),
                isNew: false,
                workAreaAX: workArea
            )
        )
        XCTAssertNil(
            LayoutTemplates.editorToolbarSavedLayout(
                original: LayoutTemplates.focus(),
                isNew: false,
                workAreaAX: workArea
            )
        )

        var renamedPreset = try LayoutTemplates.columns(3).convertingGridToCanvas(workAreaAX: workArea)
        renamedPreset.name = "My Desk"
        XCTAssertNil(
            LayoutTemplates.editorToolbarSavedLayout(
                original: renamedPreset,
                isNew: false,
                workAreaAX: workArea
            )
        )
        XCTAssertNil(
            LayoutTemplates.editorToolbarSavedLayout(
                original: LayoutTemplates.emptyCanvas(name: "Canvas 8"),
                isNew: true,
                workAreaAX: workArea
            )
        )

        let rows3 = LayoutTemplates.rows(3)
        XCTAssertEqual(
            LayoutTemplates.editorToolbarSavedLayout(
                original: rows3,
                isNew: false,
                workAreaAX: workArea
            )?.name,
            "Rows 3"
        )

        var custom = try LayoutTemplates.columns(3).convertingGridToCanvas(workAreaAX: workArea)
        custom.name = "My Desk"
        custom.zones[0].canvasRect?.width = 0.2
        XCTAssertEqual(
            LayoutTemplates.editorToolbarSavedLayout(
                original: custom,
                isNew: false,
                workAreaAX: workArea
            )?.id,
            custom.id
        )
        XCTAssertNil(
            LayoutTemplates.editorToolbarSavedLayout(
                original: custom,
                isNew: true,
                workAreaAX: workArea
            )
        )

        var empty = custom
        empty.zones = []
        XCTAssertNil(
            LayoutTemplates.editorToolbarSavedLayout(
                original: empty,
                isNew: false,
                workAreaAX: workArea
            )
        )
    }

    func testCycledZoneIDWrapsInNumberOrder() {
        let a = Zone(number: 1)
        let b = Zone(number: 2)
        let c = Zone(number: 3)
        let layout = Layout(name: "Canvas", kind: .canvas, zones: [c, a, b])

        XCTAssertEqual(layout.cycledZoneID(from: nil, forward: true), a.id)
        XCTAssertEqual(layout.cycledZoneID(from: nil, forward: false), c.id)
        XCTAssertEqual(layout.cycledZoneID(from: a.id, forward: true), b.id)
        XCTAssertEqual(layout.cycledZoneID(from: b.id, forward: true), c.id)
        XCTAssertEqual(layout.cycledZoneID(from: c.id, forward: true), a.id)
        XCTAssertEqual(layout.cycledZoneID(from: a.id, forward: false), c.id)
        XCTAssertEqual(layout.cycledZoneID(from: b.id, forward: false), a.id)
    }

    func testTabFollowsPaintedNumbersNotPosition() {
        let right = Zone(
            number: 1,
            canvasRect: NormalizedRect(x: 0.55, y: 0.1, width: 0.3, height: 0.3)
        )
        let left = Zone(
            number: 2,
            canvasRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        )
        let layout = Layout(name: "Canvas", kind: .canvas, zones: [right, left])

        XCTAssertEqual(layout.cycledZoneID(from: nil, forward: true), right.id)
        XCTAssertEqual(layout.cycledZoneID(from: right.id, forward: true), left.id)
        XCTAssertEqual(layout.cycledZoneID(from: left.id, forward: true), right.id)
    }

    func testCycledZoneIDEmptyAndCreating() {
        let empty = Layout(name: "Canvas", kind: .canvas, zones: [])
        XCTAssertNil(empty.cycledZoneID(from: nil, forward: true))

        let live = Zone(number: 1)
        let creating = Zone(number: 2, name: "__creating")
        let layout = Layout(name: "Canvas", kind: .canvas, zones: [live, creating])
        XCTAssertEqual(layout.cycledZoneID(from: nil, forward: true), live.id)
        XCTAssertEqual(layout.cycledZoneID(from: live.id, forward: true), live.id)
    }

    func testArrowKeysMoveToSpatiallyAdjacentPanes() throws {
        let grid = try LayoutTemplates.grid2x2().convertingGridToCanvas(workAreaAX: workArea)
        func zoneID(in layout: Layout, atX x: Double, y: Double) -> UUID {
            layout.zones.first { zone in
                guard let rect = zone.canvasRect else { return false }
                return abs(rect.x - x) < 0.001 && abs(rect.y - y) < 0.001
            }!.id
        }
        let topLeft = zoneID(in: grid, atX: 0.0, y: 0.0)
        let topRight = zoneID(in: grid, atX: 0.5, y: 0.0)
        let bottomLeft = zoneID(in: grid, atX: 0.0, y: 0.5)
        let bottomRight = zoneID(in: grid, atX: 0.5, y: 0.5)

        XCTAssertEqual(grid.neighborZoneID(from: topLeft, direction: .right), topRight)
        XCTAssertEqual(grid.neighborZoneID(from: topLeft, direction: .down), bottomLeft)
        XCTAssertEqual(grid.neighborZoneID(from: topRight, direction: .left), topLeft)
        XCTAssertEqual(grid.neighborZoneID(from: bottomRight, direction: .up), topRight)
        XCTAssertEqual(grid.neighborZoneID(from: topLeft, direction: .left), topLeft)
        XCTAssertEqual(grid.neighborZoneID(from: topLeft, direction: .up), topLeft)

        let priority = try LayoutTemplates.priority3().convertingGridToCanvas(workAreaAX: workArea)
        let left = zoneID(in: priority, atX: 0.0, y: 0.0)
        let topRightPriority = zoneID(in: priority, atX: 0.5, y: 0.0)
        let bottomRightPriority = zoneID(in: priority, atX: 0.5, y: 0.5)
        XCTAssertEqual(priority.neighborZoneID(from: left, direction: .right), topRightPriority)
        XCTAssertEqual(priority.neighborZoneID(from: topRightPriority, direction: .down), bottomRightPriority)
        XCTAssertEqual(priority.neighborZoneID(from: bottomRightPriority, direction: .left), left)

        XCTAssertEqual(priority.neighborZoneID(from: bottomRightPriority, direction: .up), topRightPriority)
        XCTAssertEqual(priority.neighborZoneID(from: topRightPriority, direction: .left), left)

        let scatteredLeft = Zone(number: 2, canvasRect: NormalizedRect(x: 0.0, y: 0.1, width: 0.3, height: 0.3))
        let scatteredRight = Zone(number: 1, canvasRect: NormalizedRect(x: 0.55, y: 0.1, width: 0.3, height: 0.3))
        let scattered = Layout(name: "Canvas", kind: .canvas, zones: [scatteredRight, scatteredLeft])
        XCTAssertEqual(scattered.neighborZoneID(from: scatteredRight.id, direction: .left), scatteredLeft.id)
        XCTAssertEqual(scattered.neighborZoneID(from: scatteredLeft.id, direction: .right), scatteredRight.id)
        XCTAssertEqual(scattered.neighborZoneID(from: nil, direction: .right), scatteredLeft.id)
    }

    func testColumns3WASDStaysOnAdjacentPane() throws {
        let columns = try LayoutTemplates.columns(3).convertingGridToCanvas(workAreaAX: workArea)
        let ordered = columns.zones.sorted { $0.canvasRect!.x < $1.canvasRect!.x }
        XCTAssertEqual(ordered.count, 3)
        let left = ordered[0]
        let middle = ordered[1]
        let right = ordered[2]

        XCTAssertEqual(columns.neighborZoneID(from: left.id, direction: .right), middle.id)
        XCTAssertEqual(columns.neighborZoneID(from: middle.id, direction: .right), right.id)
        XCTAssertEqual(columns.neighborZoneID(from: right.id, direction: .left), middle.id)
        XCTAssertEqual(columns.neighborZoneID(from: left.id, direction: .up), left.id)
        XCTAssertEqual(columns.neighborZoneID(from: left.id, direction: .down), left.id)
        XCTAssertEqual(columns.neighborZoneID(from: middle.id, direction: .up), middle.id)
        XCTAssertEqual(columns.neighborZoneID(from: middle.id, direction: .left), left.id)
    }

    func testColumns3DoesNotSkipOverlappingAdjacentPane() {
        let left = Zone(number: 1, canvasRect: NormalizedRect(x: 0.0, y: 0.0, width: 0.34, height: 1))
        let middle = Zone(number: 2, canvasRect: NormalizedRect(x: 0.333, y: 0.0, width: 0.334, height: 1))
        let right = Zone(number: 3, canvasRect: NormalizedRect(x: 0.667, y: 0.0, width: 0.333, height: 1))
        let layout = Layout(name: "Columns 3", kind: .canvas, zones: [left, middle, right])

        XCTAssertEqual(layout.neighborZoneID(from: left.id, direction: .right), middle.id)
        XCTAssertEqual(layout.neighborZoneID(from: middle.id, direction: .right), right.id)
        XCTAssertEqual(layout.neighborZoneID(from: middle.id, direction: .left), left.id)
        XCTAssertEqual(layout.neighborZoneID(from: left.id, direction: .up), left.id)
    }

    func testColumns3DoesNotSkipWhenRightPaneIsNarrower() {
        let left = Zone(number: 1, canvasRect: NormalizedRect(x: 0.00, y: 0.0, width: 0.40, height: 1))
        let middle = Zone(number: 2, canvasRect: NormalizedRect(x: 0.38, y: 0.0, width: 0.40, height: 1))
        let right = Zone(number: 3, canvasRect: NormalizedRect(x: 0.76, y: 0.0, width: 0.24, height: 1))
        let layout = Layout(name: "Columns 3", kind: .canvas, zones: [left, middle, right])

        XCTAssertEqual(layout.neighborZoneID(from: left.id, direction: .right), middle.id)
        XCTAssertEqual(layout.neighborZoneID(from: middle.id, direction: .right), right.id)
        XCTAssertEqual(layout.neighborZoneID(from: right.id, direction: .left), middle.id)
        XCTAssertEqual(layout.neighborZoneID(from: middle.id, direction: .left), left.id)
    }

    func testPriorityBottomPaneWSelectsStackedPaneNotWrappingLeft() {
        let left = Zone(number: 1, canvasRect: NormalizedRect(x: 0.0, y: 0.0, width: 0.52, height: 1))
        let topRight = Zone(number: 2, canvasRect: NormalizedRect(x: 0.5, y: 0.0, width: 0.5, height: 0.5))
        let bottomRight = Zone(number: 3, canvasRect: NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let layout = Layout(name: "Code", kind: .canvas, zones: [left, topRight, bottomRight])

        XCTAssertEqual(layout.neighborZoneID(from: bottomRight.id, direction: .up), topRight.id)
        XCTAssertEqual(layout.neighborZoneID(from: topRight.id, direction: .down), bottomRight.id)
        XCTAssertEqual(layout.neighborZoneID(from: bottomRight.id, direction: .left), left.id)
        XCTAssertEqual(layout.neighborZoneID(from: topRight.id, direction: .left), left.id)
        XCTAssertEqual(layout.neighborZoneID(from: left.id, direction: .right), topRight.id)
    }

    func testColumns3NeighborSurvivesOffOriginWorkArea() throws {
        let work = CGRect(x: 123.7, y: 45.3, width: 1600, height: 1000)
        let columns = try LayoutTemplates.columns(3).convertingGridToCanvas(workAreaAX: work)
        let ordered = columns.zones.sorted { $0.canvasRect!.x < $1.canvasRect!.x }
        XCTAssertEqual(columns.neighborZoneID(from: ordered[0].id, direction: .right), ordered[1].id)
        XCTAssertEqual(columns.neighborZoneID(from: ordered[1].id, direction: .right), ordered[2].id)
        XCTAssertEqual(columns.neighborZoneID(from: ordered[0].id, direction: .up), ordered[0].id)
    }

    func testEditorTargetStaysCapturedAndUnavailableTargetDoesNotRetarget() {
        let otherDisplayID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        let layout = LayoutTemplates.focus()
        let transaction = LayoutEditTransaction(
            original: layout,
            draft: layout,
            targetDisplayID: displayID
        )

        XCTAssertEqual(transaction.targetDisplayID, displayID)
        XCTAssertTrue(transaction.targetIsAvailable(in: [otherDisplayID, displayID]))
        XCTAssertFalse(transaction.targetIsAvailable(in: [otherDisplayID]))
        XCTAssertEqual(transaction.targetDisplayID, displayID)
    }
}
