import Foundation

public enum WorkspaceSwitcherPhase: Equatable, Sendable {
    case hidden
    case browsing(highlight: Int)
    /// `thisDisplayOnly` narrows the save to the pointer's display; it only
    /// takes effect while the input offers a `displayChoice`.
    case naming(text: String, highlight: Int, thisDisplayOnly: Bool = false)
}

public enum WorkspaceSwitcherEvent: Equatable, Sendable {
    case invoke
    case digit(Int)
    case move(dx: Int, dy: Int)
    case confirm
    case beginSave
    case textChanged(String)
    case toggleCaptureScope
    case save
    case update
    case dismiss
}

public enum WorkspaceSwitcherEffect: Equatable, Sendable {
    case show
    case hide
    case apply(WorkspaceProfile.ID)
    /// nil `displayID` saves every display that holds windows.
    case capture(name: String, displayID: DisplayIdentity.ID? = nil)
    case updateProfile(WorkspaceProfile.ID)
    case beep
}

/// The "only this display" alternative offered while naming. Present only
/// when at least two displays hold windows and the pointer's display is known.
public struct WorkspaceSwitcherDisplayChoice: Equatable, Sendable {
    public var displayID: DisplayIdentity.ID
    public var suggestedName: String
    public var captureCount: Int

    public init(displayID: DisplayIdentity.ID, suggestedName: String, captureCount: Int) {
        self.displayID = displayID
        self.suggestedName = suggestedName
        self.captureCount = captureCount
    }
}

public struct WorkspaceSwitcherInput: Equatable, Sendable {
    public var phase: WorkspaceSwitcherPhase
    public var event: WorkspaceSwitcherEvent
    public var profileIDs: [WorkspaceProfile.ID]
    public var activeProfileID: WorkspaceProfile.ID?
    public var isIdle: Bool
    public var trusted: Bool
    public var captureCount: Int
    public var suggestedName: String
    public var displayChoice: WorkspaceSwitcherDisplayChoice?

    public init(
        phase: WorkspaceSwitcherPhase,
        event: WorkspaceSwitcherEvent,
        profileIDs: [WorkspaceProfile.ID] = [],
        activeProfileID: WorkspaceProfile.ID? = nil,
        isIdle: Bool = true,
        trusted: Bool = true,
        captureCount: Int = 0,
        suggestedName: String = "",
        displayChoice: WorkspaceSwitcherDisplayChoice? = nil
    ) {
        self.phase = phase
        self.event = event
        self.profileIDs = profileIDs
        self.activeProfileID = activeProfileID
        self.isIdle = isIdle
        self.trusted = trusted
        self.captureCount = captureCount
        self.suggestedName = suggestedName
        self.displayChoice = displayChoice
    }
}

public struct WorkspaceSwitcherOutput: Equatable, Sendable {
    public var phase: WorkspaceSwitcherPhase
    public var effects: [WorkspaceSwitcherEffect]

    public init(phase: WorkspaceSwitcherPhase, effects: [WorkspaceSwitcherEffect]) {
        self.phase = phase
        self.effects = effects
    }
}

public enum WorkspaceSwitcherReducer {
    public static let columns = 3

    public static func reduce(_ input: WorkspaceSwitcherInput) -> WorkspaceSwitcherOutput {
        switch input.event {
        case .invoke:
            return invoke(input)
        case .digit(let number):
            return digit(input, number: number)
        case .move(let dx, let dy):
            return move(input, dx: dx, dy: dy)
        case .confirm:
            return confirm(input)
        case .beginSave:
            return beginSave(input)
        case .textChanged(let text):
            return textChanged(input, text: text)
        case .toggleCaptureScope:
            return toggleCaptureScope(input)
        case .save:
            return save(input)
        case .update:
            return update(input)
        case .dismiss:
            return dismiss(input)
        }
    }

    public static func defaultHighlight(
        profileIDs: [WorkspaceProfile.ID],
        activeProfileID: WorkspaceProfile.ID?
    ) -> Int {
        if let activeProfileID, let index = profileIDs.firstIndex(of: activeProfileID) {
            return index
        }
        return 0
    }

    public static func movedHighlight(
        current: Int,
        dx: Int,
        dy: Int,
        count: Int,
        columns: Int = columns
    ) -> Int {
        guard count > 0 else { return 0 }
        if dx != 0 && dy == 0 {
            return (current + dx % count + count) % count
        }
        if dy != 0 && dx == 0 {
            let rowCount = max((count + columns - 1) / columns, 1)
            let row = current / columns
            let col = current % columns
            let nextRow = (row + dy % rowCount + rowCount) % rowCount
            var next = nextRow * columns + col
            if next >= count {
                next = count - 1
            }
            return next
        }
        return min(max(current, 0), count - 1)
    }

    private static func invoke(_ input: WorkspaceSwitcherInput) -> WorkspaceSwitcherOutput {
        switch input.phase {
        case .hidden:
            guard input.trusted, input.isIdle else {
                return WorkspaceSwitcherOutput(
                    phase: .hidden,
                    effects: input.trusted ? [.beep] : []
                )
            }
            let highlight = defaultHighlight(
                profileIDs: input.profileIDs,
                activeProfileID: input.activeProfileID
            )
            return WorkspaceSwitcherOutput(phase: .browsing(highlight: highlight), effects: [.show])
        case .browsing, .naming:
            return confirm(input)
        }
    }

    private static func digit(_ input: WorkspaceSwitcherInput, number: Int) -> WorkspaceSwitcherOutput {
        guard case .browsing(let highlight) = input.phase else {
            return WorkspaceSwitcherOutput(phase: input.phase, effects: [])
        }
        guard (1...9).contains(number) else {
            return WorkspaceSwitcherOutput(phase: .browsing(highlight: highlight), effects: [])
        }
        let index = number - 1
        guard input.profileIDs.indices.contains(index) else {
            return WorkspaceSwitcherOutput(phase: .browsing(highlight: highlight), effects: [])
        }
        return apply(input, index: index)
    }

    private static func move(_ input: WorkspaceSwitcherInput, dx: Int, dy: Int) -> WorkspaceSwitcherOutput {
        guard case .browsing(let highlight) = input.phase else {
            return WorkspaceSwitcherOutput(phase: input.phase, effects: [])
        }
        let next = movedHighlight(current: highlight, dx: dx, dy: dy, count: input.profileIDs.count)
        return WorkspaceSwitcherOutput(phase: .browsing(highlight: next), effects: [])
    }

    private static func confirm(_ input: WorkspaceSwitcherInput) -> WorkspaceSwitcherOutput {
        switch input.phase {
        case .hidden:
            return WorkspaceSwitcherOutput(phase: .hidden, effects: [])
        case .naming:
            return save(input)
        case .browsing(let highlight):
            return apply(input, index: highlight)
        }
    }

    private static func beginSave(_ input: WorkspaceSwitcherInput) -> WorkspaceSwitcherOutput {
        switch input.phase {
        case .browsing(let highlight):
            return WorkspaceSwitcherOutput(
                phase: .naming(text: input.suggestedName, highlight: highlight),
                effects: []
            )
        case .hidden, .naming:
            return WorkspaceSwitcherOutput(phase: input.phase, effects: [])
        }
    }

    private static func textChanged(_ input: WorkspaceSwitcherInput, text: String) -> WorkspaceSwitcherOutput {
        guard case .naming(_, let highlight, let thisDisplayOnly) = input.phase else {
            return WorkspaceSwitcherOutput(phase: input.phase, effects: [])
        }
        return WorkspaceSwitcherOutput(
            phase: .naming(text: text, highlight: highlight, thisDisplayOnly: thisDisplayOnly),
            effects: []
        )
    }

    /// Flips between saving every display and only the pointer's display. A
    /// name the user has not edited follows the scope; a typed name is kept.
    private static func toggleCaptureScope(_ input: WorkspaceSwitcherInput) -> WorkspaceSwitcherOutput {
        guard case .naming(let text, let highlight, let thisDisplayOnly) = input.phase,
              let choice = input.displayChoice
        else {
            return WorkspaceSwitcherOutput(phase: input.phase, effects: [])
        }
        let previousSuggestion = thisDisplayOnly ? choice.suggestedName : input.suggestedName
        let nextSuggestion = thisDisplayOnly ? input.suggestedName : choice.suggestedName
        return WorkspaceSwitcherOutput(
            phase: .naming(
                text: text == previousSuggestion ? nextSuggestion : text,
                highlight: highlight,
                thisDisplayOnly: !thisDisplayOnly
            ),
            effects: []
        )
    }

    private static func save(_ input: WorkspaceSwitcherInput) -> WorkspaceSwitcherOutput {
        guard case .naming(let text, let highlight, let thisDisplayOnly) = input.phase else {
            return WorkspaceSwitcherOutput(phase: input.phase, effects: [])
        }
        // A scope narrowed while two displays held windows falls back to the
        // whole desk once the choice disappears (display unplugged mid-save).
        let scope = thisDisplayOnly ? input.displayChoice : nil
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (scope?.captureCount ?? input.captureCount) == 0 || name.isEmpty {
            return WorkspaceSwitcherOutput(
                phase: .naming(text: text, highlight: highlight, thisDisplayOnly: thisDisplayOnly),
                effects: [.beep]
            )
        }
        return WorkspaceSwitcherOutput(
            phase: .hidden,
            effects: [.hide, .capture(name: name, displayID: scope?.displayID)]
        )
    }

    private static func update(_ input: WorkspaceSwitcherInput) -> WorkspaceSwitcherOutput {
        guard case .browsing(let highlight) = input.phase else {
            return WorkspaceSwitcherOutput(phase: input.phase, effects: [])
        }
        guard input.profileIDs.indices.contains(highlight) else {
            return WorkspaceSwitcherOutput(phase: .browsing(highlight: highlight), effects: [.beep])
        }
        return WorkspaceSwitcherOutput(
            phase: .hidden,
            effects: [.hide, .updateProfile(input.profileIDs[highlight])]
        )
    }

    private static func dismiss(_ input: WorkspaceSwitcherInput) -> WorkspaceSwitcherOutput {
        switch input.phase {
        case .hidden:
            return WorkspaceSwitcherOutput(phase: .hidden, effects: [])
        case .naming(_, let highlight, _):
            return WorkspaceSwitcherOutput(phase: .browsing(highlight: highlight), effects: [])
        case .browsing:
            return WorkspaceSwitcherOutput(phase: .hidden, effects: [.hide])
        }
    }

    private static func apply(_ input: WorkspaceSwitcherInput, index: Int) -> WorkspaceSwitcherOutput {
        let browsing = browsingPhase(input)
        guard input.profileIDs.indices.contains(index) else {
            return WorkspaceSwitcherOutput(phase: browsing, effects: [.beep])
        }
        return WorkspaceSwitcherOutput(
            phase: .hidden,
            effects: [.hide, .apply(input.profileIDs[index])]
        )
    }

    private static func browsingPhase(_ input: WorkspaceSwitcherInput) -> WorkspaceSwitcherPhase {
        switch input.phase {
        case .browsing(let highlight):
            return .browsing(highlight: highlight)
        case .naming(_, let highlight, _):
            return .browsing(highlight: highlight)
        case .hidden:
            return .hidden
        }
    }
}
