import ApplicationServices
import AppKit
import ZoneBoxCore

@MainActor
final class AppRuntime {
    var isEditorOpen = false
    var settings: AppSettings = .default
    var document = StoreDocument()
    var pendingWindow: AXWindow?
    var pendingFrame: CGRect?
    var pendingStartedOnMoveChrome = false
    var pendingIdentity: WindowIdentity?

    let uiSession = UISession()
    let trust = TrustMonitor()
    let displays = DisplayWatcher()
    let overlay = OverlayController()
    let organizeFeedback = OrganizeFeedbackController()
    let catalog = WindowCatalog()
    let engine = SnapEngine()
    let drag = DragMonitor()
    let hotkeys = HotkeyCenter()
    let workspace = WorkspaceCenter()
    let pins = PinCenter()
    let pinHover = PinHoverMonitor()
    var ax: AccessibilityClientLive
    let query = CGWindowQuery()

    private let layoutStore = LayoutStore()
    private let settingsStore = SettingsStore()
    var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var editor: LayoutEditorController?
    private var shortcutPanel: ShortcutPanelController?
    private var quickSnapperUIActive = false
    private var previewHideWorkItem: DispatchWorkItem?
    private var pendingLayoutPreview: PendingLayoutPreview?
    private(set) var isOrganizingWindows = false
    private var organizeBehaviorCache: [WindowIdentity: WindowOrganizeWindowBehavior] = [:]
    private var lastOrganizeSnapshot: [WindowIdentity: (window: AXWindow, frame: CGRect)] = [:]
    private var resolvedLayoutCache: [ResolvedLayoutCacheKey: [ResolvedZone]] = [:]

    init() {
        ax = AccessibilityClientLive(
            query: query,
            excluded: { AppSettings.default.excludedBundleIDs },
            snapDialogs: { false },
            trusted: { TrustMonitor.hasAccessibilityAccess() }
        )
    }

    func start() {
        isEditorOpen = false
        settings = (try? settingsStore.load()) ?? .default
        document = (try? layoutStore.load()) ?? StoreDocument()
        ax = rebindAX()

        engine.runtime = self
        drag.runtime = self
        hotkeys.runtime = self
        workspace.runtime = self
        pins.runtime = self
        pinHover.runtime = self

        displays.refresh(document: &document)
        overlay.rebuild(workAreas: displays.workAreas, screens: NSScreen.screens)
        overlay.settings = settings
        overlay.primaryFlipHeight = displays.primaryFlipHeight
        persist()

        LanguageCenter.preference = settings.uiLanguage
        LanguageCenter.shared.start()
        LanguageCenter.shared.refresh(force: true)
        NotificationCenter.default.addObserver(
            forName: LanguageCenter.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let runtime = self else { return }
            Task { @MainActor in runtime.applyLanguage() }
        }

        menuBar = MenuBarController(runtime: self)
        menuBar?.install()

        drag.start()
        hotkeys.start()
        workspace.start()
        pins.start()
        pinHover.start()
        observeSystem()

        Log.trust.info(
            "Trust trusted=\(self.trust.isTrusted(), privacy: .public) path=\(TrustMonitor.currentBuildPath, privacy: .public)"
        )
        if !trust.isTrusted() {
            onboarding = OnboardingWindowController(runtime: self)
            onboarding?.show()
        }

        Log.app.info("ZoneBox started")
    }

    private func rebindAX() -> AccessibilityClientLive {
        AccessibilityClientLive(
            query: query,
            excluded: { [weak self] in self?.settings.excludedBundleIDs ?? AppSettings.default.excludedBundleIDs },
            snapDialogs: { [weak self] in self?.settings.snapDialogs ?? false },
            trusted: { TrustMonitor.hasAccessibilityAccess() }
        )
    }

    func teardown() {
        workspace.stop()
        pinHover.stop()
        pins.stop()
        overlay.hideAll()
        organizeFeedback.dismiss()
        drag.stop()
        hotkeys.stop()
        previewHideWorkItem?.cancel()
        editor = nil
        shortcutPanel?.close()
        onboarding?.close()
        settingsWindow?.close()
        menuBar?.remove()
        menuBar = nil
        Log.app.info("ZoneBox stopped")
    }

    func hideAllOverlays() {
        pinHover.hideImmediately()
        pins.hideBadges()
        overlay.hideAll()
    }

    var snapEnabled: Bool { true }

    func openSettings() {
        menuBar?.closeConsole()
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(runtime: self)
            uiSession.enterRegular()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow()
    }

    func openWorkspaceSettings() {
        menuBar?.closeConsole()
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(runtime: self)
            uiSession.enterRegular()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWorkspaces()
    }

    func settingsDidClose() {
        guard settingsWindow != nil else { return }
        settingsWindow = nil
        persistSettings()
        hotkeys.reregister()
        menuBar?.reloadMenu()
        uiSession.leaveRegular()
    }

    func refreshWorkspaceSettings() {
        settingsWindow?.reloadWorkspaceProfiles()
    }

    func openEditor() {
        guard editor == nil else {
            editor?.activate()
            return
        }
        guard let target = pointerEditorTarget() else { return }
        openEditor(on: target)
    }

    func openEditorForFocusedWindow() {
        guard editor == nil else {
            editor?.activate()
            return
        }
        Task { @MainActor in
            if let focused = await focusedWindowTarget(),
               let target = editorTarget(for: focused.area)
            {
                openEditor(on: target)
                return
            }
            guard !trust.isTrusted(), let target = pointerEditorTarget() else {
                Log.hotkey.error("Editor shortcut could not resolve a focused-window target")
                return
            }
            Log.hotkey.info("Editor shortcut falling back to pointer display because Accessibility is unavailable")
            openEditor(on: target)
        }
    }

    func openEditor(for layout: Layout) {
        guard editor == nil else {
            editor?.activate()
            return
        }
        guard let target = pointerEditorTarget() else { return }
        beginEditing(layout, isNew: false, target: target)
    }

    private func openEditor(on target: EditorTarget) {
        guard editor == nil else {
            editor?.activate()
            return
        }
        let layout = document.layout(for: target.area.display.id)
            ?? document.layouts.first
            ?? LayoutTemplates.columns(2)
        beginEditing(layout, isNew: false, target: target)
    }

    func editorDidClose() {
        editor = nil
        menuBar?.reloadMenu()
    }

    func cancelEditor() {
        editor?.cancelEditing()
    }

    var editorClaimsKeyboard: Bool {
        guard isEditorOpen else { return false }
        guard let key = NSApp.keyWindow else { return true }
        return editor?.owns(key) == true
    }

    var isEditorEditingMetrics: Bool { editor?.isEditingMetrics == true }

    @discardableResult
    func handleEditorKey(_ event: NSEvent) -> Bool {
        if editor?.isEditingMetrics == true { return false }
        let modifiers = KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        if ShortcutCatalog.editorSaveChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            return editor?.handleLocalKey(event) ?? false
        }
        if ShortcutCatalog.isEditorUndoChord(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            return editor?.handleLocalKey(event) ?? false
        }
        if ShortcutCatalog.isEditorRedoChord(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            return editor?.handleLocalKey(event) ?? false
        }
        if ShortcutCatalog.editorDuplicateChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            return editor?.handleLocalKey(event) ?? false
        }
        if ShortcutCatalog.editorSelectAllChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            return editor?.handleLocalKey(event) ?? false
        }
        if ShortcutCatalog.editorSplitVerticalChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            return editor?.handleLocalKey(event) ?? false
        }
        if ShortcutCatalog.editorSplitHorizontalChord.matches(
            keyCode: event.keyCode,
            carbonModifiers: modifiers
        ) {
            return editor?.handleLocalKey(event) ?? false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) { return false }
        return editor?.handleLocalKey(event) ?? false
    }

    func openShortcutPanel() {
        if let shortcutPanel {
            shortcutPanel.show()
            return
        }
        let panel = ShortcutPanelController(runtime: self)
        shortcutPanel = panel
        uiSession.enterRegular()
        panel.show()
    }

    func toggleShortcutPanel() {
        if shortcutPanel != nil {
            shortcutPanel?.close()
            return
        }
        openShortcutPanel()
    }

    var shortcutPanelIsKey: Bool { shortcutPanel?.isKey == true }
    var settingsIsKey: Bool { settingsWindow?.isKey == true }
    var onboardingIsKey: Bool { onboarding?.isKey == true }
    var consoleIsVisible: Bool { menuBar?.isConsoleVisible == true }
    var isRecordingHotkey: Bool { settingsWindow?.isRecordingHotkey == true }

    @discardableResult
    func closeShortcutPanelIfOpen() -> Bool {
        guard shortcutPanelIsKey else { return false }
        shortcutPanel?.close()
        return true
    }

    @discardableResult
    func closeSettingsIfOpen() -> Bool {
        guard settingsWindow != nil else { return false }
        settingsWindow?.close()
        return true
    }

    @discardableResult
    func closeOnboardingIfOpen() -> Bool {
        guard onboarding != nil else { return false }
        onboarding?.close()
        return true
    }

    @discardableResult
    func closeConsoleIfOpen() -> Bool {
        guard consoleIsVisible else { return false }
        menuBar?.closeConsole()
        return true
    }

    @discardableResult
    func cancelHotkeyRecordingIfNeeded() -> Bool {
        settingsWindow?.cancelHotkeyRecording() == true
    }

    func shortcutPanelDidClose() {
        guard shortcutPanel != nil else { return }
        shortcutPanel = nil
        uiSession.leaveRegular()
        if isEditorOpen {
            editor?.activate()
        }
    }

    @discardableResult
    func saveLayout(_ layout: Layout, to displayID: DisplayIdentity.ID) -> Bool {
        guard displays.isActive(displayID: displayID) else { return false }
        document.upsertAndAssign(layout, to: displayID)
        document.markLayoutUsed(layout.id)
        persist()
        menuBar?.reloadMenu()
        return true
    }

    func selectLayout(_ layout: Layout) {
        let area = displays.area(containingAppKit: NSEvent.mouseLocation)
            ?? displays.workAreas.first
        guard let area, displays.isActive(displayID: area.display.id) else {
            Log.overlay.error("Layout preview skipped because no active display was available")
            return
        }
        document.assign(layoutID: layout.id, to: area.display.id)
        document.markLayoutUsed(layout.id)
        persist()
        menuBar?.reloadMenu()
        previewAssignedLayoutIfNeeded(layout, on: area)
    }

    @discardableResult
    func deleteLayout(_ layout: Layout) -> Bool {
        let deleted = document.deleteLayout(id: layout.id)
        guard deleted else { return false }
        persist()
        menuBar?.reloadMenu()
        refreshWorkspaceSettings()
        if editor?.originalLayoutID == layout.id {
            editor?.cancelEditing()
        }
        return true
    }

    func newCanvasLayout() {
        newLayout(kind: .canvas)
    }

    func newGridLayout() {
        newLayout(kind: .grid)
    }

    private func newLayout(kind: LayoutKind) {
        guard editor == nil else {
            editor?.activate()
            return
        }
        guard let target = pointerEditorTarget() else { return }
        let count = document.layouts.count + 1
        if kind == .grid {
            let name = LayoutEditTransaction.uniqueName(
                base: "Grid \(count)",
                existingNames: document.layouts.map(\.name)
            )
            beginEditing(GridEditing.empty(name: name), isNew: true, target: target)
        } else {
            let name = LayoutEditTransaction.uniqueName(
                base: "Canvas \(count)",
                existingNames: document.layouts.map(\.name)
            )
            beginEditing(LayoutTemplates.emptyCanvas(name: name), isNew: true, target: target)
        }
    }

    private typealias EditorTarget = (screen: NSScreen, area: WorkArea)

    private func pointerEditorTarget() -> EditorTarget? {
        let point = NSEvent.mouseLocation
        guard let area = displays.area(containingAppKit: point) else { return nil }
        return editorTarget(for: area)
    }

    private func editorTarget(for area: WorkArea) -> EditorTarget? {
        guard let screen = displays.screen(for: area.display.id) else { return nil }
        return (screen, area)
    }

    func focusedWindowTarget() async -> (window: AXWindow, frameAX: CGRect, area: WorkArea)? {
        guard let window = await ax.focusedWindow(),
              let frameAX = await ax.frame(of: window),
              let area = DisplayTargetResolver.workArea(
                  containingWindowFrameAX: frameAX,
                  from: displays.workAreas,
                  primaryFlipHeight: displays.primaryFlipHeight
              ),
              displays.isActive(displayID: area.display.id)
        else { return nil }
        return (window, frameAX, area)
    }

    private func beginEditing(_ layout: Layout, isNew: Bool, target: EditorTarget) {
        pinHover.hideImmediately()
        pins.hideBadges()
        let controller = LayoutEditorController(
            runtime: self,
            layout: layout,
            targetDisplayID: target.area.display.id,
            isNew: isNew
        )
        editor = controller
        controller.show(on: target.screen)
    }

    func organizeWindowsFromPointer() {
        guard WindowOrganize.isPubliclyAvailable else { return }
        guard beginWindowTransaction() else { return }
        let area = displays.area(containingAppKit: NSEvent.mouseLocation)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { finishWindowTransaction() }
            await organizeWindows(on: area)
        }
    }

    func organizeWindowsFromHotkey() {
        guard WindowOrganize.isPubliclyAvailable else { return }
        guard beginWindowTransaction() else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { finishWindowTransaction() }
            guard let target = await focusedWindowTarget() else {
                NSSound.beep()
                return
            }
            await organizeWindows(on: target.area)
        }
    }

    func beginWindowTransaction() -> Bool {
        guard !isOrganizingWindows else {
            Log.ax.info("Organize ignored because another transaction is running")
            return false
        }
        isOrganizingWindows = true
        pinHover.hideImmediately()
        menuBar?.reloadMenu()
        return true
    }

    func finishWindowTransaction() {
        isOrganizingWindows = false
        menuBar?.reloadMenu()
    }

    func previewZones() {
        guard let area = displays.area(containingAppKit: NSEvent.mouseLocation),
              let layout = document.layout(for: area.display.id)
        else { return }
        flashZones(area: area, layout: layout, duration: 1.6)
    }

    private func previewAssignedLayoutIfNeeded(_ layout: Layout, on area: WorkArea) {
        guard settings.previewLayoutOnSelect else { return }
        pendingLayoutPreview = PendingLayoutPreview(layout: layout, area: area)
        if engine.isSnapGestureActive {
            return
        }
        presentPendingLayoutPreview()
    }

    func noteSnapSessionBecameIdle() {
        presentPendingLayoutPreview()
    }

    private func presentPendingLayoutPreview() {
        guard let pending = pendingLayoutPreview else { return }
        pendingLayoutPreview = nil
        flashZones(area: pending.area, layout: pending.layout, duration: 0.5, showName: true)
    }

    private func organizeWindows(on area: WorkArea?) async {
        if isEditorOpen {
            NSSound.beep()
            return
        }
        guard trust.isTrusted() else {
            openAccessibility()
            return
        }
        guard let area, displays.isActive(displayID: area.display.id) else {
            NSSound.beep()
            return
        }

        let focused = await ax.focusedWindow()
        let focusedIdentity = focused?.identity
        let candidates = await snappableWindows(on: area)
        let ranked = WindowOrganize.rankedIdentities(
            candidates: candidates.map(\.identity),
            focused: focusedIdentity
        )
        let byIdentity = Dictionary(uniqueKeysWithValues: candidates.map { ($0.identity, $0) })
        let orderedWindows = ranked.compactMap { identity -> (identity: WindowIdentity, handle: AXWindow)? in
            guard let window = byIdentity[identity] else { return nil }
            return (identity, window)
        }
        var issues: [WindowOrganizeIssue] = []
        var knownFixed: [WindowOrganizeIssue] = []
        var knownConstrained: [WindowOrganizeIssue] = []
        var activeWindows: [(identity: WindowIdentity, handle: AXWindow)] = []
        for entry in orderedWindows {
            switch organizeBehaviorCache[entry.identity] {
            case .sizeConstrained:
                guard let frame = await ax.frame(of: entry.handle) else { continue }
                knownConstrained.append(
                    WindowOrganizeIssue(
                        identity: entry.identity,
                        behavior: .sizeConstrained,
                        obstacleFrameAX: frame,
                        observedFrameAX: frame
                    )
                )
                activeWindows.append(entry)
            case .positionConstrained, .immutable, .unstable:
                guard let frame = await ax.frame(of: entry.handle) else { continue }
                knownFixed.append(
                    WindowOrganizeIssue(
                        identity: entry.identity,
                        behavior: organizeBehaviorCache[entry.identity] ?? .immutable,
                        obstacleFrameAX: frame,
                        observedFrameAX: frame
                    )
                )
            default:
                activeWindows.append(entry)
            }
        }
        issues = knownFixed + knownConstrained
        lastOrganizeSnapshot = [:]
        previewHideWorkItem?.cancel()
        overlay.hideAll()
        let result = await WindowOrganizeExecutor.execute(
            windows: activeWindows,
            initialSkipped: knownFixed.map(\.identity),
            makePlan: { [weak self] identities in
                guard let self else { return nil }
                let fixed = issues.filter { $0.behavior != .sizeConstrained }
                if !knownConstrained.isEmpty,
                   let plan = WindowOrganize.fallbackPlan(forWindowCount: identities.count)
                {
                    let ranked = WindowOrganize.fallbackRanking(
                        candidates: identities,
                        rejected: knownConstrained.map(\.identity)
                    )
                    return organizeAttemptPlan(for: ranked, using: plan, avoiding: fixed, on: area)
                }
                return organizeAttemptPlan(for: identities, avoiding: fixed, on: area)
            },
            makeFallbackPlan: { [weak self] identities, observed in
                self?.organizeFallbackPlan(for: identities, issues: knownFixed + observed, on: area)
            },
            readFrame: { [ax] window in await ax.frame(of: window) },
            applyFrame: { [weak self] frame, window in
                guard let self else {
                    return WindowOrganizeApplication(actualFrameAX: nil, behavior: .immutable)
                }
                return await applyOrganizeFrame(frame, to: window)
            },
            onIssues: { observed in
                for issue in observed {
                    issues.removeAll { $0.identity == issue.identity }
                    issues.append(issue)
                }
            }
        )

        for issue in issues {
            organizeBehaviorCache[issue.identity] = issue.behavior
        }

        switch result {
        case .success(let plan, let moves, let skipped):
            lastOrganizeSnapshot = Dictionary(uniqueKeysWithValues: moves.compactMap { move in
                guard let window = byIdentity[move.identity] else { return nil }
                return (move.identity, (window, move.originalFrameAX))
            })
            for move in moves {
                catalog.record(
                    UnsnapRecord(
                        identity: move.identity,
                        originalFrameAX: move.originalFrameAX,
                        snappedFrameAX: move.appliedFrameAX,
                        zoneIDs: []
                    ),
                    displayID: area.display.id
                )
            }
            if let identity = plan.placements.first?.identity, let moved = byIdentity[identity] {
                await ax.raise(moved)
                NSRunningApplication(processIdentifier: moved.identity.pid)?.activate()
            }
            if !skipped.isEmpty {
                Log.ax.info("Organize completed after skipping \(skipped.count, privacy: .public) windows")
            }
            if !issues.isEmpty || !skipped.isEmpty {
                showOrganizeFeedback(issues: issues, skipped: skipped, failed: false, area: area)
            } else {
                flashZones(area: area, layout: plan.layout, duration: 1.2, workAreaAX: plan.workAreaAX)
            }

        case .noMovableWindows(let skipped):
            Log.ax.info("Organize found no movable windows skipped=\(skipped.count, privacy: .public)")
            NSSound.beep()
            showOrganizeFeedback(issues: issues, skipped: skipped, failed: true, area: area)

        case .failed(let skipped, let rollbackFailed):
            Log.ax.error(
                "Organize failed skipped=\(skipped.count, privacy: .public) rollbackFailed=\(rollbackFailed.count, privacy: .public)"
            )
            NSSound.beep()
            showOrganizeFeedback(
                issues: issues,
                skipped: skipped,
                failed: true,
                rollbackFailed: rollbackFailed,
                area: area
            )
        }
    }

    private func organizeAttemptPlan(
        for identities: [WindowIdentity],
        using requestedPlan: WindowOrganizePlan? = nil,
        avoiding issues: [WindowOrganizeIssue] = [],
        on area: WorkArea
    ) -> WindowOrganizeAttemptPlan? {
        guard displays.isActive(displayID: area.display.id),
              let plan = requestedPlan ?? WindowOrganize.plan(forWindowCount: identities.count)
        else { return nil }
        let layout = WindowOrganize.layout(for: plan)
        var workAX = CoordinateConverter.axRect(
            fromAppKit: area.visibleFrameAppKit,
            primaryFlipHeight: displays.primaryFlipHeight
        )
        if !issues.isEmpty {
            guard let available = WindowOrganize.largestAvailableRect(
                in: workAX,
                avoiding: issues.map(\.obstacleFrameAX)
            ) else { return nil }
            workAX = available
        }
        guard let zones = try? resolveLayout(
            layout,
            workAreaAX: workAX,
            gutter: CGFloat(settings.gutterPoints)
        ) else { return nil }
        let frames = WindowOrganize.frames(for: plan, windowCount: identities.count, zones: zones)
        guard frames.count == identities.count else { return nil }
        return WindowOrganizeAttemptPlan(
            layout: layout,
            placements: zip(identities, frames).map {
                WindowOrganizePlacement(identity: $0.0, targetFrameAX: $0.1)
            },
            workAreaAX: workAX
        )
    }

    private func organizeFallbackPlan(
        for identities: [WindowIdentity],
        issues: [WindowOrganizeIssue],
        on area: WorkArea
    ) -> WindowOrganizeAttemptPlan? {
        guard let plan = WindowOrganize.fallbackPlan(forWindowCount: identities.count) else { return nil }
        let constrained = issues.filter { $0.behavior == .sizeConstrained }.map(\.identity)
        guard !constrained.isEmpty else { return nil }
        let ranked = WindowOrganize.fallbackRanking(candidates: identities, rejected: constrained)
        Log.ax.info(
            "Organize retrying constrained layout windows=\(identities.count, privacy: .public) issues=\(issues.count, privacy: .public)"
        )
        let fixed = issues.filter { $0.behavior != .sizeConstrained }
        return organizeAttemptPlan(for: ranked, using: plan, avoiding: fixed, on: area)
    }

    private func applyOrganizeFrame(_ target: CGRect, to window: AXWindow) async -> WindowOrganizeApplication {
        _ = await ax.setFrame(target, of: window)
        try? await Task.sleep(nanoseconds: 120_000_000)
        let first = await ax.frame(of: window)
        try? await Task.sleep(nanoseconds: 120_000_000)
        let second = await ax.frame(of: window)
        let stable = framesMatch(first, second, tolerance: 2)
        return WindowOrganizeApplication(
            actualFrameAX: second ?? first,
            behavior: WindowOrganize.behavior(actual: second ?? first, target: target, stable: stable)
        )
    }

    func applyWorkspaceFrame(_ target: CGRect, to window: AXWindow) async -> WindowOrganizeApplication {
        await applyOrganizeFrame(target, to: window)
    }

    func cachedOrganizeBehavior(for identity: WindowIdentity) -> WindowOrganizeWindowBehavior? {
        organizeBehaviorCache[identity]
    }

    func cacheOrganizeBehavior(_ behavior: WindowOrganizeWindowBehavior, for identity: WindowIdentity) {
        organizeBehaviorCache[identity] = behavior
    }

    private func framesMatch(_ lhs: CGRect?, _ rhs: CGRect?, tolerance: CGFloat) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func showOrganizeFeedback(
        issues: [WindowOrganizeIssue],
        skipped: [WindowIdentity],
        failed: Bool,
        rollbackFailed: [WindowIdentity] = [],
        area: WorkArea
    ) {
        guard let screen = displays.screen(for: area.display.id) else { return }
        let namedIssues = uniqueFeedbackIssues(issues)
        let primaryIssue = namedIssues.first
        let appName = primaryIssue.map { applicationName(for: $0.identity) }
        let title: String
        let detail: String

        if !rollbackFailed.isEmpty {
            title = L10n.text(.organizeFailedTitle)
            detail = L10n.text(.organizeRestoreFailedDetail)
        } else if failed {
            title = L10n.text(skipped.isEmpty ? .organizeFailedTitle : .organizeNoWindowsTitle)
            detail = feedbackDetail(for: namedIssues) ?? L10n.text(.organizeRestoredDetail)
        } else if !namedIssues.isEmpty {
            let hasFixed = namedIssues.contains { $0.behavior != .sizeConstrained }
            title = hasFixed ? L10n.text(.organizePartialTitle) : L10n.text(.organizeAdjustedTitle)
            detail = feedbackDetail(for: namedIssues) ?? L10n.organizeSkipped(skipped.count)
        } else {
            title = L10n.text(.organizePartialTitle)
            detail = L10n.organizeSkipped(skipped.count)
        }

        let ignoredBundle = primaryIssue?.identity.bundleID
        organizeFeedback.show(
            OrganizeFeedback(
                tone: failed || !rollbackFailed.isEmpty ? .error : .warning,
                title: title,
                detail: detail,
                restoreTitle: lastOrganizeSnapshot.isEmpty ? nil : L10n.text(.organizeRestoreAction),
                ignoreTitle: ignoredBundle == nil || appName == nil ? nil : L10n.organizeIgnore(appName!),
                onRestore: lastOrganizeSnapshot.isEmpty ? nil : { [weak self] in
                    Task { @MainActor in await self?.restoreLastOrganize(on: area) }
                },
                onIgnore: ignoredBundle.map { bundleID in
                    { [weak self] in self?.ignoreApplication(bundleID, name: appName ?? bundleID, on: area) }
                }
            ),
            on: screen
        )
    }

    private func issueDetail(_ issue: WindowOrganizeIssue, appName: String) -> String {
        switch issue.behavior {
        case .sizeConstrained:
            L10n.organizeNeedsSpace(appName)
        case .positionConstrained, .immutable, .unstable, .compliant:
            L10n.organizeKeptInPlace(appName)
        }
    }

    private func uniqueFeedbackIssues(_ issues: [WindowOrganizeIssue]) -> [WindowOrganizeIssue] {
        var seen = Set<String>()
        return issues.filter { issue in
            let name = applicationName(for: issue.identity)
            return seen.insert("\(issue.behavior.rawValue)|\(name)").inserted
        }
    }

    private func feedbackDetail(for issues: [WindowOrganizeIssue]) -> String? {
        let parts = issues.map { issueDetail($0, appName: applicationName(for: $0.identity)) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func applicationName(for identity: WindowIdentity) -> String {
        NSRunningApplication(processIdentifier: identity.pid)?.localizedName
            ?? identity.bundleID
            ?? L10n.text(.organizeNoWindowsTitle)
    }

    private func restoreLastOrganize(on area: WorkArea) async {
        let snapshot = lastOrganizeSnapshot
        lastOrganizeSnapshot = [:]
        var failed = false
        for entry in snapshot.values {
            let restored = await applyOrganizeFrame(entry.frame, to: entry.window)
            if restored.behavior != .compliant { failed = true }
        }
        guard let screen = displays.screen(for: area.display.id) else { return }
        organizeFeedback.show(
            OrganizeFeedback(
                tone: failed ? .error : .warning,
                title: L10n.text(failed ? .organizeFailedTitle : .organizeRestoredTitle),
                detail: L10n.text(failed ? .organizeRestoreFailedDetail : .organizeRestoredDetail)
            ),
            on: screen
        )
    }

    private func ignoreApplication(_ bundleID: String, name: String, on area: WorkArea) {
        guard !settings.excludedBundleIDs.contains(bundleID) else { return }
        settings.excludedBundleIDs.append(bundleID)
        persistSettings()
        organizeBehaviorCache = organizeBehaviorCache.filter { $0.key.bundleID != bundleID }
        guard let screen = displays.screen(for: area.display.id) else { return }
        organizeFeedback.show(
            OrganizeFeedback(
                tone: .warning,
                title: L10n.text(.organizeIgnoredTitle),
                detail: L10n.organizeIgnored(name)
            ),
            on: screen
        )
    }

    private func snappableWindows(on area: WorkArea) async -> [AXWindow] {
        var seen = Set<WindowIdentity>()
        var windows: [AXWindow] = []
        for ref in query.windows(excludingPID: ProcessInfo.processInfo.processIdentifier) {
            guard let window = await ax.resolveAsync(ref: ref) else { continue }
            guard !seen.contains(window.identity) else { continue }
            guard let frameAX = await ax.frame(of: window) else { continue }
            guard let owner = DisplayTargetResolver.workArea(
                containingWindowFrameAX: frameAX,
                from: displays.workAreas,
                primaryFlipHeight: displays.primaryFlipHeight
            ), owner.display.id == area.display.id else { continue }
            seen.insert(window.identity)
            windows.append(window)
        }
        return windows
    }

    private func flashZones(
        area: WorkArea,
        layout: Layout,
        duration: TimeInterval,
        workAreaAX: CGRect? = nil,
        showName: Bool = false
    ) {
        previewHideWorkItem?.cancel()
        previewHideWorkItem = nil
        let workAX = workAreaAX ?? CoordinateConverter.axRect(
            fromAppKit: area.visibleFrameAppKit,
            primaryFlipHeight: displays.primaryFlipHeight
        )
        let zones = (try? resolveLayout(layout, workAreaAX: workAX, gutter: CGFloat(settings.gutterPoints))) ?? []
        overlay.settings = settings
        overlay.primaryFlipHeight = displays.primaryFlipHeight
        let presentation = OverlayPresentation(
            layoutName: showName ? L10n.layoutDisplayName(layout.name) : nil
        )
        let displayID = area.display.id
        let present: () -> Void = { [weak self] in
            guard let self else { return }
            if showName {
                self.overlay.showPreview(
                    displayID: displayID,
                    zones: zones,
                    presentation: presentation
                )
            } else {
                self.overlay.show(
                    displayID: displayID,
                    zones: zones,
                    highlight: .none,
                    presentation: presentation
                )
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if showName {
                    if self.overlay.isPreviewVisible {
                        self.overlay.hideAll()
                    }
                } else if !self.engine.isSessionActive {
                    self.overlay.hideAll()
                }
                self.previewHideWorkItem = nil
            }
            self.previewHideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
        if showName {
            DispatchQueue.main.async { present() }
        } else {
            present()
        }
    }

    func flashWorkspaceZones(area: WorkArea, layout: Layout) {
        flashZones(area: area, layout: layout, duration: 1.2)
    }

    func openAccessibility() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(runtime: self)
        }
        onboarding?.show()
    }

    func accessibilityGranted() {
        drag.stop()
        drag.start()
        hotkeys.reregister()
        refreshTrustChrome()
        Log.trust.info("Accessibility granted")
    }

    func accessibilityGuideClosed() {
        onboarding = nil
        refreshTrustChrome()
    }

    func refreshTrustChrome() {
        menuBar?.reloadMenu()
        menuBar?.updateTrustAppearance()
        settingsWindow?.refreshAccessStatus()
    }

    func noteQuickSnapperUI(showing: Bool) {
        if showing, !quickSnapperUIActive {
            quickSnapperUIActive = true
            uiSession.enterRegular()
        } else if !showing, quickSnapperUIActive {
            quickSnapperUIActive = false
            uiSession.leaveRegular()
        }
    }

    func resolvedZones(for area: WorkArea?) -> [ResolvedZone] {
        resolvedZones(for: area, layoutOverride: nil)
    }

    func gridCoverage(for area: WorkArea?) -> (cells: [GridCell], gutter: CGFloat, workAreaAX: CGRect) {
        gridCoverage(for: area, layoutOverride: nil)
    }

    func resolvedZones(for area: WorkArea?, layoutOverride: Layout.ID?) -> [ResolvedZone] {
        guard let area, let layout = layout(for: area, override: layoutOverride) else { return [] }
        return cachedResolvedZones(layout: layout, area: area)
    }

    func gridCoverage(
        for area: WorkArea?,
        layoutOverride: Layout.ID?
    ) -> (cells: [GridCell], gutter: CGFloat, workAreaAX: CGRect) {
        let gutter = CGFloat(settings.gutterPoints)
        guard let area else { return ([], gutter, .null) }
        guard let layout = layout(for: area, override: layoutOverride),
              layout.kind == .grid,
              let spec = layout.grid
        else {
            return ([], gutter, .null)
        }
        let workAX = CoordinateConverter.axRect(
            fromAppKit: area.visibleFrameAppKit,
            primaryFlipHeight: displays.primaryFlipHeight
        )
        return (GridCoverage.cells(spec: spec, workAreaAX: workAX), gutter, workAX)
    }

    func allResolvedLayouts(for area: WorkArea?) -> [(layout: Layout, zones: [ResolvedZone])] {
        guard let area else { return [] }
        let assignedID = document.layout(for: area.display.id)?.id
        return document.orderedLayouts(assignedID: assignedID).compactMap { layout in
            let zones = cachedResolvedZones(layout: layout, area: area)
            guard !zones.isEmpty else { return nil }
            return (layout, zones)
        }
    }

    func markLayoutUsed(_ id: Layout.ID) {
        document.markLayoutUsed(id)
    }

    func setShowLayoutStrip(_ enabled: Bool) {
        settings.showLayoutStrip = enabled
        persistSettings()
    }

    func setPreviewLayoutOnSelect(_ enabled: Bool) {
        settings.previewLayoutOnSelect = enabled
        persistSettings()
        if !enabled {
            previewHideWorkItem?.cancel()
            previewHideWorkItem = nil
            if !engine.isSessionActive {
                overlay.hideAll()
            }
        }
    }

    func invalidateResolvedLayoutCache() {
        resolvedLayoutCache.removeAll()
    }

    private func layout(for area: WorkArea, override: Layout.ID?) -> Layout? {
        if let override {
            return document.layouts.first(where: { $0.id == override })
        }
        return document.layout(for: area.display.id)
    }

    private func cachedResolvedZones(layout: Layout, area: WorkArea) -> [ResolvedZone] {
        let workAX = CoordinateConverter.axRect(
            fromAppKit: area.visibleFrameAppKit,
            primaryFlipHeight: displays.primaryFlipHeight
        )
        let key = ResolvedLayoutCacheKey(
            layoutID: layout.id,
            displayID: area.display.id,
            gutter: settings.gutterPoints,
            width: Int(workAX.width.rounded()),
            height: Int(workAX.height.rounded()),
            updatedAt: layout.updatedAt.timeIntervalSinceReferenceDate
        )
        if let cached = resolvedLayoutCache[key] {
            return cached
        }
        let zones = (try? resolveLayout(layout, workAreaAX: workAX, gutter: CGFloat(settings.gutterPoints))) ?? []
        resolvedLayoutCache[key] = zones
        return zones
    }

    func resolvedZones(layout: Layout, area: WorkArea) -> [ResolvedZone] {
        cachedResolvedZones(layout: layout, area: area)
    }

    func persist() {
        invalidateResolvedLayoutCache()
        try? layoutStore.save(document)
        persistSettings()
    }

    func persistSettings() {
        try? settingsStore.save(settings)
        overlay.settings = settings
        overlay.primaryFlipHeight = displays.primaryFlipHeight
        if overlay.isVisible {
            overlay.refreshVisible()
        }
        editor?.applySettings(settings)
        settingsWindow?.refreshPreview()
    }

    func setHoverPinEnabled(_ enabled: Bool) {
        settings.hoverPinEnabled = enabled
        persistSettings()
        pinHover.settingsChanged()
        if !enabled { pinHover.hideImmediately() }
    }

    func setHotkeyRecording(_ recording: Bool) {
        hotkeys.setRecordingPaused(recording)
    }

    func updateHotkey(_ id: ShortcutCustomizationID, to chord: KeyChord) -> ShortcutBindingIssue? {
        if let issue = ShortcutCatalog.validate(chord, replacing: id, in: settings) {
            return issue
        }
        settings = ShortcutCatalog.applying(chord, to: id, in: settings)
        persistSettings()
        hotkeys.reregister()
        shortcutPanel?.applyLanguage()
        return nil
    }

    func resetHotkey(_ id: ShortcutCustomizationID) -> ShortcutBindingIssue? {
        updateHotkey(id, to: ShortcutCatalog.chord(for: id, in: .default))
    }

    func resetAllHotkeys() {
        settings = ShortcutCatalog.resettingAll(in: settings)
        persistSettings()
        hotkeys.reregister()
        shortcutPanel?.applyLanguage()
    }

    func applyLanguage() {
        menuBar?.reloadMenu()
        menuBar?.updateTrustAppearance()
        pins.refreshAppearance()
        pinHover.refreshAppearance()
        settingsWindow?.applyLanguage()
        onboarding?.applyLanguage()
        editor?.applyLanguage()
        shortcutPanel?.applyLanguage()
    }

    func setUILanguage(_ preference: AppLanguagePreference) {
        settings.uiLanguage = preference
        persistSettings()
        LanguageCenter.shared.applyPreference(preference)
    }

    private func observeSystem() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let runtime = self else { return }
            Task { @MainActor in
                runtime.displays.refresh(document: &runtime.document)
                runtime.overlay.rebuild(workAreas: runtime.displays.workAreas, screens: NSScreen.screens)
                runtime.invalidateResolvedLayoutCache()
                runtime.persist()
                runtime.workspace.displaysDidChange()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            guard let runtime = self else { return }
            Task { @MainActor in
                if let pid {
                    runtime.catalog.drop(pid: pid)
                    runtime.pins.drop(pid: pid)
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    runtime.workspace.applicationDidTerminate(pid: pid, bundleID: app?.bundleIdentifier)
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let runtime = self else { return }
            Task { @MainActor in
                runtime.hideAllOverlays()
                runtime.workspace.pause()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let runtime = self else { return }
            Task { @MainActor in runtime.workspace.resume() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let runtime = self else { return }
            Task { @MainActor in
                runtime.hideAllOverlays()
                runtime.workspace.pause()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let runtime = self else { return }
            Task { @MainActor in runtime.workspace.resume() }
        }
    }
}

private struct ResolvedLayoutCacheKey: Hashable {
    var layoutID: Layout.ID
    var displayID: DisplayIdentity.ID
    var gutter: Int
    var width: Int
    var height: Int
    var updatedAt: TimeInterval
}

private struct PendingLayoutPreview {
    var layout: Layout
    var area: WorkArea
}
