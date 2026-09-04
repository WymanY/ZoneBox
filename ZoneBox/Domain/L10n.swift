import Foundation

public enum AppLanguagePreference: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case english
    case chineseSimplified
}

public enum AppLanguage: String, Sendable, Equatable, CaseIterable {
    case english = "en"
    case chineseSimplified = "zh-Hans"

    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .chineseSimplified: Locale(identifier: "zh_CN")
        }
    }

    /// First supported language in the preferred list; Chinese (any script) maps to Simplified.
    public static func resolve(preferred: [String]) -> AppLanguage {
        for raw in preferred {
            let lower = raw.replacingOccurrences(of: "_", with: "-").lowercased()
            if lower == "zh" || lower.hasPrefix("zh-") { return .chineseSimplified }
            let code = Locale(identifier: raw).language.languageCode?.identifier.lowercased()
            if code == "zh" { return .chineseSimplified }
            if code == "en" || lower == "en" || lower.hasPrefix("en-") { return .english }
        }
        return .english
    }
}

public enum L10nKey: String, Sendable, CaseIterable {
    case statusTooltip
    case statusTooltipNeedsAccess
    case menuEnableAccessibility
    case menuSnapEnabled
    case menuHotkeysPausedVO
    case menuOrganizeWindows
    case menuOpenEditor
    case menuPreviewZones
    case menuLayouts
    case menuWorkspaces
    case menuCaptureWorkspace
    case menuUpdateActiveWorkspace
    case menuManageWorkspaces
    case menuNewCanvas
    case menuNewGrid
    case menuDeleteLayout
    case menuDeleteLayoutTitle
    case menuDeleteLayoutMessage
    case menuDeleteLayoutConfirm
    case menuSettings
    case menuKeyboardShortcuts
    case menuQuit
    case menuUnpinAllWindows
    case pinOnTop
    case pinUnpin
    case pinScreenRecordingTitle
    case pinScreenRecordingMessage
    case pinScreenRecordingRequest
    case consoleSnap
    case consoleOrganize
    case consoleEdit
    case consolePreview
    case consoleNew
    case consoleNoDisplay
    case consoleCurrentDisplay
    case consoleOtherLayouts
    case organizeAdjustedTitle
    case organizePartialTitle
    case organizeFailedTitle
    case organizeNoWindowsTitle
    case organizeNeedsSpaceDetail
    case organizeKeptInPlaceDetail
    case organizeSkippedDetail
    case organizeRestoredDetail
    case organizeRestoreFailedDetail
    case organizeRestoredTitle
    case organizeIgnoredTitle
    case organizeIgnoredDetail
    case organizeRestoreAction
    case organizeIgnoreAction
    case organizeClose
    case workspaceNameTitle
    case workspaceNameMessage
    case workspaceNamePlaceholder
    case workspaceSave
    case workspaceDefaultName
    case workspaceCapturedTitle
    case workspaceUpdatedTitle
    case workspaceCapturedDetail
    case workspaceCaptureEmptyTitle
    case workspaceCaptureEmptyDetail
    case workspaceAppliedTitle
    case workspaceApplyPartialTitle
    case workspaceMovedDetail
    case workspaceSizeConstrainedDetail
    case workspaceMissingDetail
    case workspaceStaleDetail
    case workspaceDisplaysSkippedDetail
    case workspaceWindowsSkippedDetail
    case workspaceAppMissingTitle
    case workspaceAppNotInstalledDetail
    case workspaceLaunchTimeoutDetail
    case workspaceLayoutDeleteImpact

    case settingsTitle
    case settingsAccessBanner
    case settingsShowGuide
    case settingsEnableSnapping
    case settingsShiftDrag
    case settingsRightClick
    case settingsShakeToSnap
    case settingsShakeIntensity
    case settingsShakeIntensityHint
    case settingsQuickSnapper
    case settingsMagneticResize
    case settingsShowNumbers
    case settingsRestoreSize
    case settingsGutter
    case settingsHotkeys
    case settingsOpenAccess
    case settingsLaunchAtLogin
    case settingsHoverPin
    case settingsBeta
    case settingsLanguage
    case settingsLanguageSystem
    case settingsLanguageEnglish
    case settingsLanguageChinese
    case settingsShowShortcuts
    case settingsSectionGeneral
    case settingsSectionSnapping
    case settingsSectionOverlay
    case settingsSectionKeyboard
    case settingsSectionWorkspaces
    case settingsGeneralSubtitle
    case settingsSnappingSubtitle
    case settingsOverlaySubtitle
    case settingsKeyboardSubtitle
    case settingsWorkspacesSubtitle
    case settingsLanguageDetail
    case settingsLaunchAtLoginDetail
    case settingsHoverPinDetail
    case settingsShiftDragDetail
    case settingsRightClickDetail
    case settingsShakeToSnapDetail
    case settingsMagneticResizeDetail
    case settingsRestoreSizeDetail
    case settingsQuickSnapperDetail
    case settingsShowNumbersDetail
    case settingsGutterDetail
    case settingsShowLayoutStrip
    case settingsShowLayoutStripDetail
    case settingsPreviewLayoutOnSelect
    case settingsPreviewLayoutOnSelectDetail
    case settingsSnappingTriggersSection
    case settingsSnappingBehaviorSection
    case settingsGeneralPreviewTitle
    case settingsSnappingPreviewTitle
    case settingsOverlayPreviewTitle
    case settingsKeyboardPreviewTitle
    case settingsWorkspacesPreviewTitle
    case settingsGeneralPreviewDescription
    case settingsSnappingPreviewDescription
    case settingsOverlayPreviewDescription
    case settingsKeyboardPreviewDescription
    case settingsWorkspacesPreviewDescription
    case settingsWorkspaceEmpty
    case settingsWorkspaceLaunchMissing
    case settingsWorkspaceRename
    case settingsWorkspaceDelete
    case settingsWorkspaceDeleteTitle
    case settingsWorkspaceRecapture
    case settingsWorkspaceSummary
    case settingsWorkspaceShowDetails
    case settingsWorkspaceHideDetails
    case settingsWorkspaceSectionSummary
    case settingsWorkspaceZone
    case settingsWorkspaceUnavailableDisplay
    case settingsWorkspaceUnavailableLayout
    case settingsWorkspaceActive
    case settingsAccessGranted
    case settingsAccessRequired
    case settingsManageAccess
    case settingsHotkeyCaptureHint
    case settingsHotkeyRecording
    case settingsResetShortcut
    case settingsResetAllShortcuts
    case settingsQuickSnapperToggle
    case shortcutErrorSequoia
    case shortcutErrorDuplicate
    case shortcutErrorReserved

    case shortcutsTitle
    case shortcutsSectionGlobal
    case shortcutsSectionEditor
    case shortcutsSectionSnap
    case shortcutsSectionApp
    case shortcutsVoiceOverNote
    case shortcutsSubtitle
    case shortcutOpenEditor
    case shortcutSnapZone
    case shortcutSnapZones
    case shortcutPreviousZone
    case shortcutNextZone
    case shortcutCycleBackward
    case shortcutCycleForward
    case shortcutUnsnap
    case shortcutShowShortcuts
    case shortcutQuickSnapper
    case shortcutOrganizeWindows
    case shortcutApplyWorkspace
    case shortcutEditorCancel
    case shortcutEditorCycle
    case shortcutEditorCycleBack
    case shortcutEditorDelete
    case shortcutEditorSave
    case shortcutEditorUndo
    case shortcutEditorRedo
    case shortcutEditorNewPane
    case shortcutEditorDuplicate
    case shortcutEditorSplitVertical
    case shortcutEditorSplitHorizontal
    case shortcutEditorNudge
    case shortcutEditorMarquee
    case shortcutEditorSnapOff
    case shortcutEditorZoomHeight
    case shortcutEditorZoomWidth
    case shortcutSnapShiftDrag
    case shortcutSnapRightClick
    case shortcutSnapShake
    case shortcutSnapGridDraw
    case shortcutSnapMagneticResize
    case shortcutSnapOverlayDigit
    case shortcutSnapCycleLayout
    case shortcutSnapLayoutStrip
    case shortcutSettings
    case shortcutQuit
    case shortcutGestureScroll
    case shortcutGestureHorizontalScroll
    case shortcutGestureShiftDrag
    case shortcutGestureRightClick
    case shortcutGestureShake
    case shortcutGestureGridDraw
    case shortcutGestureMagneticResize
    case shortcutGestureOverlayDigit
    case shortcutGestureDrag
    case shortcutGestureCycleLayout
    case shortcutGestureLayoutStrip
    case shortcutGestureClickEmpty
    case shortcutGestureArrowKeys
    case shortcutGestureCommandDrag
    case shortcutGestureControlHold

    case onboardingWindowTitle
    case onboardingTitle
    case onboardingSubtitle
    case onboardingStep1Title
    case onboardingStep1Detail
    case onboardingStep2Title
    case onboardingStep2Detail
    case onboardingStep3Title
    case onboardingStep3Detail
    case onboardingMockHeader
    case onboardingStatusNeedsPermission
    case onboardingStatusWaiting
    case onboardingStatusGranted
    case onboardingStatusNeedsRelaunch
    case onboardingOpenSettings
    case onboardingOpenSettingsAgain
    case onboardingNotNow
    case onboardingQuitRelaunch
    case onboardingContinue
    case onboardingQuitRelaunchApp
    case onboardingOpenSettingsAgainShort
    case onboardingIveTurnedItOn
    case onboardingStepAccessibility

    case welcomeWindowTitle
    case welcomeSkip
    case welcomeBack
    case welcomeContinue
    case welcomeSkipForNow
    case welcomeDone
    case welcomeStepOf
    case welcomeIntroTitle
    case welcomeIntroSubtitle
    case welcomeIntroMenuBar
    case welcomeIntroLocate
    case welcomeLayoutsTitle
    case welcomeLayoutsBody
    case welcomeLayoutsPerDisplay
    case welcomeLayoutsCurrent
    case welcomeAccessTitle
    case welcomeSnapTitle
    case welcomeSnapBody
    case welcomeSnapShiftDrag
    case welcomeSnapRightClick
    case welcomeSnapKeyboard
    case welcomeSnapWhileArmed
    case welcomeSnapShake
    case welcomeSnapShowZones
    case welcomeSnapNeedsAccess
    case welcomeSnapGoToAccess
    case welcomeSnapWaiting
    case welcomeSnapDone
    case welcomeMoreTitle
    case welcomeMoreEditor
    case welcomeMoreDivider
    case welcomeMoreWorkspaces
    case welcomeMoreQuickAndPin
    case welcomeMoreOpenEditor
    case welcomeFinishTitle
    case welcomeFinishBody
    case welcomeFinishReopen
    case welcomeFinishOpenSettings
    case menuWelcomeTour
    case settingsWelcomeTour
    case settingsWelcomeTourDetail
    case settingsShowWelcomeTour

    case editorColumns2
    case editorColumns3
    case editorRows2
    case editorGrid2x2
    case editorPriority
    case editorFocus
    case editorModeGrid
    case editorModeCanvas
    case editorSave
    case editorSaveCopy
    case editorCancel
    case editorDelete
    case editorDeleteTooltip
    case editorFromTemplate
    case editorCustomLayout
    case editorFromTemplateTooltip
    case editorHint
    case editorGridHint
    case editorGridProtected
    case editorSaveTooltip
    case editorSaveCopyTooltip
    case editorSaveDisabledTooltip
    case editorSaveNameTitle
    case editorSaveNameMessage
    case editorCopyNameTitle
    case editorCopyNameMessage
    case editorCopyUnchangedMessage
    case editorCopyNamePlaceholder
    case editorCopyNameConfirm
    case editorWidth
    case editorHeight
    case editorPixels
    case editorAspect
    case editorAspectFree
    case editorAspectSquare
    case editorAspect16x9
    case editorAspect4x3
    case editorLockAspect
    case editorNoZoneSelected
    case editorX
    case editorY
    case canvasEmptyTitle
    case canvasEmptySubtitle
    case canvasNewPane
    case canvasDuplicate
    case canvasSplitVertical
    case canvasSplitHorizontal
    case canvasAlign
    case canvasAlignLeft
    case canvasAlignCenterX
    case canvasAlignRight
    case canvasAlignTop
    case canvasAlignCenterY
    case canvasAlignBottom
    case canvasMatchSize
    case canvasMatchWidth
    case canvasMatchHeight
    case canvasMatchBoth
    case canvasDistribute
    case canvasDistributeHorizontal
    case canvasDistributeVertical
    case canvasSnapToHalf
    case canvasSnapHalfLeft
    case canvasSnapHalfRight
    case canvasSnapHalfTop
    case canvasSnapHalfBottom
    case canvasCenter
    case canvasFillFromTemplate
    case canvasSelectAll
    case canvasNumber
    case canvasDeletePane
    case editorRedo

    case layoutColumns
    case layoutRows
    case layoutGrid2x2
    case layoutPriority3
    case layoutFocus
    case layoutCanvas
    case layoutCopy
}

public enum L10n {
    public static func text(_ key: L10nKey, language: AppLanguage = LanguageCenter.language) -> String {
        table(language)[key] ?? table(.english)[key] ?? key.rawValue
    }

    public static func gutter(_ points: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.settingsGutter, language: language), locale: language.locale, points)
    }

    public static func shakeIntensity(_ value: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.settingsShakeIntensity, language: language), locale: language.locale, value)
    }

    public static func unpinAll(_ count: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.menuUnpinAllWindows, language: language), locale: language.locale, count)
    }

    public static func shortcutDuplicate(_ name: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.shortcutErrorDuplicate, language: language), locale: language.locale, name)
    }

    public static func shortcutReserved(_ name: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.shortcutErrorReserved, language: language), locale: language.locale, name)
    }

    public static func columns(_ count: Int, language: AppLanguage = LanguageCenter.language) -> String {
        if language == .chineseSimplified {
            switch count {
            case 2: return "两列"
            case 3: return "三列"
            default: return "\(count) 列"
            }
        }
        return String(format: text(.layoutColumns, language: language), locale: language.locale, count)
    }

    public static func rows(_ count: Int, language: AppLanguage = LanguageCenter.language) -> String {
        if language == .chineseSimplified {
            switch count {
            case 2: return "两行"
            case 3: return "三行"
            default: return "\(count) 行"
            }
        }
        return String(format: text(.layoutRows, language: language), locale: language.locale, count)
    }

    public static func canvas(_ index: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.layoutCanvas, language: language), locale: language.locale, index)
    }

    public static func stepAccessibility(_ number: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.onboardingStepAccessibility, language: language), locale: language.locale, number)
    }

    public static func welcomeStepOf(_ current: Int, _ total: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.welcomeStepOf, language: language), locale: language.locale, current, total)
    }

    public static func welcomeLayoutsCurrent(_ name: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.welcomeLayoutsCurrent, language: language), locale: language.locale, name)
    }

    public static func welcomeSnapKeyboard(_ shortcut: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.welcomeSnapKeyboard, language: language), locale: language.locale, shortcut)
    }

    public static func welcomeSnapDone(_ shortcut: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.welcomeSnapDone, language: language), locale: language.locale, shortcut)
    }

    public static func welcomeMoreEditor(_ shortcut: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.welcomeMoreEditor, language: language), locale: language.locale, shortcut)
    }

    public static func welcomeMoreWorkspaces(_ shortcut: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.welcomeMoreWorkspaces, language: language), locale: language.locale, shortcut)
    }

    public static func welcomeMoreQuickAndPin(_ shortcut: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.welcomeMoreQuickAndPin, language: language), locale: language.locale, shortcut)
    }

    public static func organizeNeedsSpace(_ appName: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.organizeNeedsSpaceDetail, language: language), locale: language.locale, appName)
    }

    public static func organizeKeptInPlace(_ appName: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.organizeKeptInPlaceDetail, language: language), locale: language.locale, appName)
    }

    public static func organizeSkipped(_ count: Int, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.organizeSkippedDetail, language: language), locale: language.locale, count)
    }

    public static func organizeIgnore(_ appName: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.organizeIgnoreAction, language: language), locale: language.locale, appName)
    }

    public static func organizeIgnored(_ appName: String, language: AppLanguage = LanguageCenter.language) -> String {
        String(format: text(.organizeIgnoredDetail, language: language), locale: language.locale, appName)
    }

    public static func workspaceSizeConstrained(
        _ appName: String,
        language: AppLanguage = LanguageCenter.language
    ) -> String {
        String(format: text(.workspaceSizeConstrainedDetail, language: language), locale: language.locale, appName)
    }

    /// Localize a stored layout name. Canonical storage stays English (`Columns 2`, `Canvas 3 Copy`).
    public static func layoutDisplayName(_ stored: String, language: AppLanguage = LanguageCenter.language) -> String {
        let copyWord = text(.layoutCopy, language: .english)
        var rest = stored
        var copySuffix = ""
        if let range = rest.range(of: " \(copyWord)", options: .backwards) {
            let after = String(rest[range.upperBound...])
            rest = String(rest[..<range.lowerBound])
            let localizedCopy = text(.layoutCopy, language: language)
            copySuffix = after.isEmpty ? " \(localizedCopy)" : " \(localizedCopy)\(after)"
        }

        let localized: String
        if rest == "Focus" {
            localized = text(.layoutFocus, language: language)
        } else if rest == "Grid 2×2" || rest == "Grid 2x2" {
            localized = text(.layoutGrid2x2, language: language)
        } else if rest == "Priority 3" {
            localized = text(.layoutPriority3, language: language)
        } else if rest.hasPrefix("Columns "), let n = Int(rest.dropFirst("Columns ".count)) {
            localized = columns(n, language: language)
        } else if rest.hasPrefix("Rows "), let n = Int(rest.dropFirst("Rows ".count)) {
            localized = rows(n, language: language)
        } else if rest.hasPrefix("Canvas "), let n = Int(rest.dropFirst("Canvas ".count)) {
            localized = canvas(n, language: language)
        } else {
            localized = rest
        }
        return localized + copySuffix
    }

    private static func table(_ language: AppLanguage) -> [L10nKey: String] {
        switch language {
        case .english: english
        case .chineseSimplified: chinese
        }
    }

    private static let english: [L10nKey: String] = [
        .statusTooltip: "ZoneBox",
        .statusTooltipNeedsAccess: "ZoneBox needs Accessibility to snap windows",
        .menuEnableAccessibility: "Enable Accessibility to Snap Windows…",
        .menuSnapEnabled: "Snap Enabled",
        .menuHotkeysPausedVO: "Hotkeys paused — VoiceOver on",
        .menuOrganizeWindows: "Organize Windows",
        .menuOpenEditor: "Open Layout Editor",
        .menuPreviewZones: "Preview Zones",
        .menuLayouts: "Layouts",
        .menuWorkspaces: "Workspaces",
        .menuCaptureWorkspace: "Save Current Arrangement…",
        .menuUpdateActiveWorkspace: "Update Last Applied Workspace",
        .menuManageWorkspaces: "Manage Workspaces…",
        .menuNewCanvas: "New Canvas Layout…",
        .menuNewGrid: "New Grid Layout…",
        .menuDeleteLayout: "Delete Current Layout…",
        .menuDeleteLayoutTitle: "Delete %@?",
        .menuDeleteLayoutMessage: "This layout is removed from every display that uses it. ZoneBox keeps at least one layout.",
        .menuDeleteLayoutConfirm: "Delete",
        .menuSettings: "Settings…",
        .menuKeyboardShortcuts: "Keyboard Shortcuts",
        .menuQuit: "Quit ZoneBox",
        .menuUnpinAllWindows: "Unpin All Windows (%d)",
        .pinOnTop: "Pin on top",
        .pinUnpin: "Unpin",
        .pinScreenRecordingTitle: "Allow Screen Recording to pin windows",
        .pinScreenRecordingMessage: "ZoneBox shows a live picture of the pinned window above other apps. Clicks and scrolling go to the original window. The picture stays on this Mac and is never uploaded.",
        .pinScreenRecordingRequest: "Continue",
        .consoleSnap: "Snap",
        .consoleOrganize: "Organize",
        .consoleEdit: "Edit",
        .consolePreview: "Preview",
        .consoleNew: "New Layout",
        .consoleNoDisplay: "No display",
        .consoleCurrentDisplay: "Current Display",
        .consoleOtherLayouts: "Other Layouts",
        .organizeAdjustedTitle: "Arrangement adjusted",
        .organizePartialTitle: "Partially organized",
        .organizeFailedTitle: "Arrangement not completed",
        .organizeNoWindowsTitle: "No windows were moved",
        .organizeNeedsSpaceDetail: "%@ needs more space, so it was placed in the primary area.",
        .organizeKeptInPlaceDetail: "%@ did not accept window changes. It was kept in place while other windows were organized.",
        .organizeSkippedDetail: "%d windows could not be adjusted and were left in place.",
        .organizeRestoredDetail: "The windows were restored to their previous positions.",
        .organizeRestoreFailedDetail: "Some windows could not be restored. Their current positions were preserved.",
        .organizeRestoredTitle: "Previous layout restored",
        .organizeIgnoredTitle: "Application ignored",
        .organizeIgnoredDetail: "%@ will be excluded from future window actions.",
        .organizeRestoreAction: "Restore Layout",
        .organizeIgnoreAction: "Ignore %@",
        .organizeClose: "Close",
        .workspaceNameTitle: "Save Workspace",
        .workspaceNameMessage: "Name this arrangement of apps and zones.",
        .workspaceNamePlaceholder: "Workspace name",
        .workspaceSave: "Save",
        .workspaceDefaultName: "Workspace",
        .workspaceCapturedTitle: "Workspace saved",
        .workspaceUpdatedTitle: "Workspace updated",
        .workspaceCapturedDetail: "%@ includes %d applications.",
        .workspaceCaptureEmptyTitle: "Nothing to save",
        .workspaceCaptureEmptyDetail: "Place at least one application window mostly inside a zone, then try again.",
        .workspaceAppliedTitle: "Workspace applied",
        .workspaceApplyPartialTitle: "Workspace partially applied",
        .workspaceMovedDetail: "%d windows fully placed.",
        .workspaceSizeConstrainedDetail: "%@ was moved into place, but its minimum window size is larger than the zone.",
        .workspaceMissingDetail: "%d applications have missing windows.",
        .workspaceStaleDetail: "%d rules need recapturing.",
        .workspaceDisplaysSkippedDetail: "%d disconnected displays were skipped.",
        .workspaceWindowsSkippedDetail: "%d windows could not be moved.",
        .workspaceAppMissingTitle: "Application could not be placed",
        .workspaceAppNotInstalledDetail: "%@ is not installed.",
        .workspaceLaunchTimeoutDetail: "%@ did not open a window in time.",
        .workspaceLayoutDeleteImpact: "%d workspace profiles will be affected.",

        .settingsTitle: "ZoneBox Settings",
        .settingsAccessBanner: "Snapping is off until Accessibility is allowed. Open the guide to turn on the ZoneBox switch.",
        .settingsShowGuide: "Show Accessibility Guide…",
        .settingsEnableSnapping: "Enable snapping",
        .settingsShiftDrag: "Hold Shift while dragging the title bar to snap",
        .settingsRightClick: "Right-click while dragging the title bar to snap",
        .settingsShakeToSnap: "Shake the title bar while dragging to snap",
        .settingsShakeIntensity: "Shake force: %d",
        .settingsShakeIntensityHint: "Lower is easier to trigger",
        .settingsQuickSnapper: "Quick Snapper overlay, then 1–9",
        .settingsMagneticResize: "Magnet window edges to zones while resizing",
        .settingsShowNumbers: "Show zone numbers",
        .settingsRestoreSize: "Restore size when unsnapping",
        .settingsGutter: "Space between zones: %d pt",
        .settingsHotkeys: "Click a shortcut to record a new combination. Global shortcuts need Control or Command. VoiceOver still pauses only Control+Option chords.",
        .settingsShowShortcuts: "Keyboard Shortcuts…",
        .settingsOpenAccess: "Open Accessibility Settings",
        .settingsLaunchAtLogin: "Launch at login",
        .settingsHoverPin: "Show a pin button when hovering a window title bar",
        .settingsBeta: "Beta",
        .settingsLanguage: "Language",
        .settingsLanguageSystem: "Follow System",
        .settingsLanguageEnglish: "English",
        .settingsLanguageChinese: "简体中文",
        .settingsSectionGeneral: "General",
        .settingsSectionSnapping: "Snapping",
        .settingsSectionOverlay: "Overlay",
        .settingsSectionKeyboard: "Keyboard",
        .settingsSectionWorkspaces: "Workspaces",
        .settingsGeneralSubtitle: "Choose the language and how ZoneBox starts.",
        .settingsSnappingSubtitle: "Choose how windows enter zones and what happens when they leave.",
        .settingsOverlaySubtitle: "Tune the information and spacing shown while snapping.",
        .settingsKeyboardSubtitle: "Record the shortcuts you use to move between zones.",
        .settingsWorkspacesSubtitle: "Manage saved arrangements. Applying one is a one-time action.",
        .settingsLanguageDetail: "Change ZoneBox without changing the system language.",
        .settingsLaunchAtLoginDetail: "Keep ZoneBox ready after you sign in.",
        .settingsHoverPinDetail: "Keep a window above other apps. This feature is still unstable. The original window stays clickable and scrollable. macOS Screen Recording permission is required.",
        .settingsShiftDragDetail: "Reveal zones while you place a window precisely.",
        .settingsRightClickDetail: "Use the secondary button without changing your drag.",
        .settingsShakeToSnapDetail: "Reveal zones after a short left-right motion.",
        .settingsMagneticResizeDetail: "Align a resizing edge with the nearest zone boundary.",
        .settingsRestoreSizeDetail: "Return the window to its pre-snap dimensions.",
        .settingsQuickSnapperDetail: "Show the overlay first, then choose a numbered zone.",
        .settingsShowNumbersDetail: "Make numbered keyboard targets visible in the overlay.",
        .settingsGutterDetail: "Set the breathing room between neighboring zones.",
        .settingsShowLayoutStrip: "Show candidate layouts while dragging",
        .settingsShowLayoutStripDetail: "Drop a window onto a thumbnail to switch layouts and snap in one step.",
        .settingsPreviewLayoutOnSelect: "Preview layout after selecting",
        .settingsPreviewLayoutOnSelectDetail: "Close the picker and briefly show the assigned layout on screen.",
        .settingsSnappingTriggersSection: "Snap triggers",
        .settingsSnappingBehaviorSection: "Window behavior",
        .settingsGeneralPreviewTitle: "General overview",
        .settingsSnappingPreviewTitle: "Snapping preview",
        .settingsOverlayPreviewTitle: "Overlay preview",
        .settingsKeyboardPreviewTitle: "Keyboard control",
        .settingsWorkspacesPreviewTitle: "Saved workspaces",
        .settingsGeneralPreviewDescription: "Language and startup preferences apply across ZoneBox.",
        .settingsSnappingPreviewDescription: "Drag, right-click, or shake a title bar to place a window in a zone.",
        .settingsOverlayPreviewDescription: "Zone labels and spacing stay visible only while you need them.",
        .settingsKeyboardPreviewDescription: "Move, cycle, and restore windows without leaving the keyboard.",
        .settingsWorkspacesPreviewDescription: "Restore a complete app layout once and launch missing applications when needed.",
        .settingsWorkspaceEmpty: "No workspaces saved yet. Save the current arrangement from the menu bar.",
        .settingsWorkspaceLaunchMissing: "Launch missing applications",
        .settingsWorkspaceRename: "Rename…",
        .settingsWorkspaceDelete: "Delete",
        .settingsWorkspaceDeleteTitle: "Delete “%@”?",
        .settingsWorkspaceRecapture: "Recapture",
        .settingsWorkspaceSummary: "%d displays · %d applications",
        .settingsWorkspaceShowDetails: "Show details",
        .settingsWorkspaceHideDetails: "Hide details",
        .settingsWorkspaceSectionSummary: "%@ · %@",
        .settingsWorkspaceZone: "Zone %d",
        .settingsWorkspaceUnavailableDisplay: "Unavailable display",
        .settingsWorkspaceUnavailableLayout: "Unavailable layout",
        .settingsWorkspaceActive: "Last applied",
        .settingsAccessGranted: "Accessibility allowed",
        .settingsAccessRequired: "Accessibility required",
        .settingsManageAccess: "Manage…",
        .settingsHotkeyCaptureHint: "Click a shortcut, then press a new key combination. Global shortcuts need Control or Command. VoiceOver still pauses only Control+Option chords.",
        .settingsHotkeyRecording: "Press a shortcut…",
        .settingsResetShortcut: "Reset",
        .settingsResetAllShortcuts: "Reset All Shortcuts",
        .settingsQuickSnapperToggle: "Enable Quick Snapper overlay",
        .shortcutErrorSequoia: "macOS requires Control or Command in a global shortcut.",
        .shortcutErrorDuplicate: "That shortcut is already used by %@.",
        .shortcutErrorReserved: "That shortcut is reserved by %@.",

        .shortcutsTitle: "Keyboard Shortcuts",
        .shortcutsSectionGlobal: "Global",
        .shortcutsSectionEditor: "Layout Editor",
        .shortcutsSectionSnap: "Snap",
        .shortcutsSectionApp: "ZoneBox",
        .shortcutsVoiceOverNote: "VoiceOver still pauses Control+Option global shortcuts. Other modifiers stay active.",
        .shortcutsSubtitle: "Customize global shortcuts in Settings",
        .shortcutOpenEditor: "Open layout editor",
        .shortcutSnapZone: "Snap to zone %d",
        .shortcutSnapZones: "Snap to zone",
        .shortcutPreviousZone: "Previous zone",
        .shortcutNextZone: "Next zone",
        .shortcutCycleBackward: "Cycle window backward",
        .shortcutCycleForward: "Cycle window forward",
        .shortcutUnsnap: "Unsnap window",
        .shortcutShowShortcuts: "Keyboard shortcuts",
        .shortcutQuickSnapper: "Quick Snapper overlay",
        .shortcutOrganizeWindows: "Organize windows",
        .shortcutApplyWorkspace: "Apply active workspace",
        .shortcutEditorCancel: "Close editor",
        .shortcutEditorCycle: "Select next zone",
        .shortcutEditorCycleBack: "Select previous zone",
        .shortcutEditorDelete: "Delete zone",
        .shortcutEditorSave: "Save layout or copy",
        .shortcutEditorUndo: "Undo last edit",
        .shortcutEditorRedo: "Redo last undone edit",
        .shortcutEditorNewPane: "Create a pane",
        .shortcutEditorDuplicate: "Duplicate pane",
        .shortcutEditorSplitVertical: "Split pane vertically",
        .shortcutEditorSplitHorizontal: "Split pane horizontally",
        .shortcutEditorNudge: "Nudge selected panes",
        .shortcutEditorMarquee: "Marquee-select panes",
        .shortcutEditorSnapOff: "Disable snapping while dragging",
        .shortcutEditorZoomHeight: "Scale height",
        .shortcutEditorZoomWidth: "Scale width",
        .shortcutSnapShiftDrag: "Snap while dragging the title bar",
        .shortcutSnapRightClick: "Right-click while dragging the title bar",
        .shortcutSnapShake: "Shake title bar to snap",
        .shortcutSnapGridDraw: "Draw a rectangle across grid cells",
        .shortcutSnapMagneticResize: "Magnetic resize to zone edges",
        .shortcutSnapOverlayDigit: "Snap to a numbered zone while the overlay is showing",
        .shortcutSnapCycleLayout: "Switch to the next layout while the overlay is showing",
        .shortcutSnapLayoutStrip: "Drop onto a candidate-layout thumbnail",
        .shortcutSettings: "Settings",
        .shortcutQuit: "Quit ZoneBox",
        .shortcutGestureScroll: "Scroll",
        .shortcutGestureHorizontalScroll: "Horizontal scroll",
        .shortcutGestureShiftDrag: "⇧  title-bar drag",
        .shortcutGestureRightClick: "Title-bar right-click drag",
        .shortcutGestureShake: "Shake while dragging",
        .shortcutGestureGridDraw: "⇧  drag across cells",
        .shortcutGestureMagneticResize: "Drag a window edge",
        .shortcutGestureOverlayDigit: "1–9",
        .shortcutGestureDrag: "Drag",
        .shortcutGestureCycleLayout: "Scroll or ⇥",
        .shortcutGestureLayoutStrip: "Drop on candidate list",
        .shortcutGestureClickEmpty: "Click empty space",
        .shortcutGestureArrowKeys: "← → ↑ ↓",
        .shortcutGestureCommandDrag: "⌘  drag empty space",
        .shortcutGestureControlHold: "⌃  while dragging",

        .onboardingWindowTitle: "Enable Accessibility",
        .onboardingTitle: "Allow ZoneBox to arrange windows",
        .onboardingSubtitle: "macOS requires Accessibility permission before ZoneBox can move and resize other apps. This stays on your Mac — nothing is uploaded.",
        .onboardingStep1Title: "Open Accessibility settings",
        .onboardingStep1Detail: "Use the button below. System Settings opens to Privacy & Security → Accessibility.",
        .onboardingStep2Title: "Turn on ZoneBox",
        .onboardingStep2Detail: "Find ZoneBox in the list and turn on its switch.",
        .onboardingStep3Title: "Come back to ZoneBox",
        .onboardingStep3Detail: "Snapping turns on automatically once the switch is on. If it doesn’t, use Quit & Relaunch below.",
        .onboardingMockHeader: "Accessibility",
        .onboardingStatusNeedsPermission: "Snapping is paused until Accessibility is allowed.",
        .onboardingStatusWaiting: "Waiting for the switch next to ZoneBox…",
        .onboardingStatusGranted: "Accessibility is on. You can snap windows now.",
        .onboardingStatusNeedsRelaunch: "The switch can be on while this process still isn’t trusted. Quit & Relaunch applies the grant.",
        .onboardingOpenSettings: "Open Accessibility Settings",
        .onboardingOpenSettingsAgain: "Open Accessibility Settings again",
        .onboardingNotNow: "Not now",
        .onboardingQuitRelaunch: "Quit & Relaunch",
        .onboardingContinue: "Continue",
        .onboardingQuitRelaunchApp: "Quit & Relaunch ZoneBox",
        .onboardingOpenSettingsAgainShort: "Open Settings again",
        .onboardingIveTurnedItOn: "I've turned it on",
        .onboardingStepAccessibility: "Step %d",

        .welcomeWindowTitle: "Welcome to ZoneBox",
        .welcomeSkip: "Skip Tour",
        .welcomeBack: "Back",
        .welcomeContinue: "Continue",
        .welcomeSkipForNow: "Skip for Now",
        .welcomeDone: "Done",
        .welcomeStepOf: "Step %d of %d",
        .welcomeIntroTitle: "Welcome to ZoneBox",
        .welcomeIntroSubtitle: "Draw zones on your screen, then snap windows into them with a drag or a keystroke.",
        .welcomeIntroMenuBar: "ZoneBox lives in the menu bar, next to the clock. There is no Dock icon. Left-click the icon for the panel, right-click for the menu.",
        .welcomeIntroLocate: "Show Me",
        .welcomeLayoutsTitle: "Zones are where windows land",
        .welcomeLayoutsBody: "A layout is a set of numbered zones for one display. Pick a starting layout. You can change it or draw your own later.",
        .welcomeLayoutsPerDisplay: "Each display keeps its own layout.",
        .welcomeLayoutsCurrent: "Current: %@",
        .welcomeAccessTitle: "Allow ZoneBox to move windows",
        .welcomeSnapTitle: "Snap your first window",
        .welcomeSnapBody: "Pick any of these and try placing a window in a zone.",
        .welcomeSnapShiftDrag: "Drag a window by its title bar, hold Shift, and drop it on a zone.",
        .welcomeSnapRightClick: "Right-click once while dragging to show the zones.",
        .welcomeSnapKeyboard: "Click another window first, then press %@.",
        .welcomeSnapWhileArmed: "While zones are showing, press 1–9 to pick one.",
        .welcomeSnapShake: "Shaking the title bar while dragging also shows the zones.",
        .welcomeSnapShowZones: "Show Zones on This Display",
        .welcomeSnapNeedsAccess: "Snapping is paused until Accessibility is on.",
        .welcomeSnapGoToAccess: "Turn It On",
        .welcomeSnapWaiting: "Waiting for your first snap…",
        .welcomeSnapDone: "Snapped! Press %@ to put the window back.",
        .welcomeMoreTitle: "Beyond snapping",
        .welcomeMoreEditor: "Layout Editor: columns, rows, 2×2, or draw zones freely. Open with %@.",
        .welcomeMoreDivider: "Divider handles: snap two neighbors, then drag the seam between them to resize both and save the ratio.",
        .welcomeMoreWorkspaces: "Workspaces: remember which app lives in which zone, then bring them all back with %@.",
        .welcomeMoreQuickAndPin: "%@ shows zone numbers for the focused window. Hover a title bar to pin a window on top.",
        .welcomeMoreOpenEditor: "Open Layout Editor",
        .welcomeFinishTitle: "You're all set",
        .welcomeFinishBody: "These are the shortcuts you'll use most. Change any of them in Settings → Keyboard.",
        .welcomeFinishReopen: "To see this tour again: right-click the menu bar icon → Welcome Tour.",
        .welcomeFinishOpenSettings: "Open Settings",
        .menuWelcomeTour: "Welcome Tour…",
        .settingsWelcomeTour: "Welcome tour",
        .settingsWelcomeTourDetail: "Replay the first-launch walkthrough.",
        .settingsShowWelcomeTour: "Show Tour",

        .editorColumns2: "Columns 2",
        .editorColumns3: "Columns 3",
        .editorRows2: "Rows 2",
        .editorGrid2x2: "2×2",
        .editorPriority: "Priority",
        .editorFocus: "Focus",
        .editorModeGrid: "Grid",
        .editorModeCanvas: "Canvas",
        .editorSave: "Save",
        .editorSaveCopy: "Save Copy",
        .editorCancel: "Cancel",
        .editorDelete: "Delete",
        .editorDeleteTooltip: "Delete this saved layout",
        .editorFromTemplate: "From Template",
        .editorCustomLayout: "Custom",
        .editorFromTemplateTooltip: "Replace the draft with a template. Save updates this layout. Save Copy creates a new one.",
        .editorHint: "Click empty space or drag to create a pane. ⌘D duplicates, ⌘⇧\\ / ⌘- split, arrows nudge. Hold ⌃ while dragging to turn off snapping. ⌘Z undoes, Esc exits.",
        .editorGridHint: "Click splits a cell. Shift-click splits a row. Drag across cells to merge. ⌘Z undoes, ⌘⇧Z redoes.",
        .editorGridProtected: "Grid layouts are protected; saving creates a copy and does not overwrite the original.",
        .editorSaveTooltip: "Save layout",
        .editorSaveCopyTooltip: "Save changes as a new layout",
        .editorSaveDisabledTooltip: "Create at least one zone before saving",
        .editorSaveNameTitle: "Save Layout",
        .editorSaveNameMessage: "Name the layout. If that name already exists, ZoneBox adds a number.",
        .editorCopyNameTitle: "Save Copy",
        .editorCopyNameMessage: "Name the copy. If that name already exists, ZoneBox adds a number.",
        .editorCopyUnchangedMessage: "This layout has no changes. Save an identical copy anyway? You can rename it below.",
        .editorCopyNamePlaceholder: "Layout name",
        .editorCopyNameConfirm: "Save",
        .editorWidth: "W",
        .editorHeight: "H",
        .editorPixels: "px",
        .editorAspect: "Aspect",
        .editorAspectFree: "Free",
        .editorAspectSquare: "1:1",
        .editorAspect16x9: "16:9",
        .editorAspect4x3: "4:3",
        .editorLockAspect: "Lock aspect",
        .editorNoZoneSelected: "Select a zone to set pixels",
        .editorX: "X",
        .editorY: "Y",
        .canvasEmptyTitle: "Click anywhere to create a pane",
        .canvasEmptySubtitle: "Or drag out a rectangle. You can also start from a template.",
        .canvasNewPane: "New Pane",
        .canvasDuplicate: "Duplicate Pane",
        .canvasSplitVertical: "Split Vertically",
        .canvasSplitHorizontal: "Split Horizontally",
        .canvasAlign: "Align",
        .canvasAlignLeft: "Left",
        .canvasAlignCenterX: "Horizontal Centers",
        .canvasAlignRight: "Right",
        .canvasAlignTop: "Top",
        .canvasAlignCenterY: "Vertical Centers",
        .canvasAlignBottom: "Bottom",
        .canvasMatchSize: "Size",
        .canvasMatchWidth: "Make Same Width",
        .canvasMatchHeight: "Make Same Height",
        .canvasMatchBoth: "Make Same Size",
        .canvasDistribute: "Distribute",
        .canvasDistributeHorizontal: "Horizontally",
        .canvasDistributeVertical: "Vertically",
        .canvasSnapToHalf: "Snap to Half",
        .canvasSnapHalfLeft: "Left Half",
        .canvasSnapHalfRight: "Right Half",
        .canvasSnapHalfTop: "Top Half",
        .canvasSnapHalfBottom: "Bottom Half",
        .canvasCenter: "Center",
        .canvasFillFromTemplate: "Fill From Template",
        .canvasSelectAll: "Select All",
        .canvasNumber: "Number",
        .canvasDeletePane: "Delete Pane",
        .editorRedo: "Redo",

        .layoutColumns: "Columns %d",
        .layoutRows: "Rows %d",
        .layoutGrid2x2: "Grid 2×2",
        .layoutPriority3: "Priority 3",
        .layoutFocus: "Focus",
        .layoutCanvas: "Canvas %d",
        .layoutCopy: "Copy",
    ]

    private static let chinese: [L10nKey: String] = [
        .statusTooltip: "ZoneBox",
        .statusTooltipNeedsAccess: "ZoneBox 需要辅助功能才能吸附窗口",
        .menuEnableAccessibility: "开启辅助功能以吸附窗口…",
        .menuSnapEnabled: "启用吸附",
        .menuHotkeysPausedVO: "快捷键已暂停 — VoiceOver 开启中",
        .menuOrganizeWindows: "一键布局",
        .menuOpenEditor: "打开布局编辑器",
        .menuPreviewZones: "预览分区",
        .menuLayouts: "布局",
        .menuWorkspaces: "工作区",
        .menuCaptureWorkspace: "保存当前排布…",
        .menuUpdateActiveWorkspace: "更新最近应用的工作区",
        .menuManageWorkspaces: "管理工作区…",
        .menuNewCanvas: "新建画布布局…",
        .menuNewGrid: "新建网格布局…",
        .menuDeleteLayout: "删除当前布局…",
        .menuDeleteLayoutTitle: "删除“%@”？",
        .menuDeleteLayoutMessage: "使用这个布局的显示器都会改用剩余布局。ZoneBox 至少会保留一个布局。",
        .menuDeleteLayoutConfirm: "删除",
        .menuSettings: "设置…",
        .menuKeyboardShortcuts: "键盘快捷键",
        .menuQuit: "退出 ZoneBox",
        .menuUnpinAllWindows: "取消所有窗口置顶（%d）",
        .pinOnTop: "置顶显示",
        .pinUnpin: "取消置顶",
        .pinScreenRecordingTitle: "允许录屏权限以置顶窗口",
        .pinScreenRecordingMessage: "ZoneBox 会在其他应用上方显示置顶窗口的实时画面。点击和滚动会落到原来的窗口。画面只留在这台 Mac，不会上传。",
        .pinScreenRecordingRequest: "继续",
        .consoleSnap: "吸附",
        .consoleOrganize: "一键布局",
        .consoleEdit: "编辑",
        .consolePreview: "预览",
        .consoleNew: "新建布局",
        .consoleNoDisplay: "没有显示器",
        .consoleCurrentDisplay: "当前显示器",
        .consoleOtherLayouts: "其他布局",
        .organizeAdjustedTitle: "已调整整理方式",
        .organizePartialTitle: "已完成部分整理",
        .organizeFailedTitle: "整理未完成",
        .organizeNoWindowsTitle: "没有移动窗口",
        .organizeNeedsSpaceDetail: "%@ 需要更大空间，已将它放入主区域。",
        .organizeKeptInPlaceDetail: "%@ 未接受窗口调整，已保留原位并整理其他窗口。",
        .organizeSkippedDetail: "%d 个窗口无法调整，已保留原位。",
        .organizeRestoredDetail: "窗口已恢复到整理前的位置。",
        .organizeRestoreFailedDetail: "部分窗口无法恢复，已保留它们当前的位置。",
        .organizeRestoredTitle: "已恢复原布局",
        .organizeIgnoredTitle: "已忽略应用",
        .organizeIgnoredDetail: "之后的窗口操作将不再处理 %@。",
        .organizeRestoreAction: "恢复原布局",
        .organizeIgnoreAction: "以后忽略 %@",
        .organizeClose: "关闭",
        .workspaceNameTitle: "保存工作区",
        .workspaceNameMessage: "为这组应用与分区排布命名。",
        .workspaceNamePlaceholder: "工作区名称",
        .workspaceSave: "保存",
        .workspaceDefaultName: "工作区",
        .workspaceCapturedTitle: "工作区已保存",
        .workspaceUpdatedTitle: "工作区已更新",
        .workspaceCapturedDetail: "“%@”包含 %d 个应用。",
        .workspaceCaptureEmptyTitle: "没有可保存的窗口",
        .workspaceCaptureEmptyDetail: "请先把至少一个应用窗口大部分放入分区，再重试。",
        .workspaceAppliedTitle: "工作区已归位",
        .workspaceApplyPartialTitle: "工作区已部分归位",
        .workspaceMovedDetail: "已完整归位 %d 个窗口。",
        .workspaceSizeConstrainedDetail: "%@已移动到位，但其最小窗口尺寸大于当前分区。",
        .workspaceMissingDetail: "%d 个应用缺少窗口。",
        .workspaceStaleDetail: "%d 条规则需要重新捕获。",
        .workspaceDisplaysSkippedDetail: "已跳过 %d 台未连接显示器。",
        .workspaceWindowsSkippedDetail: "%d 个窗口无法移动。",
        .workspaceAppMissingTitle: "应用未能归位",
        .workspaceAppNotInstalledDetail: "未安装 %@。",
        .workspaceLaunchTimeoutDetail: "%@ 未在限定时间内打开窗口。",
        .workspaceLayoutDeleteImpact: "%d 个工作区方案将受影响。",

        .settingsTitle: "ZoneBox 设置",
        .settingsAccessBanner: "未允许辅助功能时无法吸附。请打开引导，打开 ZoneBox 开关。",
        .settingsShowGuide: "显示辅助功能引导…",
        .settingsEnableSnapping: "启用吸附",
        .settingsShiftDrag: "拖动标题栏时按住 Shift 吸附",
        .settingsRightClick: "拖动标题栏时右键吸附",
        .settingsShakeToSnap: "拖动标题栏时左右晃动即可吸附",
        .settingsShakeIntensity: "晃动力度：%d",
        .settingsShakeIntensityHint: "数值越小越容易触发",
        .settingsQuickSnapper: "快速吸附覆盖层，再按 1–9",
        .settingsMagneticResize: "缩放窗口时边缘吸附到分区",
        .settingsShowNumbers: "显示分区编号",
        .settingsRestoreSize: "取消吸附时恢复原来的大小",
        .settingsGutter: "分区间距：%d 点",
        .settingsHotkeys: "点一下快捷键即可录制新组合。全局快捷键需要 Control 或 Command。VoiceOver 仍只暂停 Control+Option 组合。",
        .settingsShowShortcuts: "键盘快捷键…",
        .settingsOpenAccess: "打开辅助功能设置",
        .settingsLaunchAtLogin: "登录时启动",
        .settingsHoverPin: "悬停窗口标题栏时显示置顶按钮",
        .settingsBeta: "Beta",
        .settingsLanguage: "语言",
        .settingsLanguageSystem: "跟随系统",
        .settingsLanguageEnglish: "English",
        .settingsLanguageChinese: "简体中文",
        .settingsSectionGeneral: "通用",
        .settingsSectionSnapping: "吸附",
        .settingsSectionOverlay: "覆盖层",
        .settingsSectionKeyboard: "键盘",
        .settingsSectionWorkspaces: "工作区",
        .settingsGeneralSubtitle: "设置界面语言，以及 ZoneBox 的启动方式。",
        .settingsSnappingSubtitle: "选择窗口如何进入分区，以及离开吸附时如何恢复。",
        .settingsOverlaySubtitle: "调整吸附时显示的信息和分区间距。",
        .settingsKeyboardSubtitle: "录制用于移动、切换和恢复窗口的快捷键。",
        .settingsWorkspacesSubtitle: "管理已保存的整桌排布。切换只在当次执行，不会持续固定窗口。",
        .settingsLanguageDetail: "只更改 ZoneBox，不影响系统语言。",
        .settingsLaunchAtLoginDetail: "登录后让 ZoneBox 随时可以使用。",
        .settingsHoverPinDetail: "让窗口保持在其他应用上方。该功能仍不稳定。原窗口仍可点击和滚动。需要 macOS 录屏权限。",
        .settingsShiftDragDetail: "拖动窗口时显示分区，便于精确放置。",
        .settingsRightClickDetail: "拖动时按下鼠标右键即可显示分区。",
        .settingsShakeToSnapDetail: "短距离左右晃动标题栏即可显示分区。",
        .settingsMagneticResizeDetail: "缩放时让窗口边缘对齐最近的分区边界。",
        .settingsRestoreSizeDetail: "离开吸附后恢复窗口原来的尺寸。",
        .settingsQuickSnapperDetail: "先显示覆盖层，再按数字选择分区。",
        .settingsShowNumbersDetail: "在覆盖层中显示可用键盘选择的编号。",
        .settingsGutterDetail: "设置相邻分区之间的留白。",
        .settingsShowLayoutStrip: "拖拽时显示候选布局列表",
        .settingsShowLayoutStripDetail: "把窗口拖到缩略图上松手，即可一步换布局并贴入。",
        .settingsPreviewLayoutOnSelect: "选择布局后预览分区",
        .settingsPreviewLayoutOnSelectDetail: "收起选择面板，并在屏幕上短暂显示当前布局。",
        .settingsSnappingTriggersSection: "吸附触发方式",
        .settingsSnappingBehaviorSection: "窗口行为",
        .settingsGeneralPreviewTitle: "通用概览",
        .settingsSnappingPreviewTitle: "吸附预览",
        .settingsOverlayPreviewTitle: "覆盖层预览",
        .settingsKeyboardPreviewTitle: "键盘控制",
        .settingsWorkspacesPreviewTitle: "已保存的工作区",
        .settingsGeneralPreviewDescription: "语言和启动偏好会应用到整个 ZoneBox。",
        .settingsSnappingPreviewDescription: "通过拖动、右键或晃动标题栏，将窗口快速吸附到分区。",
        .settingsOverlayPreviewDescription: "分区编号和间距只在需要吸附时出现。",
        .settingsKeyboardPreviewDescription: "不用离开键盘，即可移动、切换和恢复窗口。",
        .settingsWorkspacesPreviewDescription: "一次性恢复整套应用布局，并按需启动缺失应用。",
        .settingsWorkspaceEmpty: "还没有工作区。请从菜单栏保存当前排布。",
        .settingsWorkspaceLaunchMissing: "启动缺失应用",
        .settingsWorkspaceRename: "重命名…",
        .settingsWorkspaceDelete: "删除",
        .settingsWorkspaceDeleteTitle: "删除“%@”？",
        .settingsWorkspaceRecapture: "重新捕获",
        .settingsWorkspaceSummary: "%d 台显示器 · %d 个应用",
        .settingsWorkspaceShowDetails: "查看详情",
        .settingsWorkspaceHideDetails: "收起详情",
        .settingsWorkspaceSectionSummary: "%@ · %@",
        .settingsWorkspaceZone: "分区 %d",
        .settingsWorkspaceUnavailableDisplay: "不可用的显示器",
        .settingsWorkspaceUnavailableLayout: "不可用的布局",
        .settingsWorkspaceActive: "最近应用",
        .settingsAccessGranted: "辅助功能权限：已授权",
        .settingsAccessRequired: "需要辅助功能权限",
        .settingsManageAccess: "管理权限…",
        .settingsHotkeyCaptureHint: "点一下快捷键，再按下新的组合。全局快捷键需要 Control 或 Command。VoiceOver 仍只暂停 Control+Option 组合。",
        .settingsHotkeyRecording: "请按下快捷键…",
        .settingsResetShortcut: "还原",
        .settingsResetAllShortcuts: "还原全部快捷键",
        .settingsQuickSnapperToggle: "启用快速吸附覆盖层",
        .shortcutErrorSequoia: "macOS 要求全局快捷键包含 Control 或 Command。",
        .shortcutErrorDuplicate: "这个快捷键已被“%@”占用。",
        .shortcutErrorReserved: "这个快捷键保留给 %@。",

        .shortcutsTitle: "键盘快捷键",
        .shortcutsSectionGlobal: "全局",
        .shortcutsSectionEditor: "布局编辑器",
        .shortcutsSectionSnap: "吸附",
        .shortcutsSectionApp: "ZoneBox",
        .shortcutsVoiceOverNote: "开启 VoiceOver 时，仍会暂停 Control+Option 全局快捷键。其他修饰键组合保持可用。",
        .shortcutsSubtitle: "可在设置里自定义全局快捷键",
        .shortcutOpenEditor: "打开布局编辑器",
        .shortcutSnapZone: "吸附到分区 %d",
        .shortcutSnapZones: "吸附到分区",
        .shortcutPreviousZone: "上一分区",
        .shortcutNextZone: "下一分区",
        .shortcutCycleBackward: "分区内上一窗口",
        .shortcutCycleForward: "分区内下一窗口",
        .shortcutUnsnap: "取消吸附",
        .shortcutShowShortcuts: "键盘快捷键",
        .shortcutQuickSnapper: "快速吸附覆盖层",
        .shortcutOrganizeWindows: "一键布局",
        .shortcutApplyWorkspace: "应用当前工作区",
        .shortcutEditorCancel: "关闭编辑器",
        .shortcutEditorCycle: "选中下一分区",
        .shortcutEditorCycleBack: "选中上一分区",
        .shortcutEditorDelete: "删除分区",
        .shortcutEditorSave: "保存布局或另存副本",
        .shortcutEditorUndo: "撤销上一步",
        .shortcutEditorRedo: "重做上一步",
        .shortcutEditorNewPane: "新建窗格",
        .shortcutEditorDuplicate: "复制窗格",
        .shortcutEditorSplitVertical: "垂直二等分窗格",
        .shortcutEditorSplitHorizontal: "水平二等分窗格",
        .shortcutEditorNudge: "微调选中窗格",
        .shortcutEditorMarquee: "框选窗格",
        .shortcutEditorSnapOff: "拖动时关闭吸附",
        .shortcutEditorZoomHeight: "缩放高度",
        .shortcutEditorZoomWidth: "缩放宽度",
        .shortcutSnapShiftDrag: "拖动标题栏时吸附",
        .shortcutSnapRightClick: "拖动标题栏时右键",
        .shortcutSnapShake: "晃动标题栏吸附",
        .shortcutSnapGridDraw: "在网格上画矩形吸附",
        .shortcutSnapMagneticResize: "缩放时磁性对齐分区边缘",
        .shortcutSnapOverlayDigit: "覆盖层显示时按分区编号吸附",
        .shortcutSnapCycleLayout: "覆盖层显示时切换到相邻布局",
        .shortcutSnapLayoutStrip: "拖到候选布局缩略图上松手",
        .shortcutSettings: "设置",
        .shortcutQuit: "退出 ZoneBox",
        .shortcutGestureScroll: "滚动",
        .shortcutGestureHorizontalScroll: "水平滚动",
        .shortcutGestureShiftDrag: "⇧  拖动标题栏",
        .shortcutGestureRightClick: "拖动标题栏时右键",
        .shortcutGestureShake: "拖动时晃动",
        .shortcutGestureGridDraw: "⇧  拖过多个格子",
        .shortcutGestureMagneticResize: "拖动窗口边缘",
        .shortcutGestureOverlayDigit: "1–9",
        .shortcutGestureDrag: "拖动",
        .shortcutGestureCycleLayout: "滚轮或 ⇥",
        .shortcutGestureLayoutStrip: "拖到候选布局列表",
        .shortcutGestureClickEmpty: "点击空白处",
        .shortcutGestureArrowKeys: "← → ↑ ↓",
        .shortcutGestureCommandDrag: "⌘  拖空白处",
        .shortcutGestureControlHold: "拖动时按 ⌃",

        .onboardingWindowTitle: "开启辅助功能",
        .onboardingTitle: "允许 ZoneBox 排列窗口",
        .onboardingSubtitle: "macOS 要求先开启辅助功能，ZoneBox 才能移动和调整其他应用的窗口。权限只留在这台 Mac 上，不会上传。",
        .onboardingStep1Title: "打开辅助功能设置",
        .onboardingStep1Detail: "点下面的按钮。系统设置会打开到“隐私与安全性 → 辅助功能”。",
        .onboardingStep2Title: "打开 ZoneBox",
        .onboardingStep2Detail: "在列表里找到 ZoneBox，打开旁边的开关。",
        .onboardingStep3Title: "回到 ZoneBox",
        .onboardingStep3Detail: "开关打开后，吸附会自动启用。如果没有生效，请用下方的“退出并重新打开”。",
        .onboardingMockHeader: "辅助功能",
        .onboardingStatusNeedsPermission: "未允许辅助功能时，吸附会暂停。",
        .onboardingStatusWaiting: "正在等待 ZoneBox 旁边的开关…",
        .onboardingStatusGranted: "辅助功能已开启，可以吸附窗口了。",
        .onboardingStatusNeedsRelaunch: "开关打开后，当前进程仍可能未被信任。退出并重新打开才会生效。",
        .onboardingOpenSettings: "打开辅助功能设置",
        .onboardingOpenSettingsAgain: "再次打开辅助功能设置",
        .onboardingNotNow: "稍后再说",
        .onboardingQuitRelaunch: "退出并重新打开",
        .onboardingContinue: "继续",
        .onboardingQuitRelaunchApp: "退出并重新打开 ZoneBox",
        .onboardingOpenSettingsAgainShort: "再次打开设置",
        .onboardingIveTurnedItOn: "我已打开开关",
        .onboardingStepAccessibility: "第 %d 步",

        .welcomeWindowTitle: "欢迎使用 ZoneBox",
        .welcomeSkip: "跳过引导",
        .welcomeBack: "上一步",
        .welcomeContinue: "继续",
        .welcomeSkipForNow: "暂时跳过",
        .welcomeDone: "完成",
        .welcomeStepOf: "第 %d 步，共 %d 步",
        .welcomeIntroTitle: "欢迎使用 ZoneBox",
        .welcomeIntroSubtitle: "在屏幕上划出分区，拖一下或按个快捷键，窗口就吸附进去。",
        .welcomeIntroMenuBar: "ZoneBox 常驻菜单栏（时钟旁边），没有 Dock 图标。左键点图标打开面板，右键打开菜单。",
        .welcomeIntroLocate: "指给我看",
        .welcomeLayoutsTitle: "分区就是窗口的落点",
        .welcomeLayoutsBody: "一套布局就是一个显示器上的一组带编号分区。先选一个起始布局，之后随时可以改，或者自己画。",
        .welcomeLayoutsPerDisplay: "每个显示器各自记住一套布局。",
        .welcomeLayoutsCurrent: "当前：%@",
        .welcomeAccessTitle: "允许 ZoneBox 移动窗口",
        .welcomeSnapTitle: "吸附第一个窗口",
        .welcomeSnapBody: "三种方式任选一种，试试把任意窗口放进一个分区。",
        .welcomeSnapShiftDrag: "按住标题栏拖动窗口，同时按住 Shift，放到分区上。",
        .welcomeSnapRightClick: "拖动时按一下右键，也会显示分区。",
        .welcomeSnapKeyboard: "先点一下别的窗口，再按 %@。",
        .welcomeSnapWhileArmed: "分区显示时，按 1–9 直接落到对应编号。",
        .welcomeSnapShake: "拖动时左右晃动标题栏也能呼出分区。",
        .welcomeSnapShowZones: "在这个屏幕上显示分区",
        .welcomeSnapNeedsAccess: "辅助功能未开启，吸附暂时不可用。",
        .welcomeSnapGoToAccess: "去开启",
        .welcomeSnapWaiting: "等待你的第一次吸附…",
        .welcomeSnapDone: "成功！按 %@ 可以把窗口放回原处。",
        .welcomeMoreTitle: "吸附之外，还能做这些",
        .welcomeMoreEditor: "布局编辑器：列、行、2×2，或自由画分区。%@ 打开。",
        .welcomeMoreDivider: "分隔杆：相邻两个分区各放一个窗口后，拖动它们之间的缝，一次改两边比例并保存回布局。",
        .welcomeMoreWorkspaces: "工作区方案：记住每个应用住在哪个分区，%@ 一键全部归位。",
        .welcomeMoreQuickAndPin: "%@ 为当前窗口呼出分区编号；悬停标题栏出现置顶按钮，可把窗口固定在最前。",
        .welcomeMoreOpenEditor: "打开布局编辑器",
        .welcomeFinishTitle: "一切就绪",
        .welcomeFinishBody: "以下是最常用的快捷键，都可以在设置 → 键盘里改。",
        .welcomeFinishReopen: "想再看一遍：右键菜单栏图标 → 欢迎引导。",
        .welcomeFinishOpenSettings: "打开设置",
        .menuWelcomeTour: "欢迎引导…",
        .settingsWelcomeTour: "欢迎引导",
        .settingsWelcomeTourDetail: "重看首次启动的分步引导。",
        .settingsShowWelcomeTour: "查看引导",

        .editorColumns2: "两列",
        .editorColumns3: "三列",
        .editorRows2: "两行",
        .editorGrid2x2: "2×2",
        .editorPriority: "优先",
        .editorFocus: "焦点",
        .editorModeGrid: "网格",
        .editorModeCanvas: "画布",
        .editorSave: "保存",
        .editorSaveCopy: "另存副本",
        .editorCancel: "取消",
        .editorDelete: "删除",
        .editorDeleteTooltip: "删除这个已保存的布局",
        .editorFromTemplate: "基于模板",
        .editorCustomLayout: "自定义",
        .editorFromTemplateTooltip: "用模板替换当前草稿。保存会更新当前布局，另存副本会创建新布局。",
        .editorHint: "空白处点击或拖拽新建窗格。⌘D 复制，⌘⇧\\ / ⌘- 二等分，方向键微调。拖动时按 ⌃ 关闭吸附。⌘Z 撤销，Esc 退出。",
        .editorGridHint: "点击竖切，Shift+点击横切。拖过相邻格子可合并。⌘Z 撤销，⌘⇧Z 重做。",
        .editorGridProtected: "Grid 布局受保护；修改后会创建副本，不会覆盖原布局。",
        .editorSaveTooltip: "保存布局",
        .editorSaveCopyTooltip: "将修改保存为新布局",
        .editorSaveDisabledTooltip: "至少创建一个区域后才能保存",
        .editorSaveNameTitle: "保存布局",
        .editorSaveNameMessage: "给布局起个名字。如果重名，ZoneBox 会自动加上序号。",
        .editorCopyNameTitle: "另存副本",
        .editorCopyNameMessage: "给副本起个名字。如果重名，ZoneBox 会自动加上序号。",
        .editorCopyUnchangedMessage: "当前布局没有变化。仍要保存一个相同的副本吗？可以在下方修改名称。",
        .editorCopyNamePlaceholder: "布局名称",
        .editorCopyNameConfirm: "保存",
        .editorWidth: "宽",
        .editorHeight: "高",
        .editorPixels: "像素",
        .editorAspect: "长宽比",
        .editorAspectFree: "自由",
        .editorAspectSquare: "1:1",
        .editorAspect16x9: "16:9",
        .editorAspect4x3: "4:3",
        .editorLockAspect: "锁定比例",
        .editorNoZoneSelected: "选中分区后可设置像素",
        .editorX: "X",
        .editorY: "Y",
        .canvasEmptyTitle: "点击任意位置新建窗格",
        .canvasEmptySubtitle: "或拖出一个矩形；也可以从模板起手",
        .canvasNewPane: "新建窗格",
        .canvasDuplicate: "复制窗格",
        .canvasSplitVertical: "垂直二等分",
        .canvasSplitHorizontal: "水平二等分",
        .canvasAlign: "对齐",
        .canvasAlignLeft: "左",
        .canvasAlignCenterX: "水平居中",
        .canvasAlignRight: "右",
        .canvasAlignTop: "上",
        .canvasAlignCenterY: "垂直居中",
        .canvasAlignBottom: "下",
        .canvasMatchSize: "尺寸",
        .canvasMatchWidth: "等宽",
        .canvasMatchHeight: "等高",
        .canvasMatchBoth: "等宽高",
        .canvasDistribute: "分布",
        .canvasDistributeHorizontal: "水平等距",
        .canvasDistributeVertical: "垂直等距",
        .canvasSnapToHalf: "贴到半屏",
        .canvasSnapHalfLeft: "左半",
        .canvasSnapHalfRight: "右半",
        .canvasSnapHalfTop: "上半",
        .canvasSnapHalfBottom: "下半",
        .canvasCenter: "居中",
        .canvasFillFromTemplate: "从模板填充",
        .canvasSelectAll: "全选",
        .canvasNumber: "编号",
        .canvasDeletePane: "删除窗格",
        .editorRedo: "重做",

        .layoutColumns: "%d 列",
        .layoutRows: "%d 行",
        .layoutGrid2x2: "2×2 网格",
        .layoutPriority3: "优先三分",
        .layoutFocus: "焦点",
        .layoutCanvas: "画布 %d",
        .layoutCopy: "副本",
    ]
}
