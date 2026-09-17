import Foundation

/// Whether an application should appear in a workspace snapshot.
///
/// Runtime activation policy is authoritative because some menu-bar-only apps
/// ship `LSUIElement=false`, start `.regular`, then switch to `.accessory`
/// once their status item is on the menu bar. Info.plist flags are the fallback
/// when no running process is available. Dock apps that also own a menu-bar
/// extra stay `.regular` and remain eligible.
public enum WorkspaceCaptureEligibility: Sendable {
    public enum ActivationPolicy: Equatable, Sendable {
        case regular
        case accessory
        case prohibited
    }

    public struct BundlePresentation: Equatable, Sendable {
        public var lsUIElement: Bool
        public var lsBackgroundOnly: Bool

        public init(lsUIElement: Bool = false, lsBackgroundOnly: Bool = false) {
            self.lsUIElement = lsUIElement
            self.lsBackgroundOnly = lsBackgroundOnly
        }
    }

    public static func shouldCapture(
        bundleID: String?,
        activationPolicy: ActivationPolicy?,
        presentation: BundlePresentation = BundlePresentation()
    ) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        if let activationPolicy {
            switch activationPolicy {
            case .regular:
                return true
            case .accessory, .prohibited:
                return false
            }
        }
        return !presentation.lsUIElement && !presentation.lsBackgroundOnly
    }

    public static func boolFlag(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let number as Int:
            return number != 0
        case let text as String:
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes":
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}
