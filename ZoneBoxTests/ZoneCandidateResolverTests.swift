import XCTest
@testable import ZoneBoxCore

final class ZoneCandidateResolverTests: XCTestCase {
    func testAssignedHitStaysFirstAndDuplicatesCollapse() {
        let assigned = Layout(name: "Assigned", kind: .canvas, zones: [])
        let recent = Layout(name: "Recent", kind: .canvas, zones: [])
        let leftover = Layout(name: "Other", kind: .canvas, zones: [])
        let leftHalf = CGRect(x: 0, y: 0, width: 500, height: 800)
        let leftThird = CGRect(x: 0, y: 0, width: 333, height: 800)
        let leftTwoThirds = CGRect(x: 0, y: 0, width: 666, height: 800)
        let duplicate = CGRect(x: 0, y: 0, width: 500.2, height: 800)

        let candidates = ZoneCandidateResolver.resolve(
            layouts: [
                (leftover, [ResolvedZone(zoneID: UUID(), number: 1, frameAX: leftTwoThirds)]),
                (recent, [ResolvedZone(zoneID: UUID(), number: 1, frameAX: leftThird)]),
                (assigned, [
                    ResolvedZone(zoneID: UUID(), number: 1, frameAX: leftHalf),
                    ResolvedZone(zoneID: UUID(), number: 2, frameAX: duplicate),
                ]),
            ],
            pointAX: CGPoint(x: 100, y: 100),
            assignedLayoutID: assigned.id,
            recentLayoutIDs: [recent.id]
        )

        XCTAssertEqual(candidates.map(\.layoutName), ["Assigned", "Recent", "Other"])
        XCTAssertEqual(candidates[0].zone.frameAX.width, 500, accuracy: 0.01)
    }

    func testEmptyHitsFallBackToNoCandidates() {
        let layout = Layout(name: "Empty", kind: .canvas, zones: [])
        let candidates = ZoneCandidateResolver.resolve(
            layouts: [(layout, [ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 400, y: 0, width: 200, height: 200))])],
            pointAX: CGPoint(x: 10, y: 10),
            assignedLayoutID: layout.id,
            recentLayoutIDs: []
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    func testWrappingIndexCyclesBothDirections() {
        XCTAssertEqual(ZoneCandidateResolver.wrappingIndex(current: 0, delta: 1, count: 3), 1)
        XCTAssertEqual(ZoneCandidateResolver.wrappingIndex(current: 2, delta: 1, count: 3), 0)
        XCTAssertEqual(ZoneCandidateResolver.wrappingIndex(current: 0, delta: -1, count: 3), 2)
        XCTAssertEqual(ZoneCandidateResolver.wrappingIndex(current: 1, delta: 0, count: 3), 1)
        XCTAssertEqual(ZoneCandidateResolver.wrappingIndex(current: 0, delta: 1, count: 0), 0)
    }

    func testAssignedOverlapUsesConfiguredPolicyForCandidateZero() {
        let assigned = Layout(name: "Assigned", kind: .canvas, zones: [])
        let small = ResolvedZone(zoneID: UUID(), number: 1, frameAX: CGRect(x: 0, y: 0, width: 200, height: 200))
        let large = ResolvedZone(zoneID: UUID(), number: 2, frameAX: CGRect(x: 0, y: 0, width: 800, height: 800))
        let point = CGPoint(x: 50, y: 50)
        let layouts = [(assigned, [small, large])]

        let smallest = ZoneCandidateResolver.resolve(
            layouts: layouts,
            pointAX: point,
            assignedLayoutID: assigned.id,
            recentLayoutIDs: [],
            overlapPolicy: .smallestArea
        )
        XCTAssertEqual(smallest.first?.zone.zoneID, small.zoneID)

        let largest = ZoneCandidateResolver.resolve(
            layouts: layouts,
            pointAX: point,
            assignedLayoutID: assigned.id,
            recentLayoutIDs: [],
            overlapPolicy: .largestArea
        )
        XCTAssertEqual(largest.first?.zone.zoneID, large.zoneID)
    }

}
