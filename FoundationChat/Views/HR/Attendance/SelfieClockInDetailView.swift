import CoreLocation
import MapKit
import SwiftUI

struct SelfieClockInDetailView: View {
    let mode: PunchFlowView.PunchMode
    let selfie: UIImage
    let location: CLLocation
    let address: String?
    let timestamp: Date
    let isSubmitting: Bool
    let statusText: String?
    let errorMessage: String?

    var onRetake: () -> Void
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    private var title: String {
        mode == .punchIn ? "Confirm Clock In" : "Confirm Clock Out"
    }

    private var accent: Color {
        mode == .punchIn ? .green : .orange
    }

    private var confirmLabel: String {
        mode == .punchIn ? "Confirm Clock In" : "Confirm Clock Out"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                selfiePreview
                infoCard
                miniMap

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                if let statusText {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                actionButtons
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
                    .disabled(isSubmitting)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var selfiePreview: some View {
        Image(uiImage: selfie)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(accent.opacity(0.4), lineWidth: 2)
            )
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(icon: "clock.fill", tint: .blue, title: "Time") {
                Text(Self.timeFormatter.string(from: timestamp))
                    .font(.subheadline)
            }

            Divider()

            row(icon: "location.fill", tint: .blue, title: "Location") {
                VStack(alignment: .leading, spacing: 2) {
                    if let address, !address.isEmpty {
                        Text(address)
                            .font(.subheadline)
                    } else {
                        Text("Address unavailable")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(location.coordinate.latitude, specifier: "%.5f"), \(location.coordinate.longitude, specifier: "%.5f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            row(icon: "scope", tint: .blue, title: "Accuracy") {
                Text(String(format: "±%.0f m", location.horizontalAccuracy))
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row<Trailing: View>(icon: String, tint: Color, title: String, @ViewBuilder content: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                content()
            }
            Spacer()
        }
    }

    private var miniMap: some View {
        Map(initialPosition: .camera(MapCamera(
            centerCoordinate: location.coordinate,
            distance: 400
        ))) {
            Annotation("You", coordinate: location.coordinate) {
                ZStack {
                    Circle().fill(.blue.opacity(0.2)).frame(width: 50, height: 50)
                    Circle().fill(.blue).frame(width: 18, height: 18)
                    Circle().stroke(.white, lineWidth: 3).frame(width: 18, height: 18)
                }
            }
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: onConfirm) {
                HStack {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    }
                    Text(confirmLabel)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(isSubmitting)

            Button(action: onRetake) {
                Label("Retake Selfie", systemImage: "arrow.counterclockwise.circle")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(isSubmitting)
        }
    }
}
