import AppKit
import ZoneBoxCore

@MainActor
protocol RuntimeModeOwning: AnyObject {
    var mode: RuntimeMode { get }
    var isEditorOpen: Bool { get }
    var isOrganizingWindows: Bool { get }
    func allows(_ capability: RuntimeCapability) -> Bool
    func begin(_ request: RuntimeModeRequest) -> Bool
    func end(_ request: RuntimeModeRequest)
}

@MainActor
protocol RuntimeTrusting: AnyObject {
    func isTrusted() -> Bool
}

@MainActor
protocol RuntimeDisplayCatalog: AnyObject {
    var workAreas: [WorkArea] { get }
    var primaryFlipHeight: CGFloat { get }
    func area(containingAppKit point: CGPoint) -> WorkArea?
    func isActive(displayID: DisplayIdentity.ID) -> Bool
    func screen(for displayID: DisplayIdentity.ID) -> NSScreen?
}

@MainActor
protocol RuntimeSettingsReading: AnyObject {
    var settings: AppSettings { get }
}

@MainActor
protocol RuntimeWindowCataloging: AnyObject {
    var catalog: WindowCatalog { get }
}

@MainActor
protocol RuntimeLayoutMutating: AnyObject {
    var document: StoreDocument { get set }
    func persist()
    func saveLayout(_ layout: Layout, to displayID: DisplayIdentity.ID) -> Bool
    func resolvedZones(for area: WorkArea?) -> [ResolvedZone]
    func resolvedZones(for area: WorkArea?, layoutOverride: Layout.ID?) -> [ResolvedZone]
    func resolvedZones(layout: Layout, area: WorkArea) -> [ResolvedZone]
    func allResolvedLayouts(for area: WorkArea?) -> [(layout: Layout, zones: [ResolvedZone])]
    func gridCoverage(for area: WorkArea?, layoutOverride: Layout.ID?) -> (cells: [GridCell], gutter: CGFloat, workAreaAX: CGRect)
    func markLayoutUsed(_ id: Layout.ID)
}

@MainActor
protocol RuntimeWindowMutating: AnyObject {
    var ax: AccessibilityClientLive { get }
    func applyFrame(_ frame: CGRect, of window: AXWindow, sessionID: UUID, generation: Int) async -> CGRect?
    func applyWorkspaceFrame(_ target: CGRect, to window: AXWindow, sessionID: UUID, generation: Int) async -> WindowOrganizeApplication
    func raise(_ window: AXWindow, sessionID: UUID, generation: Int) async -> AXError
    func cancelMutations(sessionID: UUID)
    func finishMutations(sessionID: UUID)
}

@MainActor
protocol RuntimeChromeNotifying: AnyObject {
    func hideLiveOverlays()
    func refreshDivider()
    func reloadMenu()
    func closeConsole()
    func noteUserSnapCompleted()
    func noteSnapSessionBecameIdle()
    func noteQuickSnapperUI(showing: Bool)
}

@MainActor
protocol SnapRuntimeHosting: RuntimeModeOwning, RuntimeTrusting, RuntimeDisplayCatalog, RuntimeSettingsReading, RuntimeWindowCataloging, RuntimeLayoutMutating, RuntimeWindowMutating, RuntimeChromeNotifying {
    var overlay: OverlayController { get }
    var pendingWindow: AXWindow? { get set }
    var pendingFrame: CGRect? { get set }
    var pendingStartedOnMoveChrome: Bool { get set }
    var pendingIdentity: WindowIdentity? { get set }
    func focusedWindowTarget() async -> (window: AXWindow, frameAX: CGRect, area: WorkArea)?
}

@MainActor
protocol DragRuntimeHosting: RuntimeModeOwning, RuntimeTrusting, RuntimeDisplayCatalog, RuntimeWindowMutating {
    var pendingWindow: AXWindow? { get set }
    var pendingFrame: CGRect? { get set }
    var pendingStartedOnMoveChrome: Bool { get set }
    var pendingIdentity: WindowIdentity? { get set }
    var engine: SnapEngine { get }
    var pinHover: PinHoverMonitor { get }
    var divider: DividerController { get }
    func isSnappableOwnWindow(_ number: CGWindowID) -> Bool
}

@MainActor
protocol DividerRuntimeHosting: RuntimeModeOwning, RuntimeTrusting, RuntimeDisplayCatalog, RuntimeSettingsReading, RuntimeWindowCataloging, RuntimeLayoutMutating, RuntimeWindowMutating {}

@MainActor
protocol PinRuntimeHosting: RuntimeModeOwning, RuntimeTrusting, RuntimeDisplayCatalog, RuntimeWindowMutating, RuntimeChromeNotifying {
    var pinHover: PinHoverMonitor { get }
    var uiSession: UISession { get }
}

@MainActor
protocol PinHoverRuntimeHosting: RuntimeModeOwning, RuntimeTrusting, RuntimeDisplayCatalog, RuntimeSettingsReading, RuntimeWindowMutating {
    var pins: PinCenter { get }
}

@MainActor
protocol WorkspaceRuntimeHosting: RuntimeModeOwning, RuntimeTrusting, RuntimeDisplayCatalog, RuntimeSettingsReading, RuntimeWindowCataloging, RuntimeLayoutMutating, RuntimeWindowMutating, RuntimeChromeNotifying {
    var query: CGWindowQuery { get }
    var organizeFeedback: OrganizeFeedbackController { get }
    func openAccessibility()
    func beginWindowTransaction() -> Bool
    func finishWindowTransaction()
    func flashWorkspaceZones(area: WorkArea, layout: Layout)
    func refreshWorkspaceSettings()
    func cacheOrganizeBehavior(_ behavior: WindowOrganizeWindowBehavior, for identity: WindowIdentity)
}

@MainActor
protocol HotkeyRuntimeHosting: RuntimeModeOwning, RuntimeTrusting, RuntimeSettingsReading {
    var engine: SnapEngine { get }
    var divider: DividerController { get }
    var workspace: WorkspaceCenter { get }
    var editorClaimsKeyboard: Bool { get }
    var isEditorEditingMetrics: Bool { get }
    var shortcutPanelIsKey: Bool { get }
    var isRecordingHotkey: Bool { get }
    var settingsIsKey: Bool { get }
    var onboardingIsKey: Bool { get }
    var consoleIsVisible: Bool { get }
    func handleEditorKey(_ event: NSEvent) -> Bool
    func openEditorForFocusedWindow()
    func organizeWindowsFromHotkey()
    func toggleShortcutPanel()
    func cancelEditor()
    func cancelHotkeyRecordingIfNeeded() -> Bool
    func closeShortcutPanelIfOpen() -> Bool
    func closeSettingsIfOpen() -> Bool
    func closeOnboardingIfOpen() -> Bool
    func closeConsoleIfOpen() -> Bool
    func reloadMenu()
}
