import Foundation

/// Keeps layout editing isolated from the persisted document until the user commits.
public struct LayoutEditTransaction: Sendable {
    public let original: Layout?
    public let baseline: Layout
    public let targetDisplayID: DisplayIdentity.ID
    public private(set) var draft: Layout
    private var undoStack: [Layout] = []
    private var redoStack: [Layout] = []
    private var interactionBase: Layout?

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
        recordUndoIfNeeded(layout)
        draft = layout
    }

    public mutating func replaceDraftWithoutRecording(_ layout: Layout) {
        draft = layout
    }

    public mutating func beginInteraction() {
        if interactionBase == nil {
            interactionBase = draft
        }
    }

    public mutating func previewDraft(_ layout: Layout) {
        beginInteraction()
        draft = layout
    }

    public mutating func finishInteraction(_ layout: Layout) {
        let base = interactionBase ?? draft
        interactionBase = nil
        if !Self.sameEditingState(layout, base) {
            if undoStack.last.map({ Self.sameEditingState($0, base) }) != true {
                undoStack.append(base)
                if undoStack.count > 50 {
                    undoStack.removeFirst(undoStack.count - 50)
                }
            }
            redoStack.removeAll()
        }
        draft = layout
    }

    public mutating func cancelInteraction() {
        if let base = interactionBase {
            draft = base
        }
        interactionBase = nil
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    @discardableResult
    public mutating func undo() -> Layout? {
        guard let previous = undoStack.popLast() else { return nil }
        if redoStack.last.map({ Self.sameEditingState($0, draft) }) != true {
            redoStack.append(draft)
            if redoStack.count > 50 {
                redoStack.removeFirst(redoStack.count - 50)
            }
        }
        draft = previous
        return previous
    }

    @discardableResult
    public mutating func redo() -> Layout? {
        guard let next = redoStack.popLast() else { return nil }
        if undoStack.last.map({ Self.sameEditingState($0, draft) }) != true {
            undoStack.append(draft)
            if undoStack.count > 50 {
                undoStack.removeFirst(undoStack.count - 50)
            }
        }
        draft = next
        return next
    }

    private mutating func recordUndoIfNeeded(_ layout: Layout) {
        guard !Self.sameEditingState(layout, draft) else { return }
        if let last = undoStack.last, Self.sameEditingState(last, draft) { return }
        undoStack.append(draft)
        if undoStack.count > 50 {
            undoStack.removeFirst(undoStack.count - 50)
        }
        redoStack.removeAll()
    }

    static func sameEditingState(_ lhs: Layout, _ rhs: Layout) -> Bool {
        lhs.kind == rhs.kind
            && lhs.zones == rhs.zones
            && lhs.grid == rhs.grid
    }

    public func suggestedCopyName(sourceName: String? = nil, existingNames: [String]) -> String {
        let source = sourceName ?? original?.name ?? draft.name
        return Self.uniqueName(base: Self.copyBaseName(from: source), existingNames: existingNames)
    }

    /// Returns nil when Save should only close the editor, or when the draft is invalid.
    public func layoutForCommit(
        existingNames: [String],
        newID: UUID = UUID(),
        now: Date = Date(),
        requestedName: String? = nil,
        createsCopy: Bool = false
    ) -> Layout? {
        guard canCommit else { return nil }
        let isCopyCommit = createsCopy
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
