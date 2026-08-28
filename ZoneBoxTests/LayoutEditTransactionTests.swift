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
        let editable = try original.convertingGridToCanvas(workAreaAX: workArea)
        let transaction = LayoutEditTransaction(original: original, draft: editable, targetDisplayID: displayID)

        XCTAssertFalse(transaction.hasChanges)
        XCTAssertNil(transaction.layoutForCommit(existingNames: [original.name]))
        XCTAssertEqual(original.kind, .grid)
    }

    func testChangedGridCommitsAsUniqueCopy() throws {
        let original = LayoutTemplates.columns(2)
        var editable = try original.convertingGridToCanvas(workAreaAX: workArea)
        var transaction = LayoutEditTransaction(original: original, draft: editable, targetDisplayID: displayID)
        editable.zones[0].canvasRect?.width = 0.4
        transaction.updateDraft(editable)

        let committed = try XCTUnwrap(
            transaction.layoutForCommit(
                existingNames: [original.name, "Columns 2 Copy"],
                newID: copyID,
                now: now
            )
        )

        XCTAssertEqual(committed.id, copyID)
        XCTAssertEqual(committed.name, "Columns 2 Copy 2")
        XCTAssertEqual(committed.kind, .canvas)
        XCTAssertEqual(committed.createdAt, now)
        XCTAssertEqual(original.kind, .grid)
        XCTAssertEqual(original.id, transaction.original?.id)
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

    func testDocumentUpsertAssignsCapturedDisplay() {
        var document = StoreDocument()
        let layout = LayoutTemplates.focus()

        document.upsertAndAssign(layout, to: displayID)

        XCTAssertEqual(document.layout(for: displayID)?.id, layout.id)
        XCTAssertEqual(document.layouts.filter { $0.id == layout.id }.count, 1)
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

    func testCycledZoneIDEmptyAndCreating() {
        let empty = Layout(name: "Canvas", kind: .canvas, zones: [])
        XCTAssertNil(empty.cycledZoneID(from: nil, forward: true))

        let live = Zone(number: 1)
        let creating = Zone(number: 2, name: "__creating")
        let layout = Layout(name: "Canvas", kind: .canvas, zones: [live, creating])
        XCTAssertEqual(layout.cycledZoneID(from: nil, forward: true), live.id)
        XCTAssertEqual(layout.cycledZoneID(from: live.id, forward: true), live.id)
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
