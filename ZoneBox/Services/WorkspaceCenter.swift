import AppKit
import ZoneBoxCore

@MainActor
final class WorkspaceCenter {
    unowned var runtime: AppRuntime!

    private struct WindowCandidate {
        var sample: ProfileCapture.WindowSample
        var handle: AXWindow
        var isMinimized = false
        var isHiddenApp = false
    }

    private struct CandidateSet {
        var candidates: [WindowCandidate] = []
        /// Running saved apps whose standard windows exist but cannot be
        /// reached from this Space (another Space or native full screen).
        /// Reopening them would yank the user to that Space, so restore only
        /// reports them.
        var unreachableBundleIDs: Set<String> = []
    }

    /// Cold launches of heavy apps (editors, Electron shells) routinely take
    /// longer than 15s before their first standard window appears.
    static let launchTimeout: TimeInterval = 30

    private struct PendingPlacement: Identifiable {
        var id = UUID()
        var bundleID: String
        var zoneID: UUID
        var zoneNumber: Int
        var layoutID: Layout.ID
        var displayID: DisplayIdentity.ID
        var expiresAt: Date
    }

    private struct ObservedWindow {
        var pendingID: UUID?
        var target: PendingPlacement
        var lastFrame: CGRect
        var stableSamples: Int
        var rejectedAttempts = 0
    }

    /// A freshly launched window may still be resizing itself when the first
    /// placement lands. Retry a few polls before giving the target up.
    private static let maxRejectedAttempts = 3

    private var pending: [PendingPlacement] = []
    private var observed: [WindowIdentity: ObservedWindow] = [:]
    private var baseline: Set<WindowIdentity> = []
    private var censusTask: Task<Void, Never>?
    private var paused = false

    func start() {
        resetBaseline()
        updateCensus()
    }

    func stop() {
        censusTask?.cancel()
        censusTask = nil
        pending.removeAll()
        observed.removeAll()
        baseline.removeAll()
    }

    func pause() {
        paused = true
        censusTask?.cancel()
        censusTask = nil
    }

    func resume() {
        paused = false
        resetBaseline()
        updateCensus()
    }

    func displaysDidChange() {
        observed.removeAll()
        resetBaseline()
        updateCensus()
    }

    func applicationDidTerminate(pid: pid_t, bundleID: String?) {
        observed = observed.filter { $0.key.pid != pid }
        if let bundleID {
            pending.removeAll { $0.bundleID == bundleID }
        }
        updateCensus()
    }

    func capture(name: String, replacing profileID: WorkspaceProfile.ID? = nil) {
        Task { @MainActor [weak self] in
            await self?.captureNow(name: name, replacing: profileID)
        }
    }

    func suggestedCaptureName() -> String {
        let fallback = L10n.text(.workspaceDefaultName)
        let samples = collectVisibleSamples()
        let names = captureSections(from: samples).flatMap { section in
            section.rules.map { rule -> String in
                if let sample = samples.first(where: { $0.identity.bundleID == rule.bundleID }) {
                    return applicationName(for: sample.identity)
                }
                return applicationName(forBundleID: rule.bundleID)
            }
        }
        return WorkspaceProfile.suggestedName(appNames: names, fallback: fallback)
    }

    func apply(profileID: WorkspaceProfile.ID) {
        guard let profile = runtime.document.profiles.first(where: { $0.id == profileID }) else {
            NSSound.beep()
            return
        }
        guard runtime.beginWindowTransaction() else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { runtime.finishWindowTransaction() }
            await applyNow(profile)
        }
    }

    func applyCurrentOrMostRecent() {
        let profile = runtime.document.activeProfileID
            .flatMap { id in runtime.document.profiles.first(where: { $0.id == id }) }
            ?? runtime.document.profiles.max(by: { $0.updatedAt < $1.updatedAt })
        guard let profile else {
            NSSound.beep()
            return
        }
        apply(profileID: profile.id)
    }

    func updateProfile(_ profile: WorkspaceProfile) {
        var copy = profile
        copy.updatedAt = Date()
        runtime.document.upsertProfile(copy)
        runtime.persist()
        runtime.menuBar?.reloadMenu()
        runtime.refreshWorkspaceSettings()
        updateCensus()
    }

    func deleteProfile(id: WorkspaceProfile.ID) {
        guard runtime.document.deleteProfile(id: id) else { return }
        pending.removeAll()
        observed.removeAll()
        runtime.persist()
        runtime.menuBar?.reloadMenu()
        runtime.refreshWorkspaceSettings()
        updateCensus()
    }

    private func captureNow(name: String, replacing profileID: WorkspaceProfile.ID?) async {
        guard !runtime.isEditorOpen, !runtime.isOrganizingWindows, !runtime.engine.isSessionActive else {
            NSSound.beep()
            return
        }
        guard runtime.trust.isTrusted() else {
            runtime.openAccessibility()
            return
        }
        let candidates = await collectCandidates(visibleOnly: true).candidates
        let sections = captureSections(from: candidates.map(\.sample))
        Log.workspace.info(
            "Capture visibleWindows=\(candidates.count, privacy: .public) sections=\(sections.count, privacy: .public) rules=\(sections.reduce(0) { $0 + $1.rules.count }, privacy: .public)"
        )
        for section in sections {
            for rule in section.rules {
                Log.workspace.info(
                    "Capture rule display=\(section.space.displayID.uuidString.prefix(8), privacy: .public) zone=\(rule.zoneNumber, privacy: .public) app=\(rule.bundleID, privacy: .public)"
                )
            }
        }
        guard !sections.isEmpty else {
            NSSound.beep()
            showFeedback(
                title: L10n.text(.workspaceCaptureEmptyTitle),
                detail: L10n.text(.workspaceCaptureEmptyDetail),
                error: true
            )
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let desiredName = trimmed.isEmpty ? L10n.text(.workspaceDefaultName) : trimmed
        let now = Date()
        let existing = profileID.flatMap { id in runtime.document.profiles.first(where: { $0.id == id }) }
        let profile = WorkspaceProfile(
            id: existing?.id ?? UUID(),
            name: LayoutEditTransaction.uniqueName(
                base: desiredName,
                existingNames: runtime.document.profiles.filter { $0.id != profileID }.map(\.name)
            ),
            sections: sections,
            launchMissingApps: existing?.launchMissingApps ?? true,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        runtime.document.upsertProfile(profile)
        runtime.document.activeProfileID = profile.id
        runtime.persist()
        runtime.menuBar?.reloadMenu()
        runtime.refreshWorkspaceSettings()
        resetBaseline()
        updateCensus()
        showFeedback(
            title: L10n.text(existing == nil ? .workspaceCapturedTitle : .workspaceUpdatedTitle),
            detail: String(format: L10n.text(.workspaceCapturedDetail), profile.name, profile.applicationCount),
            error: false
        )
    }

    private func applyNow(_ profile: WorkspaceProfile) async {
        if runtime.isEditorOpen || runtime.engine.isSessionActive {
            NSSound.beep()
            return
        }
        guard runtime.trust.isTrusted() else {
            runtime.openAccessibility()
            return
        }

        var profile = profile
        let repairedSections = profile.sections.map { section in
            var section = section
            section.rules = ProfileCapture.frontmostRulesPerZone(section.rules)
            return section
        }
        if repairedSections != profile.sections {
            profile.sections = repairedSections
            runtime.document.upsertProfile(profile)
            runtime.persist()
        }

        pending.removeAll()
        observed.removeAll()
        var zonesBySection: [DisplayIdentity.ID: [ResolvedZone]] = [:]
        for section in profile.sections {
            guard let area = runtime.displays.workAreas.first(where: { $0.display.id == section.space.displayID }),
                  let layout = runtime.document.layouts.first(where: { $0.id == section.layoutID })
            else { continue }
            zonesBySection[section.space.displayID] = runtime.resolvedZones(layout: layout, area: area)
        }
        let restorableBundleIDs = ProfilePlan.restorableBundleIDs(
            profile: profile,
            availableDisplayIDs: Set(zonesBySection.keys)
        )
        let collected = await collectCandidates(restorableBundleIDs: restorableBundleIDs)
        let candidates = collected.candidates
        let handles = Dictionary(uniqueKeysWithValues: candidates.map { ($0.sample.identity, $0.handle) })
        let candidatesByIdentity = Dictionary(uniqueKeysWithValues: candidates.map { ($0.sample.identity, $0) })
        let outcome = ProfilePlan.make(
            profile: profile,
            zonesBySection: zonesBySection,
            candidates: candidates.map(\.sample)
        )
        Log.workspace.info(
            "Apply profile=\(profile.name, privacy: .public) candidates=\(candidates.count, privacy: .public) placements=\(outcome.sections.reduce(0) { $0 + $1.placements.count }, privacy: .public) missing=\(outcome.missingBundleIDs.joined(separator: ","), privacy: .public) unreachable=\(collected.unreachableBundleIDs.sorted().joined(separator: ","), privacy: .public) stale=\(outcome.staleRules.count, privacy: .public) skippedDisplays=\(outcome.skippedDisplayIDs.count, privacy: .public)"
        )

        await revealPlannedWindows(outcome: outcome, candidates: candidatesByIdentity)

        var issues: [WindowOrganizeIssue] = []
        var skippedWindows: [WindowIdentity] = []
        var restoredWindows: [AXWindow] = []
        var movedWindows: [WindowIdentity] = []

        for sectionPlan in outcome.sections {
            guard runtime.displays.isActive(displayID: sectionPlan.displayID),
                  let area = runtime.displays.workAreas.first(where: { $0.display.id == sectionPlan.displayID }),
                  let layout = runtime.document.layouts.first(where: { $0.id == sectionPlan.layoutID })
            else { continue }
            let initialSkipped = sectionPlan.placements.map(\.identity).filter { handles[$0] == nil }
            let entries = sectionPlan.placements.compactMap { placement -> (identity: WindowIdentity, handle: AXWindow)? in
                return handles[placement.identity].map { (placement.identity, $0) }
            }
            let placements = Dictionary(uniqueKeysWithValues: sectionPlan.placements.map { ($0.identity, $0) })
            let workAX = CoordinateConverter.axRect(
                fromAppKit: area.visibleFrameAppKit,
                primaryFlipHeight: runtime.displays.primaryFlipHeight
            )
            runtime.document.assign(layoutID: layout.id, to: sectionPlan.displayID)
            runtime.document.markLayoutUsed(layout.id)
            let result = await WindowOrganizeExecutor.execute(
                windows: entries,
                initialSkipped: initialSkipped,
                acceptance: .placement,
                makePlan: { identities in
                    let filtered = identities.compactMap { placements[$0] }
                    guard filtered.count == identities.count else { return nil }
                    return WindowOrganizeAttemptPlan(layout: layout, placements: filtered, workAreaAX: workAX)
                },
                readFrame: { [weak self] window in await self?.runtime.ax.frame(of: window) },
                applyFrame: { [weak self] frame, window in
                    guard let self else {
                        return WindowOrganizeApplication(actualFrameAX: nil, behavior: .immutable)
                    }
                    return await self.runtime.applyWorkspaceFrame(frame, to: window)
                },
                onIssues: { observedIssues in
                    for issue in observedIssues {
                        issues.removeAll { $0.identity == issue.identity }
                        issues.append(issue)
                        self.runtime.cacheOrganizeBehavior(issue.behavior, for: issue.identity)
                    }
                }
            )
            switch result {
            case .success(_, let moves, let skipped):
                Log.workspace.info(
                    "Apply section display=\(sectionPlan.displayID.uuidString.prefix(8), privacy: .public) moved=\(moves.count, privacy: .public) skipped=\(skipped.count, privacy: .public)"
                )
                appendUnique(moves.map { $0.identity }, to: &movedWindows)
                appendUnique(skipped, to: &skippedWindows)
                for move in moves {
                    runtime.catalog.record(
                        UnsnapRecord(
                            identity: move.identity,
                            originalFrameAX: move.originalFrameAX,
                            snappedFrameAX: move.appliedFrameAX,
                            zoneIDs: sectionPlan.zoneIDByIdentity[move.identity].map { [$0] } ?? []
                        ),
                        displayID: sectionPlan.displayID
                    )
                    if let window = handles[move.identity] {
                        restoredWindows.append(window)
                    }
                }
                runtime.flashWorkspaceZones(area: area, layout: layout)
            case .noMovableWindows(let skipped):
                Log.workspace.info(
                    "Apply section display=\(sectionPlan.displayID.uuidString.prefix(8), privacy: .public) no movable windows skipped=\(skipped.count, privacy: .public)"
                )
                appendUnique(skipped, to: &skippedWindows)
            case .failed(let skipped, let rollbackFailed):
                Log.workspace.error(
                    "Apply section display=\(sectionPlan.displayID.uuidString.prefix(8), privacy: .public) failed skipped=\(skipped.count, privacy: .public) rollbackFailed=\(rollbackFailed.count, privacy: .public)"
                )
                appendUnique(skipped, to: &skippedWindows)
                appendUnique(rollbackFailed, to: &skippedWindows)
            }
        }
        for issue in issues {
            Log.workspace.info(
                "Apply issue app=\(issue.identity.bundleID ?? "?", privacy: .public) window=\(issue.identity.windowNumber, privacy: .public) behavior=\(issue.behavior.rawValue, privacy: .public)"
            )
        }

        // Frame changes do not affect WindowServer ordering. Raise every
        // restored workspace window after placement so unrelated windows left
        // untouched by the profile cannot continue covering the result. AXRaise
        // changes stacking without activating the application or stealing focus.
        for window in restoredWindows {
            _ = await runtime.ax.raise(window)
        }

        runtime.document.activeProfileID = profile.id
        runtime.persist()
        runtime.menuBar?.reloadMenu()
        runtime.refreshWorkspaceSettings()
        resetBaseline()
        prepareMissingPlacements(
            profile: profile,
            outcome: outcome,
            unreachableBundleIDs: collected.unreachableBundleIDs
        )
        updateCensus()

        let launchingCount = Set(pending.map(\.bundleID)).count
        let unresolvedMissingCount = max(0, outcome.missingBundleIDs.count - launchingCount)
        let feedback = WorkspaceApplyFeedback.make(
            moved: movedWindows,
            issues: issues,
            skipped: skippedWindows,
            missingCount: unresolvedMissingCount,
            launchingCount: launchingCount,
            staleCount: outcome.staleRules.count,
            disconnectedCount: outcome.skippedDisplayIDs.count,
            applicationName: applicationName(for:)
        )
        if !feedback.detail.isEmpty {
            showFeedback(
                title: L10n.text(feedback.titleKey),
                detail: feedback.detail,
                error: feedback.isError
            )
        }
    }

    private func collectVisibleSamples() -> [ProfileCapture.WindowSample] {
        let refs = runtime.query.windows(excludingPID: ProcessInfo.processInfo.processIdentifier)
        let visible = ProfileCapture.visibleWindowIdentities(
            frontToBack: refs.map {
                ProfileCapture.VisibilitySample(
                    identity: $0.identity,
                    frameAX: $0.boundsAX,
                    opacity: $0.alpha,
                    isOpaqueOccluder: $0.layer == 0 && $0.alpha >= 0.99
                )
            }
        )
        return refs.compactMap { ref in
            guard visible.contains(ref.identity),
                  let bundleID = ref.bundleID,
                  !bundleID.isEmpty,
                  !runtime.settings.excludedBundleIDs.contains(bundleID)
            else { return nil }
            return ProfileCapture.WindowSample(identity: ref.identity, frameAX: ref.boundsAX)
        }
    }

    private func captureSections(from samples: [ProfileCapture.WindowSample]) -> [ProfileSection] {
        var sections: [ProfileSection] = []
        for area in runtime.displays.workAreas {
            guard let layout = runtime.document.layout(for: area.display.id) else { continue }
            let zones = runtime.resolvedZones(layout: layout, area: area)
            let owned = samples.filter { sample in
                DisplayTargetResolver.workArea(
                    containingWindowFrameAX: sample.frameAX,
                    from: runtime.displays.workAreas,
                    primaryFlipHeight: runtime.displays.primaryFlipHeight
                )?.display.id == area.display.id
            }
            let rules = ProfileCapture.rules(windows: owned, zones: zones)
            if !rules.isEmpty {
                sections.append(
                    ProfileSection(
                        space: SpaceKey(displayID: area.display.id),
                        layoutID: layout.id,
                        rules: rules
                    )
                )
            }
        }
        return sections
    }

    /// On-screen windows in WindowServer z-order, resolved through one AX
    /// enumeration per application. Apps named in `restorableBundleIDs` also
    /// contribute their minimized windows and, when the app is hidden, the
    /// windows CGWindowList cannot see; those are appended after the visible
    /// ones so a visible window is always consumed first.
    private func collectCandidates(
        visibleOnly: Bool = false,
        restorableBundleIDs: Set<String> = []
    ) async -> CandidateSet {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let refs = runtime.query.windows(excludingPID: ownPID)
        let visibleIdentities = visibleOnly
            ? ProfileCapture.visibleWindowIdentities(
                frontToBack: refs.map {
                    ProfileCapture.VisibilitySample(
                        identity: $0.identity,
                        frameAX: $0.boundsAX,
                        opacity: $0.alpha,
                        isOpaqueOccluder: $0.layer == 0 && $0.alpha >= 0.99
                    )
                }
            )
            : nil

        var pidOrder: [pid_t] = []
        var refsByPID: [pid_t: [WindowRef]] = [:]
        for ref in refs where ref.layer == 0 {
            if let visibleIdentities, !visibleIdentities.contains(ref.identity) { continue }
            guard let bundleID = ref.bundleID, !bundleID.isEmpty, !isExcluded(bundleID) else { continue }
            if refsByPID[ref.pid] == nil { pidOrder.append(ref.pid) }
            refsByPID[ref.pid, default: []].append(ref)
        }
        var hiddenByPID: [pid_t: Bool] = [:]
        var revealedRunning = false
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  restorableBundleIDs.contains(bundleID),
                  !isExcluded(bundleID),
                  app.processIdentifier != ownPID,
                  !app.isTerminated
            else { continue }
            hiddenByPID[app.processIdentifier] = app.isHidden
            if refsByPID[app.processIdentifier] == nil {
                pidOrder.append(app.processIdentifier)
                refsByPID[app.processIdentifier] = []
            }
            // Hidden apps must be unhidden before AX can see their windows.
            // Windowless running apps are reopened later, then all windows are
            // activated — activating here would skip that restore step.
            let hasUsableWindow = (refsByPID[app.processIdentifier] ?? []).contains {
                isLargeEnough($0.boundsAX)
            }
            if !hasUsableWindow, app.isHidden, app.unhide() {
                revealedRunning = true
                Log.workspace.info("Apply unhide app=\(bundleID, privacy: .public)")
            }
        }
        if revealedRunning {
            try? await Task.sleep(nanoseconds: 300_000_000)
            let refreshed = runtime.query.windows(excludingPID: ownPID)
            pidOrder = []
            refsByPID = [:]
            for ref in refreshed where ref.layer == 0 {
                if let visibleIdentities, !visibleIdentities.contains(ref.identity) { continue }
                guard let bundleID = ref.bundleID, !bundleID.isEmpty, !isExcluded(bundleID) else { continue }
                if refsByPID[ref.pid] == nil { pidOrder.append(ref.pid) }
                refsByPID[ref.pid, default: []].append(ref)
            }
            for app in NSWorkspace.shared.runningApplications {
                guard let bundleID = app.bundleIdentifier,
                      restorableBundleIDs.contains(bundleID),
                      !isExcluded(bundleID),
                      app.processIdentifier != ownPID,
                      !app.isTerminated
                else { continue }
                if refsByPID[app.processIdentifier] == nil {
                    pidOrder.append(app.processIdentifier)
                    refsByPID[app.processIdentifier] = []
                }
            }
        }

        var result = CandidateSet()
        var seen = Set<WindowIdentity>()
        var offscreen: [WindowCandidate] = []
        for pid in pidOrder {
            let windows = await runtime.ax.applicationWindows(pid: pid)
            if !restorableBundleIDs.isEmpty {
                Log.workspace.info(
                    "Candidates pid=\(pid, privacy: .public) app=\(refsByPID[pid]?.first?.bundleID ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?", privacy: .public) onScreen=\(refsByPID[pid]?.count ?? 0, privacy: .public) ax=\(windows.count, privacy: .public) minimized=\(windows.filter(\.isMinimized).count, privacy: .public) fullscreen=\(windows.filter(\.isFullscreen).count, privacy: .public) hidden=\(hiddenByPID[pid] ?? false, privacy: .public)"
                )
            }
            guard !windows.isEmpty else { continue }
            var unmatched = windows.filter { !$0.isFullscreen }
            for ref in refsByPID[pid] ?? [] {
                let index = unmatched.firstIndex { $0.window.identity.windowNumber == ref.windowNumber }
                    ?? unmatched.firstIndex { framesMatch($0.frameAX, ref.boundsAX) }
                guard let index else { continue }
                let window = unmatched.remove(at: index)
                // CGWindowList can report a stub menu/chrome strip for apps like
                // Simulator. Prefer the AX frame, which is the real window size.
                guard isLargeEnough(window.frameAX) else { continue }
                guard seen.insert(window.window.identity).inserted else { continue }
                result.candidates.append(
                    WindowCandidate(
                        sample: ProfileCapture.WindowSample(identity: window.window.identity, frameAX: window.frameAX),
                        handle: window.window
                    )
                )
            }
            guard let bundleID = windows.first?.window.identity.bundleID ?? refsByPID[pid]?.first?.bundleID,
                  restorableBundleIDs.contains(bundleID)
            else { continue }
            let appHidden = hiddenByPID[pid] ?? false
            var hasUnreachableLeftover = windows.contains(where: \.isFullscreen)
            for window in unmatched where isLargeEnough(window.frameAX) {
                guard seen.insert(window.window.identity).inserted else { continue }
                if window.isFullscreen {
                    hasUnreachableLeftover = true
                    continue
                }
                if window.isMinimized || appHidden {
                    offscreen.append(
                        WindowCandidate(
                            sample: ProfileCapture.WindowSample(identity: window.window.identity, frameAX: window.frameAX),
                            handle: window.window,
                            isMinimized: window.isMinimized,
                            isHiddenApp: appHidden
                        )
                    )
                    continue
                }
                // CGWindowList can miss or stub a real window (Simulator chrome
                // strips, Electron shells). After activate, the AX window is the
                // source of truth and should be placed like any other app.
                result.candidates.append(
                    WindowCandidate(
                        sample: ProfileCapture.WindowSample(identity: window.window.identity, frameAX: window.frameAX),
                        handle: window.window
                    )
                )
            }
            if hasUnreachableLeftover {
                result.unreachableBundleIDs.insert(bundleID)
            }
        }
        result.candidates.append(contentsOf: offscreen)
        return result
    }

    /// Minimized windows and hidden apps are part of the saved arrangement, so
    /// restore brings them back before writing frames. Frames written to a
    /// window that is still miniaturizing are dropped by many apps.
    private func revealPlannedWindows(
        outcome: ProfilePlan.Outcome,
        candidates: [WindowIdentity: WindowCandidate]
    ) async {
        var revealed = 0
        var unhiddenPIDs = Set<pid_t>()
        for placement in outcome.sections.flatMap(\.placements) {
            guard let candidate = candidates[placement.identity] else { continue }
            if candidate.isHiddenApp, !unhiddenPIDs.contains(placement.identity.pid) {
                unhiddenPIDs.insert(placement.identity.pid)
                if NSRunningApplication(processIdentifier: placement.identity.pid)?.unhide() == true {
                    revealed += 1
                    Log.workspace.info(
                        "Apply unhide app=\(placement.identity.bundleID ?? "?", privacy: .public)"
                    )
                }
            }
            if candidate.isMinimized {
                let restored = await runtime.ax.unminimize(candidate.handle)
                if restored { revealed += 1 }
                Log.workspace.info(
                    "Apply unminimize app=\(placement.identity.bundleID ?? "?", privacy: .public) window=\(placement.identity.windowNumber, privacy: .public) ok=\(restored, privacy: .public)"
                )
            }
        }
        if revealed > 0 {
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    private func isExcluded(_ bundleID: String) -> Bool {
        runtime.settings.excludedBundleIDs.contains(bundleID)
    }

    private func isLargeEnough(_ frame: CGRect) -> Bool {
        frame.width >= 80 && frame.height >= 80
    }

    private func prepareMissingPlacements(
        profile: WorkspaceProfile,
        outcome: ProfilePlan.Outcome,
        unreachableBundleIDs: Set<String>
    ) {
        guard profile.launchMissingApps else { return }
        var consumed = Dictionary(
            grouping: outcome.sections.flatMap(\.placements),
            by: { $0.identity.bundleID ?? "" }
        ).mapValues(\.count)
        let expiresAt = Date().addingTimeInterval(Self.launchTimeout)
        var openActions: [String: ProfilePlan.AppOpenAction] = [:]
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        for section in profile.sections {
            guard let zones = resolvedZones(for: section) else { continue }
            for rule in section.rules {
                if (consumed[rule.bundleID] ?? 0) > 0 {
                    consumed[rule.bundleID, default: 0] -= 1
                    continue
                }
                if unreachableBundleIDs.contains(rule.bundleID) { continue }
                let action = ProfilePlan.openAction(
                    bundleID: rule.bundleID,
                    missingBundleIDs: outcome.missingBundleIDs,
                    runningBundleIDs: runningBundleIDs,
                    launchMissingApps: profile.launchMissingApps
                )
                guard action != .none,
                      let zone = zones.first(where: { $0.zoneID == rule.zoneID })
                        ?? zones.first(where: { $0.number == rule.zoneNumber })
                else { continue }
                pending.append(
                    PendingPlacement(
                        bundleID: rule.bundleID,
                        zoneID: zone.zoneID,
                        zoneNumber: zone.number,
                        layoutID: section.layoutID,
                        displayID: section.space.displayID,
                        expiresAt: expiresAt
                    )
                )
                if openActions[rule.bundleID] == nil {
                    openActions[rule.bundleID] = action
                }
            }
        }
        for (bundleID, action) in openActions {
            Log.workspace.info(
                "Apply open app=\(bundleID, privacy: .public) action=\(action == .reopen ? "reopen" : "launch", privacy: .public)"
            )
            open(bundleID: bundleID, action: action)
        }
    }

    private func open(bundleID: String, action: ProfilePlan.AppOpenAction) {
        guard action != .none else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            pending.removeAll { $0.bundleID == bundleID }
            showFeedback(
                title: L10n.text(.workspaceAppMissingTitle),
                detail: String(format: L10n.text(.workspaceAppNotInstalledDetail), bundleID),
                error: true
            )
            return
        }
        if action == .reopen {
            reopenRunningApplication(bundleID: bundleID)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] running, error in
            if let error {
                Log.workspace.error(
                    "Apply open failed app=\(bundleID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                Task { @MainActor in
                    self?.pending.removeAll { $0.bundleID == bundleID }
                    self?.showFeedback(
                        title: L10n.text(.workspaceAppMissingTitle),
                        detail: error.localizedDescription,
                        error: true
                    )
                }
                return
            }
            let app = running ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            _ = app?.unhide()
            _ = app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            Log.workspace.info("Apply activated all windows app=\(bundleID, privacy: .public)")
            if bundleID == SimulatorDevicePlan.bundleID {
                Task { @MainActor [weak self] in
                    await self?.bootSimulatorDeviceIfNeeded(simulatorAppURL: url)
                }
            }
        }
    }

    /// Simulator.app stays alive with only menu-bar strips after its last
    /// device shuts down. Reopen and relaunch just activate it, so restore
    /// would wait the whole launch timeout for a window that never comes.
    /// Boot the device Simulator itself would have opened. A cold launch
    /// starts that boot on its own; the delay lets it show up as Booting so
    /// the check below leaves it alone.
    private func bootSimulatorDeviceIfNeeded(simulatorAppURL: URL) async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard pending.contains(where: { $0.bundleID == SimulatorDevicePlan.bundleID }) else { return }
        let booter = SimulatorDeviceBooter(
            developerDirectory: SimulatorDeviceBooter.developerDirectory(simulatorAppURL: simulatorAppURL)
        )
        let outcome = await Task.detached(priority: .userInitiated) { booter.ensureDeviceBooted() }.value
        switch outcome {
        case .alreadyActive:
            Log.workspace.info("Apply simulator device already active")
        case .booted(let udid, let name):
            Log.workspace.info(
                "Apply simulator boot device=\(name, privacy: .public) udid=\(udid, privacy: .public)"
            )
        case .noDevice:
            Log.workspace.error("Apply simulator boot skipped: no available device")
        case .failed(let reason):
            Log.workspace.error("Apply simulator boot failed: \(reason, privacy: .public)")
        }
    }

    /// Dock-click / Keyboard Maestro "Reopen initial windows": tell an already
    /// running app to restore its saved windows before activating them.
    private func reopenRunningApplication(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return
        }
        _ = app.unhide()
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        do {
            try event.sendEvent(options: [.noReply], timeout: 1)
            Log.workspace.info("Apply reopen app=\(bundleID, privacy: .public)")
        } catch {
            Log.workspace.error(
                "Apply reopen failed app=\(bundleID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func updateCensus() {
        let needed = !paused && !pending.isEmpty
        if needed, censusTask == nil {
            Log.workspace.info("Census started pending=\(self.pending.count, privacy: .public)")
            censusTask = Task { @MainActor [weak self] in
                while let self, !Task.isCancelled {
                    await self.poll()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        } else if !needed {
            censusTask?.cancel()
            censusTask = nil
            observed.removeAll()
        }
    }

    private func poll() async {
        guard !paused else { return }
        let now = Date()
        let expiredBundles = Set(pending.filter { $0.expiresAt <= now }.map(\.bundleID))
        pending.removeAll { $0.expiresAt <= now }
        if !expiredBundles.isEmpty {
            Log.workspace.error(
                "Census timeout apps=\(expiredBundles.sorted().joined(separator: ","), privacy: .public)"
            )
            showFeedback(
                title: L10n.text(.workspaceAppMissingTitle),
                detail: String(
                    format: L10n.text(.workspaceLaunchTimeoutDetail),
                    expiredBundles.sorted().joined(separator: ", ")
                ),
                error: true
            )
        }
        guard !runtime.engine.isSessionActive, !runtime.isEditorOpen else { return }

        let refs = runtime.query.windows(excludingPID: ProcessInfo.processInfo.processIdentifier)
        let current = Dictionary(uniqueKeysWithValues: refs.map { ($0.identity, $0) })
        await claimExistingWindowsForPending()
        // Splash screens, tooltips and helper panels appear before an app's
        // real window. Only a window that resolves to a standard AX window may
        // reserve a pending target; one that does not resolve yet is checked
        // again next poll without holding a reservation, so it can never block
        // the real window when it arrives.
        for ref in refs where !baseline.contains(ref.identity) {
            guard ref.layer == 0 else {
                baseline.insert(ref.identity)
                continue
            }
            // Splash/tool windows often start below 80x80 and later grow into
            // the real document window under the same identity. Keep them out
            // of baseline until they are large enough to reserve a zone.
            guard isLargeEnough(ref.boundsAX) else { continue }
            guard let target = reserveTarget(for: ref) else {
                baseline.insert(ref.identity)
                continue
            }
            guard await runtime.ax.resolveAsync(ref: ref) != nil else { continue }
            baseline.insert(ref.identity)
            Log.workspace.info(
                "Census observed app=\(ref.bundleID ?? "?", privacy: .public) window=\(ref.windowNumber, privacy: .public) zone=\(target.placement.zoneNumber, privacy: .public)"
            )
            observed[ref.identity] = ObservedWindow(
                pendingID: target.pendingID,
                target: target.placement,
                lastFrame: ref.boundsAX,
                stableSamples: 1
            )
        }

        for identity in Array(observed.keys) {
            guard let ref = current[identity], var item = observed[identity] else {
                observed[identity] = nil
                continue
            }
            if framesMatch(item.lastFrame, ref.boundsAX) {
                item.stableSamples += 1
            } else {
                item.lastFrame = ref.boundsAX
                item.stableSamples = 1
            }
            observed[identity] = item
            guard item.stableSamples >= 2 else { continue }
            guard let zone = resolvedZone(for: item.target) else {
                // The target display went away; free the reservation so the
                // pending entry can expire or be claimed on another screen.
                observed[identity] = nil
                continue
            }
            guard let window = await runtime.ax.resolveAsync(ref: ref),
                  let original = await runtime.ax.frame(of: window)
            else {
                observed[identity] = nil
                continue
            }
            guard let applied = await acceptedDelayedFrame(zone.frameAX, of: window) else {
                item.rejectedAttempts += 1
                item.stableSamples = 0
                Log.workspace.info(
                    "Census placement rejected app=\(identity.bundleID ?? "?", privacy: .public) window=\(identity.windowNumber, privacy: .public) attempt=\(item.rejectedAttempts, privacy: .public)"
                )
                if item.rejectedAttempts >= Self.maxRejectedAttempts {
                    if let pendingID = item.pendingID { pending.removeAll { $0.id == pendingID } }
                    observed[identity] = nil
                } else {
                    observed[identity] = item
                }
                continue
            }
            Log.workspace.info(
                "Census placed app=\(identity.bundleID ?? "?", privacy: .public) window=\(identity.windowNumber, privacy: .public) zone=\(zone.number, privacy: .public)"
            )
            runtime.catalog.record(
                UnsnapRecord(
                    identity: identity,
                    originalFrameAX: original,
                    snappedFrameAX: applied,
                    zoneIDs: [zone.zoneID]
                ),
                displayID: item.target.displayID
            )
            if let pendingID = item.pendingID { pending.removeAll { $0.id == pendingID } }
            observed[identity] = nil
        }
        updateCensus()
    }

    /// Already-running apps often have a usable AX window that CGWindowList
    /// first reports as chrome, a stub, or an existing identity. After activate,
    /// claim that window instead of waiting for a brand-new one.
    private func claimExistingWindowsForPending() async {
        guard !pending.isEmpty else { return }
        var claimed = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  pending.contains(where: { $0.bundleID == bundleID }),
                  claimed.insert(bundleID).inserted
            else { continue }
            let windows = await runtime.ax.applicationWindows(pid: app.processIdentifier)
            for window in windows where isLargeEnough(window.frameAX) && !window.isFullscreen {
                let identity = window.window.identity
                guard observed[identity] == nil else { continue }
                let ref = WindowRef(
                    pid: identity.pid,
                    windowNumber: identity.windowNumber,
                    boundsAX: window.frameAX,
                    bundleID: bundleID,
                    layer: 0,
                    alpha: 1
                )
                guard let target = reserveTarget(for: ref) else { continue }
                baseline.insert(identity)
                Log.workspace.info(
                    "Census claimed existing app=\(bundleID, privacy: .public) window=\(identity.windowNumber, privacy: .public) zone=\(target.placement.zoneNumber, privacy: .public)"
                )
                observed[identity] = ObservedWindow(
                    pendingID: target.pendingID,
                    target: target.placement,
                    lastFrame: window.frameAX,
                    stableSamples: 2
                )
            }
        }
    }

    private func reserveTarget(for ref: WindowRef) -> (pendingID: UUID?, placement: PendingPlacement)? {
        guard let bundleID = ref.bundleID,
              !runtime.settings.excludedBundleIDs.contains(bundleID)
        else { return nil }
        let reserved = Set(observed.values.compactMap(\.pendingID))
        if let placement = pending.first(where: { $0.bundleID == bundleID && !reserved.contains($0.id) }) {
            return (placement.id, placement)
        }
        return nil
    }

    private func resolvedZones(for section: ProfileSection) -> [ResolvedZone]? {
        guard let area = runtime.displays.workAreas.first(where: { $0.display.id == section.space.displayID }),
              let layout = runtime.document.layouts.first(where: { $0.id == section.layoutID })
        else { return nil }
        return runtime.resolvedZones(layout: layout, area: area)
    }

    private func resolvedZone(for placement: PendingPlacement) -> ResolvedZone? {
        guard let area = runtime.displays.workAreas.first(where: { $0.display.id == placement.displayID }),
              let layout = runtime.document.layouts.first(where: { $0.id == placement.layoutID })
        else { return nil }
        let zones = runtime.resolvedZones(layout: layout, area: area)
        return zones.first(where: { $0.zoneID == placement.zoneID })
            ?? zones.first(where: { $0.number == placement.zoneNumber })
    }

    private func resetBaseline() {
        baseline = Set(
            runtime.query.windows(excludingPID: ProcessInfo.processInfo.processIdentifier).map(\.identity)
        )
        observed.removeAll()
    }

    private func applicationName(for identity: WindowIdentity) -> String {
        NSRunningApplication(processIdentifier: identity.pid)?.localizedName
            ?? identity.bundleID
            ?? L10n.text(.organizeNoWindowsTitle)
    }

    private func applicationName(forBundleID bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? bundleID
    }

    private func acceptedDelayedFrame(_ target: CGRect, of window: AXWindow) async -> CGRect? {
        let application = await runtime.applyWorkspaceFrame(target, to: window)
        switch application.behavior {
        case .compliant, .sizeConstrained:
            return application.actualFrameAX
        case .positionConstrained, .immutable, .unstable:
            return nil
        }
    }

    private func showFeedback(title: String, detail: String, error: Bool) {
        let area = runtime.displays.area(containingAppKit: NSEvent.mouseLocation)
            ?? runtime.displays.workAreas.first
        guard let area, let screen = runtime.displays.screen(for: area.display.id) else { return }
        runtime.organizeFeedback.show(
            OrganizeFeedback(tone: error ? .error : .warning, title: title, detail: detail),
            on: screen
        )
    }

    private func appendUnique(_ identities: [WindowIdentity], to values: inout [WindowIdentity]) {
        for identity in identities where !values.contains(identity) { values.append(identity) }
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 2
            && abs(lhs.minY - rhs.minY) <= 2
            && abs(lhs.width - rhs.width) <= 2
            && abs(lhs.height - rhs.height) <= 2
    }
}
