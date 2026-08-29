import XCTest
@testable import ZoneBoxCore

final class WindowOrganizeTests: XCTestCase {
    private let work = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testPlanMatchesWindowCount() {
        XCTAssertNil(WindowOrganize.plan(forWindowCount: 0))
        XCTAssertEqual(WindowOrganize.plan(forWindowCount: 1)?.kind, .fill)
        XCTAssertEqual(WindowOrganize.plan(forWindowCount: 2)?.kind, .split65)
        XCTAssertEqual(WindowOrganize.plan(forWindowCount: 3)?.kind, .priority60)
        XCTAssertEqual(WindowOrganize.plan(forWindowCount: 4)?.kind, .grid2x2)
        XCTAssertEqual(WindowOrganize.plan(forWindowCount: 5)?.kind, .focusStack)
        XCTAssertEqual(WindowOrganize.plan(forWindowCount: 9)?.layoutName, WindowOrganize.focusStackName)
    }

    func testFourWindowFallbackUsesFocusStackAndPromotesRejectedWindow() throws {
        let identities = makeIdentities(4)
        let fallback = try XCTUnwrap(WindowOrganize.fallbackPlan(forWindowCount: identities.count))
        XCTAssertEqual(fallback.kind, .focusStack)
        XCTAssertEqual(
            WindowOrganize.fallbackRanking(candidates: identities, rejected: [identities[2]]),
            [identities[2], identities[0], identities[1], identities[3]]
        )
    }

    func testFillCoversTheWorkArea() throws {
        let plan = try XCTUnwrap(WindowOrganize.plan(forWindowCount: 1))
        let zones = try resolveLayout(WindowOrganize.layout(for: plan), workAreaAX: work, gutter: 0)
        XCTAssertEqual(zones.count, 1)
        XCTAssertEqual(zones[0].frameAX, work)
    }

    func testSplitUsesSixtyFiveThirtyFiveColumns() throws {
        let plan = try XCTUnwrap(WindowOrganize.plan(forWindowCount: 2))
        let layout = WindowOrganize.layout(for: plan)
        XCTAssertEqual(layout.grid?.columnWeights, [6_500, 3_500])
        let zones = try resolveLayout(layout, workAreaAX: work, gutter: 0)
        XCTAssertEqual(zones.map(\.number), [1, 2])
        XCTAssertEqual(zones[0].frameAX, CGRect(x: 0, y: 0, width: 650, height: 800))
        XCTAssertEqual(zones[1].frameAX, CGRect(x: 650, y: 0, width: 350, height: 800))
    }

    func testPrioritySixtyKeepsMainColumnAndStackedRight() throws {
        let plan = try XCTUnwrap(WindowOrganize.plan(forWindowCount: 3))
        let layout = WindowOrganize.layout(for: plan)
        XCTAssertEqual(layout.grid?.columnWeights, [6_000, 4_000])
        XCTAssertEqual(layout.grid?.cellMap, [[0, 1], [0, 2]])
        let zones = try resolveLayout(layout, workAreaAX: work, gutter: 0)
        let byNumber = Dictionary(uniqueKeysWithValues: zones.map { ($0.number, $0.frameAX) })
        XCTAssertEqual(byNumber[1], CGRect(x: 0, y: 0, width: 600, height: 800))
        XCTAssertEqual(byNumber[2], CGRect(x: 600, y: 0, width: 400, height: 400))
        XCTAssertEqual(byNumber[3], CGRect(x: 600, y: 400, width: 400, height: 400))
    }

    func testFourWindowsReuseGrid2x2() throws {
        let plan = try XCTUnwrap(WindowOrganize.plan(forWindowCount: 4))
        XCTAssertEqual(plan.layoutName, "Grid 2×2")
        let layout = WindowOrganize.layout(for: plan)
        XCTAssertEqual(layout.name, LayoutTemplates.grid2x2().name)
        XCTAssertEqual(try resolveLayout(layout, workAreaAX: work, gutter: 0).count, 4)
    }

    func testFocusStackUsesEqualSizeBoundedCascadeFrames() throws {
        let plan = try XCTUnwrap(WindowOrganize.plan(forWindowCount: 5))
        let zones = try resolveLayout(WindowOrganize.layout(for: plan), workAreaAX: work, gutter: 0)
        XCTAssertEqual(WindowOrganize.zoneNumbers(for: plan, windowCount: 5), [1, 2, 2, 2, 2])

        let frames = WindowOrganize.frames(for: plan, windowCount: 5, zones: zones)
        let stack = try XCTUnwrap(zones.first(where: { $0.number == 2 })?.frameAX)
        let cascaded = Array(frames.dropFirst())
        XCTAssertEqual(frames.first, CGRect(x: 0, y: 0, width: 600, height: 800))
        XCTAssertEqual(cascaded.count, 4)
        XCTAssertTrue(cascaded.dropFirst().allSatisfy { $0.size == cascaded.first?.size })
        XCTAssertEqual(cascaded.first?.origin, stack.origin)
        XCTAssertEqual(cascaded.last?.maxX, stack.maxX)
        XCTAssertEqual(cascaded.last?.maxY, stack.maxY)
        XCTAssertTrue(cascaded.allSatisfy(stack.contains))
    }

    func testCascadeUsesFiniteSlotsInsteadOfShrinkingTowardOnePixel() {
        let zone = CGRect(x: 10, y: 20, width: 400, height: 300)
        let frames = WindowOrganize.cascadeFrames(in: zone, count: 40)
        XCTAssertEqual(frames.count, 40)
        XCTAssertTrue(frames.dropFirst().allSatisfy { $0.size == frames.first?.size })
        XCTAssertTrue(frames.allSatisfy(zone.contains))
        XCTAssertGreaterThan(frames[0].width, 300)
        XCTAssertGreaterThan(frames[0].height, 200)
        XCTAssertEqual(frames[0], frames[WindowOrganize.maxCascadeSlots])
    }

    func testRankingPutsFocusedWindowFirstAndKeepsZOrder() {
        let a = WindowIdentity(pid: 1, windowNumber: 10)
        let b = WindowIdentity(pid: 2, windowNumber: 20)
        let c = WindowIdentity(pid: 3, windowNumber: 30)
        XCTAssertEqual(WindowOrganize.rankedIdentities(candidates: [a, b, c], focused: b), [b, a, c])
        XCTAssertEqual(WindowOrganize.rankedIdentities(candidates: [a, b, c], focused: nil), [a, b, c])
        XCTAssertEqual(
            WindowOrganize.rankedIdentities(
                candidates: [a, b, c],
                focused: WindowIdentity(pid: 9, windowNumber: 90)
            ),
            [a, b, c]
        )
    }

    func testDidApplyRejectsSizeLockedWindow() {
        let target = CGRect(x: 16, y: 47, width: 688, height: 403)
        let movedOnly = CGRect(x: 16, y: 47, width: 1056, height: 752)
        XCTAssertFalse(WindowOrganize.didApply(movedOnly, to: target))
        XCTAssertTrue(WindowOrganize.didApply(target, to: target))
        XCTAssertTrue(
            WindowOrganize.didApply(
                CGRect(x: 18, y: 49, width: 690, height: 405),
                to: target
            )
        )
    }

    func testBehaviorClassification() {
        let target = CGRect(x: 16, y: 47, width: 688, height: 403)
        XCTAssertEqual(WindowOrganize.behavior(actual: target, target: target), .compliant)
        XCTAssertEqual(
            WindowOrganize.behavior(actual: CGRect(x: 16, y: 47, width: 320, height: 240), target: target),
            .sizeConstrained
        )
        XCTAssertEqual(
            WindowOrganize.behavior(actual: CGRect(x: 80, y: 90, width: 688, height: 403), target: target),
            .positionConstrained
        )
        XCTAssertEqual(
            WindowOrganize.behavior(actual: CGRect(x: 80, y: 90, width: 320, height: 240), target: target),
            .immutable
        )
        XCTAssertEqual(WindowOrganize.behavior(actual: nil, target: target), .immutable)
        XCTAssertEqual(WindowOrganize.behavior(actual: target, target: target, stable: false), .unstable)
    }

    func testUniquePrimaryFrameRequiresASingleLargestArea() {
        let primary = CGRect(x: 0, y: 0, width: 650, height: 800)
        let side = CGRect(x: 650, y: 0, width: 350, height: 800)
        XCTAssertEqual(WindowOrganize.uniquePrimaryFrame(in: [primary, side]), primary)
        XCTAssertNil(WindowOrganize.uniquePrimaryFrame(in: [primary, primary]))
        XCTAssertNil(WindowOrganize.uniquePrimaryFrame(in: []))
    }

    func testLargestAvailableRectKeepsTheBiggestGapAroundObstacles() {
        let obstacle = CGRect(x: 0, y: 0, width: 280, height: 800)
        XCTAssertEqual(
            WindowOrganize.largestAvailableRect(in: work, avoiding: [obstacle]),
            CGRect(x: 280, y: 0, width: 720, height: 800)
        )
        let floating = CGRect(x: 200, y: 200, width: 200, height: 200)
        let available = WindowOrganize.largestAvailableRect(in: work, avoiding: [floating])
        XCTAssertEqual(available, CGRect(x: 400, y: 0, width: 600, height: 800))
    }

    @MainActor
    func testExecutorRollsBackWholeAttemptBeforeReplanning() async throws {
        let identities = makeIdentities(3)
        let originals = Dictionary(uniqueKeysWithValues: identities.enumerated().map {
            ($0.element, CGRect(x: CGFloat($0.offset * 200), y: 20, width: 160, height: 120))
        })
        let mover = FakeMover(frames: originals, locked: [identities[2]])

        let result = await WindowOrganizeExecutor.execute(
            windows: identities.map { ($0, $0) },
            makePlan: { self.attemptPlan(for: $0, baseX: $0.count == 3 ? 1_000 : 2_000) },
            readFrame: { mover.frame(of: $0) },
            applyFrame: { mover.apply($0, to: $1) }
        )

        guard case .success(let plan, let moves, let skipped) = result else {
            return XCTFail("expected a successful replan, got \(result)")
        }
        XCTAssertEqual(plan.placements.count, 2)
        XCTAssertEqual(skipped, [identities[2]])
        XCTAssertEqual(moves.map(\.identity), Array(identities.prefix(2)))
        XCTAssertEqual(moves.map(\.originalFrameAX), Array(identities.prefix(2)).compactMap { originals[$0] })
        XCTAssertEqual(mover.frames[identities[2]], originals[identities[2]])
        XCTAssertEqual(mover.frames[identities[0]]?.minX, 2_000)
        XCTAssertEqual(mover.frames[identities[1]]?.minX, 2_200)

        let firstRetryCall = try XCTUnwrap(mover.calls.firstIndex { $0.frame.minX == 2_000 })
        let rollbackCalls = mover.calls[..<firstRetryCall].filter { call in
            originals[call.identity] == call.frame
        }
        XCTAssertEqual(Set(rollbackCalls.map(\.identity)), Set(identities.prefix(2)))
    }

    @MainActor
    func testExecutorTriesFallbackBeforeSkippingSizeLockedWindow() async throws {
        let identities = makeIdentities(4)
        let originals = Dictionary(uniqueKeysWithValues: identities.enumerated().map {
            ($0.element, CGRect(x: CGFloat($0.offset * 200), y: 20, width: 160, height: 120))
        })
        let constrained = identities[2]
        let mover = FakeMover(frames: originals)
        var usedFallback = false

        let result = await WindowOrganizeExecutor.execute(
            windows: identities.map { ($0, $0) },
            makePlan: { self.attemptPlan(for: $0, baseX: 1_000) },
            makeFallbackPlan: { active, rejected in
                XCTAssertEqual(active, identities)
                XCTAssertEqual(rejected, [constrained])
                usedFallback = true
                return self.attemptPlan(
                    for: WindowOrganize.fallbackRanking(candidates: active, rejected: rejected),
                    baseX: 2_000
                )
            },
            readFrame: { mover.frame(of: $0) },
            applyFrame: { frame, identity in
                if identity == constrained, frame.minX < 2_000 {
                    mover.calls.append(FakeMover.Call(identity: identity, frame: frame))
                    return mover.frames[identity]
                }
                return mover.apply(frame, to: identity)
            }
        )

        guard case .success(let plan, let moves, let skipped) = result else {
            return XCTFail("expected fallback success, got \(result)")
        }
        XCTAssertTrue(usedFallback)
        XCTAssertEqual(plan.placements.count, 4)
        XCTAssertEqual(Set(moves.map(\.identity)), Set(identities))
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(mover.frames[constrained]?.minX, 2_000)

        let fallbackStart = try XCTUnwrap(mover.calls.firstIndex { $0.frame.minX >= 2_000 })
        let rollbackCalls = mover.calls[..<fallbackStart].filter { originals[$0.identity] == $0.frame }
        XCTAssertEqual(Set(rollbackCalls.map(\.identity)), Set(identities.prefix(2)))
        XCTAssertFalse(mover.calls[..<fallbackStart].contains { $0.identity == identities[3] })
    }

    @MainActor
    func testExecutorStopsWhenRollbackCannotRestoreEveryWindow() async {
        let identities = makeIdentities(2)
        let originals = [
            identities[0]: CGRect(x: 0, y: 0, width: 200, height: 160),
            identities[1]: CGRect(x: 300, y: 0, width: 200, height: 160),
        ]
        let mover = FakeMover(
            frames: originals,
            locked: [identities[1]],
            rollbackFailures: [identities[0]]
        )

        let result = await WindowOrganizeExecutor.execute(
            windows: identities.map { ($0, $0) },
            makePlan: { self.attemptPlan(for: $0, baseX: 1_000) },
            readFrame: { mover.frame(of: $0) },
            applyFrame: { mover.apply($0, to: $1) }
        )

        guard case .failed(let skipped, let rollbackFailed) = result else {
            return XCTFail("expected rollback failure, got \(result)")
        }
        XCTAssertEqual(skipped, [identities[1]])
        XCTAssertEqual(rollbackFailed, [identities[0]])
        XCTAssertEqual(mover.frames[identities[0]]?.minX, 1_000)
    }

    @MainActor
    func testExecutorSkipsUnreadableWindowsWithoutApplyingAPlan() async {
        let identity = makeIdentities(1)[0]
        let mover = FakeMover(frames: [:])
        var planned = false

        let result = await WindowOrganizeExecutor.execute(
            windows: [(identity, identity)],
            makePlan: {
                planned = true
                return self.attemptPlan(for: $0, baseX: 1_000)
            },
            readFrame: { mover.frame(of: $0) },
            applyFrame: { mover.apply($0, to: $1) }
        )

        XCTAssertEqual(result, .noMovableWindows(skipped: [identity]))
        XCTAssertFalse(planned)
        XCTAssertTrue(mover.calls.isEmpty)
    }

    @MainActor
    func testExecutorTreatsAClosedWindowAsSkippedAndReplansTheRest() async {
        let identities = makeIdentities(2)
        let originals = [
            identities[0]: CGRect(x: 0, y: 0, width: 200, height: 160),
            identities[1]: CGRect(x: 300, y: 0, width: 200, height: 160),
        ]
        let mover = FakeMover(frames: originals, disappearsOnApply: [identities[1]])

        let result = await WindowOrganizeExecutor.execute(
            windows: identities.map { ($0, $0) },
            makePlan: { self.attemptPlan(for: $0, baseX: $0.count == 2 ? 1_000 : 2_000) },
            readFrame: { mover.frame(of: $0) },
            applyFrame: { mover.apply($0, to: $1) }
        )

        guard case .success(_, let moves, let skipped) = result else {
            return XCTFail("expected remaining window to be replanned, got \(result)")
        }
        XCTAssertEqual(moves.map(\.identity), [identities[0]])
        XCTAssertEqual(skipped, [identities[1]])
        XCTAssertEqual(mover.frames[identities[0]]?.minX, 2_000)
        XCTAssertNil(mover.frames[identities[1]])
    }

    @MainActor
    func testExecutorRejectsDuplicatePlacementsWithoutMovingWindows() async {
        let identities = makeIdentities(2)
        let originals = [
            identities[0]: CGRect(x: 0, y: 0, width: 200, height: 160),
            identities[1]: CGRect(x: 300, y: 0, width: 200, height: 160),
        ]
        let mover = FakeMover(frames: originals)
        let duplicate = WindowOrganizePlacement(
            identity: identities[0],
            targetFrameAX: CGRect(x: 1_000, y: 0, width: 200, height: 160)
        )

        let result = await WindowOrganizeExecutor.execute(
            windows: identities.map { ($0, $0) },
            makePlan: { _ in
                WindowOrganizeAttemptPlan(layout: LayoutTemplates.fill(), placements: [duplicate, duplicate])
            },
            readFrame: { mover.frame(of: $0) },
            applyFrame: { mover.apply($0, to: $1) }
        )

        XCTAssertEqual(result, .failed(skipped: identities, rollbackFailed: []))
        XCTAssertEqual(mover.frames, originals)
        XCTAssertTrue(mover.calls.isEmpty)
    }

    @MainActor
    func testExecutorKeepsASizeConstrainedWindowInThePrimaryArea() async throws {
        let identities = makeIdentities(2)
        let originals = [
            identities[0]: CGRect(x: 20, y: 20, width: 320, height: 240),
            identities[1]: CGRect(x: 360, y: 20, width: 180, height: 140),
        ]
        let mover = FakeMover(frames: originals, sizeLocked: [identities[0]])
        var issues: [WindowOrganizeIssue] = []

        let result = await WindowOrganizeExecutor.execute(
            windows: identities.map { ($0, $0) },
            makePlan: { self.primaryAttemptPlan(for: $0, baseX: 1_000) },
            readFrame: { mover.frame(of: $0) },
            applyFrame: { frame, identity in
                let actual = mover.apply(frame, to: identity)
                return WindowOrganizeApplication(
                    actualFrameAX: actual,
                    behavior: WindowOrganize.behavior(actual: actual, target: frame)
                )
            },
            onIssues: { issues = $0 }
        )

        guard case .success(_, let moves, let skipped) = result else {
            return XCTFail("expected a successful primary placement, got \(result)")
        }
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(Set(moves.map(\.identity)), Set(identities))
        XCTAssertEqual(mover.frames[identities[0]]?.origin, CGPoint(x: 1_000, y: 100))
        XCTAssertEqual(mover.frames[identities[0]]?.size, CGSize(width: 320, height: 240))
        XCTAssertEqual(mover.frames[identities[1]]?.origin, CGPoint(x: 1_400, y: 100))
        XCTAssertEqual(issues.map(\.identity), [identities[0]])
        XCTAssertEqual(issues.map(\.behavior), [.sizeConstrained])
        XCTAssertFalse(mover.calls.contains { $0.identity == identities[0] && $0.frame == originals[identities[0]] })
    }

    @MainActor
    func testExecutorStopsBeforeLaterWindowsAndReportsTheFirstRejection() async {
        let identities = makeIdentities(3)
        let originals = Dictionary(uniqueKeysWithValues: identities.enumerated().map {
            ($0.element, CGRect(x: CGFloat($0.offset * 200), y: 20, width: 160, height: 120))
        })
        let mover = FakeMover(frames: originals, locked: [identities[1]])
        var reported: [[WindowOrganizeIssue]] = []
        var planned: [[WindowIdentity]] = []

        let result = await WindowOrganizeExecutor.execute(
            windows: identities.map { ($0, $0) },
            makePlan: {
                planned.append($0)
                return self.attemptPlan(for: $0, baseX: $0.count == 3 ? 1_000 : 2_000)
            },
            readFrame: { mover.frame(of: $0) },
            applyFrame: { frame, identity in
                let actual = mover.apply(frame, to: identity)
                return WindowOrganizeApplication(
                    actualFrameAX: actual,
                    behavior: WindowOrganize.behavior(actual: actual, target: frame)
                )
            },
            onIssues: { reported.append($0) }
        )

        guard case .success(_, let moves, let skipped) = result else {
            return XCTFail("expected remaining windows to be replanned, got \(result)")
        }
        XCTAssertEqual(skipped, [identities[1]])
        XCTAssertEqual(moves.map(\.identity), [identities[0], identities[2]])
        XCTAssertEqual(planned, [identities, [identities[0], identities[2]]])
        XCTAssertEqual(reported.map { $0.map(\.identity) }, [[identities[1]], [identities[1]]])
        XCTAssertEqual(Set(reported.flatMap { $0.map(\.behavior) }), [.positionConstrained])
        XCTAssertFalse(mover.calls.contains { $0.identity == identities[2] && $0.frame.minX == 1_400 })
        XCTAssertEqual(mover.frames[identities[1]], originals[identities[1]])
    }

    private func makeIdentities(_ count: Int) -> [WindowIdentity] {
        (0..<count).map { WindowIdentity(pid: pid_t($0 + 1), windowNumber: UInt32($0 + 10)) }
    }

    private func attemptPlan(for identities: [WindowIdentity], baseX: CGFloat) -> WindowOrganizeAttemptPlan {
        WindowOrganizeAttemptPlan(
            layout: LayoutTemplates.fill(),
            placements: identities.enumerated().map {
                WindowOrganizePlacement(
                    identity: $0.element,
                    targetFrameAX: CGRect(
                        x: baseX + CGFloat($0.offset * 200),
                        y: 100,
                        width: 180,
                        height: 140
                    )
                )
            }
        )
    }

    private func primaryAttemptPlan(for identities: [WindowIdentity], baseX: CGFloat) -> WindowOrganizeAttemptPlan {
        WindowOrganizeAttemptPlan(
            layout: LayoutTemplates.fill(),
            placements: identities.enumerated().map { item in
                WindowOrganizePlacement(
                    identity: item.element,
                    targetFrameAX: CGRect(
                        x: baseX + CGFloat(item.offset * 400),
                        y: 100,
                        width: item.offset == 0 ? 360 : 180,
                        height: item.offset == 0 ? 280 : 140
                    )
                )
            }
        )
    }
}

@MainActor
private final class FakeMover {
    struct Call: Equatable {
        var identity: WindowIdentity
        var frame: CGRect
    }

    let originals: [WindowIdentity: CGRect]
    var frames: [WindowIdentity: CGRect]
    var locked: Set<WindowIdentity>
    var sizeLocked: Set<WindowIdentity>
    var rollbackFailures: Set<WindowIdentity>
    var disappearsOnApply: Set<WindowIdentity>
    var calls: [Call] = []

    init(
        frames: [WindowIdentity: CGRect],
        locked: Set<WindowIdentity> = [],
        sizeLocked: Set<WindowIdentity> = [],
        rollbackFailures: Set<WindowIdentity> = [],
        disappearsOnApply: Set<WindowIdentity> = []
    ) {
        originals = frames
        self.frames = frames
        self.locked = locked
        self.sizeLocked = sizeLocked
        self.rollbackFailures = rollbackFailures
        self.disappearsOnApply = disappearsOnApply
    }

    func frame(of identity: WindowIdentity) -> CGRect? {
        frames[identity]
    }

    func apply(_ frame: CGRect, to identity: WindowIdentity) -> CGRect? {
        calls.append(Call(identity: identity, frame: frame))
        let original = originals[identity]
        let isRollback = original == frame
        if rollbackFailures.contains(identity), isRollback, frames[identity] != original {
            return frames[identity]
        }
        if locked.contains(identity), !isRollback {
            return frames[identity]
        }
        if sizeLocked.contains(identity), !isRollback {
            let current = frames[identity] ?? frame
            let moved = CGRect(x: frame.minX, y: frame.minY, width: current.width, height: current.height)
            frames[identity] = moved
            return moved
        }
        if disappearsOnApply.contains(identity), !isRollback {
            frames[identity] = nil
            return nil
        }
        frames[identity] = frame
        return frame
    }
}
