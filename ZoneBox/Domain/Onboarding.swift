import Foundation

public enum OnboardingPage: String, CaseIterable, Sendable {
    case welcome
    case layouts
    case accessibility
    case firstSnap
    case more
    case finish
}

public struct OnboardingLaunchInput: Equatable, Sendable {
    public var completedVersion: Int
    public var currentVersion: Int
    public var trusted: Bool
    public var forceTour: Bool
    public var suppressTour: Bool
    public var resumePage: OnboardingPage?

    public init(
        completedVersion: Int,
        currentVersion: Int,
        trusted: Bool,
        forceTour: Bool = false,
        suppressTour: Bool = false,
        resumePage: OnboardingPage? = nil
    ) {
        self.completedVersion = completedVersion
        self.currentVersion = currentVersion
        self.trusted = trusted
        self.forceTour = forceTour
        self.suppressTour = suppressTour
        self.resumePage = resumePage
    }
}

public enum OnboardingLaunchDecision: Equatable, Sendable {
    case welcomeTour
    case accessibilityGuide
    case none
}

public enum OnboardingPolicy {
    /// Bump this when the tour pages change and existing users should see it again.
    public static let currentVersion = 1

    public static func launchDecision(_ input: OnboardingLaunchInput) -> OnboardingLaunchDecision {
        if input.forceTour { return .welcomeTour }
        if !input.suppressTour && input.completedVersion < input.currentVersion {
            return .welcomeTour
        }
        return input.trusted ? .none : .accessibilityGuide
    }

    public static func pages(trusted: Bool) -> [OnboardingPage] {
        if trusted {
            return OnboardingPage.allCases.filter { $0 != .accessibility }
        }
        return Array(OnboardingPage.allCases)
    }

    public static func initialIndex(resume: OnboardingPage?, pages: [OnboardingPage]) -> Int {
        guard !pages.isEmpty else { return 0 }
        guard let resume else { return 0 }
        if let index = pages.firstIndex(of: resume) {
            return index
        }
        guard let original = OnboardingPage.allCases.firstIndex(of: resume) else { return 0 }
        return pages.firstIndex { page in
            guard let candidate = OnboardingPage.allCases.firstIndex(of: page) else { return false }
            return candidate > original
        } ?? max(pages.count - 1, 0)
    }
}

public struct OnboardingFlowState: Equatable, Sendable {
    public var pages: [OnboardingPage]
    public var index: Int
    public var trusted: Bool
    public var didSnap: Bool

    public init(pages: [OnboardingPage], index: Int, trusted: Bool, didSnap: Bool = false) {
        self.pages = pages
        self.index = index
        self.trusted = trusted
        self.didSnap = didSnap
    }

    public var page: OnboardingPage { pages[index] }
    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index == pages.count - 1 }
}

public enum OnboardingFlowEvent: Equatable, Sendable {
    case next
    case back
    case skip
    case closeRequested
    case finish
    case trustChanged(Bool)
    case snapCompleted
}

public enum OnboardingFlowEffect: Equatable, Sendable {
    case showPage(OnboardingPage)
    case refreshCurrentPage
    case markCompleted
    case close
}

public enum OnboardingFlowReducer {
    public static func reduce(
        _ state: inout OnboardingFlowState,
        _ event: OnboardingFlowEvent
    ) -> [OnboardingFlowEffect] {
        switch event {
        case .next:
            guard !state.isLast else { return [.markCompleted, .close] }
            state.index += 1
            return [.showPage(state.page)]
        case .back:
            guard !state.isFirst else { return [] }
            state.index -= 1
            return [.showPage(state.page)]
        case .skip, .closeRequested, .finish:
            return [.markCompleted, .close]
        case .trustChanged(let trusted):
            guard trusted != state.trusted else { return [] }
            state.trusted = trusted
            return [.refreshCurrentPage]
        case .snapCompleted:
            guard !state.didSnap else { return [] }
            state.didSnap = true
            return state.page == .firstSnap ? [.refreshCurrentPage] : []
        }
    }
}

public enum OnboardingNavigation {
    public static func primaryTitle(_ state: OnboardingFlowState) -> L10nKey {
        if state.isLast { return .welcomeDone }
        if state.page == .accessibility, !state.trusted { return .welcomeSkipForNow }
        return .welcomeContinue
    }

    public static func showsSkip(_ state: OnboardingFlowState) -> Bool { !state.isLast }
    public static func showsBack(_ state: OnboardingFlowState) -> Bool { !state.isFirst }

    public static func stepLabel(_ state: OnboardingFlowState) -> (current: Int, total: Int) {
        (state.index + 1, state.pages.count)
    }
}

