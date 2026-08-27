import XCTest
@testable import ZoneBoxCore

final class LayoutStoreTests: XCTestCase {
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
}
