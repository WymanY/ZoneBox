import CoreGraphics
import Foundation

public enum WindowOrganizeLayoutKind: Equatable, Sendable {
    case fill
    case split65
    case priority60
    case grid2x2
    case focusStack
}

public struct WindowOrganizePlan: Equatable, Sendable {
    public var kind: WindowOrganizeLayoutKind
    public var layoutName: String

    public init(kind: WindowOrganizeLayoutKind, layoutName: String) {
        self.kind = kind
        self.layoutName = layoutName
    }
}

public struct WindowOrganizePlacement: Equatable, Sendable {
    public var identity: WindowIdentity
    public var targetFrameAX: CGRect

    public init(identity: WindowIdentity, targetFrameAX: CGRect) {
        self.identity = identity
        self.targetFrameAX = targetFrameAX
    }
}

public struct WindowOrganizeAttemptPlan: Equatable, Sendable {
    public var layout: Layout
    public var placements: [WindowOrganizePlacement]
    public var workAreaAX: CGRect?

    public init(layout: Layout, placements: [WindowOrganizePlacement], workAreaAX: CGRect? = nil) {
        self.layout = layout
        self.placements = placements
        self.workAreaAX = workAreaAX
    }
}

public struct WindowOrganizeMove: Equatable, Sendable {
    public var identity: WindowIdentity
    public var originalFrameAX: CGRect
    public var appliedFrameAX: CGRect

    public init(identity: WindowIdentity, originalFrameAX: CGRect, appliedFrameAX: CGRect) {
        self.identity = identity
        self.originalFrameAX = originalFrameAX
        self.appliedFrameAX = appliedFrameAX
    }
}

public enum WindowOrganizeWindowBehavior: String, Equatable, Sendable {
    case compliant
    case sizeConstrained
    case positionConstrained
    case immutable
    case unstable
}

public struct WindowOrganizeApplication: Equatable, Sendable {
    public var actualFrameAX: CGRect?
    public var behavior: WindowOrganizeWindowBehavior

    public init(actualFrameAX: CGRect?, behavior: WindowOrganizeWindowBehavior) {
        self.actualFrameAX = actualFrameAX
        self.behavior = behavior
    }
}

public struct WindowOrganizeIssue: Equatable, Sendable {
    public var identity: WindowIdentity
    public var behavior: WindowOrganizeWindowBehavior
    public var obstacleFrameAX: CGRect
    public var observedFrameAX: CGRect?

    public init(
        identity: WindowIdentity,
        behavior: WindowOrganizeWindowBehavior,
        obstacleFrameAX: CGRect,
        observedFrameAX: CGRect? = nil
    ) {
        self.identity = identity
        self.behavior = behavior
        self.obstacleFrameAX = obstacleFrameAX
        self.observedFrameAX = observedFrameAX
    }
}

public enum WindowOrganizeExecutionResult: Equatable, Sendable {
    case success(
        plan: WindowOrganizeAttemptPlan,
        moves: [WindowOrganizeMove],
        skipped: [WindowIdentity]
    )
    case noMovableWindows(skipped: [WindowIdentity])
    case failed(skipped: [WindowIdentity], rollbackFailed: [WindowIdentity])
}

public enum WindowOrganizeExecutor {
    @MainActor
    public static func execute<Handle>(
        windows: [(identity: WindowIdentity, handle: Handle)],
        makePlan: ([WindowIdentity]) -> WindowOrganizeAttemptPlan?,
        makeFallbackPlan: (([WindowIdentity], [WindowIdentity]) -> WindowOrganizeAttemptPlan?)? = nil,
        readFrame: (Handle) async -> CGRect?,
        applyFrame: (CGRect, Handle) async -> CGRect?
    ) async -> WindowOrganizeExecutionResult {
        await execute(
            windows: windows,
            makePlan: makePlan,
            makeFallbackPlan: makeFallbackPlan.map { fallback in
                { identities, issues in fallback(identities, issues.map(\.identity)) }
            },
            readFrame: readFrame,
            applyFrame: { frame, handle in
                let actual = await applyFrame(frame, handle)
                return WindowOrganizeApplication(
                    actualFrameAX: actual,
                    behavior: WindowOrganize.behavior(actual: actual, target: frame)
                )
            }
        )
    }

    /// Applies a plan transactionally. If any window rejects its target, every
    /// window in that attempt is restored to the frame captured before the first
    /// move. Size-constrained windows may keep their own size when they occupy
    /// the unique primary area; other rejections stay in place as obstacles.
    /// An optional constrained-window fallback runs once before rejected
    /// windows are removed and the remaining set is replanned around them.
    @MainActor
    public static func execute<Handle>(
        windows: [(identity: WindowIdentity, handle: Handle)],
        initialSkipped: [WindowIdentity] = [],
        makePlan: ([WindowIdentity]) -> WindowOrganizeAttemptPlan?,
        makeFallbackPlan: (([WindowIdentity], [WindowOrganizeIssue]) -> WindowOrganizeAttemptPlan?)? = nil,
        readFrame: (Handle) async -> CGRect?,
        applyFrame: (CGRect, Handle) async -> WindowOrganizeApplication,
        onIssues: (([WindowOrganizeIssue]) -> Void)? = nil
    ) async -> WindowOrganizeExecutionResult {
        var handles: [WindowIdentity: Handle] = [:]
        var orderedIdentities: [WindowIdentity] = []
        for window in windows where handles[window.identity] == nil {
            handles[window.identity] = window.handle
            orderedIdentities.append(window.identity)
        }

        var originals: [WindowIdentity: CGRect] = [:]
        var active: [WindowIdentity] = []
        var skipped = initialSkipped
        var issues: [WindowOrganizeIssue] = []
        var pendingPlan: WindowOrganizeAttemptPlan?
        var triedFallback = false
        for identity in orderedIdentities {
            guard let handle = handles[identity], let frame = await readFrame(handle) else {
                appendUnique(identity, to: &skipped)
                continue
            }
            originals[identity] = frame
            active.append(identity)
        }

        while !active.isEmpty {
            guard let plan = pendingPlan ?? makePlan(active) else {
                appendUnique(active, to: &skipped)
                return .failed(skipped: skipped, rollbackFailed: [])
            }
            pendingPlan = nil
            var placements: [WindowIdentity: WindowOrganizePlacement] = [:]
            var hasDuplicatePlacement = false
            for placement in plan.placements {
                if placements.updateValue(placement, forKey: placement.identity) != nil {
                    hasDuplicatePlacement = true
                }
            }
            guard !hasDuplicatePlacement,
                  placements.count == active.count,
                  active.allSatisfy({ placements[$0] != nil })
            else {
                appendUnique(active, to: &skipped)
                return .failed(skipped: skipped, rollbackFailed: [])
            }

            var applied: [WindowIdentity: CGRect] = [:]
            var rejected: [WindowOrganizeIssue] = []
            var attemptIssues: [WindowOrganizeIssue] = []
            let primaryFrame = WindowOrganize.uniquePrimaryFrame(
                in: plan.placements.map(\.targetFrameAX)
            )
            for identity in active {
                guard let handle = handles[identity], let placement = placements[identity] else { continue }
                let application = await applyFrame(placement.targetFrameAX, handle)
                let inPrimary = primaryFrame.map {
                    WindowOrganize.didApply(
                        placement.targetFrameAX,
                        to: $0,
                        sizeTolerance: 1,
                        originTolerance: 1
                    )
                } ?? false
                if let actual = application.actualFrameAX,
                   accepts(application, inPrimary: inPrimary)
                {
                    applied[identity] = actual
                    if application.behavior != .compliant {
                        attemptIssues.append(
                            WindowOrganizeIssue(
                                identity: identity,
                                behavior: application.behavior,
                                obstacleFrameAX: actual,
                                observedFrameAX: actual
                            )
                        )
                    }
                    continue
                }
                rejected.append(
                    WindowOrganizeIssue(
                        identity: identity,
                        behavior: application.behavior,
                        obstacleFrameAX: originals[identity] ?? placement.targetFrameAX,
                        observedFrameAX: application.actualFrameAX
                    )
                )
                break
            }

            if rejected.isEmpty {
                mergeIssues(attemptIssues, into: &issues)
                if !issues.isEmpty {
                    onIssues?(issues)
                }
                let moves = active.compactMap { identity -> WindowOrganizeMove? in
                    guard let original = originals[identity], let actual = applied[identity] else { return nil }
                    return WindowOrganizeMove(
                        identity: identity,
                        originalFrameAX: original,
                        appliedFrameAX: actual
                    )
                }
                return .success(plan: plan, moves: moves, skipped: skipped)
            }

            var rollbackFailed: [WindowIdentity] = []
            for identity in active {
                guard let handle = handles[identity], let original = originals[identity] else {
                    rollbackFailed.append(identity)
                    continue
                }
                guard let current = await readFrame(handle) else {
                    // A closed window has no state left to restore.
                    continue
                }
                if WindowOrganize.didApply(
                    current,
                    to: original,
                    sizeTolerance: 2,
                    originTolerance: 2
                ) {
                    continue
                }
                let restored = await applyFrame(original, handle)
                guard let restoredFrame = restored.actualFrameAX,
                      WindowOrganize.didApply(
                          restoredFrame,
                          to: original,
                          sizeTolerance: 2,
                          originTolerance: 2
                      )
                else {
                    rollbackFailed.append(identity)
                    continue
                }
            }
            if !rollbackFailed.isEmpty {
                appendUnique(rejected.map(\.identity), to: &skipped)
                mergeIssues(rejected, into: &issues)
                onIssues?(issues)
                return .failed(skipped: skipped, rollbackFailed: rollbackFailed)
            }

            if !triedFallback,
               let fallback = makeFallbackPlan?(active, rejected)
            {
                mergeIssues(rejected, into: &issues)
                onIssues?(issues)
                pendingPlan = fallback
                triedFallback = true
                continue
            }

            appendUnique(rejected.map(\.identity), to: &skipped)
            mergeIssues(rejected, into: &issues)
            onIssues?(issues)
            let rejectedSet = Set(rejected.map(\.identity))
            active.removeAll { rejectedSet.contains($0) }
            triedFallback = false
        }

        return .noMovableWindows(skipped: skipped)
    }

    private static func accepts(
        _ application: WindowOrganizeApplication,
        inPrimary: Bool
    ) -> Bool {
        switch application.behavior {
        case .compliant:
            true
        case .sizeConstrained:
            inPrimary
        case .positionConstrained, .immutable, .unstable:
            false
        }
    }

    private static func appendUnique(_ identity: WindowIdentity, to values: inout [WindowIdentity]) {
        if !values.contains(identity) { values.append(identity) }
    }

    private static func appendUnique(_ identities: [WindowIdentity], to values: inout [WindowIdentity]) {
        for identity in identities { appendUnique(identity, to: &values) }
    }

    private static func mergeIssues(
        _ additions: [WindowOrganizeIssue],
        into values: inout [WindowOrganizeIssue]
    ) {
        for issue in additions {
            values.removeAll { $0.identity == issue.identity }
            values.append(issue)
        }
    }
}

public enum WindowOrganize {
    /// Temporary product gate. Flip this back to `true` to restore the
    /// Organize button, menu item, and Control+Option+O shortcut.
    public static let isPubliclyAvailable = false
    public static let fillName = "Fill"
    public static let split65Name = "Split 65/35"
    public static let priority60Name = "Priority 60"
    public static let grid2x2Name = "Grid 2\u{00d7}2"
    public static let focusStackName = "Focus Stack"
    public static let cascadeStep: CGFloat = 18
    public static let maxCascadeSlots = 5

    public static func plan(forWindowCount count: Int) -> WindowOrganizePlan? {
        switch count {
        case 0: nil
        case 1: WindowOrganizePlan(kind: .fill, layoutName: fillName)
        case 2: WindowOrganizePlan(kind: .split65, layoutName: split65Name)
        case 3: WindowOrganizePlan(kind: .priority60, layoutName: priority60Name)
        case 4: WindowOrganizePlan(kind: .grid2x2, layoutName: grid2x2Name)
        default: WindowOrganizePlan(kind: .focusStack, layoutName: focusStackName)
        }
    }

    public static func fallbackPlan(forWindowCount count: Int) -> WindowOrganizePlan? {
        switch count {
        case 0, 1:
            nil
        case 2:
            WindowOrganizePlan(kind: .split65, layoutName: split65Name)
        case 3:
            WindowOrganizePlan(kind: .priority60, layoutName: priority60Name)
        default:
            WindowOrganizePlan(kind: .focusStack, layoutName: focusStackName)
        }
    }

    public static func fallbackRanking(
        candidates: [WindowIdentity],
        rejected: [WindowIdentity]
    ) -> [WindowIdentity] {
        let rejectedSet = Set(rejected)
        return rejected.filter(candidates.contains) + candidates.filter { !rejectedSet.contains($0) }
    }

    public static func layout(for plan: WindowOrganizePlan) -> Layout {
        switch plan.kind {
        case .fill: LayoutTemplates.fill()
        case .split65: LayoutTemplates.split65()
        case .priority60: LayoutTemplates.priority60()
        case .grid2x2: LayoutTemplates.grid2x2()
        case .focusStack: LayoutTemplates.focusStack()
        }
    }

    public static func rankedIdentities(
        candidates: [WindowIdentity],
        focused: WindowIdentity?
    ) -> [WindowIdentity] {
        guard !candidates.isEmpty else { return [] }
        var remaining = candidates
        var ranked: [WindowIdentity] = []
        if let focused, let index = remaining.firstIndex(of: focused) {
            ranked.append(remaining.remove(at: index))
        }
        ranked.append(contentsOf: remaining)
        return ranked
    }

    public static func assignmentCount(for plan: WindowOrganizePlan, windowCount: Int) -> Int {
        switch plan.kind {
        case .fill: min(windowCount, 1)
        case .split65: min(windowCount, 2)
        case .priority60: min(windowCount, 3)
        case .grid2x2: min(windowCount, 4)
        case .focusStack: windowCount
        }
    }

    public static func zoneNumbers(for plan: WindowOrganizePlan, windowCount: Int) -> [Int] {
        let count = assignmentCount(for: plan, windowCount: windowCount)
        switch plan.kind {
        case .focusStack:
            return (0..<count).map { $0 == 0 ? 1 : 2 }
        default:
            return Array(1...count)
        }
    }

    public static func frames(
        for plan: WindowOrganizePlan,
        windowCount: Int,
        zones: [ResolvedZone]
    ) -> [CGRect] {
        let byNumber = Dictionary(uniqueKeysWithValues: zones.map { ($0.number, $0) })
        if plan.kind == .focusStack {
            guard let main = byNumber[1]?.frameAX, let stack = byNumber[2]?.frameAX else { return [] }
            return [main] + cascadeFrames(in: stack, count: max(0, windowCount - 1))
        }
        return zoneNumbers(for: plan, windowCount: windowCount).compactMap { byNumber[$0]?.frameAX }
    }

    public static func cascadeFrames(
        in zone: CGRect,
        count: Int,
        step: CGFloat = cascadeStep,
        maxSlots: Int = maxCascadeSlots
    ) -> [CGRect] {
        guard count > 0 else { return [] }
        guard zone.width > 0, zone.height > 0 else { return Array(repeating: zone, count: count) }

        let slots = max(1, min(count, maxSlots))
        let slotDistance = CGFloat(max(slots - 1, 0))
        let totalOffsetX = min(max(0, step) * slotDistance, max(0, zone.width - 1))
        let totalOffsetY = min(max(0, step) * slotDistance, max(0, zone.height - 1))
        let stepX = slots > 1 ? totalOffsetX / slotDistance : 0
        let stepY = slots > 1 ? totalOffsetY / slotDistance : 0
        let size = CGSize(width: zone.width - totalOffsetX, height: zone.height - totalOffsetY)

        return (0..<count).map { index in
            let slot = index % slots
            return CGRect(
                x: zone.minX + CGFloat(slot) * stepX,
                y: zone.minY + CGFloat(slot) * stepY,
                width: size.width,
                height: size.height
            )
        }
    }

    /// Windows like NetEase Music accept AX position but ignore size. Organize
    /// must treat that as a failed snap so the rest of the layout can be replanned.
    public static func didApply(
        _ actual: CGRect,
        to target: CGRect,
        sizeTolerance: CGFloat = 32,
        originTolerance: CGFloat = 32
    ) -> Bool {
        abs(actual.width - target.width) <= sizeTolerance
            && abs(actual.height - target.height) <= sizeTolerance
            && abs(actual.minX - target.minX) <= originTolerance
            && abs(actual.minY - target.minY) <= originTolerance
    }

    public static func behavior(
        actual: CGRect?,
        target: CGRect,
        stable: Bool = true,
        sizeTolerance: CGFloat = 32,
        originTolerance: CGFloat = 32
    ) -> WindowOrganizeWindowBehavior {
        guard stable else { return .unstable }
        guard let actual else { return .immutable }
        let sizeMatches = abs(actual.width - target.width) <= sizeTolerance
            && abs(actual.height - target.height) <= sizeTolerance
        let originMatches = abs(actual.minX - target.minX) <= originTolerance
            && abs(actual.minY - target.minY) <= originTolerance
        switch (sizeMatches, originMatches) {
        case (true, true): return .compliant
        case (false, true): return .sizeConstrained
        case (true, false): return .positionConstrained
        case (false, false): return .immutable
        }
    }

    public static func largestAvailableRect(
        in workArea: CGRect,
        avoiding obstacles: [CGRect],
        minimumSize: CGSize = CGSize(width: 160, height: 120)
    ) -> CGRect? {
        guard workArea.width >= minimumSize.width, workArea.height >= minimumSize.height else { return nil }
        let clipped = obstacles.map { $0.intersection(workArea) }.filter { !$0.isNull && !$0.isEmpty }
        guard !clipped.isEmpty else { return workArea }

        let xs = Set([workArea.minX, workArea.maxX] + clipped.flatMap { [$0.minX, $0.maxX] }).sorted()
        let ys = Set([workArea.minY, workArea.maxY] + clipped.flatMap { [$0.minY, $0.maxY] }).sorted()
        var best: CGRect?
        for x0 in xs {
            for x1 in xs where x1 - x0 >= minimumSize.width {
                for y0 in ys {
                    for y1 in ys where y1 - y0 >= minimumSize.height {
                        let candidate = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                        guard workArea.contains(candidate),
                              !clipped.contains(where: { overlapsInterior($0, candidate) })
                        else { continue }
                        if best == nil || candidate.width * candidate.height > best!.width * best!.height {
                            best = candidate
                        }
                    }
                }
            }
        }
        return best
    }

    public static func uniquePrimaryFrame(
        in frames: [CGRect],
        sizeTolerance: CGFloat = 1,
        originTolerance: CGFloat = 1
    ) -> CGRect? {
        guard let largest = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }
        let matches = frames.filter {
            didApply($0, to: largest, sizeTolerance: sizeTolerance, originTolerance: originTolerance)
        }
        return matches.count == 1 ? largest : nil
    }

    private static func overlapsInterior(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = lhs.intersection(rhs)
        return !overlap.isNull && overlap.width > 0 && overlap.height > 0
    }

}
