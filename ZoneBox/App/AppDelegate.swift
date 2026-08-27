import AppKit

/// AppKit's default `@main` on `NSApplicationDelegate` is `NSApplicationMain()`,
/// which only instantiates a delegate from a MainMenu nib. This project has no
/// nib, so that path never calls `applicationDidFinishLaunching` and never
/// creates the status item. Provide an explicit `main()` that retains the
/// delegate (`NSApplication.delegate` is weak).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retained: AppDelegate?
    private let runtime = AppRuntime()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        NSApp.setActivationPolicy(.accessory)
        runtime.isEditorOpen = false
        runtime.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.hideAllOverlays()
        runtime.teardown()
    }
}
