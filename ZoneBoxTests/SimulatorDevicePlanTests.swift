import XCTest
import ZoneBoxCore

final class SimulatorDevicePlanTests: XCTestCase {
    private let json = """
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.watchOS-11-0": [
          {"udid": "W-1", "name": "Apple Watch", "state": "Shutdown", "isAvailable": true,
           "lastBootedAt": "2026-09-01T10:00:00Z"}
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
          {"udid": "A-1", "name": "iPhone 16 Pro", "state": "Shutdown", "isAvailable": true,
           "lastBootedAt": "2026-08-01T10:00:00Z"},
          {"udid": "A-2", "name": "iPhone 17 Pro", "state": "Shutdown", "isAvailable": true,
           "lastBootedAt": "2026-08-15T10:00:00Z"},
          {"udid": "A-3", "name": "Broken", "state": "Shutdown", "isAvailable": false,
           "lastBootedAt": "2026-08-30T10:00:00Z"}
        ]
      }
    }
    """

    private var devices: [SimulatorDevicePlan.Device] {
        SimulatorDevicePlan.devices(fromSimctlJSON: Data(json.utf8))
    }

    func testParsesEveryRuntime() {
        let parsed = devices
        XCTAssertEqual(parsed.map(\.udid), ["A-1", "A-2", "A-3", "W-1"])
        XCTAssertEqual(parsed.first?.runtime, "com.apple.CoreSimulator.SimRuntime.iOS-18-5")
        XCTAssertNotNil(parsed.first?.lastBootedAt)
        XCTAssertFalse(SimulatorDevicePlan.hasActiveDevice(parsed))
    }

    func testBootingAndBootedCountAsActive() {
        var booting = devices
        booting[0].state = "Booting"
        XCTAssertTrue(SimulatorDevicePlan.hasActiveDevice(booting))
        var booted = devices
        booted[1].state = "Booted"
        XCTAssertTrue(SimulatorDevicePlan.hasActiveDevice(booted))
    }

    func testPrefersSimulatorsRememberedCurrentDevice() {
        XCTAssertEqual(
            SimulatorDevicePlan.deviceToBoot(preferredUDID: "a-1", devices: devices)?.udid,
            "A-1"
        )
    }

    func testUnavailableOrUnknownPreferredDeviceFallsBackToRecentIOSDevice() {
        XCTAssertEqual(
            SimulatorDevicePlan.deviceToBoot(preferredUDID: "A-3", devices: devices)?.udid,
            "A-2"
        )
        XCTAssertEqual(
            SimulatorDevicePlan.deviceToBoot(preferredUDID: "GONE", devices: devices)?.udid,
            "A-2"
        )
        XCTAssertEqual(
            SimulatorDevicePlan.deviceToBoot(preferredUDID: nil, devices: devices)?.udid,
            "A-2"
        )
    }

    func testNonIOSDeviceOnlyWhenNothingElseIsAvailable() {
        let watchOnly = devices.filter { $0.runtime.contains("watchOS") }
        XCTAssertEqual(SimulatorDevicePlan.deviceToBoot(preferredUDID: nil, devices: watchOnly)?.udid, "W-1")
        XCTAssertNil(SimulatorDevicePlan.deviceToBoot(preferredUDID: nil, devices: []))
    }

    func testMalformedJSONYieldsNoDevices() {
        XCTAssertEqual(SimulatorDevicePlan.devices(fromSimctlJSON: Data("nope".utf8)), [])
        XCTAssertEqual(SimulatorDevicePlan.devices(fromSimctlJSON: Data("{}".utf8)), [])
    }
}
