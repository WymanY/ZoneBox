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

    public init(
        phase: QuickSnapperPhase,
        event: QuickSnapperEvent,
        zoneNumbers: Set<Int> = [],
        trusted: Bool = true,
        snapEnabled: Bool = true,
        isEditorOpen: Bool = false,
        enabled: Bool = true,
        focusedWindow: WindowIdentity? = nil
    ) {
        self.phase = phase
        self.event = event
        self.zoneNumbers = zoneNumbers
        self.trusted = trusted
        self.snapEnabled = snapEnabled
        self.isEditorOpen = isEditorOpen
        self.enabled = enabled
        self.focusedWindow = focusedWindow
    }
}

public struct QuickSnapperOutput: Equatable, Sendable {
    public var phase: QuickSnapperPhase
    public var effects: [QuickSnapperEffect]

    public init(phase: QuickSnapperPhase, effects: [QuickSnapperEffect]) {
        self.phase = phase
        self.effects = effects
    }
}

/// Numbered 1–9 overlay path. Distinct from silent Control+Option+1–9 hotkeys.
public enum QuickSnapperReducer {
    public static func reduce(_ input: QuickSnapperInput) -> QuickSnapperOutput {
        if !input.trusted || !input.snapEnabled || input.isEditorOpen || !input.enabled {
            if input.phase == .hidden {
                return QuickSnapperOutput(phase: .hidden, effects: [])
            }
            return QuickSnapperOutput(phase: .hidden, effects: [.hideOverlay])
        }

        switch input.event {
        case .invoke:
            return QuickSnapperOutput(
                phase: .showing(target: input.focusedWindow),
                effects: [.showOverlay]
            )
        case .digit(let number):
            guard case .showing(let target) = input.phase else {
                return QuickSnapperOutput(phase: input.phase, effects: [])
            }
            guard (1...9).contains(number), input.zoneNumbers.contains(number) else {
                return QuickSnapperOutput(phase: .showing(target: target), effects: [])
            }
            guard let target else {
                return QuickSnapperOutput(phase: .showing(target: nil), effects: [])
            }
            return QuickSnapperOutput(
                phase: .hidden,
                effects: [.snap(target, zoneNumber: number), .hideOverlay]
            )
        case .dismiss:
            if input.phase == .hidden {
                return QuickSnapperOutput(phase: .hidden, effects: [])
            }
            return QuickSnapperOutput(phase: .hidden, effects: [.hideOverlay])
        }
    }

    public static func zoneNumber(forKeyCode keyCode: UInt16) -> Int? {
        guard let index = AppSettings.zoneKeyCodes.firstIndex(of: keyCode) else { return nil }
        return index + 1
    }
}
