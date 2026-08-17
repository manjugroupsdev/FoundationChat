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

    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("app.language") private var languagePreference = ProfileLanguage.english.rawValue
    @AppStorage("app.appearance") private var appearancePreference = ProfileAppearance.light.rawValue

    private var preferredColorScheme: ColorScheme? {
        (ProfileAppearance(rawValue: appearancePreference) ?? .light).colorScheme
    }

    @State private var authStore = AuthStore()
    @State private var launchPhase: LaunchPhase

    init() {
        UINavigationController.enableGlobalSwipeBack()
        Self.configureBrandInputAppearance()
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
            .background(Color.appScreenBackground.ignoresSafeArea())
            .background {
                GlobalSwipeBackInstaller()
                    .frame(width: 0, height: 0)
            }
            .environment(\.locale, Locale(identifier: languagePreference))
            .preferredColorScheme(preferredColorScheme)
            .modelContainer(for: [Conversation.self, Message.self])
            .environment(authStore)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
        }
    }

    private static func configureBrandInputAppearance() {
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

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .inactive, .background:
            UIApplication.shared.fc_dismissKeyboard()

        case .active where oldPhase != .active:
            // Window bounds and safe-area values can still be transitioning at
            // the first active callback after an unlock. Re-layout once UIKit
            // has restored the foreground window metrics.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard UIApplication.shared.applicationState == .active else { return }
                Self.recoverVisibleWindowLayout()
            }
            Task { await flushPendingAttendancePunchesIfSignedIn() }

        default:
            break
        }
    }

    private func flushPendingAttendancePunchesIfSignedIn() async {
        guard let token = authStore.currentSession?.token else { return }
        await PendingPunchSyncCoordinator.shared.flush(token: token)
    }

    private static func recoverVisibleWindowLayout() {
        configureBrandInputAppearance()
        UINavigationController.enableGlobalSwipeBack()

        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter { !$0.isHidden }

        UIView.performWithoutAnimation {
            for window in windows {
                if let rootViewController = window.rootViewController {
                    markLayoutForRefresh(rootViewController)
                }
                window.setNeedsUpdateConstraints()
                window.setNeedsLayout()
                window.layoutIfNeeded()
            }
        }
    }

    private static func markLayoutForRefresh(_ viewController: UIViewController) {
        if let view = viewController.viewIfLoaded {
            view.setNeedsUpdateConstraints()
            view.setNeedsLayout()
            viewController.setNeedsStatusBarAppearanceUpdate()
        }

        for child in viewController.children {
            markLayoutForRefresh(child)
        }
        if let presentedViewController = viewController.presentedViewController {
            markLayoutForRefresh(presentedViewController)
        }
    }
}
