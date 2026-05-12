import SwiftData
import SwiftUI

enum LaunchPhase {
    case splash
    case onboarding
    case auth
}

@main
struct FoundationChatApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationAppDelegate.self)
    private var pushNotificationAppDelegate

    @State private var authStore = AuthStore()
    @State private var launchPhase: LaunchPhase

    init() {
        let mgr = OnboardingManager()
        _launchPhase = State(initialValue: mgr.shouldShowOnboarding ? .splash : .auth)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch launchPhase {
                case .splash:
                    SplashVideoView {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            launchPhase = .onboarding
                        }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)

                case .onboarding:
                    OnboardingView {
                        OnboardingManager().isOnboardingCompleted = true
                        withAnimation(.easeInOut(duration: 0.5)) {
                            launchPhase = .auth
                        }
                    }
                    .transition(.opacity)

                case .auth:
                    AuthRootView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: launchPhase)
            .modelContainer(for: [Conversation.self, Message.self])
            .environment(authStore)
        }
    }
}
