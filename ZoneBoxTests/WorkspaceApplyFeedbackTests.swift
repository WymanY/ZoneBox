import XCTest
@testable import ZoneBoxCore

final class WorkspaceApplyFeedbackTests: XCTestCase {
    func testConstrainedMovedWindowIsNotReportedAsThirdFailure() {
        let chatGPT = WindowIdentity(pid: 10, windowNumber: 1, bundleID: "com.openai.codex")
        let aliDrive = WindowIdentity(pid: 20, windowNumber: 2, bundleID: "com.alicloud.smartdrive")
        let issue = WindowOrganizeIssue(
            identity: aliDrive,
            behavior: .sizeConstrained,
            obstacleFrameAX: .zero,
            observedFrameAX: .zero
        )

        let feedback = WorkspaceApplyFeedback.make(
            moved: [chatGPT, aliDrive],
            issues: [issue],
            skipped: [],
            missingCount: 0,
            staleCount: 0,
            disconnectedCount: 0,
            applicationName: { $0 == aliDrive ? "阿里云盘" : "ChatGPT" },
            language: .chineseSimplified
        )

        XCTAssertEqual(feedback.titleKey, .workspaceApplyPartialTitle)
        XCTAssertEqual(
            feedback.detail,
            "已完整归位 1 个窗口。 阿里云盘已移动到位，但其最小窗口尺寸大于当前分区。"
        )
        XCTAssertFalse(feedback.detail.contains("3"))
        XCTAssertFalse(feedback.detail.contains("无法移动"))
        XCTAssertFalse(feedback.isError)
    }

    func testFailedWindowIsDeduplicatedAcrossIssueAndSkippedCollections() {
        let blocked = WindowIdentity(pid: 30, windowNumber: 3, bundleID: "example.blocked")
        let issue = WindowOrganizeIssue(
            identity: blocked,
            behavior: .immutable,
            obstacleFrameAX: .zero,
            observedFrameAX: .zero
        )

        let feedback = WorkspaceApplyFeedback.make(
            moved: [],
            issues: [issue],
            skipped: [blocked],
            missingCount: 0,
            staleCount: 0,
            disconnectedCount: 0,
            applicationName: { _ in "Blocked" },
            language: .chineseSimplified
        )

        XCTAssertEqual(feedback.titleKey, .workspaceApplyPartialTitle)
        XCTAssertEqual(feedback.detail, "1 个窗口无法移动。")
        XCTAssertTrue(feedback.isError)
    }

    func testSuccessfulWorkspaceReportsOnlyFullyPlacedWindows() {
        let first = WindowIdentity(pid: 10, windowNumber: 1)
        let second = WindowIdentity(pid: 20, windowNumber: 2)

        let feedback = WorkspaceApplyFeedback.make(
            moved: [first, second],
            issues: [],
            skipped: [],
            missingCount: 0,
            staleCount: 0,
            disconnectedCount: 0,
            applicationName: { _ in "App" },
            language: .chineseSimplified
        )

        XCTAssertEqual(feedback.titleKey, .workspaceAppliedTitle)
        XCTAssertEqual(feedback.detail, "已完整归位 2 个窗口。")
        XCTAssertFalse(feedback.isError)
    }
}
