import CoreGraphics

struct WindowRef: Equatable, Sendable {
    var pid: pid_t
    var windowNumber: CGWindowID
    var boundsAX: CGRect
    var bundleID: String?
    var layer: Int
}

protocol WindowQuerying: Sendable {
    func topmostWindow(atAXPoint point: CGPoint, excludingPID: pid_t) -> WindowRef?
    func windowExists(pid: pid_t, windowNumber: CGWindowID) -> Bool
    func windows(pid: pid_t) -> [WindowRef]
}
