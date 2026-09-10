import ApplicationServices
import AppKit
import CoreGraphics
import ZoneBoxCore

final class AXWindow: @unchecked Sendable {
    let identity: WindowIdentity
    fileprivate let element: AXUIElement

    fileprivate init(identity: WindowIdentity, element: AXUIElement) {
        self.identity = identity
        self.element = element
    }
}

/// One standard window of an application as seen through AX, including
/// windows that CGWindowList's on-screen enumeration cannot see.
struct AXApplicationWindow {
    var window: AXWindow
    var frameAX: CGRect
    var isMinimized: Bool
    var isFullscreen: Bool
}

protocol AccessibilityClient: AnyObject {
    func focusedWindow() async -> AXWindow?
    func window(matching identity: WindowIdentity) async -> AXWindow?
    func frame(of window: AXWindow) async -> CGRect?
    func setFrame(_ frame: CGRect, of window: AXWindow) async -> CGRect?
    @discardableResult func raise(_ window: AXWindow) async -> AXError
}

final class AccessibilityClientLive: AccessibilityClient {
    /// A hung application must not stall a whole workspace restore. AX calls
    /// default to several seconds per message; two seconds is generous for a
    /// healthy process and keeps a beachballing one from blocking the queue.
    static let messagingTimeout: Float = 2.0

    private let queue = DispatchQueue(label: "com.fancyzone.ax", qos: .userInteractive)
    private let query: WindowQuerying
    private let excluded: () -> [String]
    private let snapDialogs: () -> Bool
    private let trusted: () -> Bool
    private let allowedWindowNumbers: () -> Set<CGWindowID>

    init(
        query: WindowQuerying,
        excluded: @escaping () -> [String],
        snapDialogs: @escaping () -> Bool,
        trusted: @escaping () -> Bool,
        allowedWindowNumbers: @escaping () -> Set<CGWindowID> = { [] }
    ) {
        self.query = query
        self.excluded = excluded
        self.snapDialogs = snapDialogs
        self.trusted = trusted
        self.allowedWindowNumbers = allowedWindowNumbers
    }

    func focusedWindow() async -> AXWindow? {
        await onAX { [self] in
            let system = AXUIElementCreateSystemWide()
            guard let focusedApp = copyElement(system, kAXFocusedApplicationAttribute) else { return nil }
            var pid: pid_t = 0
            AXUIElementGetPid(focusedApp, &pid)
            guard let focused = copyElement(focusedApp, kAXFocusedWindowAttribute) else { return nil }
            return makeWindow(pid: pid, element: focused)
        }
    }

    func window(matching identity: WindowIdentity) async -> AXWindow? {
        await onAX { [self] in
            lookupWindow(
                pid: identity.pid,
                windowNumber: identity.windowNumber,
                operationID: UUID(),
                event: "ax.matching",
                targetBoundsAX: query.windows(pid: identity.pid).first(where: { $0.windowNumber == identity.windowNumber })?.boundsAX
            )
        }
    }

    /// Every standard window of one process in AX order, including minimized,
    /// full-screen and hidden-application windows that the on-screen CG list
    /// cannot see. Workspace restore uses this instead of resolving each CG
    /// window separately so a saved app costs one AX enumeration regardless of
    /// how many windows it has.
    func applicationWindows(pid: pid_t) async -> [AXApplicationWindow] {
        await onAX { [self] in
            let app = applicationElement(pid: pid)
            guard let windows = copyArray(app, kAXWindowsAttribute) else {
                Log.ax.info("AX windows pid=\(pid, privacy: .public) attribute unavailable")
                return []
            }
            var result: [AXApplicationWindow] = []
            var seen = Set<CGWindowID>()
            for element in windows {
                let axElement = unsafeBitCast(element as AnyObject, to: AXUIElement.self)
                guard let window = makeWindow(pid: pid, element: axElement, includeUnreachable: true),
                      seen.insert(window.identity.windowNumber).inserted,
                      let frame = Self.readFrame(axElement)
                else {
                    Log.ax.debug(
                        "AX window skipped pid=\(pid, privacy: .public) role=\(stringAttribute(axElement, kAXRoleAttribute) ?? "nil", privacy: .public) subrole=\(stringAttribute(axElement, kAXSubroleAttribute) ?? "nil", privacy: .public) minimized=\(boolAttribute(axElement, "AXMinimized" as CFString) ?? false, privacy: .public) number=\(AXPrivate.windowNumber(axElement).map(String.init) ?? "nil", privacy: .public)"
                    )
                    continue
                }
                result.append(
                    AXApplicationWindow(
                        window: window,
                        frameAX: frame,
                        isMinimized: boolAttribute(axElement, "AXMinimized" as CFString) == true,
                        isFullscreen: isFullscreen(axElement)
                    )
                )
            }
            return result
        }
    }

    /// Restores a miniaturized window to the desktop. Returns true once AX
    /// reports the window as no longer minimized.
    func unminimize(_ window: AXWindow) async -> Bool {
        await onAX { [self] in
            guard trusted() else { return false }
            let name = "AXMinimized" as CFString
            if boolAttribute(window.element, name) != true { return true }
            let error = AXUIElementSetAttributeValue(window.element, name, kCFBooleanFalse)
            guard error == .success else { return false }
            for _ in 0..<10 {
                if boolAttribute(window.element, name) == false { return true }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return boolAttribute(window.element, name) == false
        }
    }

    func frame(of window: AXWindow) async -> CGRect? {
        await onAX { Self.readFrame(window.element) }
    }

    func setFrame(_ frame: CGRect, of window: AXWindow) async -> CGRect? {
        await onAX(pid: window.identity.pid) { [self] in
            guard trusted() else { return nil }
            return AXFrameMutator.setFrame(frame, of: window.element)
        }
    }

    @discardableResult
    func raise(_ window: AXWindow) async -> AXError {
        await onAX(pid: window.identity.pid) { [self] in
            guard trusted() else { return .apiDisabled }
            return AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
    }

    func isSnappable(_ ref: WindowRef) -> Bool {
        SnapWindowEligibility.isSnappable(
            layer: ref.layer,
            size: ref.boundsAX.size,
            pid: ref.pid,
            ownPID: ProcessInfo.processInfo.processIdentifier,
            windowNumber: ref.windowNumber,
            bundleID: ref.bundleID,
            excludedBundleIDs: excluded(),
            allowedWindowNumbers: allowedWindowNumbers()
        )
    }

    func resolveAsync(ref: WindowRef) async -> AXWindow? {
        await resolveAsync(ref: ref, operationID: UUID())
    }

    func resolveAsync(ref: WindowRef, operationID: UUID) async -> AXWindow? {
        await onAX { self.resolve(ref: ref, operationID: operationID) }
    }

    func resolve(ref: WindowRef, operationID: UUID = UUID()) -> AXWindow? {
        let started = ProcessInfo.processInfo.systemUptime
        guard isSnappable(ref) else {
            recordAXLookup(
                event: "ax.resolve",
                operationID: operationID,
                pid: ref.pid,
                windowNumber: ref.windowNumber,
                snappable: "false",
                axError: "n/a",
                axCount: "n/a",
                axValues: "false",
                matched: false,
                matchPath: "none",
                elapsedMs: elapsedMs(since: started)
            )
            return nil
        }
        return lookupWindow(
            pid: ref.pid,
            windowNumber: ref.windowNumber,
            operationID: operationID,
            event: "ax.resolve",
            snappable: "true",
            targetBoundsAX: ref.boundsAX,
            started: started
        )
    }

    private func applicationElement(pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        return app
    }

    private func makeWindow(pid: pid_t, element: AXUIElement, includeUnreachable: Bool = false) -> AXWindow? {
        makeWindowDetailed(pid: pid, element: element, includeUnreachable: includeUnreachable).window
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute)
        guard role == kAXWindowRole else { return false }
        let sub = stringAttribute(element, kAXSubroleAttribute)
        if sub == kAXStandardWindowSubrole { return true }
        if snapDialogs(), sub == kAXDialogSubrole { return true }
        return false
    }

    private func isFullscreen(_ element: AXUIElement) -> Bool {
        boolAttribute(element, "AXFullScreen" as CFString) == true
    }

    private func windowNumber(of element: AXUIElement, pid: pid_t) -> CGWindowID? {
        windowNumberProbe(of: element, pid: pid).id
    }

    private struct MakeWindowDetailed {
        var window: AXWindow? = nil
        var skip: String? = nil
        var dlsym = "n/a"
        var numberError = "n/a"
        var geometryMatches = "n/a"
        var numberSource = "n/a"
    }

    private func lookupWindow(
        pid: pid_t,
        windowNumber: CGWindowID,
        operationID: UUID,
        event: String,
        snappable: String? = nil,
        targetBoundsAX: CGRect? = nil,
        started: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> AXWindow? {
        let app = applicationElement(pid: pid)
        let copied = copyArrayResult(app, kAXWindowsAttribute)
        guard let windows = copied.values else {
            recordAXLookup(
                event: event,
                operationID: operationID,
                pid: pid,
                windowNumber: windowNumber,
                snappable: snappable,
                axError: "\(copied.error.rawValue)",
                axCount: "0",
                axValues: "false",
                matched: false,
                matchPath: "none",
                elapsedMs: elapsedMs(since: started)
            )
            return nil
        }
        var skips: [String] = []
        var skipCounts: [String: Int] = [:]
        var probeDlsym = "n/a"
        var probeError = "n/a"
        var probeGeometry = "n/a"
        var probeSource = "n/a"
        for element in windows {
            let axElement = unsafeBitCast(element as AnyObject, to: AXUIElement.self)
            let detail = makeWindowDetailed(pid: pid, element: axElement)
            if let skip = detail.skip {
                skipCounts[skip, default: 0] += 1
                if skips.count < SnapDiagnosticLog.maxListItems {
                    skips.append(skip)
                }
                if skip == "missingWindowNumber" || probeSource == "n/a" {
                    probeDlsym = detail.dlsym
                    probeError = detail.numberError
                    probeGeometry = detail.geometryMatches
                    probeSource = detail.numberSource
                }
            }
            if let window = detail.window, window.identity.windowNumber == windowNumber {
                recordAXLookup(
                    event: event,
                    operationID: operationID,
                    pid: pid,
                    windowNumber: windowNumber,
                    snappable: snappable,
                    axError: "\(copied.error.rawValue)",
                    axCount: "\(windows.count)",
                    axValues: "true",
                    skips: skips,
                    skipCounts: skipCounts,
                    privateDlsym: detail.dlsym,
                    privateError: detail.numberError,
                    geometryMatches: detail.geometryMatches,
                    numberSource: detail.numberSource,
                    matched: true,
                    matchPath: "identity",
                    resultWindowNumber: "\(window.identity.windowNumber)",
                    elapsedMs: elapsedMs(since: started)
                )
                return window
            }
        }
        if let targetBoundsAX {
            if let match = windows.compactMap({ element -> AXWindow? in
                let el = unsafeBitCast(element as AnyObject, to: AXUIElement.self)
                guard let frame = Self.readFrame(el) else { return nil }
                guard frame.insetBy(dx: -2, dy: -2).intersects(targetBoundsAX) else { return nil }
                return makeWindow(pid: pid, element: el)
            }).first {
                recordAXLookup(
                    event: event,
                    operationID: operationID,
                    pid: pid,
                    windowNumber: windowNumber,
                    snappable: snappable,
                    axError: "\(copied.error.rawValue)",
                    axCount: "\(windows.count)",
                    axValues: "true",
                    skips: skips,
                    skipCounts: skipCounts,
                    privateDlsym: probeDlsym,
                    privateError: probeError,
                    geometryMatches: probeGeometry,
                    numberSource: probeSource,
                    matched: true,
                    matchPath: "geometry",
                    resultWindowNumber: "\(match.identity.windowNumber)",
                    elapsedMs: elapsedMs(since: started)
                )
                return match
            }
        }
        recordAXLookup(
            event: event,
            operationID: operationID,
            pid: pid,
            windowNumber: windowNumber,
            snappable: snappable,
            axError: "\(copied.error.rawValue)",
            axCount: "\(windows.count)",
            axValues: "true",
            skips: skips,
            skipCounts: skipCounts,
            privateDlsym: probeDlsym,
            privateError: probeError,
            geometryMatches: probeGeometry,
            numberSource: probeSource,
            matched: false,
            matchPath: "none",
            elapsedMs: elapsedMs(since: started)
        )
        return nil
    }

    private func makeWindowDetailed(
        pid: pid_t,
        element: AXUIElement,
        includeUnreachable: Bool = false
    ) -> MakeWindowDetailed {
        let minimized = boolAttribute(element, "AXMinimized" as CFString) == true
        // While a window sits in the Dock its subrole is reported as AXDialog,
        // so the standard-window test would drop every minimized document
        // window. Minimized windows in the unreachable set only need the role.
        if includeUnreachable, minimized {
            guard stringAttribute(element, kAXRoleAttribute) == kAXWindowRole else {
                return MakeWindowDetailed(skip: "notWindowRole")
            }
        } else {
            guard isStandardWindow(element) else {
                return MakeWindowDetailed(skip: "notStandardWindow")
            }
        }
        if !includeUnreachable {
            if isFullscreen(element) { return MakeWindowDetailed(skip: "fullscreen") }
            if minimized { return MakeWindowDetailed(skip: "minimized") }
        }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let probe = windowNumberProbe(of: element, pid: pid)
        var detail = MakeWindowDetailed(
            skip: nil,
            dlsym: probe.dlsym,
            numberError: probe.error,
            geometryMatches: probe.geometryMatches,
            numberSource: probe.source
        )
        if let number = probe.id, allowedWindowNumbers().contains(number) {
            detail.window = AXWindow(
                identity: WindowIdentity(pid: pid, windowNumber: number, bundleID: bundleID),
                element: element
            )
            return detail
        }
        if let bundleID, excluded().contains(bundleID) {
            detail.skip = "excludedBundle"
            return detail
        }
        guard let number = probe.id else {
            detail.skip = "missingWindowNumber"
            return detail
        }
        detail.window = AXWindow(
            identity: WindowIdentity(pid: pid, windowNumber: number, bundleID: bundleID),
            element: element
        )
        return detail
    }

    private func windowNumberProbe(of element: AXUIElement, pid: pid_t) -> (
        id: CGWindowID?,
        dlsym: String,
        error: String,
        geometryMatches: String,
        source: String
    ) {
        let privateProbe = AXPrivate.probe(element)
        let dlsym = privateProbe.dlsym ? "true" : "false"
        let error = privateProbe.dlsym ? "\(privateProbe.error.rawValue)" : "missing-symbol"
        if let id = privateProbe.id {
            return (id, dlsym, error, "n/a", "private")
        }
        guard let frame = Self.readFrame(element) else {
            return (nil, dlsym, error, "n/a", "none")
        }
        let matches = query.windows(pid: pid).filter {
            abs($0.boundsAX.origin.x - frame.origin.x) <= 2
                && abs($0.boundsAX.origin.y - frame.origin.y) <= 2
                && abs($0.boundsAX.width - frame.width) <= 2
                && abs($0.boundsAX.height - frame.height) <= 2
        }
        let id = matches.count == 1 ? matches[0].windowNumber : nil
        return (id, dlsym, error, "\(matches.count)", id == nil ? "none" : "geometry")
    }

    private func recordAXLookup(
        event: String,
        operationID: UUID,
        pid: pid_t,
        windowNumber: CGWindowID,
        snappable: String? = nil,
        axError: String,
        axCount: String,
        axValues: String,
        skips: [String] = [],
        skipCounts: [String: Int] = [:],
        privateDlsym: String = "n/a",
        privateError: String = "n/a",
        geometryMatches: String = "n/a",
        numberSource: String = "n/a",
        matched: Bool,
        matchPath: String,
        resultWindowNumber: String = "nil",
        elapsedMs: String
    ) {
        var fields = [
            "operationID": operationID.uuidString,
            "pid": "\(pid)",
            "windowNumber": "\(windowNumber)",
            "axError": axError,
            "axCount": axCount,
            "axValues": axValues,
            "skips": SnapDiagnosticLog.boundedList(skips),
            "skipCounts": SnapDiagnosticLog.countSummary(skipCounts),
            "privateDlsym": privateDlsym,
            "privateError": privateError,
            "geometryMatches": geometryMatches,
            "numberSource": numberSource,
            "matched": matched ? "true" : "false",
            "matchPath": matchPath,
            "resultWindowNumber": resultWindowNumber,
            "elapsedMs": elapsedMs,
        ]
        if let snappable {
            fields["snappable"] = snappable
        }
        Log.snapDiagnostics.record(event, fields: fields)
    }

    private func elapsedMs(since start: TimeInterval) -> String {
        "\(Int((ProcessInfo.processInfo.systemUptime - start) * 1000))"
    }

    static func readFrame(_ element: AXUIElement) -> CGRect? {
        guard let origin = pointAttribute(element, kAXPositionAttribute as CFString),
              let size = sizeAttribute(element, kAXSizeAttribute as CFString) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func onAX<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// AX writes against this process bounce onto AppKit's window coordinator.
    /// Those mutations must run on the main thread; foreign windows stay on the
    /// dedicated AX queue so a hung target cannot stall the UI.
    private func onAX<T>(pid: pid_t, _ work: @escaping () -> T) async -> T {
        if OwnWindowFrameMutation.usesMainThreadAppKit(
            pid: pid,
            ownPID: ProcessInfo.processInfo.processIdentifier
        ) {
            await MainActor.run { work() }
        } else {
            await onAX(work)
        }
    }
}

private enum AXPrivate {
    typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    static func windowNumber(_ element: AXUIElement) -> CGWindowID? {
        probe(element).id
    }

    static func probe(_ element: AXUIElement) -> (id: CGWindowID?, dlsym: Bool, error: AXError) {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            return (nil, false, .failure)
        }
        let fn = unsafeBitCast(sym, to: GetWindow.self)
        var id: CGWindowID = 0
        let error = fn(element, &id)
        return (error == .success ? id : nil, true, error)
    }
}

private func copyElement(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
    return (ref as! AXUIElement)
}

private func copyArray(_ element: AXUIElement, _ name: String) -> [Any]? {
    copyArrayResult(element, name).values
}

private func copyArrayResult(_ element: AXUIElement, _ name: String) -> (values: [Any]?, error: AXError) {
    var ref: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &ref)
    guard error == .success else { return (nil, error) }
    return (ref as? [Any], error)
}

private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
    return ref as? String
}

private func boolAttribute(_ element: AXUIElement, _ name: CFString) -> Bool? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &ref) == .success else { return nil }
    return (ref as? Bool)
}

private func pointAttribute(_ element: AXUIElement, _ name: CFString) -> CGPoint? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &ref) == .success,
          CFGetTypeID(ref!) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    AXValueGetValue(ref as! AXValue, .cgPoint, &point)
    return point
}

private func sizeAttribute(_ element: AXUIElement, _ name: CFString) -> CGSize? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &ref) == .success,
          CFGetTypeID(ref!) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    AXValueGetValue(ref as! AXValue, .cgSize, &size)
    return size
}

enum AXFrameMutator {
    static func setFrame(_ frame: CGRect, of element: AXUIElement) -> CGRect? {
        var enhanced: Bool?
        if let value = boolAttribute(element, "AXEnhancedUserInterface" as CFString) {
            enhanced = value
            if value { setBool(element, "AXEnhancedUserInterface" as CFString, false) }
        }
        defer {
            if let enhanced { setBool(element, "AXEnhancedUserInterface" as CFString, enhanced) }
        }

        var target = frame
        if let minSize = sizeAttribute(element, "AXMinSize" as CFString) {
            target.size.width = max(target.size.width, minSize.width)
            target.size.height = max(target.size.height, minSize.height)
        }
        if let maxSize = sizeAttribute(element, "AXMaxSize" as CFString), maxSize.width > 0 {
            target.size.width = min(target.size.width, maxSize.width)
            target.size.height = min(target.size.height, maxSize.height)
        }

        for _ in 0..<3 {
            setSize(element, target.size)
            setPoint(element, target.origin)
            setSize(element, target.size)
            if let actual = AccessibilityClientLive.readFrame(element) {
                let err = max(abs(actual.origin.x - target.origin.x), abs(actual.origin.y - target.origin.y),
                              abs(actual.size.width - target.size.width), abs(actual.size.height - target.size.height))
                if err <= 2 { return actual }
            }
            Thread.sleep(forTimeInterval: 0.016)
        }
        return AccessibilityClientLive.readFrame(element)
    }

    private static func setPoint(_ element: AXUIElement, _ point: CGPoint) {
        var value = point
        if let ax = AXValueCreate(.cgPoint, &value) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, ax)
        }
    }

    private static func setSize(_ element: AXUIElement, _ size: CGSize) {
        var value = size
        if let ax = AXValueCreate(.cgSize, &value) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, ax)
        }
    }

    private static func setBool(_ element: AXUIElement, _ name: CFString, _ value: Bool) {
        AXUIElementSetAttributeValue(element, name, value as CFBoolean)
    }
}
