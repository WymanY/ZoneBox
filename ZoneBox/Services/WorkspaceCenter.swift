import AppKit
import ZoneBoxCore

@MainActor
final class WorkspaceCenter {
    unowned var runtime: AppRuntime!

    private struct WindowCandidate {
        var sample: ProfileCapture.WindowSample
        var handle: AXWindow
    }

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
    }

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
        let candidates = await collectCandidates(visibleOnly: true)
        var sections: [ProfileSection] = []
        for area in runtime.displays.workAreas {
            guard let layout = runtime.document.layout(for: area.display.id) else { continue }
            let zones = runtime.resolvedZones(layout: layout, area: area)
            let samples = candidates.compactMap { candidate -> ProfileCapture.WindowSample? in
                guard let owner = DisplayTargetResolver.workArea(
                    containingWindowFrameAX: candidate.sample.frameAX,
                    from: runtime.displays.workAreas,
                    primaryFlipHeight: runtime.displays.primaryFlipHeight
                ), owner.display.id == area.display.id else { return nil }
                return candidate.sample
            }
            let rules = ProfileCapture.rules(windows: samples, zones: zones)
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
        let candidates = await collectCandidates()
        let handles = Dictionary(uniqueKeysWithValues: candidates.map { ($0.sample.identity, $0.handle) })
        var zonesBySection: [DisplayIdentity.ID: [ResolvedZone]] = [:]
        for section in profile.sections {
            guard let area = runtime.displays.workAreas.first(where: { $0.display.id == section.space.displayID }),
                  let layout = runtime.document.layouts.first(where: { $0.id == section.layoutID })
            else { continue }
            zonesBySection[section.space.displayID] = runtime.resolvedZones(layout: layout, area: area)
        }
        let outcome = ProfilePlan.make(
            profile: profile,
            zonesBySection: zonesBySection,
            candidates: candidates.map(\.sample)
        )
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
                appendUnique(skipped, to: &skippedWindows)
            case .failed(let skipped, let rollbackFailed):
                appendUnique(skipped, to: &skippedWindows)
                appendUnique(rollbackFailed, to: &skippedWindows)
            }
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
        prepareMissingPlacements(profile: profile, outcome: outcome)
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

    private func collectCandidates(visibleOnly: Bool = false) async -> [WindowCandidate] {
        var seen = Set<WindowIdentity>()
        var candidates: [WindowCandidate] = []
        let refs = runtime.query.windows(excludingPID: ProcessInfo.processInfo.processIdentifier)
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
        for ref in refs {
            if let visibleIdentities, !visibleIdentities.contains(ref.identity) { continue }
            guard let window = await runtime.ax.resolveAsync(ref: ref),
                  !seen.contains(window.identity),
                  let frame = await runtime.ax.frame(of: window),
                  !runtime.settings.excludedBundleIDs.contains(window.identity.bundleID ?? "")
            else { continue }
            seen.insert(window.identity)
            candidates.append(
                WindowCandidate(
                    sample: ProfileCapture.WindowSample(identity: window.identity, frameAX: frame),
                    handle: window
                )
            )
        }
        return candidates
    }

    private func prepareMissingPlacements(profile: WorkspaceProfile, outcome: ProfilePlan.Outcome) {
        guard profile.launchMissingApps else { return }
        var consumed = Dictionary(
            grouping: outcome.sections.flatMap(\.placements),
            by: { $0.identity.bundleID ?? "" }
        ).mapValues(\.count)
        let expiresAt = Date().addingTimeInterval(15)
        for section in profile.sections {
            guard let zones = resolvedZones(for: section) else { continue }
            for rule in section.rules {
                if (consumed[rule.bundleID] ?? 0) > 0 {
                    consumed[rule.bundleID, default: 0] -= 1
                    continue
                }
                guard outcome.missingBundleIDs.contains(rule.bundleID),
                      NSRunningApplication.runningApplications(withBundleIdentifier: rule.bundleID).isEmpty,
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
            }
        }
        for bundleID in Set(pending.map(\.bundleID)) {
            launch(bundleID: bundleID)
        }
    }

    private func launch(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            pending.removeAll { $0.bundleID == bundleID }
            showFeedback(
                title: L10n.text(.workspaceAppMissingTitle),
                detail: String(format: L10n.text(.workspaceAppNotInstalledDetail), bundleID),
                error: true
            )
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.pending.removeAll { $0.bundleID == bundleID }
                self?.showFeedback(
                    title: L10n.text(.workspaceAppMissingTitle),
                    detail: error.localizedDescription,
                    error: true
                )
            }
        }
    }

    private func updateCensus() {
        let needed = !paused && !pending.isEmpty
        if needed, censusTask == nil {
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
        for (identity, ref) in current where !baseline.contains(identity) {
            if let target = reserveTarget(for: ref) {
                observed[identity] = ObservedWindow(
                    pendingID: target.pendingID,
                    target: target.placement,
                    lastFrame: ref.boundsAX,
                    stableSamples: 1
                )
            }
        }
        baseline.formUnion(current.keys)

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
            guard item.stableSamples >= 2,
                  let zone = resolvedZone(for: item.target),
                  let window = await runtime.ax.resolveAsync(ref: ref),
                  let original = await runtime.ax.frame(of: window),
                  let applied = await acceptedDelayedFrame(zone.frameAX, of: window)
            else { continue }
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
