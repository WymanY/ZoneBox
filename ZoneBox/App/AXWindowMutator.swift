import AppKit
import CoreGraphics
import Foundation
import ZoneBoxCore

@MainActor
final class AXWindowMutator: WindowMutating {
    weak var runtime: AppRuntime?
    var ax: AccessibilityClientLive?
    private var windows: [WindowIdentity: AXWindow] = [:]

    func remember(_ window: AXWindow) {
        windows[window.identity] = window
    }

    func forget(_ identity: WindowIdentity) {
        windows[identity] = nil
    }

    func applyFrame(_ frame: CGRect, of identity: WindowIdentity) async -> CGRect? {
        if OwnWindowFrameMutation.usesMainThreadAppKit(
            pid: identity.pid,
            ownPID: ProcessInfo.processInfo.processIdentifier
        ) {
            return applyOwnWindowFrame(frame, of: identity)
        }
        guard let window = await resolve(identity) else { return nil }
        return await ax?.setFrame(frame, of: window)
    }

    @MainActor
    private func applyOwnWindowFrame(_ frame: CGRect, of identity: WindowIdentity) -> CGRect? {
        guard let window = ownNSWindow(matching: identity.windowNumber) else {
            return nil
        }
        let flipHeight = runtime?.primaryFlipHeight ?? CoordinateConverter.primaryFlipHeight(
            screenFramesAppKit: NSScreen.screens.map { $0.frame }
        )
        let appKitFrame = OwnWindowFrameMutation.appKitFrame(
            fromAX: frame,
            primaryFlipHeight: flipHeight
        )
        let limits = OwnWindowFrameMutation.sizeLimits(
            applied: appKitFrame.size,
            previousMin: window.minSize,
            previousMax: window.maxSize
        )
        window.minSize = limits.min
        window.maxSize = limits.max
        window.setFrame(appKitFrame, display: true)
        return CoordinateConverter.axRect(fromAppKit: window.frame, primaryFlipHeight: flipHeight)
    }

    func raise(_ identity: WindowIdentity) async -> Bool {
        if OwnWindowFrameMutation.usesMainThreadAppKit(
            pid: identity.pid,
            ownPID: ProcessInfo.processInfo.processIdentifier
        ) {
            guard let window = ownNSWindow(matching: identity.windowNumber) else {
                return false
            }
            window.orderFront(nil)
            return true
        }
        guard let window = await resolve(identity) else { return false }
        return await ax?.raise(window) == .success
    }

    private func resolve(_ identity: WindowIdentity) async -> AXWindow? {
        if let window = windows[identity] {
            return window
        }
        if let pending = runtime?.pendingWindow, pending.identity == identity {
            windows[identity] = pending
            return pending
        }
        if let window = await ax?.window(matching: identity) {
            windows[identity] = window
            return window
        }
        return nil
    }

    private func ownNSWindow(matching number: CGWindowID) -> NSWindow? {
        runtime?.ownNSWindow(matching: number)
    }
}
