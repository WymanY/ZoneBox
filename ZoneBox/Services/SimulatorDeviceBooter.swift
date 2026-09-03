import Foundation
import ZoneBoxCore

/// Boots a Simulator device through `simctl` when Simulator.app is running
/// with no device. Blocking; run it off the main actor.
struct SimulatorDeviceBooter: Sendable {
    enum Outcome: Equatable, Sendable {
        case alreadyActive
        case booted(udid: String, name: String)
        case noDevice
        case failed(String)
    }

    /// `Xcode.app/Contents/Developer`, derived from the Simulator.app the
    /// profile is about to open so `xcrun` matches that Xcode even when
    /// `xcode-select` points elsewhere.
    static func developerDirectory(simulatorAppURL: URL) -> URL {
        simulatorAppURL.deletingLastPathComponent().deletingLastPathComponent()
    }

    var developerDirectory: URL
    var runSimctl: @Sendable (_ developerDirectory: URL, _ arguments: [String]) -> (status: Int32, stdout: Data, stderr: String)
        = SimulatorDeviceBooter.runXcrun
    var preferredUDID: @Sendable () -> String? = {
        UserDefaults(suiteName: SimulatorDevicePlan.preferencesDomain)?
            .string(forKey: SimulatorDevicePlan.currentDeviceKey)
    }

    init(developerDirectory: URL) {
        self.developerDirectory = developerDirectory
    }

    func ensureDeviceBooted() -> Outcome {
        let list = runSimctl(developerDirectory, ["simctl", "list", "devices", "-j"])
        guard list.status == 0 else {
            return .failed("simctl list exit=\(list.status) \(list.stderr)")
        }
        let devices = SimulatorDevicePlan.devices(fromSimctlJSON: list.stdout)
        if SimulatorDevicePlan.hasActiveDevice(devices) { return .alreadyActive }
        guard let device = SimulatorDevicePlan.deviceToBoot(preferredUDID: preferredUDID(), devices: devices) else {
            return .noDevice
        }
        let boot = runSimctl(developerDirectory, ["simctl", "boot", device.udid])
        // Simulator may have started booting the same device between the two
        // calls; simctl then reports the device state instead of failing.
        if boot.status == 0 || boot.stderr.contains("current state: Boot") {
            return .booted(udid: device.udid, name: device.name)
        }
        return .failed("simctl boot exit=\(boot.status) \(boot.stderr)")
    }

    private static func runXcrun(developerDirectory: URL, arguments: [String]) -> (status: Int32, stdout: Data, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["DEVELOPER_DIR"] = developerDirectory.path
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return (-1, Data(), error.localizedDescription)
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            stdout,
            String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
