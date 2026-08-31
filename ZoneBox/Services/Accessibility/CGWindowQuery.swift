import AppKit
import CoreGraphics
import ZoneBoxCore

struct CGWindowQuery: WindowQuerying {
    func topmostWindow(atAXPoint point: CGPoint, excludingPID: pid_t) -> WindowRef? {
        windows(excludingPID: excludingPID).first { $0.layer == 0 && $0.boundsAX.contains(point) }
    }

    func windowExists(pid: pid_t, windowNumber: CGWindowID) -> Bool {
        allWindows(excludingPID: -1).contains { $0.pid == pid && $0.windowNumber == windowNumber }
    }

    func windows(pid: pid_t) -> [WindowRef] {
        windows(excludingPID: -1).filter { $0.pid == pid }
    }

    func windows(excludingPID: pid_t) -> [WindowRef] {
        makeWindows(options: [.optionOnScreenOnly, .excludeDesktopElements], excludingPID: excludingPID)
    }

    func allWindows(excludingPID: pid_t) -> [WindowRef] {
        makeWindows(options: [.optionAll, .excludeDesktopElements], excludingPID: excludingPID)
    }

    /// Front-to-back geometry for the pin watchdog. Unlike `windows(excludingPID:)`
    /// this skips the per-window `NSRunningApplication` lookup, which matters
    /// because the watchdog samples up to 60 times a second while a mirrored
    /// window is being dragged or resized.
    func pinSnapshots(excludingPID: pid_t) -> [PinWindowSnapshot] {
        let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return info.compactMap { dict -> PinWindowSnapshot? in
            guard let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  pid != excludingPID,
                  let number = dict[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            return PinWindowSnapshot(
                identity: WindowIdentity(pid: pid, windowNumber: number),
                frameAX: CGRect(
                    x: boundsDict["X"] ?? 0,
                    y: boundsDict["Y"] ?? 0,
                    width: boundsDict["Width"] ?? 0,
                    height: boundsDict["Height"] ?? 0
                ),
                layer: dict[kCGWindowLayer as String] as? Int ?? 0
            )
        }
    }

    /// Geometry for one known on-screen window. Roughly 0.2ms against ~1.3ms for
    /// a full on-screen enumeration, which is what makes it affordable to follow
    /// a pinned window frame-by-frame while it is being dragged or resized.
    /// Returns nil for windows that are minimized or on another Space.
    func frameAX(ofWindow windowNumber: CGWindowID) -> CGRect? {
        let info = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowNumber
        ) as? [[String: Any]] ?? []
        guard let dict = info.first,
              dict[kCGWindowLayer as String] as? Int ?? 0 == 0,
              let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat]
        else { return nil }
        return CGRect(
            x: bounds["X"] ?? 0,
            y: bounds["Y"] ?? 0,
            width: bounds["Width"] ?? 0,
            height: bounds["Height"] ?? 0
        )
    }

    /// Identities of every window including off-screen and minimized ones, with
    /// no geometry or bundle resolution. Used to tell a hidden pin apart from a
    /// closed one.
    func allWindowIdentities(excludingPID: pid_t) -> Set<WindowIdentity> {
        let info = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        var identities = Set<WindowIdentity>(minimumCapacity: info.count)
        for dict in info {
            guard let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  pid != excludingPID,
                  let number = dict[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            identities.insert(WindowIdentity(pid: pid, windowNumber: number))
        }
        return identities
    }

    private func makeWindows(options: CGWindowListOption, excludingPID: pid_t) -> [WindowRef] {
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { dict -> WindowRef? in
            guard let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  pid != excludingPID,
                  let number = dict[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            let layer = dict[kCGWindowLayer as String] as? Int ?? 0
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            return WindowRef(pid: pid, windowNumber: number, boundsAX: bounds, bundleID: bundleID, layer: layer)
        }
    }
}
