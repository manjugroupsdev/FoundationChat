import Foundation

@Observable
final class OnboardingManager {
    private let defaults = UserDefaults.standard
    private let key = "mconnect_onboarding_completed"

    var isOnboardingCompleted: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }

    var shouldShowOnboarding: Bool { !isOnboardingCompleted }
}
