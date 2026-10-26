import CoreGraphics
import Foundation

public struct LayoutStripCard: Equatable, Sendable {
    public var layoutID: Layout.ID
    public var layoutName: String
    public var frameAppKit: CGRect
    public var isAssigned: Bool
    public var zones: [LayoutStripZone]

    public init(
        layoutID: Layout.ID,
        layoutName: String,
        frameAppKit: CGRect,
        isAssigned: Bool,
        zones: [LayoutStripZone]
    ) {
        self.layoutID = layoutID
        self.layoutName = layoutName
        self.frameAppKit = frameAppKit
        self.isAssigned = isAssigned
        self.zones = zones
    }
}

public struct LayoutStripZone: Equatable, Sendable {
    public var number: Int
    public var frameAppKit: CGRect

    public init(number: Int, frameAppKit: CGRect) {
        self.number = number
        self.frameAppKit = frameAppKit
    }
}

public struct LayoutStripGeometry: Equatable, Sendable {
    public static let cardSize = CGSize(width: 128, height: 80)
    public static let cardSpacing: CGFloat = 10
    public static let topInset: CGFloat = 18
    public static let maxVisibleCards = 6
    public static let overflowWidth: CGFloat = 36
    public static let cardCorner: CGFloat = 10
    public static let zoneInset: CGFloat = 8
    public static let dropLingerBelow: CGFloat = 64

    public var frameAppKit: CGRect
    public var cards: [LayoutStripCard]
    public var overflowFrameAppKit: CGRect?
    public var leadingOverflowFrameAppKit: CGRect?

    public init(
        frameAppKit: CGRect,
        cards: [LayoutStripCard],
        overflowFrameAppKit: CGRect? = nil,
        leadingOverflowFrameAppKit: CGRect? = nil
    ) {
        self.frameAppKit = frameAppKit
        self.cards = cards
        self.overflowFrameAppKit = overflowFrameAppKit
        self.leadingOverflowFrameAppKit = leadingOverflowFrameAppKit
    }

    /// Presentation list for the drag strip: collapse identical same-name
    /// layouts, then number remaining same-name cards. Stored layouts are
    /// not modified.
    public struct PreparedLayouts: Sendable {
        public var layouts: [(layout: Layout, zones: [ResolvedZone])]
        public var representativeByID: [Layout.ID: Layout.ID]

        public init(
            layouts: [(layout: Layout, zones: [ResolvedZone])],
            representativeByID: [Layout.ID: Layout.ID]
        ) {
            self.layouts = layouts
            self.representativeByID = representativeByID
        }

        public func representativeID(for id: Layout.ID?) -> Layout.ID? {
            guard let id else { return nil }
            return representativeByID[id] ?? id
        }
    }

    public static func preparedLayouts(
        layouts: [(layout: Layout, zones: [ResolvedZone])],
        assignedLayoutID: Layout.ID?,
        persistedLayoutIDs: [Layout.ID] = [],
        language: AppLanguage = LanguageCenter.language
    ) -> PreparedLayouts {
        let bases = layouts.map { L10n.layoutDisplayName($0.layout.name, language: language) }
        var groups: [[Int]] = []
        var groupIndex = Array(repeating: -1, count: layouts.count)
        for index in layouts.indices {
            if let existing = groups.firstIndex(where: { members in
                let seed = members[0]
                return bases[seed] == bases[index]
                    && visuallyEquivalent(layouts[seed].zones, layouts[index].zones)
            }) {
                groups[existing].append(index)
                groupIndex[index] = existing
            } else {
                groupIndex[index] = groups.count
                groups.append([index])
            }
        }

        let chosen: [Int] = groups.map { members in
            members.first(where: { layouts[$0].layout.id == assignedLayoutID }) ?? members[0]
        }

        var representativeByID: [Layout.ID: Layout.ID] = [:]
        representativeByID.reserveCapacity(layouts.count)
        for (group, members) in groups.enumerated() {
            let representativeID = layouts[chosen[group]].layout.id
            for member in members {
                representativeByID[layouts[member].layout.id] = representativeID
            }
        }

        let persistedIndex = Dictionary(
            persistedLayoutIDs.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        func numberingKey(for members: [Int]) -> Int {
            members.map { persistedIndex[layouts[$0].layout.id] ?? .max }.min() ?? .max
        }

        var kept: [(layout: Layout, zones: [ResolvedZone])] = []
        var numberingKeys: [Int] = []
        kept.reserveCapacity(groups.count)
        numberingKeys.reserveCapacity(groups.count)
        var emitted = Set<Int>()
        for index in layouts.indices {
            let group = groupIndex[index]
            guard emitted.insert(group).inserted else { continue }
            kept.append(layouts[chosen[group]])
            numberingKeys.append(numberingKey(for: groups[group]))
        }

        let labels = displayNames(
            for: kept,
            numberingKeys: numberingKeys,
            language: language
        )
        let named: [(layout: Layout, zones: [ResolvedZone])] = zip(kept, labels).map { item, label in
            var layout = item.layout
            layout.name = label
            return (layout, item.zones)
        }
        return PreparedLayouts(layouts: named, representativeByID: representativeByID)
    }

    public static func make(
        workAreaAppKit: CGRect,
        layouts: [(layout: Layout, zones: [ResolvedZone])],
        assignedLayoutID: Layout.ID?,
        workAreaAX: CGRect,
        focusedLayoutID: Layout.ID? = nil,
        previousStartLayoutID: Layout.ID? = nil,
        persistedLayoutIDs: [Layout.ID] = [],
        language: AppLanguage = LanguageCenter.language
    ) -> LayoutStripGeometry {
        let prepared = preparedLayouts(
            layouts: layouts,
            assignedLayoutID: assignedLayoutID,
            persistedLayoutIDs: persistedLayoutIDs,
            language: language
        )
        let layouts = prepared.layouts
        let focusedID = prepared.representativeID(for: focusedLayoutID) ?? assignedLayoutID
        let focusedIndex = focusedID.flatMap { id in
            layouts.firstIndex(where: { $0.layout.id == id })
        } ?? 0
        let previousStart = prepared.representativeID(for: previousStartLayoutID).flatMap { id in
            layouts.firstIndex(where: { $0.layout.id == id })
        }
        let visibleRange = visibleCardRange(
            layoutCount: layouts.count,
            focusedIndex: focusedIndex,
            previousStart: previousStart
        )
        let visible = Array(layouts[visibleRange])
        let hiddenLeading = visibleRange.lowerBound
        let hiddenTrailing = layouts.count - visibleRange.upperBound
        let cardsWidth = CGFloat(visible.count) * cardSize.width
            + CGFloat(max(0, visible.count - 1)) * cardSpacing
        let reserveOverflow = layouts.count > maxVisibleCards
        let leadingExtra = reserveOverflow ? overflowWidth + cardSpacing : 0
        let trailingExtra = reserveOverflow ? overflowWidth + cardSpacing : 0
        let stripWidth = leadingExtra + cardsWidth + trailingExtra
        let originX = workAreaAppKit.midX - stripWidth / 2
        let originY = workAreaAppKit.maxY - topInset - cardSize.height
        let cardsOriginX = originX + leadingExtra
        var cards: [LayoutStripCard] = []
        for (index, item) in visible.enumerated() {
            let cardFrame = CGRect(
                x: cardsOriginX + CGFloat(index) * (cardSize.width + cardSpacing),
                y: originY,
                width: cardSize.width,
                height: cardSize.height
            )
            let inner = cardFrame.insetBy(dx: zoneInset, dy: zoneInset + 6)
            let miniZones = item.zones.map { zone in
                LayoutStripZone(
                    number: zone.number,
                    frameAppKit: mapZone(
                        zone.frameAX,
                        from: workAreaAX,
                        onto: inner
                    )
                )
            }
            cards.append(
                LayoutStripCard(
                    layoutID: item.layout.id,
                    layoutName: item.layout.name,
                    frameAppKit: cardFrame,
                    isAssigned: item.layout.id == assignedLayoutID,
                    zones: miniZones
                )
            )
        }
        let leadingOverflow: CGRect?
        if reserveOverflow, hiddenLeading > 0 {
            leadingOverflow = CGRect(
                x: originX,
                y: originY,
                width: overflowWidth,
                height: cardSize.height
            )
        } else {
            leadingOverflow = nil
        }
        let trailingOverflow: CGRect?
        if reserveOverflow, hiddenTrailing > 0 {
            trailingOverflow = CGRect(
                x: cardsOriginX + cardsWidth + cardSpacing,
                y: originY,
                width: overflowWidth,
                height: cardSize.height
            )
        } else {
            trailingOverflow = nil
        }
        let padding: CGFloat = 8
        let stripFrame = CGRect(
            x: originX - padding,
            y: originY - padding,
            width: stripWidth + padding * 2,
            height: cardSize.height + padding * 2
        )
        return LayoutStripGeometry(
            frameAppKit: stripFrame,
            cards: cards,
            overflowFrameAppKit: trailingOverflow,
            leadingOverflowFrameAppKit: leadingOverflow
        )
    }

    /// Keep the focused layout in a left-aligned window until Tab/scroll
    /// walks past the last visible card, then slide just far enough to
    /// reveal it.
    public static func visibleCardRange(
        layoutCount: Int,
        focusedIndex: Int,
        maxVisible: Int = maxVisibleCards,
        previousStart: Int? = nil
    ) -> Range<Int> {
        guard layoutCount > 0 else { return 0..<0 }
        let window = min(maxVisible, layoutCount)
        let focused = min(max(focusedIndex, 0), layoutCount - 1)
        let maxStart = layoutCount - window
        var start: Int
        if let previousStart {
            start = min(max(previousStart, 0), maxStart)
            if focused < start {
                start = focused
            } else if focused >= start + window {
                start = focused - window + 1
            }
        } else {
            start = min(max(0, focused - window + 1), maxStart)
        }
        start = min(max(start, 0), maxStart)
        return start..<(start + window)
    }

    public func contains(_ pointAppKit: CGPoint) -> Bool {
        if frameAppKit.contains(pointAppKit) { return true }
        return cards.contains { $0.frameAppKit.contains(pointAppKit) }
    }

    public func containsDropLinger(_ pointAppKit: CGPoint) -> Bool {
        if contains(pointAppKit) { return true }
        let below = CGRect(
            x: frameAppKit.minX,
            y: frameAppKit.minY - Self.dropLingerBelow,
            width: frameAppKit.width,
            height: Self.dropLingerBelow
        )
        return below.contains(pointAppKit)
    }

    /// Project a point that slipped just below the bar back onto the cards.
    /// X still chooses the column; Y prefers the previously selected mini-zone
    /// so a bottom row is not replaced by the card midpoint.
    public func dropProbePoint(
        for pointAppKit: CGPoint,
        preservingLayoutID layoutID: Layout.ID? = nil,
        zoneNumber: Int? = nil
    ) -> CGPoint {
        if cards.contains(where: { $0.frameAppKit.contains(pointAppKit) }) {
            return pointAppKit
        }
        let preferredY = cards
            .first(where: { $0.layoutID == layoutID })?
            .zones.first(where: { $0.number == zoneNumber })?
            .frameAppKit.midY
        let y = preferredY ?? cards.first?.frameAppKit.midY ?? frameAppKit.midY
        return CGPoint(x: pointAppKit.x, y: y)
    }

    public func hitZone(at pointAppKit: CGPoint) -> (layoutID: Layout.ID, zoneNumber: Int)? {
        if let hit = hitMiniZone(at: pointAppKit) {
            return hit
        }
        guard let card = cards.first(where: { $0.frameAppKit.contains(pointAppKit) }),
              let zone = Self.nearestZone(in: card.zones, to: pointAppKit)
        else {
            return nil
        }
        return (card.layoutID, zone.number)
    }

    /// Only the thumbnail panes themselves. Card titles, padding, and the
    /// linger band below the bar must not start a strip selection.
    public func hitMiniZone(at pointAppKit: CGPoint) -> (layoutID: Layout.ID, zoneNumber: Int)? {
        for card in cards {
            for zone in card.zones where zone.frameAppKit.contains(pointAppKit) {
                return (card.layoutID, zone.number)
            }
        }
        return nil
    }

    public func hitCard(at pointAppKit: CGPoint) -> Layout.ID? {
        cards.first { $0.frameAppKit.contains(pointAppKit) }?.layoutID
    }

    public func hitOverflow(at pointAppKit: CGPoint) -> Int? {
        if let leadingOverflowFrameAppKit, leadingOverflowFrameAppKit.contains(pointAppKit) {
            return -1
        }
        if let overflowFrameAppKit, overflowFrameAppKit.contains(pointAppKit) {
            return 1
        }
        return nil
    }

    public static func neighborLayoutID(
        of id: Layout.ID?,
        in layoutIDs: [Layout.ID],
        delta: Int
    ) -> Layout.ID? {
        guard let id, let index = layoutIDs.firstIndex(of: id) else { return nil }
        let next = index + delta
        guard layoutIDs.indices.contains(next) else { return nil }
        return layoutIDs[next]
    }

    private static func displayNames(
        for items: [(layout: Layout, zones: [ResolvedZone])],
        numberingKeys: [Int],
        language: AppLanguage
    ) -> [String] {
        let bases = items.map { L10n.layoutDisplayName($0.layout.name, language: language) }
        var counts: [String: Int] = [:]
        for base in bases {
            counts[base, default: 0] += 1
        }
        let colliding = Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
        var reserved = Set(bases.filter { counts[$0] == 1 })
        var labels = bases
        let grouped = Dictionary(grouping: items.indices.filter { colliding.contains(bases[$0]) }) {
            bases[$0]
        }
        let nameOrder = grouped.keys.sorted { lhs, rhs in
            let leftKey = grouped[lhs]?.map { numberingKeys[$0] }.min() ?? .max
            let rightKey = grouped[rhs]?.map { numberingKeys[$0] }.min() ?? .max
            if leftKey != rightKey { return leftKey < rightKey }
            return lhs < rhs
        }
        for base in nameOrder {
            let indices = grouped[base] ?? []
            let ordered = indices.sorted { lhs, rhs in
                if numberingKeys[lhs] != numberingKeys[rhs] {
                    return numberingKeys[lhs] < numberingKeys[rhs]
                }
                return lhs < rhs
            }
            var suffix = 1
            for index in ordered {
                var label = "\(base)\(suffix)"
                while reserved.contains(label) {
                    suffix += 1
                    label = "\(base)\(suffix)"
                }
                labels[index] = label
                reserved.insert(label)
                suffix += 1
            }
        }
        return labels
    }

    private static func visuallyEquivalent(_ lhs: [ResolvedZone], _ rhs: [ResolvedZone]) -> Bool {
        let left = lhs.sorted { $0.number < $1.number }
        let right = rhs.sorted { $0.number < $1.number }
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { a, b in
            a.number == b.number && rectsMatch(a.frameAX, b.frameAX)
        }
    }

    private static func rectsMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 0.5
        return abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func nearestZone(in zones: [LayoutStripZone], to pointAppKit: CGPoint) -> LayoutStripZone? {
        zones.min { lhs, rhs in
            distanceSquared(lhs.frameAppKit, to: pointAppKit) < distanceSquared(rhs.frameAppKit, to: pointAppKit)
        }
    }

    private static func distanceSquared(_ rect: CGRect, to point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private static func mapZone(_ zoneAX: CGRect, from workAreaAX: CGRect, onto inner: CGRect) -> CGRect {
        guard workAreaAX.width > 0, workAreaAX.height > 0 else { return .null }
        let nx = (zoneAX.minX - workAreaAX.minX) / workAreaAX.width
        let ny = (zoneAX.minY - workAreaAX.minY) / workAreaAX.height
        let nw = zoneAX.width / workAreaAX.width
        let nh = zoneAX.height / workAreaAX.height
        // AX y grows downward from the work-area origin; AppKit strip y grows upward.
        return CGRect(
            x: inner.minX + nx * inner.width,
            y: inner.minY + (1 - ny - nh) * inner.height,
            width: max(1, nw * inner.width),
            height: max(1, nh * inner.height)
        )
    }
}
