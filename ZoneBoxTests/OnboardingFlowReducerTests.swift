import XCTest
@testable import ZoneBoxCore

final class OnboardingFlowReducerTests: XCTestCase {
    func testNextWalksPagesThenCompletes() {
        var state = untrustedState()
        XCTAssertEqual(OnboardingFlowReducer.reduce(&state, .next), [.showPage(.layouts)])
        XCTAssertEqual(OnboardingFlowReducer.reduce(&state, .next), [.showPage(.accessibility)])
        XCTAssertEqual(OnboardingFlowReducer.reduce(&state, .next), [.showPage(.firstSnap)])
        XCTAssertEqual(OnboardingFlowReducer.reduce(&state, .next), [.showPage(.more)])
        XCTAssertEqual(OnboardingFlowReducer.reduce(&state, .next), [.showPage(.finish)])
        XCTAssertEqual(OnboardingFlowReducer.reduce(&state, .next), [.markCompleted, .close])
        XCTAssertEqual(state.page, .finish)
    }

    func testBackOnFirstPageIsNoOp() {
        var state = untrustedState()
        XCTAssertEqual(OnboardingFlowReducer.reduce(&state, .back), [])
        XCTAssertEqual(state.index, 0)
    }

    func testSkipCloseAndFinishAlwaysComplete() {
        for event in [OnboardingFlowEvent.skip, .closeRequested, .finish] {
            var state = untrustedState()
            XCTAssertEqual(OnboardingFlowReducer.reduce(&state, event), [.markCompleted, .close])
        }
    }

    func testTrustChangedRefreshesOnlyWhenValueChanges() {
        var state = untrustedState()
        XCTAssertEqual(OnboardingFlowReducer.reduce(&state, .trustChanged(true)), [.refreshCurrentPage])
        XCTAssertTrue(state.trusted)
        XCTAssertEqual(OnboardingFlowReducer.reduce(&state, .trustChanged(true)), [])
    }

    func testSnapCompletedRefreshesOnlyOnFirstSnapPage() {
        var onSnap = untrustedState(index: 3)
        XCTAssertEqual(onSnap.page, .firstSnap)
        XCTAssertEqual(OnboardingFlowReducer.reduce(&onSnap, .snapCompleted), [.refreshCurrentPage])
        XCTAssertTrue(onSnap.didSnap)
        XCTAssertEqual(OnboardingFlowReducer.reduce(&onSnap, .snapCompleted), [])

        var elsewhere = untrustedState()
        XCTAssertEqual(OnboardingFlowReducer.reduce(&elsewhere, .snapCompleted), [])
        XCTAssertTrue(elsewhere.didSnap)
        XCTAssertEqual(elsewhere.page, .welcome)
    }

    func testNavigationTitles() {
        var untrusted = untrustedState(index: 2)
        XCTAssertEqual(untrusted.page, .accessibility)
        XCTAssertEqual(OnboardingNavigation.primaryTitle(untrusted), .welcomeSkipForNow)
        untrusted.trusted = true
        XCTAssertEqual(OnboardingNavigation.primaryTitle(untrusted), .welcomeContinue)

        let last = untrustedState(index: 5)
        XCTAssertEqual(OnboardingNavigation.primaryTitle(last), .welcomeDone)
        XCTAssertFalse(OnboardingNavigation.showsSkip(last))
        XCTAssertTrue(OnboardingNavigation.showsBack(last))
        XCTAssertEqual(OnboardingNavigation.stepLabel(last).current, 6)
        XCTAssertEqual(OnboardingNavigation.stepLabel(last).total, 6)
    }

    private func untrustedState(index: Int = 0) -> OnboardingFlowState {
        OnboardingFlowState(
            pages: OnboardingPolicy.pages(trusted: false),
            index: index,
            trusted: false
        )
    }
}

