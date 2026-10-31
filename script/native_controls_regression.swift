import AppKit

@main private struct NativeControlsRegression {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let parent = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 400, height: 100), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let help = HoverHelpButton(frame: NSRect(x: 60, y: 30, width: 20, height: 20))
        help.helpText = "保存或更新工作区时，也包含当前桌面上被其他窗口完全遮挡的窗口。"
        parent.contentView!.addSubview(help)
        parent.orderFrontRegardless()
        parent.makeKey()

        help.performClick(nil)
        let hint = parent.childWindows!.first!
        precondition(hint.isVisible && !hint.canBecomeKey && hint.ignoresMouseEvents)
        precondition(hint.frame.width == 268 && hint.frame.height > 30)
        help.cancelOperation(nil)
        precondition(parent.childWindows?.isEmpty != false && !hint.isVisible)
        print("CASE_OK help-click-escape-and-no-focus-steal")

        help.updateTrackingAreas()
        precondition(help.trackingAreas.contains { $0.options.contains(.activeAlways) })
        let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: parent.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        let exit = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: parent.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        help.mouseEntered(with: enter)
        help.mouseExited(with: exit)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        precondition(parent.childWindows?.isEmpty != false)
        help.mouseEntered(with: enter)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        precondition(parent.childWindows?.first?.isVisible == true)
        help.mouseExited(with: exit)
        precondition(parent.childWindows?.isEmpty != false)
        print("CASE_OK help-hover-and-cancel-pending-hover")

        help.performClick(nil)
        let closingHint = parent.childWindows!.first!
        parent.close()
        precondition(!closingHint.isVisible && parent.childWindows?.isEmpty != false)
        parent.orderFrontRegardless()
        help.performClick(nil)
        precondition(parent.childWindows?.first?.isVisible == true)
        parent.close()
        help.mouseEntered(with: enter)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        precondition(parent.childWindows?.isEmpty != false)
        print("CASE_OK help-parent-close-reopen-and-no-orphan")
        print("NATIVE_CONTROLS_REGRESSION_OK")
    }
}
