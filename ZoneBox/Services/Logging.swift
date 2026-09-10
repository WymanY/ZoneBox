import Foundation
import os

public enum Log {
    public static let subsystem = AppIdentity.bundleID
    public static let snapDiagnostics = SnapDiagnosticLog()

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

/// Local, bounded history for intermittent drag failures. Callers pass technical
/// fields only, never window titles, document contents, or accessibility dumps.
public final class SnapDiagnosticLog: @unchecked Sendable {
    public let directory: URL
    public let runID = UUID()
    public var fileURL: URL { directory.appendingPathComponent("snap.jsonl") }

    private let queue = DispatchQueue(label: "com.fancyzone.snap-diagnostics", qos: .utility)
    private let maximumFileBytes: Int
    private let fileCount: Int
    private var handle: FileHandle?
    private var byteCount = 0
    private var reportedWriteError = false

    public init(
        directory: URL = AppIdentity.defaultSupportDirectory.appendingPathComponent("Logs", isDirectory: true),
        maximumFileBytes: Int = 2 * 1024 * 1024,
        fileCount: Int = 5
    ) {
        self.directory = directory
        self.maximumFileBytes = max(512, maximumFileBytes)
        self.fileCount = max(1, fileCount)
    }

    private struct Entry: Encodable, Sendable {
        var timestamp: Date
        var uptime: TimeInterval
        var runID: UUID
        var processID: Int32
        var sessionID: UUID?
        var event: String
        var fields: [String: String]
    }

    public func record(_ event: String, sessionID: UUID? = nil, fields: [String: String] = [:]) {
        let entry = Entry(
            timestamp: Date(),
            uptime: ProcessInfo.processInfo.systemUptime,
            runID: runID,
            processID: ProcessInfo.processInfo.processIdentifier,
            sessionID: sessionID,
            event: String(event.prefix(128)),
            fields: fields
        )
        queue.async { [self] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .custom { date, encoder in
                    var container = encoder.singleValueContainer()
                    try container.encode(date.ISO8601Format(.init(includingFractionalSeconds: true)))
                }
                encoder.outputFormatting = [.sortedKeys]
                var data = try encoder.encode(entry)
                data.append(0x0A)
                guard data.count <= maximumFileBytes else { return }
                try openIfNeeded()
                if byteCount + data.count > maximumFileBytes {
                    try rotate()
                    try openIfNeeded()
                }
                try handle?.write(contentsOf: data)
                byteCount += data.count
            } catch {
                try? handle?.close()
                handle = nil
                if !reportedWriteError {
                    reportedWriteError = true
                    Log.snap.error("Persistent snap diagnostics unavailable, error code \((error as NSError).code, privacy: .public)")
                }
            }
        }
    }

    /// Used at normal shutdown and by tests, never on the drag sampling path.
    public func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    private func openIfNeeded() throws {
        guard handle == nil else { return }
        let files = FileManager.default
        try files.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !files.fileExists(atPath: fileURL.path) {
            guard files.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let opened = try FileHandle(forWritingTo: fileURL)
        do {
            byteCount = Int(try opened.seekToEnd())
            handle = opened
        } catch {
            try? opened.close()
            throw error
        }
    }

    private func rotate() throws {
        try handle?.close()
        handle = nil
        let files = FileManager.default
        let oldest = archiveURL(fileCount - 1)
        if files.fileExists(atPath: oldest.path) {
            try files.removeItem(at: oldest)
        }
        if fileCount > 1 {
            for index in stride(from: fileCount - 2, through: 0, by: -1) {
                let source = archiveURL(index)
                if files.fileExists(atPath: source.path) {
                    try files.moveItem(at: source, to: archiveURL(index + 1))
                }
            }
        }
        byteCount = 0
    }

    private func archiveURL(_ index: Int) -> URL {
        index == 0 ? fileURL : directory.appendingPathComponent("snap.\(index).jsonl")
    }

    deinit {
        try? handle?.close()
    }
}

extension SnapDiagnosticLog {
    public static let maxListItems = 8

    public static func boundedList(_ values: [String], limit: Int = maxListItems) -> String {
        Array(values.prefix(limit)).joined(separator: ",")
    }

    public static func countSummary(_ counts: [String: Int]) -> String {
        counts.keys.sorted().map { key in
            "\(key):\(counts[key] ?? 0)"
        }.joined(separator: ",")
    }

    public static func captureDiscardReason(
        held: Bool,
        generation: Int,
        currentGeneration: Int,
        hasRef: Bool
    ) -> String {
        if !hasRef { return "noCapturedRef" }
        if !held { return "buttonReleased" }
        if generation != currentGeneration { return "generationMismatch" }
        return "none"
    }
}
