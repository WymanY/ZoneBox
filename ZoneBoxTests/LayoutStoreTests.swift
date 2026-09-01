import XCTest
@testable import ZoneBoxCore

final class LayoutStoreTests: XCTestCase {
    func testDefaultDirectoryFollowsAppIdentity() {
        let store = LayoutStore()
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().lastPathComponent, AppIdentity.bundleID)
        XCTAssertEqual(store.fileURL.lastPathComponent, "store.json")
    }

    func testRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LayoutStore(directory: dir)
        var doc = StoreDocument()
        doc.layouts.append(LayoutTemplates.focus())
        try store.save(doc)
        let loaded = try store.load()
        XCTAssertEqual(loaded.layouts.count, doc.layouts.count)
        XCTAssertEqual(loaded.layouts.last?.name, "Focus")
    }

    func testGridWeights() throws {
        let layout = LayoutTemplates.columns(3)
        XCTAssertEqual(layout.grid?.columnWeights.reduce(0, +), 10_000)
        let area = CGRect(x: 0, y: 0, width: 3000, height: 1000)
        let zones = try resolveLayout(layout, workAreaAX: area, gutter: 0)
        XCTAssertEqual(zones.count, 3)
        XCTAssertEqual(zones.map(\.number), [1, 2, 3])
    }

    func testLegacyStoreJSONDecodesWithoutRecentLayoutIDs() throws {
        let json = """
        {"schemaVersion":1,"layouts":[],"displays":[],"assignments":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StoreDocument.self, from: json)
        XCTAssertEqual(decoded.recentLayoutIDs, [])
        XCTAssertEqual(decoded.layouts, [])

        let missingField = Data("{\"schemaVersion\":1}".utf8)
        let legacy = try JSONDecoder().decode(StoreDocument.self, from: missingField)
        XCTAssertEqual(legacy.recentLayoutIDs, [])
        XCTAssertEqual(legacy.layouts.map(\.name), LayoutTemplates.all().map(\.name))

        var document = StoreDocument()
        let first = document.layouts[0].id
        document.markLayoutUsed(first)
        let encoded = try JSONEncoder().encode(document)
        XCTAssertTrue(String(data: encoded, encoding: .utf8)?.contains("recentLayoutIDs") == true)
        let roundTrip = try JSONDecoder().decode(StoreDocument.self, from: encoded)
        XCTAssertEqual(roundTrip.recentLayoutIDs, [first])
    }

    func testMarkLayoutUsedDedupesAndDeleteCleansMRU() {
        var document = StoreDocument(layouts: LayoutTemplates.all())
        let first = document.layouts[0].id
        let second = document.layouts[1].id
        document.markLayoutUsed(first)
        document.markLayoutUsed(second)
        document.markLayoutUsed(first)
        XCTAssertEqual(document.recentLayoutIDs.first, first)
        XCTAssertEqual(document.recentLayoutIDs.filter { $0 == first }.count, 1)
        XCTAssertTrue(document.deleteLayout(id: first))
        XCTAssertFalse(document.recentLayoutIDs.contains(first))
    }
}
