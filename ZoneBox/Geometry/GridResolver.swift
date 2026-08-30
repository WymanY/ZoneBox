import CoreGraphics

public enum GridResolver {
    public static func resolve(
        spec: GridSpec,
        zones: [Zone],
        workAreaAX: CGRect,
        gutter: CGFloat
    ) throws -> [ResolvedZone] {
        let spec = try spec.validated(zoneCount: zones.count)
        var colPrefix = [CGFloat](repeating: 0, count: spec.columns + 1)
        var rowPrefix = [CGFloat](repeating: 0, count: spec.rows + 1)
        for c in 0..<spec.columns {
            colPrefix[c + 1] = colPrefix[c] + workAreaAX.width * CGFloat(spec.columnWeights[c]) / 10_000
        }
        for r in 0..<spec.rows {
            rowPrefix[r + 1] = rowPrefix[r] + workAreaAX.height * CGFloat(spec.rowWeights[r]) / 10_000
        }

        var cellsByIndex: [Int: (r0: Int, r1: Int, c0: Int, c1: Int)] = [:]
        for r in 0..<spec.rows {
            for c in 0..<spec.columns {
                let idx = spec.cellMap[r][c]
                if let box = cellsByIndex[idx] {
                    cellsByIndex[idx] = (min(box.r0, r), max(box.r1, r), min(box.c0, c), max(box.c1, c))
                } else {
                    cellsByIndex[idx] = (r, r, c, c)
                }
            }
        }

        let ordered = try cellsByIndex.keys.sorted().map { idx -> (zone: Zone, unguttered: CGRect) in
            guard zones.indices.contains(idx) else { throw GridValidationError.zoneCountMismatch }
            let box = cellsByIndex[idx]!
            let unguttered = CGRect(
                x: workAreaAX.minX + colPrefix[box.c0],
                y: workAreaAX.minY + rowPrefix[box.r0],
                width: colPrefix[box.c1 + 1] - colPrefix[box.c0],
                height: rowPrefix[box.r1 + 1] - rowPrefix[box.r0]
            )
            return (zones[idx], unguttered)
        }
        let frames = Gutter.apply(ordered.map { $0.unguttered }, gutter: gutter, workAreaAX: workAreaAX)
        return zip(ordered, frames).map { item, frame in
            ResolvedZone(zoneID: item.zone.id, number: item.zone.number, frameAX: frame)
        }
    }
}

public func resolveLayout(_ layout: Layout, workAreaAX: CGRect, gutter: CGFloat) throws -> [ResolvedZone] {
    switch layout.kind {
    case .canvas:
        let ordered = layout.zones.sorted { $0.number < $1.number }.compactMap { zone -> (zone: Zone, unguttered: CGRect)? in
            guard let n = zone.canvasRect else { return nil }
            return (zone, n.denormalize(in: workAreaAX))
        }
        let frames = Gutter.apply(ordered.map { $0.unguttered }, gutter: gutter, workAreaAX: workAreaAX)
        return zip(ordered, frames).compactMap { item, frame in
            guard frame.width >= 40, frame.height >= 40 else { return nil }
            return ResolvedZone(zoneID: item.zone.id, number: item.zone.number, frameAX: frame)
        }
    case .grid:
        guard let grid = layout.grid else { return [] }
        return try GridResolver.resolve(spec: grid, zones: layout.zones, workAreaAX: workAreaAX, gutter: gutter)
    }
}
