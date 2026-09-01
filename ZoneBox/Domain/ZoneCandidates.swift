import CoreGraphics
import Foundation

public struct ZoneCandidate: Equatable, Sendable {
    public var layoutID: Layout.ID
    public var layoutName: String
    public var zone: ResolvedZone

    public init(layoutID: Layout.ID, layoutName: String, zone: ResolvedZone) {
        self.layoutID = layoutID
        self.layoutName = layoutName
        self.zone = zone
    }
}

public enum ZoneCandidateResolver {
    public static let frameTolerance: CGFloat = 0.5

    /// Collects unique zones that contain `pointAX` across every resolved layout.
    /// The assigned layout's hit is always first so an untouched session matches today.
    public static func resolve(
        layouts: [(layout: Layout, zones: [ResolvedZone])],
        pointAX: CGPoint,
        assignedLayoutID: Layout.ID?,
        recentLayoutIDs: [Layout.ID]
    ) -> [ZoneCandidate] {
        var hits: [ZoneCandidate] = []
        for item in layouts {
            for zone in item.zones where zone.frameAX.contains(pointAX) {
                hits.append(
                    ZoneCandidate(
                        layoutID: item.layout.id,
                        layoutName: item.layout.name,
                        zone: zone
                    )
                )
            }
        }

        var unique: [ZoneCandidate] = []
        for hit in hits {
            if unique.contains(where: { approximatelyEqual($0.zone.frameAX, hit.zone.frameAX) }) {
                continue
            }
            unique.append(hit)
        }

        let mruRank: [Layout.ID: Int] = Dictionary(
            uniqueKeysWithValues: recentLayoutIDs.enumerated().map { ($0.element, $0.offset) }
        )
        return unique.sorted { lhs, rhs in
            let lhsAssigned = lhs.layoutID == assignedLayoutID
            let rhsAssigned = rhs.layoutID == assignedLayoutID
            if lhsAssigned != rhsAssigned { return lhsAssigned }
            let lhsMRU = mruRank[lhs.layoutID] ?? Int.max
            let rhsMRU = mruRank[rhs.layoutID] ?? Int.max
            if lhsMRU != rhsMRU { return lhsMRU < rhsMRU }
            let lhsArea = lhs.zone.frameAX.width * lhs.zone.frameAX.height
            let rhsArea = rhs.zone.frameAX.width * rhs.zone.frameAX.height
            if abs(lhsArea - rhsArea) > 0.5 { return lhsArea < rhsArea }
            if lhs.layoutName != rhs.layoutName { return lhs.layoutName < rhs.layoutName }
            return lhs.zone.number < rhs.zone.number
        }
    }

    public static func wrappingIndex(current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let step = delta == 0 ? 0 : (delta > 0 ? 1 : -1)
        let next = current + step
        return ((next % count) + count) % count
    }

    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < frameTolerance
            && abs(a.minY - b.minY) < frameTolerance
            && abs(a.width - b.width) < frameTolerance
            && abs(a.height - b.height) < frameTolerance
    }
}
