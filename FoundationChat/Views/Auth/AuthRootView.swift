import SwiftData
import SwiftUI

struct AuthRootView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var geoTrackBootstrap = GeoTrackBootstrapCoordinator.shared
    @State private var mobileAlerts = MobileAlertCoordinator.shared
    @State private var appUpdate = AppUpdateCoordinator.shared
    @State private var releaseNotice: ReleaseNoticeCampaign?

    var body: some View {
        // Read here, not only inside the Binding, so Observation re-runs body
        // (and presents the cover) when the queue changes.
        let mobileAlertToPresent = presentedMobileAlert
        authenticatedContent
        .task {
            await authStore.restoreSessionIfNeeded()
            if authStore.status == .signedIn, !authStore.passwordChangeRequired {
                authStore.requestNotificationPermissions()
                showReleaseNoticeIfNeeded()
                await syncGeoTrack(reason: "session-restore", force: true)
            }
            await refreshMobileAlerts()
        }
        .overlay {
            if let releaseNotice {
                ReleaseNoticeView(campaign: releaseNotice) {
                    ReleaseNoticeStore.markSeen(releaseNotice)
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.releaseNotice = nil
                    }
                }
                .zIndex(5_000)
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
                    Task { await syncGeoTrack(reason: "permission-help-retry", force: true) }
                },
                onDismiss: {
                    geoTrackBootstrap.dismissPermissionHelp()
                },
                tracked: geoTrackBootstrap.permissionHelpTracked
            )
        }
        .fullScreenCover(item: Binding(
            get: { mobileAlertToPresent },
            set: { _ in }
        )) { alert in
            MobileAlertView(alert: alert, token: authStore.currentSession?.token) {
                mobileAlerts.close(alert)
            }
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
            #if DEBUG
            guard authStore.currentSession?.token != "FCQA_STUB_TOKEN" else { return }
            #endif
            guard let event = notification.object as? SessionInvalidationBus.Event,
                  event.matches(currentToken: authStore.currentSession?.token) else { return }
            authStore.expireSession(message: event.reason)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveGeoTrackSyncPush)) { notification in
            guard authStore.status == .signedIn, !authStore.passwordChangeRequired else { return }
            let reason = notification.object as? String ?? "push"
            Task { await syncGeoTrack(reason: "geotrack-sync-\(reason)", force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveMobileAlertPush)) { _ in
            Task { await refreshMobileAlerts() }
        }
        .alert("Couldn't open alert", isPresented: Binding(
            get: { mobileAlerts.openError != nil },
            set: { if !$0 { mobileAlerts.openError = nil } }
        )) { Button("OK") { mobileAlerts.openError = nil } }
        message: { Text(mobileAlerts.openError ?? "") }
        .onChange(of: authStore.status) { _, newStatus in
            if newStatus == .signedIn, !authStore.passwordChangeRequired {
                authStore.requestNotificationPermissions()
                showReleaseNoticeIfNeeded()
                if let existingToken = authStore.lastKnownAPNSToken {
                    Task { await authStore.handleAPNSToken(existingToken) }
                }
                Task { await syncGeoTrack(reason: "signed-in", force: true) }
            }
            // Signed in: fetch pending alerts. Signed out: drop the queue.
            Task { await refreshMobileAlerts() }
        }
        .onChange(of: authStore.passwordChangeRequired) { _, required in
            if !required, authStore.status == .signedIn {
                authStore.requestNotificationPermissions()
                showReleaseNoticeIfNeeded()
                if let existingToken = authStore.lastKnownAPNSToken {
                    Task { await authStore.handleAPNSToken(existingToken) }
                }
                Task { await syncGeoTrack(reason: "password-change-complete", force: true) }
            }
            Task { await refreshMobileAlerts() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, authStore.status == .signedIn, !authStore.passwordChangeRequired {
                Task { await syncGeoTrack(reason: "foreground") }
            }
            if newPhase == .active {
                Task { await refreshMobileAlerts() }
            }
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        switch authStore.status {
        case .loading:
            ProgressView("Restoring session...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
            LoginView()
        case .signedIn:
            if authStore.passwordChangeRequired {
                ForcePasswordChangeView()
            } else if authStore.currentSession?.user.isFleetPortalMode == true {
                AdminFleetPortalView()
            } else {
                MainTabView()
            }
        }
    }

    private func syncGeoTrack(reason: String, force: Bool = false) async {
        guard authStore.currentSession?.user.isExternalFleetPrincipal != true,
              authStore.currentSession?.user.isFleetPortalMode != true else { return }
        await geoTrackBootstrap.sync(reason: reason, force: force)
    }

    /// Mandatory mobile alerts are for signed-in staff only (not the external
    /// fleet portal, which has no staff record).
    private var canShowMobileAlerts: Bool {
        authStore.status == .signedIn
            && !authStore.passwordChangeRequired
            && authStore.currentSession?.user.isExternalFleetPrincipal != true
            && authStore.currentSession?.user.isFleetPortalMode != true
    }

    /// The alert to cover the app with. Held back while the mandatory update
    /// screen or a GeoTrack consent/permission sheet is up: the update must
    /// win, and a second presentation from this view would fail while one of
    /// its sheets is showing. It appears as soon as they are gone.
    private var presentedMobileAlert: MobileAlert? {
        guard canShowMobileAlerts,
              !appUpdate.mustShowUpdate,
              !geoTrackBootstrap.shouldPresentConsent,
              !geoTrackBootstrap.shouldPresentPermissionHelp else { return nil }
        return mobileAlerts.current
    }

    private func refreshMobileAlerts() async {
        await mobileAlerts.refresh(token: canShowMobileAlerts ? authStore.currentSession?.token : nil)
    }

    private func showReleaseNoticeIfNeeded() {
        guard authStore.status == .signedIn,
              !authStore.passwordChangeRequired,
              let campaign = ReleaseNoticeCampaign.active,
              ReleaseNoticeStore.shouldShow(campaign) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            releaseNotice = campaign
        }
    }
}

#Preview {
    AuthRootView()
        .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
        .environment(AuthStore())
}
