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

    public static func make(
        workAreaAppKit: CGRect,
        layouts: [(layout: Layout, zones: [ResolvedZone])],
        assignedLayoutID: Layout.ID?,
        workAreaAX: CGRect,
        focusedLayoutID: Layout.ID? = nil,
        previousStartLayoutID: Layout.ID? = nil
    ) -> LayoutStripGeometry {
        let focusedID = focusedLayoutID ?? assignedLayoutID
        let focusedIndex = focusedID.flatMap { id in
            layouts.firstIndex(where: { $0.layout.id == id })
        } ?? 0
        let previousStart = previousStartLayoutID.flatMap { id in
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

    public func hitZone(at pointAppKit: CGPoint) -> (layoutID: Layout.ID, zoneNumber: Int)? {
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
