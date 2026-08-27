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
            "Trust status=\(String(describing: self.trust.status()), privacy: .public) path=\(TrustMonitor.currentBuildPath, privacy: .public)"
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
        }
        uiSession.enterRegular()
        settingsWindow?.showWindow()
    }

    func settingsDidClose() {
        settingsWindow = nil
        persistSettings()
        hotkeys.reregister()
        menuBar?.reloadMenu()
    }

    func openEditor() {
        guard editor == nil else {
            editor?.activate()
            return
        }
        guard let target = editorTarget() else { return }
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

    @discardableResult
    func closeShortcutPanelIfOpen() -> Bool {
        guard shortcutPanel != nil else { return false }
        shortcutPanel?.close()
        return true
    }

    func shortcutPanelDidClose() {
        guard shortcutPanel != nil else { return }
        shortcutPanel = nil
        uiSession.leaveRegular()
    }

    func saveLayout(_ layout: Layout, to displayID: DisplayIdentity.ID) {
        document.upsertAndAssign(layout, to: displayID)
        persist()
        menuBar?.reloadMenu()
    }

    func selectLayout(_ layout: Layout) {
        if let area = displays.area(containingAppKit: NSEvent.mouseLocation) {
            document.assign(layoutID: layout.id, to: area.display.id)
            persist()
            menuBar?.reloadMenu()
        }
    }

    func newCanvasLayout() {
        guard editor == nil else {
            editor?.activate()
            return
        }
        guard let target = editorTarget() else { return }
        let name = LayoutEditTransaction.uniqueName(
            base: "Canvas \(document.layouts.count + 1)",
            existingNames: document.layouts.map(\.name)
        )
        beginEditing(LayoutTemplates.emptyCanvas(name: name), isNew: true, target: target)
    }

    private typealias EditorTarget = (screen: NSScreen, area: WorkArea)

    private func editorTarget() -> EditorTarget? {
        let point = NSEvent.mouseLocation
        guard let area = displays.area(containingAppKit: point) ?? displays.workAreas.first else { return nil }
        let screen = NSScreen.screens.first(where: {
            abs($0.frame.minX - area.frameAppKit.minX) < 1
                && abs($0.frame.minY - area.frameAppKit.minY) < 1
                && abs($0.frame.width - area.frameAppKit.width) < 1
                && abs($0.frame.height - area.frameAppKit.height) < 1
        }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return nil }
        return (screen, area)
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
        guard let area = displays.area(containingAppKit: NSEvent.mouseLocation) else { return }
        let zones = resolvedZones(for: area)
        overlay.settings = settings
        overlay.primaryFlipHeight = displays.primaryFlipHeight
        overlay.show(displayID: area.display.id, zones: zones, highlight: .none)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.overlay.hideAll()
        }
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

    func snapAdjacent(delta: Int) {
        Task { @MainActor in
            guard let window = await ax.focusedWindow() else { return }
            let area = displays.area(containingAppKit: NSEvent.mouseLocation)
            let zones = resolvedZones(for: area).sorted { $0.number < $1.number }
            guard !zones.isEmpty else { return }
            let current = catalog.zoneID(for: window.identity)
            let idx = zones.firstIndex(where: { $0.zoneID == current }) ?? 0
            let next = zones[(idx + delta + zones.count) % zones.count]
            engine.snapFocused(to: next.number)
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
