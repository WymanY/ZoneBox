import Foundation

/// Keeps layout editing isolated from the persisted document until the user commits.
public struct LayoutEditTransaction: Sendable {
    public let original: Layout?
    public let baseline: Layout
    public let targetDisplayID: DisplayIdentity.ID
    public private(set) var draft: Layout

    public init(original: Layout?, draft: Layout, targetDisplayID: DisplayIdentity.ID) {
        self.original = original
        self.baseline = draft
        self.targetDisplayID = targetDisplayID
        self.draft = draft
    }

    public var isNew: Bool { original == nil }
    public var hasChanges: Bool { draft != baseline }

    /// An active layout with no zones makes every snap command a no-op.
    public var canCommit: Bool { !draft.zones.isEmpty }

    public mutating func updateDraft(_ layout: Layout) {
        draft = layout
    }

    /// Returns nil when Save should only close the editor, or when the draft is invalid.
    /// Grid layouts are protected because this editor only produces Canvas geometry.
    public func layoutForCommit(
        existingNames: [String],
        newID: UUID = UUID(),
        now: Date = Date()
    ) -> Layout? {
        guard canCommit else { return nil }
        if original != nil, !hasChanges { return nil }

        var result = draft
        if let original {
            if original.kind == .grid {
                result.id = newID
                result.name = Self.uniqueName(base: "\(original.name) Copy", existingNames: existingNames)
                result.createdAt = now
            } else {
                result.id = original.id
                result.createdAt = original.createdAt
            }
        }
        result.updatedAt = now
        return result
    }

    public static func uniqueName(base: String, existingNames: [String]) -> String {
        let names = Set(existingNames)
        if !names.contains(base) { return base }

        var suffix = 2
        while names.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }
}
