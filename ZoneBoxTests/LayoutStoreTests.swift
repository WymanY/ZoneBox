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

    func testMergeDisplayMovesOrphanedSectionsAndAssignmentsToLiveIdentity() {
        let layout = LayoutTemplates.columns(2)
        let other = LayoutTemplates.rows(2)
        let stale = DisplayIdentity(localizedName: "Mi Monitor", visibleWidth: 1920, visibleHeight: 1049, backingScale: 2)
        let live = DisplayIdentity(localizedName: "Mi Monitor", visibleWidth: 1920, visibleHeight: 1049, backingScale: 2)
        let builtIn = DisplayIdentity(localizedName: "Built-in", visibleWidth: 1440, visibleHeight: 809, backingScale: 2)
        let rule = AppPlacementRule(bundleID: "app", zoneID: layout.zones[0].id, zoneNumber: 1)
        let orphaned = WorkspaceProfile(
            name: "Desk",
            sections: [ProfileSection(space: SpaceKey(displayID: stale.id), layoutID: layout.id, rules: [rule])]
        )
        let both = WorkspaceProfile(
            name: "Both",
            sections: [
                ProfileSection(space: SpaceKey(displayID: stale.id), layoutID: layout.id, rules: [rule]),
                ProfileSection(space: SpaceKey(displayID: live.id), layoutID: other.id, rules: [rule]),
                ProfileSection(space: SpaceKey(displayID: builtIn.id), layoutID: other.id, rules: [rule]),
            ]
        )
        var document = StoreDocument(
            layouts: [layout, other],
            displays: [builtIn, stale, live],
            assignments: [LayoutAssignment(space: SpaceKey(displayID: stale.id), layoutID: layout.id)],
            profiles: [orphaned, both]
        )

        document.mergeDisplay(stale.id, into: live.id)

        XCTAssertEqual(document.displays.map(\.id), [builtIn.id, live.id])
        XCTAssertEqual(document.assignments, [LayoutAssignment(space: SpaceKey(displayID: live.id), layoutID: layout.id)])
        XCTAssertEqual(document.profiles[0].sections.map(\.space.displayID), [live.id])
        XCTAssertEqual(document.profiles[1].sections.map(\.space.displayID), [live.id, builtIn.id])
        XCTAssertEqual(document.profiles[1].sections.map(\.layoutID), [other.id, other.id])
    }

    func testBestMatchRejectsAmbiguousNameAndSizeTies() {
        let left = DisplayIdentity(
            localizedName: "LG UltraFine",
            visibleWidth: 1920,
            visibleHeight: 1080,
            backingScale: 2
        )
        let right = DisplayIdentity(
            localizedName: "LG UltraFine",
            visibleWidth: 1920,
            visibleHeight: 1080,
            backingScale: 2
        )
        let probe = DisplayIdentity(
            uuid: UUID(),
            vendorNumber: 1,
            productNumber: 2,
            serialNumber: 3,
            localizedName: "LG UltraFine",
            visibleWidth: 1920,
            visibleHeight: 1080,
            backingScale: 2
        )

        XCTAssertNil(DisplayIdentity.bestMatch(probe: probe, candidates: [left, right]))
        XCTAssertEqual(DisplayIdentity.bestMatch(probe: probe, candidates: [left])?.0.id, left.id)
    }

    func testBestMatchStillAcceptsUniqueHardwareHitAmongIdenticalNames() {
        let left = DisplayIdentity(
            uuid: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            vendorNumber: 10,
            productNumber: 20,
            serialNumber: 30,
            localizedName: "LG UltraFine",
            visibleWidth: 1920,
            visibleHeight: 1080,
            backingScale: 2
        )
        let right = DisplayIdentity(
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555"),
            vendorNumber: 40,
            productNumber: 50,
            serialNumber: 60,
            localizedName: "LG UltraFine",
            visibleWidth: 1920,
            visibleHeight: 1080,
            backingScale: 2
        )
        let probe = DisplayIdentity(
            uuid: left.uuid,
            vendorNumber: left.vendorNumber,
            productNumber: left.productNumber,
            serialNumber: left.serialNumber,
            localizedName: "LG UltraFine",
            visibleWidth: 1920,
            visibleHeight: 1080,
            backingScale: 2
        )

        XCTAssertEqual(DisplayIdentity.bestMatch(probe: probe, candidates: [left, right])?.0.id, left.id)
    }

    func testMergeDisplayIgnoresUnknownLiveIdentity() {
        let stale = DisplayIdentity(localizedName: "A", visibleWidth: 1, visibleHeight: 1, backingScale: 1)
        var document = StoreDocument(displays: [stale])
        let before = document
        document.mergeDisplay(stale.id, into: UUID())
        XCTAssertEqual(document, before)
    }

    func testSettingsProfileOrderStaysPutWhenActiveProfileChanges() {
        let layout = LayoutTemplates.columns(2)
        let displayID = UUID()
        let older = Date(timeIntervalSince1970: 1)
        let newer = Date(timeIntervalSince1970: 2)
        func profile(name: String, createdAt: Date, updatedAt: Date) -> WorkspaceProfile {
            WorkspaceProfile(
                name: name,
                sections: [
                    ProfileSection(
                        space: SpaceKey(displayID: displayID),
                        layoutID: layout.id,
                        rules: [AppPlacementRule(bundleID: "app.\(name)", zoneID: layout.zones[0].id, zoneNumber: 1)]
                    )
                ],
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
        let first = profile(name: "First", createdAt: older, updatedAt: older)
        let second = profile(name: "Second", createdAt: newer, updatedAt: newer)
        var document = StoreDocument(layouts: [layout], profiles: [first, second], activeProfileID: first.id)
        XCTAssertEqual(document.orderedProfilesForSettings().map(\.name), ["First", "Second"])

        document.activeProfileID = second.id
        var recaptured = second
        recaptured.updatedAt = Date(timeIntervalSince1970: 99)
        document.upsertProfile(recaptured)
        XCTAssertEqual(document.orderedProfilesForSettings().map(\.name), ["First", "Second"])
        XCTAssertEqual(document.activeProfileID, second.id)
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
