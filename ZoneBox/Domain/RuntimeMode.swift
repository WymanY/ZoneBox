import Foundation

/// Exclusive owner of live window interaction. Overlay chrome, pointer
/// capture, and AX mutation all consult this instead of reading scattered
/// flags such as isEditorOpen / isOrganizingWindows / engine.isSessionActive.
public enum RuntimeMode: Equatable, Sendable {
    case idle
    case snapping
    case dividing
    case pinningFollow
    case organizing
    case editing
}

public enum RuntimeModeRequest: Equatable, Sendable {
    case snap
    case divide
    case pinFollow
    case organize
    case edit

    public var mode: RuntimeMode {
        switch self {
        case .snap: .snapping
        case .divide: .dividing
        case .pinFollow: .pinningFollow
        case .organize: .organizing
        case .edit: .editing
        }
    }
}

public enum RuntimeCapability: Equatable, Sendable {
    case capturePointer
    case presentDivider
    case presentPinHover
    case followPinnedWindows
    case raisePinnedWindows
    case censusWindows
    case mutateWindows
}

public struct RuntimeModeGate: Equatable, Sendable {
    public private(set) var mode: RuntimeMode

    public init(mode: RuntimeMode = .idle) {
        self.mode = mode
    }

    public var isIdle: Bool { mode == .idle }

    public var isEditorOpen: Bool { mode == .editing }

    public var isOrganizingWindows: Bool { mode == .organizing }

    public var isSessionActive: Bool {
        switch mode {
        case .idle:
            false
        default:
            true
        }
    }

    public mutating func begin(_ request: RuntimeModeRequest) -> Bool {
        switch (mode, request) {
        case (.idle, _):
            mode = request.mode
            return true
        case (.snapping, .snap),
             (.dividing, .divide),
             (.pinningFollow, .pinFollow),
             (.organizing, .organize),
             (.editing, .edit):
            return true
        default:
            return false
        }
    }

    public mutating func end(_ request: RuntimeModeRequest) {
        if mode == request.mode {
            mode = .idle
        }
    }

    public mutating func force(_ mode: RuntimeMode) {
        self.mode = mode
    }

    public func allows(_ capability: RuntimeCapability) -> Bool {
        switch capability {
        case .capturePointer:
            switch mode {
            case .idle, .snapping:
                true
            case .dividing, .pinningFollow, .organizing, .editing:
                false
            }
        case .presentDivider:
            mode == .idle || mode == .dividing
        case .presentPinHover:
            mode == .idle
        case .followPinnedWindows:
            switch mode {
            case .idle, .pinningFollow:
                true
            case .snapping, .dividing, .organizing, .editing:
                false
            }
        case .raisePinnedWindows:
            switch mode {
            case .idle, .pinningFollow:
                true
            case .snapping, .dividing, .organizing, .editing:
                false
            }
        case .censusWindows:
            mode == .idle
        case .mutateWindows:
            switch mode {
            case .idle, .snapping, .dividing, .organizing, .pinningFollow:
                true
            case .editing:
                false
            }
        }
    }
}
