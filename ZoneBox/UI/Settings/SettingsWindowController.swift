import AppKit
import ServiceManagement
import ZoneBoxCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: NSWindow?

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
    }

    func showWindow() {
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.delegate = nil
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        runtime.settingsDidClose()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ZoneBox Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        if !runtime.trust.isTrusted() {
            let banner = NSTextField(wrappingLabelWithString: "Snapping is off until Accessibility is allowed. Open the guide to turn on the ZoneBox switch.")
            banner.textColor = .systemOrange
            banner.font = .systemFont(ofSize: 12, weight: .medium)
            stack.addArrangedSubview(banner)
            let guide = NSButton(title: "Show Accessibility Guide…", target: self, action: #selector(openAccess))
            guide.bezelStyle = .rounded
            stack.addArrangedSubview(guide)
        }

        stack.addArrangedSubview(checkbox("Enable snapping", runtime.settings.snapEnabled, #selector(toggleSnap)))
        stack.addArrangedSubview(checkbox("Hold Shift while dragging to snap", runtime.settings.snapOnShiftDrag, #selector(toggleShift)))
        stack.addArrangedSubview(checkbox("Right-click while dragging to snap", runtime.settings.snapOnRightClickDrag, #selector(toggleRight)))
        stack.addArrangedSubview(checkbox("Show zone numbers", runtime.settings.showZoneNumbers, #selector(toggleNumbers)))
        stack.addArrangedSubview(checkbox("Restore size when unsnapping", runtime.settings.restoreSizeOnUnsnap, #selector(toggleRestore)))

        let gutterLabel = NSTextField(labelWithString: "Gutter: \(runtime.settings.gutterPoints) pt")
        gutterLabel.tag = 50
        gutterLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(gutterLabel)
        let slider = NSSlider(value: Double(runtime.settings.gutterPoints), minValue: 0, maxValue: 40, target: self, action: #selector(gutterChanged(_:)))
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        stack.addArrangedSubview(slider)

        let hotkeys = NSTextField(wrappingLabelWithString: "Hotkeys (Control+Option): 1–9 snap focused window, Z editor, U unsnap, arrows next/previous zone.\nPaused automatically while VoiceOver is on.")
        hotkeys.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hotkeys)

        let access = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccess))
        access.bezelStyle = .rounded
        stack.addArrangedSubview(access)

        let login = checkbox("Launch at login", runtime.settings.launchAtLogin, #selector(toggleLogin))
        stack.addArrangedSubview(login)

        window.contentView = NSView()
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: content.topAnchor),
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            ])
        }
        return window
    }

    private func checkbox(_ title: String, _ on: Bool, _ selector: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: selector)
        button.state = on ? .on : .off
        return button
    }

    @objc private func toggleSnap(_ sender: NSButton) { runtime.setSnapEnabled(sender.state == .on) }
    @objc private func toggleShift(_ sender: NSButton) { runtime.settings.snapOnShiftDrag = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleRight(_ sender: NSButton) { runtime.settings.snapOnRightClickDrag = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleNumbers(_ sender: NSButton) { runtime.settings.showZoneNumbers = sender.state == .on; runtime.persistSettings() }
    @objc private func toggleRestore(_ sender: NSButton) { runtime.settings.restoreSizeOnUnsnap = sender.state == .on; runtime.persistSettings() }
    @objc private func openAccess() { runtime.openAccessibility() }

    @objc private func gutterChanged(_ sender: NSSlider) {
        runtime.settings.gutterPoints = Int(sender.doubleValue.rounded())
        if let label = window?.contentView?.viewWithTag(50) as? NSTextField {
            label.stringValue = "Gutter: \(runtime.settings.gutterPoints) pt"
        }
        runtime.persistSettings()
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        runtime.settings.launchAtLogin = sender.state == .on
        runtime.persistSettings()
        do {
            if runtime.settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item failed: \(error.localizedDescription, privacy: .public)")
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}
