import SwiftData
import SwiftUI

struct AuthRootView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var geoTrackBootstrap = GeoTrackBootstrapCoordinator.shared

    var body: some View {
        Group {
            switch authStore.status {
            case .loading:
                ProgressView("Restoring session...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                LoginView()
            case .signedIn:
                if authStore.passwordChangeRequired {
                    ForcePasswordChangeView()
                } else {
                    MainTabView()
                }
            }
        }
        .task {
            await authStore.restoreSessionIfNeeded()
            if authStore.status == .signedIn, !authStore.passwordChangeRequired {
                authStore.requestNotificationPermissions()
                await geoTrackBootstrap.sync(reason: "session-restore", force: true)
            }
        }
        .sheet(isPresented: Binding(
            get: { geoTrackBootstrap.shouldPresentConsent },
            set: { _ in }
        )) {
            GeoTrackConsentView(
                onConsent: {
                    Task { await geoTrackBootstrap.handleConsentAccepted() }
                },
                onDecline: {
                    geoTrackBootstrap.handleConsentDeclined()
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { geoTrackBootstrap.shouldPresentPermissionHelp },
            set: { isPresented in
                if !isPresented {
                    geoTrackBootstrap.dismissPermissionHelp()
                }
            }
        )) {
            GeoTrackPermissionHelpView(
                errorMessage: geoTrackBootstrap.lastError,
                onRetry: {
                    Task { await geoTrackBootstrap.sync(reason: "permission-help-retry", force: true) }
                },
                onDismiss: {
                    geoTrackBootstrap.dismissPermissionHelp()
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .didRegisterForRemoteNotificationsToken)) {
            notification in
            guard let apnsToken = notification.object as? String else { return }
            Task {
                await authStore.handleAPNSToken(apnsToken)
                await geoTrackBootstrap.sync(reason: "push-token", force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didInvalidateSession)) { notification in
            let message = notification.object as? String ?? "Session expired. Please sign in again."
            authStore.expireSession(message: message)
        }
        .onChange(of: authStore.status) { _, newStatus in
            if newStatus == .signedIn, !authStore.passwordChangeRequired {
                authStore.requestNotificationPermissions()
                if let existingToken = authStore.lastKnownAPNSToken {
                    Task { await authStore.handleAPNSToken(existingToken) }
                }
                Task { await geoTrackBootstrap.sync(reason: "signed-in", force: true) }
            }
        }
        .onChange(of: authStore.passwordChangeRequired) { _, required in
            if !required, authStore.status == .signedIn {
                authStore.requestNotificationPermissions()
                if let existingToken = authStore.lastKnownAPNSToken {
                    Task { await authStore.handleAPNSToken(existingToken) }
                }
                Task { await geoTrackBootstrap.sync(reason: "password-change-complete", force: true) }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, authStore.status == .signedIn, !authStore.passwordChangeRequired {
                Task { await geoTrackBootstrap.sync(reason: "foreground") }
            }
        }
    }
}

#Preview {
    AuthRootView()
        .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
        .environment(AuthStore())
}
