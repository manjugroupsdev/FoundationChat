import Combine
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
    @AppStorage("app.appearance") private var appearancePreference = ProfileAppearance.system.rawValue

    private var preferredColorScheme: ColorScheme? {
        (ProfileAppearance(rawValue: appearancePreference) ?? .system).colorScheme
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
            .background {
                ModernDialerWebViewContainer()
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
            .environment(\.locale, Locale(identifier: languagePreference))
            .preferredColorScheme(preferredColorScheme)
            .modelContainer(for: [Conversation.self, Message.self])
            .environment(authStore)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
            .onChange(of: authStore.currentSession?.token) { _, token in
                guard token != nil, let voipToken = ModernDialerVoIPTokenCache.token else { return }
                Task { await registerModernDialerVoIPToken(voipToken) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didRegisterModernDialerVoIPToken)) { note in
                guard let token = note.object as? String else { return }
                Task { await registerModernDialerVoIPToken(token) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didInvalidateModernDialerVoIPToken)) { note in
                guard
                    let deviceToken = note.object as? String,
                    let token = authStore.currentSession?.token
                else { return }
                Task {
                    try? await ChatAPIService.unregisterPushToken(
                        token: token,
                        deviceToken: deviceToken
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didAnswerModernDialerCall)) { note in
                let payload = note.object as? [String: String] ?? [:]
                Task { await answerModernDialerCall(payload: payload) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didEndModernDialerCall)) { note in
                let payload = note.object as? [String: String]
                Task { await endModernDialerCall(payload: payload) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didFailModernDialerMedia)) { note in
                guard
                    let payload = note.object as? [String: String],
                    let callId = payload["callId"]
                else { return }
                Task { await restartModernDialerMedia(callId: callId) }
            }
        }
    }

    private static func configureBrandInputAppearance() {
        let textColor = UIColor.label
        let tintColor = UIColor(red: 0.043, green: 0.380, blue: 0.792, alpha: 1)

        UITextField.appearance().overrideUserInterfaceStyle = .unspecified
        UITextField.appearance().textColor = textColor
        UITextField.appearance().tintColor = tintColor
        UITextField.appearance().keyboardAppearance = .default

        UITextView.appearance().overrideUserInterfaceStyle = .unspecified
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

    private func registerModernDialerVoIPToken(_ deviceToken: String) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            _ = try await ChatAPIService.registerPushToken(
                token: token,
                deviceToken: deviceToken,
                platform: "ios_voip",
                provider: "apns_voip"
            )
        } catch {
            print("[dialer-ios] VoIP token registration failed: \(error.localizedDescription)")
        }
    }

    private func answerModernDialerCall(payload: [String: String]) async {
        guard
            let token = authStore.currentSession?.token,
            let callId = payload["callId"] ?? payload["call_id"]
        else { return }
        do {
            guard try await TelecallerConvexAPIService.getMobileDialerCurrentCall(
                token: token,
                callId: callId
            ) != nil else { return }
            _ = try await TelecallerConvexAPIService.performMobileDialerAction(
                token: token,
                callId: callId,
                action: "pickup",
                deviceId: Self.modernDialerDeviceId,
                eventId: payload["eventId"] ?? payload["event_id"],
                idempotencyKey: Self.mobileDialerIdempotencyKey(callId: callId, operation: "pickup")
            )
            let config = try await TelecallerConvexAPIService.getMobileDialerConfig(token: token)
            guard config.configured == true, config.mapping?.token?.nonBlank != nil else { return }
            await MainActor.run {
                ModernDialerBridge.shared.ensureLoaded(config: config)
                ModernDialerBridge.shared.pickup()
            }
        } catch {
            print("[dialer-ios] Incoming call pickup failed: \(error.localizedDescription)")
        }
    }

    private func endModernDialerCall(payload: [String: String]?) async {
        defer { Task { @MainActor in ModernDialerBridge.shared.hangup() } }
        guard
            let payload,
            let token = authStore.currentSession?.token,
            let callId = payload["callId"] ?? payload["call_id"]
        else { return }
        let operation = payload["operation"] == "hangup" ? "hangup" : "reject"
        do {
            _ = try await TelecallerConvexAPIService.performMobileDialerAction(
                token: token,
                callId: callId,
                action: operation,
                deviceId: Self.modernDialerDeviceId,
                eventId: payload["eventId"] ?? payload["event_id"],
                idempotencyKey: Self.mobileDialerIdempotencyKey(callId: callId, operation: operation)
            )
        } catch {
            print("[dialer-ios] \(operation) failed: \(error.localizedDescription)")
        }
    }

    private func restartModernDialerMedia(callId: String) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            _ = try await TelecallerConvexAPIService.restartMobileDialerMedia(
                token: token,
                callId: callId,
                deviceId: Self.modernDialerDeviceId,
                idempotencyKey: Self.mobileDialerIdempotencyKey(callId: callId, operation: "media-restart")
            )
            _ = try? await TelecallerConvexAPIService.getMobileDialerMedia(
                token: token,
                callId: callId
            )
            await MainActor.run { ModernDialerBridge.shared.mediaRestartSucceeded() }
        } catch {
            await MainActor.run {
                ModernDialerBridge.shared.mediaRestartFailed("Call audio could not reconnect")
            }
        }
    }

    private static var modernDialerDeviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "ios-unknown-device"
    }

    private static func mobileDialerIdempotencyKey(callId: String, operation: String) -> UUID {
        let storageKey = "modernDialer.idempotency.\(callId).\(operation)"
        if
            let stored = UserDefaults.standard.string(forKey: storageKey),
            let uuid = UUID(uuidString: stored)
        {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: storageKey)
        return uuid
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
