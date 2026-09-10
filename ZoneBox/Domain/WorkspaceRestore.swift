import CoreGraphics
import Foundation

/// Pure restore policy for workspace apply. WorkspaceCenter owns AppKit / AX
/// side effects; this type decides whether to launch, reopen, keep waiting, or
/// give up so Electron helpers, splash windows, and disconnected displays cannot
/// silently drop a saved app or skip the saved layout.
public enum WorkspaceRestore {
    /// Cold launches of editors and Electron shells routinely take longer than
    /// 15-30s before a standard window appears.
    public static let launchTimeout: TimeInterval = 45

    /// openApplication can fail while Launch Services is busy or the previous
    /// helper is still exiting. Retry a few times before telling the user.
    public static let launchRetryLimit = 3

    public static let launchRetryDelay: TimeInterval = 1

    /// After a running app is reopened, wait this long for a window before
    /// falling back to a Dock-style openApplication nudge.
    public static let reopenNudgeDelay: TimeInterval = 2

    /// Helper / launcher processes with the same bundle ID often die a moment
    /// before the real app registers. Do not drop pending until this gap closes.
    public static let terminationRecheckDelay: TimeInterval = 1.5

    /// A freshly launched window may still be resizing itself when the first
    /// placement lands. Retry a few polls before ignoring that window.
    public static let maxRejectedAttempts = 3

    public enum OpenCommand: Equatable, Sendable {
        case none
        case reopenRunning
        case launch
    }

    public enum OpenFailureDisposition: Equatable, Sendable {
        /// No process came up; drop pending and report the error.
        case giveUp
        /// Reopen / launch reported an error but the app is still alive, so keep
        /// waiting for a window instead of cancelling placement.
        case keepWaiting
    }

    public enum RejectedWindowDisposition: Equatable, Sendable {
        case retryAfterRestabilizing
        /// Splash / chrome consumed the reservation. Free it so a later standard
        /// window of the same app can take the zone. Keep the pending entry.
        case ignoreThisWindowKeepPending
    }

    /// Running windowless apps need a reopen event, not a second process.
    /// openApplication is a follow-up nudge, not the first step.
    public static func openCommand(for action: ProfilePlan.AppOpenAction) -> OpenCommand {
        switch action {
        case .none: .none
        case .reopen: .reopenRunning
        case .launch: .launch
        }
    }

    public static func openFailureDisposition(
        action: ProfilePlan.AppOpenAction,
        bundleID: String,
        runningBundleIDs: Set<String>
    ) -> OpenFailureDisposition {
        if runningBundleIDs.contains(bundleID) { return .keepWaiting }
        if action == .reopen { return .keepWaiting }
        return .giveUp
    }

    public static func shouldRetryLaunch(
        action: ProfilePlan.AppOpenAction,
        attempt: Int,
        runningBundleIDs: Set<String>,
        bundleID: String
    ) -> Bool {
        action == .launch
            && !runningBundleIDs.contains(bundleID)
            && attempt < launchRetryLimit
    }

    /// If reopen did not produce a window, click-the-Dock via openApplication.
    public static func shouldNudgeReopen(
        action: ProfilePlan.AppOpenAction,
        stillPending: Bool,
        running: Bool
    ) -> Bool {
        action == .reopen && stillPending && running
    }

    /// Only drop pending when the bundle is truly gone. A helper that shares the
    /// bundle ID must not cancel restore of Cursor / Codex / WeChat.
    public static func shouldDropPendingOnTermination(
        bundleID: String?,
        remainingRunningBundleIDs: Set<String>
    ) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return !remainingRunningBundleIDs.contains(bundleID)
    }

    public static func rejectedWindowDisposition(rejectedAttempts: Int) -> RejectedWindowDisposition {
        rejectedAttempts >= maxRejectedAttempts ? .ignoreThisWindowKeepPending : .retryAfterRestabilizing
    }

    /// The same AX window often starts as a splash and later grows into the
    /// document window. Revive it so restore does not wait out the timeout.
    public static func shouldReviveIgnoredWindow(previousFrame: CGRect, currentFrame: CGRect) -> Bool {
        abs(previousFrame.width - currentFrame.width) >= 80
            || abs(previousFrame.height - currentFrame.height) >= 80
    }

    /// When every saved display is unplugged, restore the first section onto the
    /// current display so a laptop-lid / clamshell desk still gets its layout.
    /// A still-connected sibling section keeps its own display and is not stolen.
    public static func remappedSections(
        _ sections: [ProfileSection],
        availableDisplayIDs: Set<DisplayIdentity.ID>,
        fallbackDisplayID: DisplayIdentity.ID?
    ) -> [ProfileSection] {
        let savedIDs = sections.map(\.space.displayID)
        let anySavedDisplayIsLive = savedIDs.contains { availableDisplayIDs.contains($0) }
        var usedFallback = false
        return sections.map { section in
            if availableDisplayIDs.contains(section.space.displayID) { return section }
            guard !anySavedDisplayIsLive,
                  !usedFallback,
                  let fallbackDisplayID,
                  availableDisplayIDs.contains(fallbackDisplayID)
            else { return section }
            usedFallback = true
            var copy = section
            copy.space.displayID = fallbackDisplayID
            return copy
        }
    }

    public static func shouldAssignLayout(displayAvailable: Bool, layoutExists: Bool) -> Bool {
        displayAvailable && layoutExists
    }

    /// Flash the saved layout even when every window is still launching, so the
    /// user can see the display switch before apps finish opening.
    public static func shouldFlashAssignedLayout(
        displayAvailable: Bool,
        layoutExists: Bool,
        organizeSucceeded: Bool,
        noMovableWindows: Bool
    ) -> Bool {
        shouldAssignLayout(displayAvailable: displayAvailable, layoutExists: layoutExists)
            && (organizeSucceeded || noMovableWindows)
    }

    /// Unique bundle IDs in first-seen order. Restore activates this sequence
    /// so every saved app sits above unrelated windows; the last ID becomes
    /// the frontmost application.
    public static func foregroundBundleIDs(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in bundleIDs {
            let bundleID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty, seen.insert(bundleID).inserted else { continue }
            ordered.append(bundleID)
        }
        return ordered
    }

    /// AXRaise does not lift a window above another application. Restore must
    /// activate each saved app. Activating every window would yank the user
    /// onto another Space, so this stays off for already-placed windows.
    public static var activateAllWindowsWhenForegroundingRestoredApps: Bool { false }
}
