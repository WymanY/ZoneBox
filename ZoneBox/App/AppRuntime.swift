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

    let uiSession = UISession()
    let trust = TrustMonitor()
    let displays = DisplayWatcher()
    let overlay = OverlayController()
    let catalog = WindowCatalog()
    let engine = SnapEngine()
    let drag = DragMonitor()
    let hotkeys = HotkeyCenter()
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
        overlay.hideAll()
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
        overlay.hideAll()
    }

    var snapEnabled: Bool { settings.snapEnabled }

    func setSnapEnabled(_ enabled: Bool) {
        settings.snapEnabled = enabled
        persistSettings()
        menuBar?.reloadMenu()
        if !enabled { overlay.hideAll() }
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(runtime: self)
            uiSession.enterRegular()
        }
        settingsWindow?.showWindow()
    }

    func settingsDidClose() {
        guard settingsWindow != nil else { return }
        settingsWindow = nil
        persistSettings()
        hotkeys.reregister()
        menuBar?.reloadMenu()
        uiSession.leaveRegular()
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

    @discardableResult
    func handleEditorKey(_ event: NSEvent) -> Bool {
        let modifiers = KeyEventBridge.carbonModifiers(from: event.modifierFlags)
        if ShortcutCatalog.editorSaveChord.matches(
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

    @discardableResult
    func closeShortcutPanelIfOpen() -> Bool {
        guard shortcutPanelIsKey else { return false }
        shortcutPanel?.close()
        return true
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
        persist()
        menuBar?.reloadMenu()
        return true
    }

    func selectLayout(_ layout: Layout) {
        if let area = displays.area(containingAppKit: NSEvent.mouseLocation),
           displays.isActive(displayID: area.display.id) {
            document.assign(layoutID: layout.id, to: area.display.id)
            persist()
            menuBar?.reloadMenu()
        }
    }

    @discardableResult
    func deleteLayout(_ layout: Layout) -> Bool {
        let deleted = document.deleteLayout(id: layout.id)
        guard deleted else { return false }
        persist()
        menuBar?.reloadMenu()
        if editor?.originalLayoutID == layout.id {
            editor?.cancelEditing()
        }
        return true
    }

    func newCanvasLayout() {
        guard editor == nil else {
            editor?.activate()
            return
        }
        guard let target = pointerEditorTarget() else { return }
        let name = LayoutEditTransaction.uniqueName(
            base: "Canvas \(document.layouts.count + 1)",
            existingNames: document.layouts.map(\.name)
        )
        beginEditing(LayoutTemplates.emptyCanvas(name: name), isNew: true, target: target)
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
        let controller = LayoutEditorController(
            runtime: self,
            layout: layout,
            targetDisplayID: target.area.display.id,
            isNew: isNew
        )
        editor = controller
        controller.show(on: target.screen)
    }

    func previewZones() {
        previewHideWorkItem?.cancel()
        previewHideWorkItem = nil
        guard let area = displays.area(containingAppKit: NSEvent.mouseLocation),
              let layout = document.layout(for: area.display.id)
        else { return }
        let workAX = CoordinateConverter.axRect(
            fromAppKit: area.visibleFrameAppKit,
            primaryFlipHeight: displays.primaryFlipHeight
        )
        let zones = (try? resolveLayout(layout, workAreaAX: workAX, gutter: CGFloat(settings.gutterPoints))) ?? []
        overlay.settings = settings
        overlay.primaryFlipHeight = displays.primaryFlipHeight
        overlay.show(displayID: area.display.id, zones: zones, highlight: .none)
        let work = DispatchWorkItem { [weak self] in
            self?.overlay.hideAll()
            self?.previewHideWorkItem = nil
        }
        previewHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
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
        guard let area else { return [] }
        guard let layout = document.layout(for: area.display.id) else { return [] }
        let workAX = CoordinateConverter.axRect(
            fromAppKit: area.visibleFrameAppKit,
            primaryFlipHeight: displays.primaryFlipHeight
        )
        return (try? resolveLayout(layout, workAreaAX: workAX, gutter: CGFloat(settings.gutterPoints))) ?? []
    }

    func gridCoverage(for area: WorkArea?) -> (cells: [GridCell], gutter: CGFloat, workAreaAX: CGRect) {
        let gutter = CGFloat(settings.gutterPoints)
        guard let area else { return ([], gutter, .null) }
        guard let layout = document.layout(for: area.display.id), layout.kind == .grid, let spec = layout.grid else {
            return ([], gutter, .null)
        }
        let workAX = CoordinateConverter.axRect(
            fromAppKit: area.visibleFrameAppKit,
            primaryFlipHeight: displays.primaryFlipHeight
        )
        return (GridCoverage.cells(spec: spec, workAreaAX: workAX), gutter, workAX)
    }

    func persist() {
        try? layoutStore.save(document)
        persistSettings()
    }

    func persistSettings() {
        try? settingsStore.save(settings)
    }

    func applyLanguage() {
        menuBar?.reloadMenu()
        menuBar?.updateTrustAppearance()
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
                runtime.persist()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            guard let runtime = self else { return }
            Task { @MainActor in
                if let pid { runtime.catalog.drop(pid: pid) }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let runtime = self else { return }
            Task { @MainActor in runtime.overlay.hideAll() }
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let runtime = self else { return }
            Task { @MainActor in runtime.overlay.hideAll() }
        }
    }
}
