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

    @AppStorage("app.language") private var languagePreference = ProfileLanguage.english.rawValue
    @AppStorage("app.appearance") private var appearancePreference = ProfileAppearance.system.rawValue

    @State private var authStore = AuthStore()
    @State private var launchPhase: LaunchPhase

    init() {
        UINavigationController.enableGlobalSwipeBack()
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
            .background {
                GlobalSwipeBackInstaller()
                    .frame(width: 0, height: 0)
            }
            .environment(\.locale, Locale(identifier: languagePreference))
            .preferredColorScheme(ProfileAppearance(rawValue: appearancePreference)?.colorScheme)
            .modelContainer(for: [Conversation.self, Message.self])
            .environment(authStore)
        }
    }
}
