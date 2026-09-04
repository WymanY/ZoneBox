import XCTest
@testable import ZoneBoxCore

final class OnboardingPolicyTests: XCTestCase {
    func testLaunchDecisionShowsTourUntilCompleted() {
        XCTAssertEqual(decision(completed: 0, trusted: false), .welcomeTour)
        XCTAssertEqual(decision(completed: 0, trusted: true), .welcomeTour)
        XCTAssertEqual(decision(completed: 1, trusted: false), .accessibilityGuide)
        XCTAssertEqual(decision(completed: 1, trusted: true), .none)
    }

    func testForceTourOverridesCompletedMarker() {
        XCTAssertEqual(
            decision(completed: 1, trusted: true, forceTour: true),
            .welcomeTour
        )
    }

    func testSuppressTourFallsBackToAccessibilityGuideWhenUntrusted() {
        XCTAssertEqual(
            decision(completed: 0, trusted: false, suppressTour: true),
            .accessibilityGuide
        )
        XCTAssertEqual(
            decision(completed: 0, trusted: true, suppressTour: true),
            .none
        )
    }

    func testResumePageDoesNotBypassCompletedMarker() {
        XCTAssertEqual(
            OnboardingPolicy.launchDecision(
                OnboardingLaunchInput(
                    completedVersion: 1,
                    currentVersion: OnboardingPolicy.currentVersion,
                    trusted: true,
                    resumePage: .firstSnap
                )
            ),
            .none
        )
    }

    func testPagesOmitAccessibilityWhenTrusted() {
        XCTAssertEqual(
            OnboardingPolicy.pages(trusted: false),
            OnboardingPage.allCases
        )
        XCTAssertEqual(
            OnboardingPolicy.pages(trusted: true),
            [.welcome, .layouts, .firstSnap, .more, .finish]
        )
    }

    func testInitialIndexResumesOrFallsForward() {
        let six = OnboardingPolicy.pages(trusted: false)
        let five = OnboardingPolicy.pages(trusted: true)
        XCTAssertEqual(OnboardingPolicy.initialIndex(resume: nil, pages: six), 0)
        XCTAssertEqual(OnboardingPolicy.initialIndex(resume: .firstSnap, pages: six), 3)
        XCTAssertEqual(OnboardingPolicy.initialIndex(resume: .firstSnap, pages: five), 2)
        XCTAssertEqual(OnboardingPolicy.initialIndex(resume: .accessibility, pages: five), 2)
        XCTAssertEqual(five[2], .firstSnap)
    }

    private func decision(
        completed: Int,
        trusted: Bool,
        forceTour: Bool = false,
        suppressTour: Bool = false
    ) -> OnboardingLaunchDecision {
        OnboardingPolicy.launchDecision(
            OnboardingLaunchInput(
                completedVersion: completed,
                currentVersion: OnboardingPolicy.currentVersion,
                trusted: trusted,
                forceTour: forceTour,
                suppressTour: suppressTour
            )
        )
    }
}

