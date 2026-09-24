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

    /// FrontmostApplication can lag the activate request. Observe after this
    /// delay before recording a mismatch or retrying.
    public static let activationSettleDelay: TimeInterval = 0.05

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

    /// Captured windows are stored front-to-back. Activation and raise must
    /// run back-to-front so the originally frontmost window stays on top.
    public static func stackingOrder<T>(_ frontToBack: [T]) -> [T] {
        Array(frontToBack.reversed())
    }

    /// Unique items in the order of their last occurrence. Used on a
    /// back-to-front list so an interleaved A, B, A capture activates B then A.
    public static func lastOccurrenceOrder<T: Hashable>(_ items: [T]) -> [T] {
        var lastIndex: [T: Int] = [:]
        for (index, item) in items.enumerated() {
            lastIndex[item] = index
        }
        return items.enumerated().compactMap { index, item in
            lastIndex[item] == index ? item : nil
        }
    }

    /// Bundle activation order for a front-to-back capture. Each bundle is
    /// taken at its last back-to-front occurrence, so the originally frontmost
    /// app is activated last.
    public static func restoreActivationBundleIDs(_ frontToBack: [String]) -> [String] {
        let normalized = frontToBack.compactMap { raw -> String? in
            let bundleID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return bundleID.isEmpty ? nil : bundleID
        }
        return lastOccurrenceOrder(stackingOrder(normalized))
    }

    /// Process activation order for one bundle in a front-to-back capture.
    /// Last back-to-front occurrence wins, matching restoreActivationBundleIDs.
    public static func restoreActivationProcessIDs(
        _ frontToBack: [WindowIdentity],
        bundleID: String
    ) -> [pid_t] {
        let pids = stackingOrder(frontToBack).compactMap { window -> pid_t? in
            guard window.bundleID == bundleID, window.pid > 0 else { return nil }
            return window.pid
        }
        return lastOccurrenceOrder(pids)
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

    /// Each restored window owner must be activated before its windows are raised.
    /// Preserve the saved window order while skipping repeated windows of one process.
    public static func foregroundProcessIDs(_ windows: [WindowIdentity], bundleID: String) -> [pid_t] {
        var seen = Set<pid_t>()
        return windows.compactMap { window in
            guard window.bundleID == bundleID, window.pid > 0, seen.insert(window.pid).inserted else { return nil }
            return window.pid
        }
    }

    /// AXRaise does not lift a window above another application. Restore must
    /// activate each saved app. Activating every window would yank the user
    /// onto another Space, so this stays off for already-placed windows.
    public static var activateAllWindowsWhenForegroundingRestoredApps: Bool { false }

    /// Live process facts used to pick which pid restore should activate.
    public struct RunningProcess: Equatable, Sendable {
        public var pid: pid_t
        public var bundleID: String?
        public var isRegular: Bool
        public var isFinished: Bool
        public var isHidden: Bool

        public init(
            pid: pid_t,
            bundleID: String?,
            isRegular: Bool,
            isFinished: Bool,
            isHidden: Bool
        ) {
            self.pid = pid
            self.bundleID = bundleID
            self.isRegular = isRegular
            self.isFinished = isFinished
            self.isHidden = isHidden
        }
    }

    public enum ActivationOutcome: Equatable, Sendable {
        case noProcess
        case rejected
        case acceptedButFrontmostMismatch
        case acceptedAndFrontmost
    }

    /// Prefer the pid that owns a restored window. Looking up a bundle ID and
    /// taking the first running process can pick a helper; activating every
    /// window would pull unsaved windows across Spaces.
    public static func preferredProcessIdentifier(
        bundleID: String,
        restoredWindowPIDs: [pid_t],
        running: [RunningProcess]
    ) -> pid_t? {
        let wanted = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let live = running.filter { process in
            !process.isFinished && process.bundleID == wanted
        }
        guard !live.isEmpty else { return nil }
        let windowPIDSet = Set(restoredWindowPIDs)
        let matchingWindows = live.filter { windowPIDSet.contains($0.pid) }
        let pool = matchingWindows.isEmpty ? live : matchingWindows
        return pool.min { lhs, rhs in
            let lhsWindow = restoredWindowPIDs.firstIndex(of: lhs.pid) ?? Int.max
            let rhsWindow = restoredWindowPIDs.firstIndex(of: rhs.pid) ?? Int.max
            if lhsWindow != rhsWindow { return lhsWindow < rhsWindow }
            if lhs.isRegular != rhs.isRegular { return lhs.isRegular && !rhs.isRegular }
            if lhs.isHidden != rhs.isHidden { return !lhs.isHidden && rhs.isHidden }
            return lhs.pid < rhs.pid
        }?.pid
    }

    public static func activationOutcome(
        requestAccepted: Bool,
        requestedPID: pid_t,
        actualFrontmostPID: pid_t?
    ) -> ActivationOutcome {
        if actualFrontmostPID == requestedPID { return .acceptedAndFrontmost }
        guard requestAccepted else { return .rejected }
        return .acceptedButFrontmostMismatch
    }

    public static func shouldRetryActivation(_ outcome: ActivationOutcome) -> Bool {
        switch outcome {
        case .rejected, .acceptedButFrontmostMismatch:
            return true
        case .noProcess, .acceptedAndFrontmost:
            return false
        }
    }
}
