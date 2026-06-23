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
    @AppStorage("app.appearance") private var appearancePreference = ProfileAppearance.light.rawValue

    @State private var authStore = AuthStore()
    @State private var launchPhase: LaunchPhase

    init() {
        UINavigationController.enableGlobalSwipeBack()
        Self.configureLightInputAppearance()
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
            .background(Color.white.ignoresSafeArea())
            .background {
                GlobalSwipeBackInstaller()
                    .frame(width: 0, height: 0)
            }
            .environment(\.locale, Locale(identifier: languagePreference))
            .preferredColorScheme(appColorScheme)
            .modelContainer(for: [Conversation.self, Message.self])
            .environment(authStore)
        }
    }

    private var appColorScheme: ColorScheme {
        switch ProfileAppearance(rawValue: appearancePreference) {
        case .dark:
            return .dark
        case .light, .system, .none:
            return .light
        }
    }

    private static func configureLightInputAppearance() {
        let textColor = UIColor.label
        let tintColor = UIColor(red: 0.043, green: 0.380, blue: 0.792, alpha: 1)

        UITextField.appearance().overrideUserInterfaceStyle = .light
        UITextField.appearance().textColor = textColor
        UITextField.appearance().tintColor = tintColor
        UITextField.appearance().keyboardAppearance = .light

        UITextView.appearance().overrideUserInterfaceStyle = .light
        UITextView.appearance().textColor = textColor
        UITextView.appearance().tintColor = tintColor
    }
}
