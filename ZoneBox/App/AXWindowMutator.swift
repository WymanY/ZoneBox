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
        guard let window = await resolve(identity) else { return nil }
        return await ax?.setFrame(frame, of: window)
    }

    func raise(_ identity: WindowIdentity) async -> Bool {
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
}
