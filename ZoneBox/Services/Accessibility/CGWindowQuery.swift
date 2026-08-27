import AppKit
import CoreGraphics
import ZoneBoxCore

struct CGWindowQuery: WindowQuerying {
    func topmostWindow(atAXPoint point: CGPoint, excludingPID: pid_t) -> WindowRef? {
        windows(excludingPID: excludingPID).first { $0.layer == 0 && $0.boundsAX.contains(point) }
    }

    func windowExists(pid: pid_t, windowNumber: CGWindowID) -> Bool {
        windows(excludingPID: -1).contains { $0.pid == pid && $0.windowNumber == windowNumber }
    }

    func windows(pid: pid_t) -> [WindowRef] {
        windows(excludingPID: -1).filter { $0.pid == pid }
    }

    func windows(excludingPID: pid_t) -> [WindowRef] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
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
