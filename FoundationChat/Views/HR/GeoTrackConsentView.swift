import CoreLocation
import CoreMotion
import SwiftUI
import UIKit

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
                            consentManager.declineConsent()
                            onDecline()
                            dismiss()
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

    @State private var permissionGuide = GeoTrackPermissionGuide()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "location.badge.exclamationmark")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("GeoTrack Needs Permissions")
                            .font(.title3.bold())
                        Text(errorMessage ?? "Enable the required iPhone permissions so GeoTrack can continue background tracking.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    GeoTrackPermissionChecklist(guide: permissionGuide)

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

                        Button {
                            onRetry()
                            dismiss()
                        } label: {
                            Text("Retry GeoTrack")
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
            .navigationTitle("GeoTrack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .onAppear {
                permissionGuide.refresh()
            }
        }
    }
}

private struct GeoTrackPermissionChecklist: View {
    @Bindable var guide: GeoTrackPermissionGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Required on iPhone")
                .font(.headline)

            permissionRow(
                icon: "location.fill",
                title: "Always Location",
                subtitle: "Required for background route capture and final sync.",
                status: guide.locationStatusLabel,
                isReady: guide.hasAlwaysLocation
            ) {
                guide.requestAlwaysLocation()
            }

            permissionRow(
                icon: "figure.walk.motion",
                title: "Motion Activity",
                subtitle: "Required to detect walking, driving, running and still states.",
                status: guide.motionStatusLabel,
                isReady: guide.hasMotionAccess
            ) {
                guide.requestMotionAccess()
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

    private(set) var locationStatus: CLAuthorizationStatus
    private(set) var motionStatus: CMAuthorizationStatus

    override init() {
        locationStatus = locationManager.authorizationStatus
        motionStatus = CMMotionActivityManager.authorizationStatus()
        super.init()
        locationManager.delegate = self
    }

    var hasAlwaysLocation: Bool {
        locationStatus == .authorizedAlways
    }

    var hasMotionAccess: Bool {
        motionStatus == .authorized || !CMMotionActivityManager.isActivityAvailable()
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
    }

    func requestAlwaysLocation() {
        locationManager.requestAlwaysAuthorization()
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

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }
}

#Preview {
    GeoTrackConsentView()
}
