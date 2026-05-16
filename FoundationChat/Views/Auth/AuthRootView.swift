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
                if authStore.currentSession == nil {
                    ZStack(alignment: .top) {
                        LoginView()
                            .allowsHitTesting(false)
                        ProgressView("Checking session...")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 24)
                    }
                } else {
                    ProgressView("Restoring session...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .task {
            await authStore.restoreSessionIfNeeded()
            if authStore.status == .signedIn {
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
        .onReceive(NotificationCenter.default.publisher(for: .didRegisterForRemoteNotificationsToken)) {
            notification in
            guard let apnsToken = notification.object as? String else { return }
            Task {
                await authStore.handleAPNSToken(apnsToken)
                await geoTrackBootstrap.sync(reason: "push-token", force: true)
            }
        }
        .onChange(of: authStore.status) { _, newStatus in
            if newStatus == .signedIn {
                authStore.requestNotificationPermissions()
                if let existingToken = authStore.lastKnownAPNSToken {
                    Task { await authStore.handleAPNSToken(existingToken) }
                }
                Task { await geoTrackBootstrap.sync(reason: "signed-in", force: true) }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, authStore.status == .signedIn {
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
