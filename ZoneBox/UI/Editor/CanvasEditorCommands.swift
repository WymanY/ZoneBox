import CoreGraphics
import Foundation
import ZoneBoxCore

enum CanvasCommand: Equatable {
    case insertDefault
    case insert(NormalizedRect)
    case duplicate
    case split(GridAxis)
    case delete
    case selectAll
    case align(CanvasAlignment.Edge)
    case matchSize(CanvasAlignment.SizeMatch)
    case distribute(CanvasAlignment.Axis)
    case snapToHalf(CanvasAlignment.Edge)
    case center
    case assignNumber(Int)
    case fillTemplate(Layout)
}

struct CanvasCommandResult {
    var layout: Layout
    var selection: Set<UUID>
    var primaryID: UUID?
}

enum CanvasCommandRunner {
    static func perform(
        _ command: CanvasCommand,
        layout: Layout,
        selection: Set<UUID>,
        primaryID: UUID?,
        workAreaAX: CGRect,
        canvasSize: CGSize
    ) -> CanvasCommandResult? {
        switch command {
        case .insertDefault:
            let rect = CanvasEditing.defaultRect(centeredAt: (0.5, 0.5), canvasSize: canvasSize)
            return insert(rect, into: layout)
        case .insert(let rect):
            return insert(rect, into: layout)
        case .duplicate:
            let ids = effectiveIDs(selection: selection, primaryID: primaryID, layout: layout)
            guard !ids.isEmpty else { return nil }
            let offset = CanvasEditing.offsetPoints(16, workAreaAX: workAreaAX)
            guard let result = CanvasEditing.duplicating(layout, ids: ids, offset: offset) else { return nil }
            return CanvasCommandResult(
                layout: result.layout,
                selection: Set(result.newIDs),
                primaryID: result.newIDs.last
            )
        case .split(let axis):
            guard let id = primaryID ?? selection.first else { return nil }
            guard let result = CanvasEditing.splitting(layout, id: id, axis: axis) else { return nil }
            return CanvasCommandResult(
                layout: result.layout,
                selection: [result.newID],
                primaryID: result.newID
            )
        case .delete:
            let ids = effectiveIDs(selection: selection, primaryID: primaryID, layout: layout)
            guard !ids.isEmpty else { return nil }
            let next = CanvasEditing.deleting(layout, ids: ids)
            return CanvasCommandResult(layout: next, selection: [], primaryID: nil)
        case .selectAll:
            let ids = Set(CanvasEditing.sanitized(layout).zones.map(\.id))
            return CanvasCommandResult(
                layout: layout,
                selection: ids,
                primaryID: primaryID.flatMap { ids.contains($0) ? $0 : ids.first } ?? ids.first
            )
        case .align(let edge):
            return transform(layout, selection: selection, primaryID: primaryID) { rects, _ in
                CanvasAlignment.aligning(rects, to: edge)
            }
        case .matchSize(let match):
            guard let primary = primaryID ?? selection.first else { return nil }
            return transform(layout, selection: selection, primaryID: primary) { rects, _ in
                CanvasAlignment.matchingSize(rects, primary: primary, match: match)
            }
        case .distribute(let axis):
            return transform(layout, selection: selection, primaryID: primaryID) { rects, _ in
                CanvasAlignment.distributing(rects, axis: axis)
            }
        case .snapToHalf(let edge):
            guard let id = primaryID ?? selection.first else { return nil }
            return transform(layout, selection: [id], primaryID: id) { _, _ in
                [id: CanvasEditing.halfWorkArea(edge)]
            }
        case .center:
            return transform(layout, selection: selection, primaryID: primaryID) { rects, _ in
                rects.mapValues(CanvasEditing.centered)
            }
        case .assignNumber(let number):
            guard let id = primaryID ?? selection.first else { return nil }
            guard let next = CanvasEditing.assigningNumber(layout, id: id, number: number) else { return nil }
            return CanvasCommandResult(layout: next, selection: selection, primaryID: id)
        case .fillTemplate(let preset):
            let converted: Layout
            if preset.kind == .grid, let canvas = try? preset.convertingGridToCanvas(workAreaAX: workAreaAX) {
                converted = canvas
            } else {
                converted = preset
            }
            var next = converted
            next.id = layout.id
            next.name = layout.name
            next.createdAt = layout.createdAt
            let ids = Set(next.zones.map(\.id))
            return CanvasCommandResult(
                layout: next,
                selection: ids,
                primaryID: next.zones.sorted { $0.number < $1.number }.first?.id
            )
        }
    }

    private static func insert(_ rect: NormalizedRect, into layout: Layout) -> CanvasCommandResult? {
        guard let result = CanvasEditing.inserting(layout, rect: rect) else { return nil }
        return CanvasCommandResult(
            layout: result.layout,
            selection: [result.newID],
            primaryID: result.newID
        )
    }

    private static func transform(
        _ layout: Layout,
        selection: Set<UUID>,
        primaryID: UUID?,
        body: ([UUID: NormalizedRect], UUID?) -> [UUID: NormalizedRect]
    ) -> CanvasCommandResult? {
        let ids = effectiveIDs(selection: selection, primaryID: primaryID, layout: layout)
        guard !ids.isEmpty else { return nil }
        let rects = Dictionary(uniqueKeysWithValues: layout.zones.compactMap { zone -> (UUID, NormalizedRect)? in
            guard ids.contains(zone.id), let rect = zone.canvasRect else { return nil }
            return (zone.id, rect)
        })
        guard !rects.isEmpty else { return nil }
        let nextRects = body(rects, primaryID)
        return CanvasCommandResult(
            layout: CanvasEditing.applying(layout, rects: nextRects),
            selection: ids,
            primaryID: primaryID ?? ids.first
        )
    }

    private static func effectiveIDs(selection: Set<UUID>, primaryID: UUID?, layout: Layout) -> Set<UUID> {
        let valid = Set(CanvasEditing.sanitized(layout).zones.map(\.id))
        let selected = selection.intersection(valid)
        if !selected.isEmpty { return selected }
        if let primaryID, valid.contains(primaryID) { return [primaryID] }
        return []
    }
}
