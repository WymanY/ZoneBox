import XCTest
@testable import ZoneBoxCore

final class LayoutStripGeometryTests: XCTestCase {
    func testCardsSitCenteredAtTopAndHitMiniZones() {
        let workAppKit = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let workAX = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = Layout(name: "Left", kind: .canvas, zones: [])
        let right = Layout(name: "Right", kind: .canvas, zones: [])
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: workAppKit,
            layouts: [
                (left, [
                    ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 800)),
                    ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 800)),
                ]),
                (right, [
                    ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 1000, height: 800)),
                ]),
            ],
            assignedLayoutID: left.id,
            workAreaAX: workAX
        )

        XCTAssertEqual(geometry.cards.count, 2)
        XCTAssertEqual(geometry.cards[0].isAssigned, true)
        XCTAssertEqual(geometry.frameAppKit.midX, workAppKit.midX, accuracy: 0.5)
        XCTAssertEqual(geometry.frameAppKit.maxY, workAppKit.maxY - LayoutStripGeometry.topInset + 8, accuracy: 0.5)

        let firstMini = geometry.cards[0].zones[0].frameAppKit
        let hit = geometry.hitZone(at: CGPoint(x: firstMini.midX, y: firstMini.midY))
        XCTAssertEqual(hit?.layoutID, left.id)
        XCTAssertEqual(hit?.zoneNumber, 1)

        XCTAssertNil(geometry.hitZone(at: CGPoint(x: geometry.frameAppKit.minX + 2, y: geometry.frameAppKit.minY + 2)))
        XCTAssertTrue(geometry.contains(CGPoint(x: geometry.frameAppKit.midX, y: geometry.frameAppKit.midY)))
        let justBelow = CGPoint(x: firstMini.midX, y: geometry.frameAppKit.minY - 24)
        XCTAssertFalse(geometry.contains(justBelow))
        XCTAssertTrue(geometry.containsDropLinger(justBelow))
        let justAbove = CGPoint(x: geometry.frameAppKit.midX, y: geometry.frameAppKit.maxY + 24)
        XCTAssertFalse(geometry.contains(justAbove))
        XCTAssertFalse(geometry.containsDropLinger(justAbove))
        let probed = geometry.dropProbePoint(for: justBelow)
        let lingerHit = geometry.hitZone(at: probed)
        XCTAssertEqual(lingerHit?.layoutID, left.id)
        XCTAssertEqual(lingerHit?.zoneNumber, 1)

        let secondMini = geometry.cards[0].zones[1].frameAppKit
        let belowSecond = CGPoint(x: secondMini.midX, y: geometry.frameAppKit.minY - 24)
        let secondHit = geometry.hitZone(at: geometry.dropProbePoint(for: belowSecond))
        XCTAssertEqual(secondHit?.layoutID, left.id)
        XCTAssertEqual(secondHit?.zoneNumber, 2)

        let otherCard = geometry.cards[1]
        let belowOther = CGPoint(x: otherCard.frameAppKit.midX, y: geometry.frameAppKit.minY - 24)
        let otherHit = geometry.hitZone(at: geometry.dropProbePoint(for: belowOther))
        XCTAssertEqual(otherHit?.layoutID, right.id)
        XCTAssertEqual(otherHit?.zoneNumber, 1)

        let chromeBelow = CGPoint(x: firstMini.midX, y: geometry.cards[0].frameAppKit.minY - 4)
        XCTAssertTrue(geometry.contains(chromeBelow))
        XCTAssertFalse(geometry.cards[0].frameAppKit.contains(chromeBelow))
        let chromeHit = geometry.hitZone(at: geometry.dropProbePoint(for: chromeBelow))
        XCTAssertEqual(chromeHit?.layoutID, left.id)
        XCTAssertEqual(chromeHit?.zoneNumber, 1)
    }

    func testDropProbeKeepsSelectedRowWhenPointerLingersBelow() throws {
        let workAppKit = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let workAX = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rows = Layout(name: "Rows", kind: .canvas, zones: [])
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: workAppKit,
            layouts: [
                (rows, [
                    ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 1000, height: 400)),
                    ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 0, y: 400, width: 1000, height: 400)),
                ]),
            ],
            assignedLayoutID: rows.id,
            workAreaAX: workAX
        )

        let bottomMini = try XCTUnwrap(geometry.cards[0].zones.first { $0.number == 2 }?.frameAppKit)
        let justBelow = CGPoint(x: bottomMini.midX, y: geometry.frameAppKit.minY - 24)
        let naive = geometry.hitZone(at: geometry.dropProbePoint(for: justBelow))
        XCTAssertEqual(naive?.zoneNumber, 1)

        let preserved = geometry.dropProbePoint(
            for: justBelow,
            preservingLayoutID: rows.id,
            zoneNumber: 2
        )
        let hit = geometry.hitZone(at: preserved)
        XCTAssertEqual(hit?.layoutID, rows.id)
        XCTAssertEqual(hit?.zoneNumber, 2)
    }

    func testCardInteriorHitsNearestMiniZone() {
        let workAppKit = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let workAX = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = Layout(name: "Left", kind: .canvas, zones: [])
        let right = Layout(name: "Right", kind: .canvas, zones: [])
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: workAppKit,
            layouts: [
                (left, [
                    ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 800)),
                    ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 800)),
                ]),
                (right, [
                    ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 1000, height: 800)),
                ]),
            ],
            assignedLayoutID: left.id,
            workAreaAX: workAX
        )

        let card = geometry.cards[1]
        let gap = CGPoint(x: card.frameAppKit.minX + 3, y: card.frameAppKit.midY)
        XCTAssertFalse(card.zones.contains { $0.frameAppKit.contains(gap) })
        let hit = geometry.hitZone(at: gap)
        XCTAssertEqual(hit?.layoutID, right.id)
        XCTAssertEqual(hit?.zoneNumber, 1)
        XCTAssertNil(geometry.hitMiniZone(at: gap))
    }

    func testHitMiniZoneIgnoresChromeAndLinger() {
        let workAppKit = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let workAX = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = Layout(name: "Split", kind: .canvas, zones: [])
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: workAppKit,
            layouts: [
                (layout, [
                    ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 500, height: 800)),
                    ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 500, y: 0, width: 500, height: 800)),
                ]),
            ],
            assignedLayoutID: layout.id,
            workAreaAX: workAX
        )
        let mini = geometry.cards[0].zones[1].frameAppKit
        let hit = geometry.hitMiniZone(at: CGPoint(x: mini.midX, y: mini.midY))
        XCTAssertEqual(hit?.layoutID, layout.id)
        XCTAssertEqual(hit?.zoneNumber, 2)

        let below = CGPoint(x: mini.midX, y: geometry.frameAppKit.minY - 24)
        XCTAssertTrue(geometry.containsDropLinger(below))
        XCTAssertNil(geometry.hitMiniZone(at: below))
    }

    func testOverflowTruncatesToSixCards() {
        let layouts = (0..<8).map { index -> (Layout, [ResolvedZone]) in
            let layout = Layout(name: "L\(index)", kind: .canvas, zones: [])
            return (layout, [ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 100, height: 100))])
        }
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: CGRect(x: 0, y: 0, width: 1600, height: 900),
            layouts: layouts,
            assignedLayoutID: layouts[0].0.id,
            workAreaAX: CGRect(x: 0, y: 0, width: 1600, height: 900)
        )
        XCTAssertEqual(geometry.cards.count, 6)
        XCTAssertNotNil(geometry.overflowFrameAppKit)
        XCTAssertNil(geometry.leadingOverflowFrameAppKit)
        XCTAssertEqual(geometry.cards.map(\.layoutName), ["L0", "L1", "L2", "L3", "L4", "L5"])
    }

    func testVisibleWindowFollowsFocusedLayoutPastTheFirstPage() {
        XCTAssertEqual(LayoutStripGeometry.visibleCardRange(layoutCount: 8, focusedIndex: 0), 0..<6)
        XCTAssertEqual(LayoutStripGeometry.visibleCardRange(layoutCount: 8, focusedIndex: 5), 0..<6)
        XCTAssertEqual(LayoutStripGeometry.visibleCardRange(layoutCount: 8, focusedIndex: 6), 1..<7)
        XCTAssertEqual(LayoutStripGeometry.visibleCardRange(layoutCount: 8, focusedIndex: 7), 2..<8)
        XCTAssertEqual(LayoutStripGeometry.visibleCardRange(layoutCount: 3, focusedIndex: 2), 0..<3)
        XCTAssertEqual(
            LayoutStripGeometry.visibleCardRange(layoutCount: 8, focusedIndex: 1, previousStart: 2),
            1..<7
        )
        XCTAssertEqual(
            LayoutStripGeometry.visibleCardRange(layoutCount: 8, focusedIndex: 6, previousStart: 1),
            1..<7
        )

        let layouts = (0..<8).map { index -> (Layout, [ResolvedZone]) in
            let layout = Layout(name: "L\(index)", kind: .canvas, zones: [])
            return (layout, [ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 100, height: 100))])
        }
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: CGRect(x: 0, y: 0, width: 1600, height: 900),
            layouts: layouts,
            assignedLayoutID: layouts[0].0.id,
            workAreaAX: CGRect(x: 0, y: 0, width: 1600, height: 900),
            focusedLayoutID: layouts[7].0.id
        )
        XCTAssertEqual(geometry.cards.map(\.layoutName), ["L2", "L3", "L4", "L5", "L6", "L7"])
        XCTAssertEqual(geometry.cards.last?.layoutID, layouts[7].0.id)
        XCTAssertNotNil(geometry.leadingOverflowFrameAppKit)
        XCTAssertNil(geometry.overflowFrameAppKit)

        let backward = LayoutStripGeometry.make(
            workAreaAppKit: CGRect(x: 0, y: 0, width: 1600, height: 900),
            layouts: layouts,
            assignedLayoutID: layouts[0].0.id,
            workAreaAX: CGRect(x: 0, y: 0, width: 1600, height: 900),
            focusedLayoutID: layouts[1].0.id,
            previousStartLayoutID: layouts[2].0.id
        )
        XCTAssertEqual(backward.cards.map(\.layoutName), ["L1", "L2", "L3", "L4", "L5", "L6"])
    }

    func testOverflowChipsStayReservedWhilePaging() {
        let layouts = (0..<8).map { index -> (Layout, [ResolvedZone]) in
            let layout = Layout(name: "L\(index)", kind: .canvas, zones: [])
            return (layout, [ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 100, height: 100))])
        }
        let first = LayoutStripGeometry.make(
            workAreaAppKit: CGRect(x: 0, y: 0, width: 1600, height: 900),
            layouts: layouts,
            assignedLayoutID: layouts[0].0.id,
            workAreaAX: CGRect(x: 0, y: 0, width: 1600, height: 900),
            focusedLayoutID: layouts[0].0.id
        )
        let last = LayoutStripGeometry.make(
            workAreaAppKit: CGRect(x: 0, y: 0, width: 1600, height: 900),
            layouts: layouts,
            assignedLayoutID: layouts[0].0.id,
            workAreaAX: CGRect(x: 0, y: 0, width: 1600, height: 900),
            focusedLayoutID: layouts[7].0.id
        )
        XCTAssertEqual(first.frameAppKit, last.frameAppKit)
        XCTAssertNil(first.leadingOverflowFrameAppKit)
        XCTAssertNotNil(first.overflowFrameAppKit)
        XCTAssertNotNil(last.leadingOverflowFrameAppKit)
        XCTAssertNil(last.overflowFrameAppKit)
        XCTAssertEqual(
            LayoutStripGeometry.neighborLayoutID(of: layouts[5].0.id, in: layouts.map(\.0.id), delta: 1),
            layouts[6].0.id
        )
        XCTAssertNil(LayoutStripGeometry.neighborLayoutID(of: layouts[7].0.id, in: layouts.map(\.0.id), delta: 1))
    }

    func testIdenticalClonesWithDifferentUUIDsCollapseToOneCard() {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let zones = evenColumns(in: work)
        let first = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let clone = Layout(name: "Columns 2", kind: .canvas, zones: [])
        XCTAssertNotEqual(first.id, clone.id)
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [(first, zones), (clone, evenColumns(in: work))],
            assignedLayoutID: first.id,
            workAreaAX: work,
            language: .english
        )
        XCTAssertEqual(geometry.cards.map(\.layoutID), [first.id])
        XCTAssertEqual(geometry.cards.map(\.layoutName), ["Columns 2"])
        XCTAssertTrue(geometry.cards[0].isAssigned)
        let mini = geometry.cards[0].zones[0].frameAppKit
        let hit = geometry.hitZone(at: CGPoint(x: mini.midX, y: mini.midY))
        XCTAssertEqual(hit?.layoutID, first.id)
        XCTAssertNil(geometry.overflowFrameAppKit)
    }

    func testSameNameDifferentGeometryGetsStableNumberingIncludingTheFirst() {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let even = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let wide = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let persisted = [even.id, wide.id]
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [
                (even, evenColumns(in: work)),
                (wide, splitColumns(left: 700, in: work)),
            ],
            assignedLayoutID: even.id,
            workAreaAX: work,
            persistedLayoutIDs: persisted,
            language: .chineseSimplified
        )
        XCTAssertEqual(geometry.cards.map(\.layoutID), [even.id, wide.id])
        XCTAssertEqual(geometry.cards.map(\.layoutName), ["两列1", "两列2"])
    }

    func testUniqueNamesStayUnnumbered() {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = Layout(name: "Left", kind: .canvas, zones: [])
        let right = Layout(name: "Right", kind: .canvas, zones: [])
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [
                (left, evenColumns(in: work)),
                (right, [ResolvedZone(zoneID: UUID(), number: 1, frameAX: work)]),
            ],
            assignedLayoutID: left.id,
            workAreaAX: work,
            language: .english
        )
        XCTAssertEqual(geometry.cards.map(\.layoutName), ["Left", "Right"])
    }

    func testAssignedCloneIsPreferredRepresentative() {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let older = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let assigned = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let prepared = LayoutStripGeometry.preparedLayouts(
            layouts: [
                (older, evenColumns(in: work)),
                (assigned, evenColumns(in: work)),
            ],
            assignedLayoutID: assigned.id,
            language: .english
        )
        XCTAssertEqual(prepared.layouts.map(\.layout.id), [assigned.id])
        XCTAssertEqual(prepared.representativeID(for: older.id), assigned.id)
        XCTAssertEqual(prepared.representativeID(for: assigned.id), assigned.id)

        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [
                (older, evenColumns(in: work)),
                (assigned, evenColumns(in: work)),
            ],
            assignedLayoutID: assigned.id,
            workAreaAX: work,
            focusedLayoutID: older.id,
            language: .english
        )
        XCTAssertEqual(geometry.cards.map(\.layoutID), [assigned.id])
        XCTAssertTrue(geometry.cards[0].isAssigned)
    }

    func testNumberingFollowsPersistedOrderAcrossMRUResort() {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let even = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let wide = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let persisted = [even.id, wide.id]
        let mruFirst = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [
                (wide, splitColumns(left: 700, in: work)),
                (even, evenColumns(in: work)),
            ],
            assignedLayoutID: wide.id,
            workAreaAX: work,
            persistedLayoutIDs: persisted,
            language: .chineseSimplified
        )
        XCTAssertEqual(mruFirst.cards.map(\.layoutID), [wide.id, even.id])
        XCTAssertEqual(mruFirst.cards.map(\.layoutName), ["两列2", "两列1"])

        let assignedFirst = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [
                (even, evenColumns(in: work)),
                (wide, splitColumns(left: 700, in: work)),
            ],
            assignedLayoutID: even.id,
            workAreaAX: work,
            persistedLayoutIDs: persisted,
            language: .chineseSimplified
        )
        XCTAssertEqual(assignedFirst.cards.map(\.layoutID), [even.id, wide.id])
        XCTAssertEqual(assignedFirst.cards.map(\.layoutName), ["两列1", "两列2"])
    }

    func testDifferentNamesSameShapeStayDistinct() {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let columns = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let custom = Layout(name: "Work", kind: .canvas, zones: [])
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [
                (columns, evenColumns(in: work)),
                (custom, evenColumns(in: work)),
            ],
            assignedLayoutID: columns.id,
            workAreaAX: work,
            language: .chineseSimplified
        )
        XCTAssertEqual(geometry.cards.map(\.layoutID), [columns.id, custom.id])
        XCTAssertEqual(geometry.cards.map(\.layoutName), ["两列", "Work"])
    }

    func testDedupedListDrivesOverflowPaging() {
        let work = CGRect(x: 0, y: 0, width: 1600, height: 900)
        var layouts: [(Layout, [ResolvedZone])] = (0..<6).map { index in
            let layout = Layout(name: "L\(index)", kind: .canvas, zones: [])
            return (layout, [ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: CGFloat(index) * 10, y: 0, width: 100, height: 100))])
        }
        let original = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let clone = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let even = evenColumns(in: work)
        layouts.append((original, even))
        layouts.append((clone, evenColumns(in: work)))
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: layouts,
            assignedLayoutID: layouts[0].0.id,
            workAreaAX: work,
            language: .english
        )
        XCTAssertEqual(geometry.cards.count, LayoutStripGeometry.maxVisibleCards)
        XCTAssertEqual(geometry.cards.map(\.layoutName), ["L0", "L1", "L2", "L3", "L4", "L5"])
        XCTAssertNotNil(geometry.overflowFrameAppKit)
        let prepared = LayoutStripGeometry.preparedLayouts(
            layouts: layouts,
            assignedLayoutID: layouts[0].0.id,
            language: .english
        )
        XCTAssertEqual(prepared.layouts.count, 7)
        XCTAssertEqual(prepared.representativeID(for: clone.id), original.id)
        XCTAssertEqual(
            LayoutStripGeometry.neighborLayoutID(
                of: prepared.layouts[5].layout.id,
                in: prepared.layouts.map(\.layout.id),
                delta: 1
            ),
            original.id
        )
    }

    func testNumberingUsesGroupPersistedIdentityWhenAssignedCloneChanges() {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let a1 = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let shapeB = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let a2 = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let persisted = [a1.id, shapeB.id, a2.id]
        let even = evenColumns(in: work)
        let wide = splitColumns(left: 700, in: work)

        let a1Assigned = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [(a1, even), (shapeB, wide), (a2, even)],
            assignedLayoutID: a1.id,
            workAreaAX: work,
            persistedLayoutIDs: persisted,
            language: .chineseSimplified
        )
        XCTAssertEqual(a1Assigned.cards.map(\.layoutID), [a1.id, shapeB.id])
        XCTAssertEqual(a1Assigned.cards.map(\.layoutName), ["两列1", "两列2"])
        XCTAssertTrue(a1Assigned.cards[0].isAssigned)

        let a2Assigned = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [(a2, even), (shapeB, wide), (a1, even)],
            assignedLayoutID: a2.id,
            workAreaAX: work,
            persistedLayoutIDs: persisted,
            language: .chineseSimplified
        )
        XCTAssertEqual(a2Assigned.cards.map(\.layoutID), [a2.id, shapeB.id])
        XCTAssertEqual(a2Assigned.cards.map(\.layoutName), ["两列1", "两列2"])
        XCTAssertTrue(a2Assigned.cards[0].isAssigned)
        XCTAssertEqual(a2Assigned.cards[0].layoutID, a2.id)
    }

    func testNumberingStaysStableWhenCloneGroupMRUChangesWithoutAssignment() {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let a1 = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let shapeB = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let a2 = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let persisted = [a1.id, shapeB.id, a2.id]
        let even = evenColumns(in: work)
        let wide = splitColumns(left: 700, in: work)

        let mruA2 = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [(a2, even), (shapeB, wide), (a1, even)],
            assignedLayoutID: nil,
            workAreaAX: work,
            persistedLayoutIDs: persisted,
            language: .chineseSimplified
        )
        XCTAssertEqual(mruA2.cards.map(\.layoutID), [a2.id, shapeB.id])
        XCTAssertEqual(mruA2.cards.map(\.layoutName), ["两列1", "两列2"])
        XCTAssertFalse(mruA2.cards[0].isAssigned)

        let mruA1 = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [(a1, even), (shapeB, wide), (a2, even)],
            assignedLayoutID: nil,
            workAreaAX: work,
            persistedLayoutIDs: persisted,
            language: .chineseSimplified
        )
        XCTAssertEqual(mruA1.cards.map(\.layoutID), [a1.id, shapeB.id])
        XCTAssertEqual(mruA1.cards.map(\.layoutName), ["两列1", "两列2"])

        let mruBFirst = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [(shapeB, wide), (a2, even), (a1, even)],
            assignedLayoutID: nil,
            workAreaAX: work,
            persistedLayoutIDs: persisted,
            language: .chineseSimplified
        )
        XCTAssertEqual(mruBFirst.cards.map(\.layoutID), [shapeB.id, a2.id])
        XCTAssertEqual(mruBFirst.cards.map(\.layoutName), ["两列2", "两列1"])
    }

    func testNumberingSkipsAnExistingSuffixedDisplayName() {
        let work = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let even = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let wide = Layout(name: "Columns 2", kind: .canvas, zones: [])
        let taken = Layout(name: "两列1", kind: .canvas, zones: [])
        let geometry = LayoutStripGeometry.make(
            workAreaAppKit: work,
            layouts: [
                (even, evenColumns(in: work)),
                (wide, splitColumns(left: 700, in: work)),
                (taken, [ResolvedZone(zoneID: UUID(), number: 1, frameAX: work)]),
            ],
            assignedLayoutID: even.id,
            workAreaAX: work,
            persistedLayoutIDs: [even.id, wide.id, taken.id],
            language: .chineseSimplified
        )
        XCTAssertEqual(geometry.cards.map(\.layoutName), ["两列2", "两列3", "两列1"])
    }

    private func evenColumns(in work: CGRect) -> [ResolvedZone] {
        splitColumns(left: work.width / 2, in: work)
    }

    private func splitColumns(left: CGFloat, in work: CGRect) -> [ResolvedZone] {
        [
            ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: work.minX, y: work.minY, width: left, height: work.height)),
            ResolvedZone(
                zoneID: UUID(),
                number: 2,
                frameAX: CGRect(x: work.minX + left, y: work.minY, width: work.width - left, height: work.height)
            ),
        ]
    }
}
