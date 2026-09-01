import Foundation

public enum QuickSnapperPhase: Equatable, Sendable {
    case hidden
    /// `target` is the window focused at invoke, captured before any HUD activation.
    case showing(target: WindowIdentity?)
}

public enum QuickSnapperEvent: Equatable, Sendable {
    case invoke
    case digit(Int)
    case dismiss
    case cycleLayout(Int)
}

public enum QuickSnapperEffect: Equatable, Sendable {
    case showOverlay
    case hideOverlay
    case snap(WindowIdentity, zoneNumber: Int)
}

public struct QuickSnapperInput: Equatable, Sendable {
    public var phase: QuickSnapperPhase
    public var event: QuickSnapperEvent
    public var zoneNumbers: Set<Int>
    public var trusted: Bool
    public var snapEnabled: Bool
    public var isEditorOpen: Bool
    public var enabled: Bool
    /// AX focused window at this event. Used on `.invoke` only; digit/dismiss ignore it.
    public var focusedWindow: WindowIdentity?
    public var layoutIDs: [Layout.ID]
    public var selectedLayoutID: Layout.ID?

    public init(
        phase: QuickSnapperPhase,
        event: QuickSnapperEvent,
        zoneNumbers: Set<Int> = [],
        trusted: Bool = true,
        snapEnabled: Bool = true,
        isEditorOpen: Bool = false,
        enabled: Bool = true,
        focusedWindow: WindowIdentity? = nil,
        layoutIDs: [Layout.ID] = [],
        selectedLayoutID: Layout.ID? = nil
    ) {
        self.phase = phase
        self.event = event
        self.zoneNumbers = zoneNumbers
        self.trusted = trusted
        self.snapEnabled = snapEnabled
        self.isEditorOpen = isEditorOpen
        self.enabled = enabled
        self.focusedWindow = focusedWindow
        self.layoutIDs = layoutIDs
        self.selectedLayoutID = selectedLayoutID
    }
}

public struct QuickSnapperOutput: Equatable, Sendable {
    public var phase: QuickSnapperPhase
    public var effects: [QuickSnapperEffect]
    public var selectedLayoutID: Layout.ID?

    public init(
        phase: QuickSnapperPhase,
        effects: [QuickSnapperEffect],
        selectedLayoutID: Layout.ID? = nil
    ) {
        self.phase = phase
        self.effects = effects
        self.selectedLayoutID = selectedLayoutID
    }
}

/// Numbered 1–9 overlay path. Distinct from silent Control+Option+1–9 hotkeys.
public enum QuickSnapperReducer {
    public static func reduce(_ input: QuickSnapperInput) -> QuickSnapperOutput {
        if !input.trusted || !input.snapEnabled || input.isEditorOpen || !input.enabled {
            if input.phase == .hidden {
                return QuickSnapperOutput(phase: .hidden, effects: [], selectedLayoutID: nil)
            }
            return QuickSnapperOutput(phase: .hidden, effects: [.hideOverlay], selectedLayoutID: nil)
        }

        switch input.event {
        case .invoke:
            return QuickSnapperOutput(
                phase: .showing(target: input.focusedWindow),
                effects: [.showOverlay],
                selectedLayoutID: input.selectedLayoutID ?? input.layoutIDs.first
            )
        case .digit(let number):
            guard case .showing(let target) = input.phase else {
                return QuickSnapperOutput(phase: input.phase, effects: [], selectedLayoutID: input.selectedLayoutID)
            }
            guard (1...9).contains(number), input.zoneNumbers.contains(number) else {
                return QuickSnapperOutput(
                    phase: .showing(target: target),
                    effects: [],
                    selectedLayoutID: input.selectedLayoutID
                )
            }
            guard let target else {
                return QuickSnapperOutput(
                    phase: .showing(target: nil),
                    effects: [],
                    selectedLayoutID: input.selectedLayoutID
                )
            }
            return QuickSnapperOutput(
                phase: .hidden,
                effects: [.snap(target, zoneNumber: number), .hideOverlay],
                selectedLayoutID: input.selectedLayoutID
            )
        case .cycleLayout(let delta):
            guard case .showing(let target) = input.phase else {
                return QuickSnapperOutput(phase: input.phase, effects: [], selectedLayoutID: input.selectedLayoutID)
            }
            guard !input.layoutIDs.isEmpty else {
                return QuickSnapperOutput(
                    phase: .showing(target: target),
                    effects: [],
                    selectedLayoutID: input.selectedLayoutID
                )
            }
            let current = input.selectedLayoutID.flatMap { input.layoutIDs.firstIndex(of: $0) } ?? 0
            let next = ZoneCandidateResolver.wrappingIndex(current: current, delta: delta, count: input.layoutIDs.count)
            return QuickSnapperOutput(
                phase: .showing(target: target),
                effects: [.showOverlay],
                selectedLayoutID: input.layoutIDs[next]
            )
        case .dismiss:
            if input.phase == .hidden {
                return QuickSnapperOutput(phase: .hidden, effects: [], selectedLayoutID: nil)
            }
            return QuickSnapperOutput(phase: .hidden, effects: [.hideOverlay], selectedLayoutID: nil)
        }
    }

    public static func zoneNumber(forKeyCode keyCode: UInt16) -> Int? {
        guard let index = AppSettings.zoneKeyCodes.firstIndex(of: keyCode) else { return nil }
        return index + 1
    }

    /// HUD and digit snaps must use the captured target window's display, not
    /// whatever screen currently holds the pointer.
    public static func displayArea(
        pointerArea: WorkArea?,
        targetWindowArea: WorkArea?
    ) -> WorkArea? {
        targetWindowArea ?? pointerArea
    }
}
