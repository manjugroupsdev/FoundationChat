import CoreLocation
import CoreMotion
import SwiftUI
import UIKit
import UserNotifications

// MARK: - GeoTrackConsentView

/// Consent screen shown before GPS time tracking begins.
/// Mirrors Android's GeoTrackConsentActivity disclosure text and button layout.
struct GeoTrackConsentView: View {
    @Environment(\.dismiss) private var dismiss

    var onConsent: () -> Void = {}
    var onDecline: () -> Void = {}

    @State private var consentManager = GeoTrackConsentManager.shared
    @State private var permissionGuide = GeoTrackPermissionGuide()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.blue)

                        Text("Location Tracking")
                            .font(.title2.bold())

                        Text("Before we begin, please review how your location data is used.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    Divider()

                    // Disclosure bullets
                    VStack(alignment: .leading, spacing: 16) {
                        disclosureRow(
                            icon: "location.fill",
                            color: .blue,
                            title: "What is collected",
                            body: "GPS location, movement type (walking, driving), and battery level — only while tracking is active."
                        )
                        disclosureRow(
                            icon: "clock.fill",
                            color: .orange,
                            title: "When tracking is active",
                            body: "Tracking starts only when your assigned attendance or visit tracking session is active, then stops when the session closes."
                        )
                        disclosureRow(
                            icon: "person.2.fill",
                            color: .green,
                            title: "Who can see your location",
                            body: "Your manager and operations admins can view your travel history during tracked sessions."
                        )
                        disclosureRow(
                            icon: "calendar",
                            color: .purple,
                            title: "Data retention",
                            body: "Raw location data is retained for 90 days. Summaries are kept for up to 1 year."
                        )
                        disclosureRow(
                            icon: "eye.fill",
                            color: .teal,
                            title: "Your access",
                            body: "You can view your own travel history and visit logs in the app at any time."
                        )
                    }

                    Divider()

                    GeoTrackPermissionChecklist(guide: permissionGuide)

                    Divider()

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                await consentManager.giveConsent()
                                permissionGuide.requestAlwaysLocation()
                                permissionGuide.requestMotionAccess()
                                onConsent()
                                dismiss()
                            }
                        } label: {
                            HStack {
                                if consentManager.isRecording {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, 4)
                                }
                                Text("I Understand and Agree")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(consentManager.isRecording)

                        Button {
                            Task {
                                await consentManager.declineConsent()
                                onDecline()
                                dismiss()
                            }
                        } label: {
                            Text("Decline")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.secondary, lineWidth: 1)
                                )
                        }
                        .foregroundStyle(.secondary)

                        Text("You can change your consent preference at any time in Settings.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                permissionGuide.refresh()
            }
        }
    }

    private func disclosureRow(
        icon: String,
        color: Color,
        title: String,
        body: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GeoTrackPermissionHelpView: View {
    @Environment(\.dismiss) private var dismiss

    let errorMessage: String?
    var onRetry: () -> Void = {}
    var onDismiss: () -> Void = {}
    /// False for staff who are not geo-tracked: they are asked only for
    /// what the app uses for them, never for Always location.
    var tracked: Bool = true

    @State private var permissionGuide = GeoTrackPermissionGuide()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "location.badge.exclamationmark")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(tracked ? "GeoTrack Needs Permissions" : "M-connect Needs a Few Permissions")
                            .font(.title3.bold())
                        Text(errorMessage ?? (tracked
                            ? "Enable the required iPhone permissions so GeoTrack can continue background tracking."
                            : "Turn these on to keep using the app. They are what punch-in and your alerts need."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    GeoTrackPermissionChecklist(guide: permissionGuide, tracked: tracked)

                    VStack(spacing: 12) {
                        Button {
                            permissionGuide.openSettings()
                        } label: {
                            Label("Open iPhone Settings", systemImage: "gearshape.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }

                        // Closes only once everything is granted. It used to
                        // dismiss unconditionally, which was a way out.
                        Button {
                            Task { await closeIfReady() }
                        } label: {
                            Text(tracked ? "Retry GeoTrack" : "Check again")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.secondary, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(tracked ? "GeoTrack" : "Permissions")
            .navigationBarTitleDisplayMode(.inline)
            // No Close button and no swipe-down: the sheet stays until what
            // it lists is granted, and closes itself the moment it is. A
            // status the user cannot change (.restricted) never blocks — see
            // GeoTrackPermissionGuide.isReady — so nobody is locked out.
            .interactiveDismissDisabled(true)
            .onAppear {
                Task { await closeIfReady() }
            }
            // Every row here sends the staff member to iPhone Settings. When
            // they come back the rows must update, or a permission they just
            // granted keeps showing as missing.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )) { _ in
                Task { await closeIfReady() }
            }
        }
    }

    @MainActor
    private func closeIfReady() async {
        permissionGuide.refresh()
        if await GeoTrackPermissionGuide.isReady(tracked: tracked) {
            onRetry()
            dismiss()
        }
    }
}

private struct GeoTrackPermissionChecklist: View {
    @Bindable var guide: GeoTrackPermissionGuide
    var tracked: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Required on iPhone")
                .font(.headline)

            permissionRow(
                icon: "location.slash.fill",
                title: "Location Services",
                subtitle: "The iPhone-wide switch. Nothing below works while it is off.",
                status: guide.locationServicesStatusLabel,
                isReady: guide.locationServicesOn
            ) {
                guide.openSettings()
            }

            if tracked {
                permissionRow(
                    icon: "location.fill",
                    title: "Always Location",
                    subtitle: "Required for background route capture and final sync.",
                    status: guide.locationStatusLabel,
                    isReady: guide.hasAlwaysLocation
                ) {
                    guide.requestAlwaysLocation()
                }
            } else {
                permissionRow(
                    icon: "location.fill",
                    title: "Location",
                    subtitle: "Needed while the app is open, for punch-in.",
                    status: guide.inUseStatusLabel,
                    isReady: guide.hasLocationInUse
                ) {
                    guide.requestLocationInUse()
                }
            }

            permissionRow(
                icon: "scope",
                title: "Precise Location",
                subtitle: "Without it fixes are too rough to record and your route stays frozen.",
                status: guide.preciseStatusLabel,
                isReady: guide.hasPreciseLocation
            ) {
                guide.openSettings()
            }

            // Motion and Background App Refresh only keep tracking alive.
            if tracked {
                permissionRow(
                    icon: "figure.walk.motion",
                    title: "Motion Activity",
                    subtitle: "Required to detect walking, driving, running and still states.",
                    status: guide.motionStatusLabel,
                    isReady: guide.hasMotionAccess
                ) {
                    guide.requestMotionAccess()
                }

                permissionRow(
                    icon: "arrow.clockwise.circle.fill",
                    title: "Background App Refresh",
                    subtitle: "Lets tracking keep sending while the app is not on screen.",
                    status: guide.backgroundRefreshStatusLabel,
                    isReady: guide.hasBackgroundRefresh
                ) {
                    guide.openSettings()
                }
            }

            permissionRow(
                icon: "bell.badge.fill",
                title: "Notifications",
                subtitle: tracked
                    ? "So the app can tell you the moment tracking stops working."
                    : "So you get approvals, tasks and alerts on time.",
                status: guide.notificationStatusLabel,
                isReady: guide.hasNotifications
            ) {
                guide.requestNotifications()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        status: String,
        isReady: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isReady ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isReady ? .green : .orange)
            }

            Spacer()

            if isReady {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow") {
                    action()
                }
                .font(.caption.weight(.semibold))
            }
        }
    }
}

@MainActor
@Observable
final class GeoTrackPermissionGuide: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private var shouldEscalateToAlways = false

    private(set) var locationStatus: CLAuthorizationStatus
    private(set) var motionStatus: CMAuthorizationStatus
    // The three below used to go unchecked. Each one stops background capture
    // on its own, and none of them makes starting the tracker throw — so the
    // sheet, which only appeared on a thrown error, never mentioned them.
    private(set) var accuracy: CLAccuracyAuthorization
    private(set) var backgroundRefresh: UIBackgroundRefreshStatus
    private(set) var locationServicesOn = true
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    override init() {
        locationStatus = locationManager.authorizationStatus
        motionStatus = CMMotionActivityManager.authorizationStatus()
        accuracy = locationManager.accuracyAuthorization
        backgroundRefresh = UIApplication.shared.backgroundRefreshStatus
        super.init()
        locationManager.delegate = self
    }

    var hasAlwaysLocation: Bool {
        locationStatus == .authorizedAlways
    }

    var hasMotionAccess: Bool {
        motionStatus == .authorized || !CMMotionActivityManager.isActivityAvailable()
    }

    /// "Precise Location: Off" gives kilometre-scale fixes that fail the
    /// capture gate, so the staff member shows Live with a pin frozen where
    /// they clocked in. Authorised, and useless for tracking.
    var hasPreciseLocation: Bool { accuracy == .fullAccuracy }

    /// What an untracked staffer needs: location while the app is open.
    var hasLocationInUse: Bool {
        locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
    }

    var hasNotifications: Bool { Self.notificationsOK(notificationStatus) }

    var inUseStatusLabel: String {
        switch locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Ready"
        case .denied:
            return "Denied. Enable Location for this app in iPhone Settings."
        case .restricted:
            return "Restricted on this iPhone."
        case .notDetermined:
            return "Not requested yet."
        @unknown default:
            return "Unknown status."
        }
    }

    var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Ready"
        case .denied:
            return "Off. Enable Notifications for this app in iPhone Settings."
        case .notDetermined:
            return "Not requested yet."
        @unknown default:
            return "Unknown status."
        }
    }

    /// With Background App Refresh off, iOS will not wake the app to deliver
    /// or upload anything once it leaves the screen.
    var hasBackgroundRefresh: Bool { backgroundRefresh == .available }

    var preciseStatusLabel: String {
        hasPreciseLocation
            ? "Ready"
            : "Precise Location is off. Turn it on for this app in iPhone Settings."
    }

    var backgroundRefreshStatusLabel: String {
        switch backgroundRefresh {
        case .available:
            return "Ready"
        case .denied:
            return "Off. Enable Background App Refresh for this app in iPhone Settings."
        case .restricted:
            return "Restricted by Low Power Mode or a device policy."
        @unknown default:
            return "Unknown status."
        }
    }

    var locationServicesStatusLabel: String {
        locationServicesOn
            ? "Ready"
            : "Location Services are off for the whole iPhone. Turn them on in Settings > Privacy."
    }

    /// Everything GeoTrack needs to keep capturing after the app leaves the
    /// screen — the same set the checklist rows show, so the sheet and this
    /// check can never disagree about whether something is missing.
    static func isTrackingReady() async -> Bool {
        await isReady(tracked: true)
    }

    /// Whether every row the sheet shows for this mode is satisfied.
    ///
    /// A status the user CANNOT change (.restricted — parental controls or
    /// a device policy) counts as satisfied: the sheet cannot be closed any
    /// other way, so blocking on it would lock that person out of the app.
    static func isReady(tracked: Bool) async -> Bool {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        let servicesOn = await locationServicesEnabled()
        let notifications = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        let locationOK: Bool = status == .restricted || (tracked
            ? status == .authorizedAlways
            : status == .authorizedAlways || status == .authorizedWhenInUse)
        let preciseOK = status == .restricted || manager.accuracyAuthorization == .fullAccuracy
        let base = servicesOn && locationOK && preciseOK && notificationsOK(notifications)
        guard tracked else { return base }
        let motion = CMMotionActivityManager.authorizationStatus()
        let motionOK = !CMMotionActivityManager.isActivityAvailable()
            || motion == .authorized || motion == .restricted
        let refresh = UIApplication.shared.backgroundRefreshStatus
        // Low Power Mode switches Background App Refresh off for every app and
        // greys the toggle out, so nothing on this sheet can fix it. Counting
        // it as missing would hold the person on an unclosable sheet until
        // they leave Low Power Mode; the location session itself keeps
        // running without it.
        let refreshOK = refresh == .available || refresh == .restricted
            || (refresh == .denied && ProcessInfo.processInfo.isLowPowerModeEnabled)
        return base && motionOK && refreshOK
    }

    nonisolated static func notificationsOK(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// `locationServicesEnabled()` is synchronous and Apple warns it can stall
    /// the main thread, so it is always asked off the main actor.
    nonisolated static func locationServicesEnabled() async -> Bool {
        await Task.detached(priority: .utility) {
            CLLocationManager.locationServicesEnabled()
        }.value
    }

    var locationStatusLabel: String {
        switch locationStatus {
        case .authorizedAlways:
            return "Ready"
        case .authorizedWhenInUse:
            return "When In Use granted. Change to Always in Settings for background tracking."
        case .denied, .restricted:
            return "Denied. Enable Always Location in iPhone Settings."
        case .notDetermined:
            return "Not requested yet."
        @unknown default:
            return "Unknown status."
        }
    }

    var motionStatusLabel: String {
        if !CMMotionActivityManager.isActivityAvailable() {
            return "Motion Activity is not available on this device."
        }
        switch motionStatus {
        case .authorized:
            return "Ready"
        case .denied, .restricted:
            return "Denied. Enable Motion & Fitness in iPhone Settings."
        case .notDetermined:
            return "Not requested yet."
        @unknown default:
            return "Unknown status."
        }
    }

    func refresh() {
        locationStatus = locationManager.authorizationStatus
        motionStatus = CMMotionActivityManager.authorizationStatus()
        accuracy = locationManager.accuracyAuthorization
        backgroundRefresh = UIApplication.shared.backgroundRefreshStatus
        Task { [weak self] in
            let on = await Self.locationServicesEnabled()
            self?.locationServicesOn = on
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            self?.notificationStatus = settings.authorizationStatus
        }
    }

    func requestAlwaysLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // iOS requires the foreground grant before it can reliably
            // escalate to Always. Continue the sequence from the delegate.
            shouldEscalateToAlways = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            shouldEscalateToAlways = true
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            shouldEscalateToAlways = false
        case .denied, .restricted:
            openSettings()
        @unknown default:
            break
        }
        refresh()
    }

    func requestMotionAccess() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            refresh()
            return
        }
        let start = Date().addingTimeInterval(-5)
        motionManager.queryActivityStarting(from: start, to: Date(), to: .main) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func requestLocationInUse() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied:
            openSettings()
        default:
            break
        }
        refresh()
    }

    /// Same request AuthStore already makes, so granting here also
    /// registers for push the way the rest of the app expects.
    func requestNotifications() {
        guard notificationStatus == .notDetermined else {
            openSettings()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            Task { @MainActor [weak self] in
                if granted { UIApplication.shared.registerForRemoteNotifications() }
                self?.refresh()
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refresh()
            if self.shouldEscalateToAlways,
               manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            } else if manager.authorizationStatus == .authorizedAlways
                        || manager.authorizationStatus == .denied
                        || manager.authorizationStatus == .restricted {
                self.shouldEscalateToAlways = false
            }
        }
    }
}

#Preview {
    GeoTrackConsentView()
}
