import CryptoKit
import Foundation
import IOKit

enum DeviceIdentity {
    static func instanceName() -> String {
        let host = Host.current().localizedName ?? "Mac"
        let digest = SHA256.hash(data: Data(platformUUID().utf8))
        let hex = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(host) (\(hex))"
    }

    static func platformUUID() -> String {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return "unknown" }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return "unknown"
        }
        return (cf.takeRetainedValue() as? String) ?? "unknown"
    }
}
