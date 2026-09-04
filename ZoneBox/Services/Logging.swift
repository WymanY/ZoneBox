import Foundation
import os

public enum Log {
    public static let subsystem = AppIdentity.bundleID

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let ax = Logger(subsystem: subsystem, category: "ax")
    public static let snap = Logger(subsystem: subsystem, category: "snap")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let overlay = Logger(subsystem: subsystem, category: "overlay")
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    public static let display = Logger(subsystem: subsystem, category: "display")
    public static let trust = Logger(subsystem: subsystem, category: "trust")
    public static let pin = Logger(subsystem: subsystem, category: "pin")
    public static let divider = Logger(subsystem: subsystem, category: "divider")
    public static let workspace = Logger(subsystem: subsystem, category: "workspace")
    public static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
}
