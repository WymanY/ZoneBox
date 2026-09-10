import XCTest
@testable import ZoneBoxCore

final class SnapDiagnosticLogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testDefaultPathIsSeparatedByAppIdentity() {
        let log = SnapDiagnosticLog()
        XCTAssertEqual(
            log.fileURL,
            AppIdentity.defaultSupportDirectory.appendingPathComponent("Logs/snap.jsonl")
        )
    }

    func testEntriesKeepOrderSessionAndEscapedFields() throws {
        let log = SnapDiagnosticLog(directory: directory)
        let session = UUID()
        for index in 0..<20 {
            log.record("target", sessionID: session, fields: [
                "index": "\(index)",
                "value": "quoted \"value\"\nnext line",
            ])
        }
        log.flush()
        let entries = try read(log.fileURL)
        XCTAssertEqual(entries.count, 20)
        for (index, entry) in entries.enumerated() {
            XCTAssertEqual(entry["sessionID"] as? String, session.uuidString)
            XCTAssertEqual(entry["runID"] as? String, log.runID.uuidString)
            let timestamp = try XCTUnwrap(entry["timestamp"] as? String)
            XCTAssertNotNil(timestamp.range(of: #"\.\d{3}Z$"#, options: .regularExpression))
            XCTAssertNotNil(entry["uptime"] as? Double)
            let fields = try XCTUnwrap(entry["fields"] as? [String: String])
            XCTAssertEqual(fields["index"], "\(index)")
            XCTAssertEqual(fields["value"], "quoted \"value\"\nnext line")
            XCTAssertNil(entry["environment"])
            XCTAssertNil(entry["windowTitle"])
        }
    }

    func testNewLoggerAppendsAcrossRestarts() throws {
        var first: SnapDiagnosticLog? = SnapDiagnosticLog(directory: directory)
        first?.record("before-restart")
        first?.flush()
        first = nil
        let second = SnapDiagnosticLog(directory: directory)
        second.record("after-restart")
        second.flush()
        let entries = try read(second.fileURL)
        XCTAssertEqual(entries.compactMap { $0["event"] as? String }, ["before-restart", "after-restart"])
        XCTAssertNotEqual(entries[0]["runID"] as? String, entries[1]["runID"] as? String)
    }

    func testRotationBoundsFileCountAndSizeAndKeepsNewestEntries() throws {
        let log = SnapDiagnosticLog(directory: directory, maximumFileBytes: 1024, fileCount: 3)
        for index in 0..<80 {
            log.record("target", fields: ["index": "\(index)"])
        }
        log.flush()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)
        var indices: [Int] = []
        for url in files {
            XCTAssertLessThanOrEqual(try Data(contentsOf: url).count, 1024)
            indices += try read(url).compactMap { entry in
                (entry["fields"] as? [String: String])?["index"].flatMap(Int.init)
            }
        }
        XCTAssertEqual(indices.sorted(), Array((80 - indices.count)..<80))
        XCTAssertEqual((try read(log.fileURL).last?["fields"] as? [String: String])?["index"], "79")
    }

    func testSingleFileRotationAndOversizedEntryStayBounded() throws {
        let log = SnapDiagnosticLog(directory: directory, maximumFileBytes: 512, fileCount: 1)
        log.record("oversized", fields: ["data": String(repeating: "x", count: 2000)])
        for index in 0..<10 {
            log.record("target", fields: ["index": "\(index)"])
        }
        log.flush()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["snap.jsonl"])
        XCTAssertLessThanOrEqual(try Data(contentsOf: log.fileURL).count, 512)
        XCTAssertEqual((try read(log.fileURL).last?["fields"] as? [String: String])?["index"], "9")
    }

    func testRestartRotatesAnAlreadyFullFileAndPreservesOtherFiles() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldData = Data(String(repeating: "x", count: 512).utf8)
        try oldData.write(to: directory.appendingPathComponent("snap.jsonl"))
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        let log = SnapDiagnosticLog(directory: directory, maximumFileBytes: 512, fileCount: 2)
        log.record("after-restart")
        log.flush()
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("snap.1.jsonl")), oldData)
        XCTAssertEqual(try read(log.fileURL).first?["event"] as? String, "after-restart")
        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "keep")
    }

    func testLogFilesAreOwnerOnly() throws {
        let log = SnapDiagnosticLog(directory: directory)
        log.record("startup")
        log.flush()
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: log.fileURL.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testUnavailableDirectoryDoesNotThrowOrOverwriteExistingFile() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("not-a-directory")
        let original = Data("keep".utf8)
        try original.write(to: blocker)
        let log = SnapDiagnosticLog(directory: blocker)
        log.record("target")
        log.flush()
        XCTAssertEqual(try Data(contentsOf: blocker), original)
    }

    func testBoundedListsAndCaptureDiscardReasonsStayTechnical() {
        XCTAssertEqual(SnapDiagnosticLog.boundedList((0..<12).map(String.init)), "0,1,2,3,4,5,6,7")
        XCTAssertEqual(
            SnapDiagnosticLog.countSummary(["missingWindowNumber": 2, "fullscreen": 1]),
            "fullscreen:1,missingWindowNumber:2"
        )
        XCTAssertEqual(
            SnapDiagnosticLog.captureDiscardReason(held: true, generation: 1, currentGeneration: 1, hasRef: false),
            "noCapturedRef"
        )
        XCTAssertEqual(
            SnapDiagnosticLog.captureDiscardReason(held: false, generation: 1, currentGeneration: 2, hasRef: true),
            "buttonReleased"
        )
        XCTAssertEqual(
            SnapDiagnosticLog.captureDiscardReason(held: true, generation: 1, currentGeneration: 2, hasRef: true),
            "generationMismatch"
        )
        XCTAssertEqual(
            SnapDiagnosticLog.captureDiscardReason(held: true, generation: 3, currentGeneration: 3, hasRef: true),
            "none"
        )
    }

    private func read(_ url: URL) throws -> [[String: Any]] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
    }
}
