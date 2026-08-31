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

protocol AccessibilityClient: AnyObject {
    func focusedWindow() async -> AXWindow?
    func window(matching identity: WindowIdentity) async -> AXWindow?
    func frame(of window: AXWindow) async -> CGRect?
    func setFrame(_ frame: CGRect, of window: AXWindow) async -> CGRect?
    @discardableResult func raise(_ window: AXWindow) async -> AXError
}

final class AccessibilityClientLive: AccessibilityClient {
    private let queue = DispatchQueue(label: "com.fancyzone.ax", qos: .userInteractive)
    private let query: WindowQuerying
    private let excluded: () -> [String]
    private let snapDialogs: () -> Bool
    private let trusted: () -> Bool

    init(
        query: WindowQuerying,
        excluded: @escaping () -> [String],
        snapDialogs: @escaping () -> Bool,
        trusted: @escaping () -> Bool
    ) {
        self.query = query
        self.excluded = excluded
        self.snapDialogs = snapDialogs
        self.trusted = trusted
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
            let app = AXUIElementCreateApplication(identity.pid)
            guard let windows = copyArray(app, kAXWindowsAttribute) else { return nil }
            for element in windows {
                let axElement = element as! AXUIElement
                if let window = makeWindow(pid: identity.pid, element: axElement),
                   window.identity.windowNumber == identity.windowNumber {
                    return window
                }
            }
            return nil
        }
    }

    func frame(of window: AXWindow) async -> CGRect? {
        await onAX { Self.readFrame(window.element) }
    }

    func setFrame(_ frame: CGRect, of window: AXWindow) async -> CGRect? {
        await onAX { [self] in
            guard trusted() else { return nil }
            return AXFrameMutator.setFrame(frame, of: window.element)
        }
    }

    @discardableResult
    func raise(_ window: AXWindow) async -> AXError {
        await onAX { [self] in
            guard trusted() else { return .apiDisabled }
            return AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
    }

    func isSnappable(_ ref: WindowRef) -> Bool {
        guard ref.layer == 0,
              ref.boundsAX.width >= 80,
              ref.boundsAX.height >= 80,
              ref.pid != ProcessInfo.processInfo.processIdentifier
        else { return false }
        if let bundle = ref.bundleID, excluded().contains(bundle) { return false }
        return true
    }

    func resolveAsync(ref: WindowRef) async -> AXWindow? {
        await onAX { self.resolve(ref: ref) }
    }

    func resolve(ref: WindowRef) -> AXWindow? {
        guard isSnappable(ref) else { return nil }
        let app = AXUIElementCreateApplication(ref.pid)
        guard let windows = copyArray(app, kAXWindowsAttribute) else { return nil }
        for element in windows {
            let axElement = unsafeBitCast(element as AnyObject, to: AXUIElement.self)
            if let window = makeWindow(pid: ref.pid, element: axElement),
               window.identity.windowNumber == ref.windowNumber {
                return window
            }
        }
        if let match = windows.compactMap({ element -> AXWindow? in
            let el = unsafeBitCast(element as AnyObject, to: AXUIElement.self)
            guard let frame = Self.readFrame(el) else { return nil }
            guard frame.insetBy(dx: -2, dy: -2).intersects(ref.boundsAX) else { return nil }
            return makeWindow(pid: ref.pid, element: el)
        }).first {
            return match
        }
        return nil
    }

    private func makeWindow(pid: pid_t, element: AXUIElement) -> AXWindow? {
        guard isStandardWindow(element) else { return nil }
        if isFullscreen(element) { return nil }
        if boolAttribute(element, "AXMinimized" as CFString) == true { return nil }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        if let bundleID, excluded().contains(bundleID) { return nil }
        guard let number = windowNumber(of: element, pid: pid) else { return nil }
        return AXWindow(identity: WindowIdentity(pid: pid, windowNumber: number, bundleID: bundleID), element: element)
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
        if let id = AXPrivate.windowNumber(element) { return id }
        guard let frame = Self.readFrame(element) else { return nil }
        let matches = query.windows(pid: pid).filter {
            abs($0.boundsAX.origin.x - frame.origin.x) <= 2
                && abs($0.boundsAX.origin.y - frame.origin.y) <= 2
                && abs($0.boundsAX.width - frame.width) <= 2
                && abs($0.boundsAX.height - frame.height) <= 2
        }
        return matches.count == 1 ? matches[0].windowNumber : nil
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
}

private enum AXPrivate {
    typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    static func windowNumber(_ element: AXUIElement) -> CGWindowID? {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: GetWindow.self)
        var id: CGWindowID = 0
        return fn(element, &id) == .success ? id : nil
    }
}

private func copyElement(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
    return (ref as! AXUIElement)
}

private func copyArray(_ element: AXUIElement, _ name: String) -> [Any]? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
    return ref as? [Any]
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
