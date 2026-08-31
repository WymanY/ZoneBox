import XCTest
@testable import ZoneBoxCore

final class PinPlannerTests: XCTestCase {
    private let pinA = WindowIdentity(pid: 1, windowNumber: 10, bundleID: "a")
    private let pinB = WindowIdentity(pid: 2, windowNumber: 20, bundleID: "b")
    func testVisiblePinIsReturnedWithFrame() {
        let plan = PinPlanner.plan(
            frontToBack: [snapshot(pinA)],
            allWindowIdentities: [pinA],
            pinOrder: [pinA]
        )

        XCTAssertEqual(plan.visible, [pinA])
        XCTAssertEqual(plan.visibleFrames[pinA], frame())
        XCTAssertEqual(plan.dormant, [])
        XCTAssertEqual(plan.gone, [])
    }

    func testVisiblePinsPreserveOldestToNewestPinOrder() {
        let plan = PinPlanner.plan(
            frontToBack: [snapshot(pinB), snapshot(pinA)],
            allWindowIdentities: [pinA, pinB],
            pinOrder: [pinA, pinB]
        )

        XCTAssertEqual(plan.visible, [pinA, pinB])
    }

    func testNonzeroLayerPinIsNotMirrored() {
        let systemOverlay = snapshot(
            pinA,
            frame: frame(),
            layer: 25
        )
        let plan = PinPlanner.plan(
            frontToBack: [systemOverlay],
            allWindowIdentities: [pinA],
            pinOrder: [pinA]
        )

        XCTAssertEqual(plan.visible, [])
        XCTAssertEqual(plan.dormant, [pinA])
    }

    func testMissingOnScreenSeparatesDormantFromGone() {
        let gone = WindowIdentity(pid: 4, windowNumber: 40)
        let plan = PinPlanner.plan(
            frontToBack: [snapshot(pinA)],
            allWindowIdentities: [pinA, pinB],
            pinOrder: [pinA, pinB, gone]
        )

        XCTAssertEqual(plan.dormant, [pinB])
        XCTAssertEqual(plan.gone, [gone])
        XCTAssertEqual(plan.visible, [pinA])
        XCTAssertEqual(plan.visibleFrames.keys.sorted { $0.pid < $1.pid }, [pinA])
    }

    func testUnsampledOffScreenListKeepsMissingPinsDormant() {
        let plan = PinPlanner.plan(
            frontToBack: [snapshot(pinA)],
            allWindowIdentities: nil,
            pinOrder: [pinA, pinB]
        )

        XCTAssertEqual(plan.visible, [pinA])
        XCTAssertEqual(plan.dormant, [pinB])
        XCTAssertEqual(plan.gone, [])
    }

    func testRetirementKeepsGoneTimestampAcrossUnsampledTicks() {
        let sampledGone = PinPlanner.plan(
            frontToBack: [snapshot(pinA)],
            allWindowIdentities: [pinA],
            pinOrder: [pinA, pinB]
        )
        XCTAssertEqual(
            PinRetirement.status(for: pinB, plan: sampledGone, sampledOffScreen: true),
            .gone
        )

        let unsampled = PinPlanner.plan(
            frontToBack: [snapshot(pinA)],
            allWindowIdentities: nil,
            pinOrder: [pinA, pinB]
        )
        XCTAssertEqual(
            PinRetirement.status(for: pinB, plan: unsampled, sampledOffScreen: false),
            .unknown
        )
        XCTAssertEqual(
            PinRetirement.status(for: pinA, plan: unsampled, sampledOffScreen: false),
            .present
        )

        let sampledDormant = PinPlanner.plan(
            frontToBack: [snapshot(pinA)],
            allWindowIdentities: [pinA, pinB],
            pinOrder: [pinA, pinB]
        )
        XCTAssertEqual(
            PinRetirement.status(for: pinB, plan: sampledDormant, sampledOffScreen: true),
            .present
        )
    }

    func testWindowIdentityIgnoresBundleMetadataForEquality() {
        let withoutBundle = WindowIdentity(pid: pinA.pid, windowNumber: pinA.windowNumber)
        XCTAssertEqual(pinA, withoutBundle)
        XCTAssertEqual(Set([pinA, withoutBundle]).count, 1)
    }

    private func frame(x: CGFloat = 100) -> CGRect {
        CGRect(x: x, y: 100, width: 400, height: 300)
    }

    private func snapshot(
        _ identity: WindowIdentity,
        frame: CGRect? = nil,
        layer: Int = 0
    ) -> PinWindowSnapshot {
        PinWindowSnapshot(identity: identity, frameAX: frame ?? self.frame(), layer: layer)
    }
}
