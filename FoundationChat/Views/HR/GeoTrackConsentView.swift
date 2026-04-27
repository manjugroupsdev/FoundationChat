import SwiftUI

// MARK: - GeoTrackConsentView

/// Consent screen shown before GPS time tracking begins.
/// Mirrors Android's GeoTrackConsentActivity disclosure text and button layout.
struct GeoTrackConsentView: View {
    @Environment(\.dismiss) private var dismiss

    var onConsent: () -> Void = {}
    var onDecline: () -> Void = {}

    @State private var consentManager = GeoTrackConsentManager.shared

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
                            body: "Tracking starts and stops manually via the app. It is not active outside of your initiated sessions."
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

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                await consentManager.giveConsent()
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

#Preview {
    GeoTrackConsentView()
}
