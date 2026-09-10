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
}
