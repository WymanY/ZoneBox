import AppKit
import ZoneBoxCore

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
        let arguments = ProcessInfo.processInfo.arguments
        let resume = Self.welcomePage(from: arguments)
        var forceTour = false
        var suppressTour = false
#if DEBUG
        forceTour = arguments.contains("--show-welcome")
        suppressTour = arguments.contains("--skip-welcome")
#endif
        runtime.start(resume: resume, forceTour: forceTour, suppressTour: suppressTour)
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--open-settings") {
            DispatchQueue.main.async { [runtime] in runtime.openSettings() }
        }
#endif
    }

    private static func welcomePage(from arguments: [String]) -> OnboardingPage? {
        guard let index = arguments.firstIndex(of: "--welcome-page"),
              arguments.index(after: index) < arguments.endIndex
        else { return nil }
        return OnboardingPage(rawValue: arguments[arguments.index(after: index)])
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.hideAllOverlays()
        runtime.teardown()
    }
}
