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
        XCTAssertEqual(decoded.profiles, [])
        XCTAssertNil(decoded.activeProfileID)
        XCTAssertEqual(decoded.layouts, [])

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                StoreDocument.self,
                from: Data("{\"schemaVersion\":1}".utf8)
            )
        )

        var document = StoreDocument()
        let first = document.layouts[0].id
        document.markLayoutUsed(first)
        let encoded = try JSONEncoder().encode(document)
        XCTAssertTrue(String(data: encoded, encoding: .utf8)?.contains("recentLayoutIDs") == true)
        let roundTrip = try JSONDecoder().decode(StoreDocument.self, from: encoded)
        XCTAssertEqual(roundTrip.recentLayoutIDs, [first])
    }

    func testProfilesRoundTripAndNormalizeDanglingReferences() throws {
        let layout = LayoutTemplates.columns(2)
        let displayID = UUID()
        let kept = WorkspaceProfile(
            name: "Coding",
            sections: [
                ProfileSection(
                    space: SpaceKey(displayID: displayID),
                    layoutID: layout.id,
                    rules: [AppPlacementRule(bundleID: "com.example.Editor", zoneID: layout.zones[0].id, zoneNumber: 1)]
                ),
            ]
        )
        let dangling = WorkspaceProfile(
            name: "Dangling",
            sections: [
                ProfileSection(
                    space: SpaceKey(displayID: displayID),
                    layoutID: UUID(),
                    rules: [AppPlacementRule(bundleID: "com.example.Other", zoneID: UUID(), zoneNumber: 1)]
                ),
            ]
        )
        let document = StoreDocument(layouts: [layout], profiles: [kept, dangling], activeProfileID: dangling.id)
        XCTAssertEqual(document.profiles, [kept])
        XCTAssertNil(document.activeProfileID)

        let decoded = try JSONDecoder().decode(StoreDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.profiles, [kept])
    }

    func testLegacyAutomaticPlacementFieldIsIgnoredAndNotReencoded() throws {
        let id = UUID()
        let json = Data(
            """
            {
              "id":"\(id.uuidString)",
              "name":"Legacy",
              "sections":[],
              "launchMissingApps":true,
              "autoPlaceNewWindows":true,
              "createdAt":0,
              "updatedAt":0
            }
            """.utf8
        )

        let profile = try JSONDecoder().decode(WorkspaceProfile.self, from: json)
        let encoded = try JSONEncoder().encode(profile)

        XCTAssertEqual(profile.name, "Legacy")
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("autoPlaceNewWindows"))
    }

    func testDeleteLayoutCascadesProfileSectionsAndActiveProfile() {
        let first = LayoutTemplates.columns(2)
        let second = LayoutTemplates.rows(2)
        let profile = WorkspaceProfile(
            name: "Coding",
            sections: [
                ProfileSection(
                    space: SpaceKey(displayID: UUID()),
                    layoutID: first.id,
                    rules: [AppPlacementRule(bundleID: "app", zoneID: first.zones[0].id, zoneNumber: 1)]
                ),
            ]
        )
        var document = StoreDocument(layouts: [first, second], profiles: [profile], activeProfileID: profile.id)
        XCTAssertTrue(document.deleteLayout(id: first.id))
        XCTAssertTrue(document.profiles.isEmpty)
        XCTAssertNil(document.activeProfileID)
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
