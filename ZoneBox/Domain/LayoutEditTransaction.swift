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

    public func targetIsAvailable(in displayIDs: some Sequence<DisplayIdentity.ID>) -> Bool {
        displayIDs.contains(targetDisplayID)
    }

    public mutating func updateDraft(_ layout: Layout) {
        draft = layout
    }

    public func suggestedCopyName(sourceName: String? = nil, existingNames: [String]) -> String {
        let source = sourceName ?? original?.name ?? draft.name
        return Self.uniqueName(base: Self.copyBaseName(from: source), existingNames: existingNames)
    }

    /// Returns nil when Save should only close the editor, or when the draft is invalid.
    /// Grid layouts are protected because this editor only produces Canvas geometry.
    public func layoutForCommit(
        existingNames: [String],
        newID: UUID = UUID(),
        now: Date = Date(),
        requestedName: String? = nil,
        createsCopy: Bool = false
    ) -> Layout? {
        guard canCommit else { return nil }
        let isCopyCommit = original.map { $0.kind == .grid || createsCopy } ?? false
        let explicitlyNamedCopy = isCopyCommit && requestedName != nil
        if original != nil, !hasChanges, !explicitlyNamedCopy { return nil }

        var result = draft
        if let original {
            if isCopyCommit {
                result.id = newID
                let trimmed = requestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let base = trimmed.isEmpty ? Self.copyBaseName(from: original.name) : trimmed
                result.name = Self.uniqueName(base: base, existingNames: existingNames)
                result.createdAt = now
            } else {
                result.id = original.id
                result.createdAt = original.createdAt
            }
        } else if let requestedName {
            let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmed.isEmpty ? draft.name : trimmed
            result.name = Self.uniqueName(base: base, existingNames: existingNames)
        }
        result.updatedAt = now
        return result
    }

    public static func copyBaseName(from name: String) -> String {
        var stem = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            if let range = stem.range(of: #" Copy(?: \d+)?$"#, options: .regularExpression) {
                stem = String(stem[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            break
        }
        return stem.isEmpty ? "Layout Copy" : "\(stem) Copy"
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
