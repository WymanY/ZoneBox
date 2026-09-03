import Foundation

/// Simulator.app keeps running after its last device shuts down, and neither
/// a reopen event nor a second launch makes it boot a device again. Restore
/// has to boot one through `simctl`; this decides which.
public enum SimulatorDevicePlan {
    public static let bundleID = "com.apple.iphonesimulator"
    public static let preferencesDomain = "com.apple.iphonesimulator"
    public static let currentDeviceKey = "CurrentDeviceUDID"

    public struct Device: Equatable, Sendable {
        public var udid: String
        public var name: String
        public var state: String
        public var isAvailable: Bool
        public var runtime: String
        public var lastBootedAt: Date?

        public init(
            udid: String,
            name: String,
            state: String,
            isAvailable: Bool,
            runtime: String,
            lastBootedAt: Date? = nil
        ) {
            self.udid = udid
            self.name = name
            self.state = state
            self.isAvailable = isAvailable
            self.runtime = runtime
            self.lastBootedAt = lastBootedAt
        }

        /// Booting counts as active: Simulator already has (or is about to
        /// show) a window for it, so booting another device would add a
        /// second window the profile never asked for.
        public var isActive: Bool {
            state == "Booted" || state == "Booting"
        }
    }

    /// Parses `xcrun simctl list devices -j`.
    public static func devices(fromSimctlJSON data: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = root["devices"] as? [String: Any]
        else { return [] }
        let formatter = ISO8601DateFormatter()
        var result: [Device] = []
        for runtime in byRuntime.keys.sorted() {
            guard let entries = byRuntime[runtime] as? [[String: Any]] else { continue }
            for entry in entries {
                guard let udid = entry["udid"] as? String, !udid.isEmpty else { continue }
                result.append(
                    Device(
                        udid: udid,
                        name: entry["name"] as? String ?? "",
                        state: entry["state"] as? String ?? "",
                        isAvailable: entry["isAvailable"] as? Bool ?? false,
                        runtime: runtime,
                        lastBootedAt: (entry["lastBootedAt"] as? String).flatMap(formatter.date(from:))
                    )
                )
            }
        }
        return result
    }

    public static func hasActiveDevice(_ devices: [Device]) -> Bool {
        devices.contains(where: \.isActive)
    }

    /// The device Simulator itself would open: its remembered current device
    /// when that still exists, otherwise the most recently booted available
    /// device, preferring iOS so a watch or TV window does not stand in for
    /// the phone the profile was captured with.
    public static func deviceToBoot(preferredUDID: String?, devices: [Device]) -> Device? {
        let available = devices.filter(\.isAvailable)
        if let preferredUDID,
           let preferred = available.first(where: { $0.udid.caseInsensitiveCompare(preferredUDID) == .orderedSame }) {
            return preferred
        }
        let ranked = available.sorted { lhs, rhs in
            let lhsIOS = lhs.runtime.contains("iOS")
            let rhsIOS = rhs.runtime.contains("iOS")
            if lhsIOS != rhsIOS { return lhsIOS }
            switch (lhs.lastBootedAt, rhs.lastBootedAt) {
            case let (l?, r?): return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.name < rhs.name
            }
        }
        return ranked.first
    }
}
