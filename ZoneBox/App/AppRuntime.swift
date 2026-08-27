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
            Task { @MainActor in self?.applyLanguage() }
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
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let area = displays.area(containingAppKit: NSEvent.mouseLocation)
        let layout = (area.flatMap { document.layout(for: $0.display.id) }) ?? document.layouts.first ?? LayoutTemplates.columns(2)
        editor = LayoutEditorController(runtime: self, layout: layout)
        editor?.show(on: screen)
    }

    func editorDidClose() {
        editor = nil
        menuBar?.reloadMenu()
    }

    func cancelEditor() {
        editor?.cancelEditing()
    }

    func saveLayout(_ layout: Layout) {
        if let idx = document.layouts.firstIndex(where: { $0.id == layout.id }) {
            document.layouts[idx] = layout
        } else {
            document.layouts.append(layout)
        }
        if let area = displays.area(containingAppKit: NSEvent.mouseLocation) {
            document.assign(layoutID: layout.id, to: area.display.id)
        }
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
        let layout = LayoutTemplates.emptyCanvas(name: "Canvas \(document.layouts.count + 1)")
        document.layouts.append(layout)
        selectLayout(layout)
        openEditor()
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
    }

    func setUILanguage(_ preference: AppLanguagePreference) {
        settings.uiLanguage = preference
        persistSettings()
        LanguageCenter.shared.applyPreference(preference)
    }

    private func observeSystem() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.displays.refresh(document: &self.document)
                self.overlay.rebuild(workAreas: self.displays.workAreas, screens: NSScreen.screens)
                self.persist()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor in
                if let pid { self?.catalog.drop(pid: pid) }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.overlay.hideAll() }
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.overlay.hideAll() }
        }
    }
}
