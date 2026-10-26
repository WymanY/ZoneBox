import CoreGraphics
import Foundation

/// Live snap overlay versus menu-bar / onboarding preview.
///
/// Keep live overlays at the drag level and avoid repeated window ordering
/// while the system owns title-bar tracking. Previews use the screensaver
/// level so they cover the console and welcome window.
public enum OverlayStackingKind: Equatable, Sendable {
    case liveSnap
    case preview
}

public struct OverlayPresentDecision: Equatable, Sendable {
    public var kind: OverlayStackingKind
    /// `orderFrontRegardless` — first show, preview, or level change only.
    public var restack: Bool
    /// Synchronous `displayIfNeeded` — first show or preview only.
    public var flushDisplay: Bool

    public init(kind: OverlayStackingKind, restack: Bool, flushDisplay: Bool) {
        self.kind = kind
        self.restack = restack
        self.flushDisplay = flushDisplay
    }
}

public enum OverlayStackingPolicy {
    public static func kind(isPreview: Bool) -> OverlayStackingKind {
        isPreview ? .preview : .liveSnap
    }

    public static func windowLevel(_ kind: OverlayStackingKind) -> CGWindowLevel {
        switch kind {
        case .liveSnap:
            CGWindowLevelForKey(.draggingWindow) + 1
        case .preview:
            CGWindowLevelForKey(.screenSaverWindow)
        }
    }

    /// Once visible at the live level, pointer samples update the view
    /// without reordering its window or forcing a synchronous display.
    public static func present(
        isPreview: Bool,
        alreadyVisible: Bool,
        stackingMatches: Bool
    ) -> OverlayPresentDecision {
        let kind = kind(isPreview: isPreview)
        return OverlayPresentDecision(
            kind: kind,
            restack: isPreview || !alreadyVisible || !stackingMatches,
            flushDisplay: isPreview || !alreadyVisible
        )
    }
}
