import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Follows the system language list and posts when it actually changes.
/// Bundle localizations are cached at launch; this reads `AppleLanguages` so a
/// live System Settings change can refresh the UI without relaunching.
public final class LanguageCenter: NSObject {
    public static let shared = LanguageCenter()
    public static let didChangeNotification = Notification.Name("ZoneBoxLanguageDidChange")

    /// Read from any isolation. Updated on the main actor when the system language changes.
    nonisolated(unsafe) public static var language: AppLanguage = LanguageCenter.resolveEffective()
    nonisolated(unsafe) public static var preference: AppLanguagePreference = .system

    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
    }

    public static func resolveFromSystem(
        appleLanguages: [String]? = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
        preferred: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        AppLanguage.resolve(preferred: appleLanguages ?? preferred)
    }

    public static func resolveEffective(
        preference: AppLanguagePreference = LanguageCenter.preference,
        preferred: [String]? = nil
    ) -> AppLanguage {
        switch preference {
        case .system:
            let list = preferred
                ?? (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])
                ?? Locale.preferredLanguages
            return AppLanguage.resolve(preferred: list)
        case .english:
            return .english
        case .chineseSimplified:
            return .chineseSimplified
        }
    }

    @MainActor
    public func applyPreference(_ preference: AppLanguagePreference) {
        Self.preference = preference
        refresh(force: true)
    }

    @MainActor
    public func start() {
        guard observers.isEmpty else { return }

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: Notification.Name("AppleLanguagePreferencesChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in LanguageCenter.shared.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in LanguageCenter.shared.refresh() }
        })
        #if canImport(AppKit)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in LanguageCenter.shared.refresh() }
        })
        #endif
        UserDefaults.standard.addObserver(
            self,
            forKeyPath: "AppleLanguages",
            options: [.new],
            context: nil
        )
    }

    nonisolated public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "AppleLanguages" else { return }
        Task { @MainActor in
            LanguageCenter.shared.refresh()
        }
    }

    @MainActor
    public func refresh(force: Bool = false) {
        let next = Self.resolveEffective()
        guard force || next != Self.language else { return }
        Self.language = next
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
