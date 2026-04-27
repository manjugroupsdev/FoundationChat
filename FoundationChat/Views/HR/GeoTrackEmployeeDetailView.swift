import MapKit
import SwiftUI

// MARK: - GeoTrackEmployeeDetailView

struct GeoTrackEmployeeDetailView: View {
    let staffId: String
    let staffName: String?

    @State private var detail: GeoTrackEmployeeDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var mapPosition: MapCameraPosition = .automatic

    private let geoAPI = GeoTrackAPIService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = errorMessage {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let detail {
                    staffHeader(detail.staff)
                    if let live = detail.liveStatus {
                        liveStatusCard(live)
                    }
                    if let tampers = detail.recentTamperEvents, !tampers.isEmpty {
                        tamperEventsCard(tampers)
                    }
                    if let consent = detail.consent {
                        consentCard(consent)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(staffName ?? "Employee Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func staffHeader(_ staff: GeoTrackStaffInfo) -> some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

            VStack(spacing: 4) {
                Text(staff.name ?? "Unknown")
                    .font(.title3.weight(.semibold))
                if let designation = staff.designation {
                    Text(designation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let department = staff.department {
                    Text(department)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: staff.geoTrackingEnabled == true ? "location.circle.fill" : "location.slash.fill")
                    .foregroundStyle(staff.geoTrackingEnabled == true ? .green : .red)
                Text(staff.geoTrackingEnabled == true ? "Geo Tracking Enabled" : "Geo Tracking Disabled")
                    .font(.caption)
                    .foregroundStyle(staff.geoTrackingEnabled == true ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func liveStatusCard(_ live: GeoTrackLiveStatusEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Status", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(live.isTracking == true ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(live.isTracking == true ? "Tracking" : "Offline")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(live.isTracking == true ? .green : .secondary)
                }
            }

            if let lat = live.lat, let lng = live.lng {
                Map(position: $mapPosition) {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                        ZStack {
                            Circle().fill(.blue).frame(width: 16, height: 16)
                            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 16, height: 16)
                        }
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear {
                    mapPosition = .camera(.init(centerCoordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), distance: 1000))
                }
            }

            VStack(spacing: 8) {
                if let activity = live.activity {
                    InfoRow(icon: "figure.walk", label: "Activity", value: activity)
                }
                if let speed = live.speed {
                    InfoRow(icon: "speedometer", label: "Speed", value: String(format: "%.0f km/h", speed * 3.6))
                }
                if let battery = live.batteryPct {
                    InfoRow(icon: "battery.75", label: "Battery", value: "\(battery)%")
                }
                if let lastSeen = live.lastSeenAt {
                    let date = Date(timeIntervalSince1970: lastSeen / 1000)
                    InfoRow(icon: "clock", label: "Last Seen", value: date.formatted(.dateTime.hour().minute().second()))
                }
            }

            if live.hasTamperAlert == true {
                Label("Active tamper alert", systemImage: "exclamationmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tamperEventsCard(_ events: [GeoTrackTamperEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tamper Events", systemImage: "exclamationmark.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)

            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(severityColor(event.severity))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.eventType.replacingOccurrences(of: "_", with: " "))
                            .font(.caption.weight(.semibold))
                        HStack {
                            Text(event.severity)
                                .font(.caption2)
                                .foregroundStyle(severityColor(event.severity))
                            Spacer()
                            let date = Date(timeIntervalSince1970: event.detectedAt / 1000)
                            Text(date, format: .dateTime.day().month().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if event.acknowledged {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func consentCard(_ consent: GeoTrackConsentRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Consent Status", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))

            HStack {
                Text(consent.consented ? "Consented" : "Declined")
                    .font(.subheadline)
                    .foregroundStyle(consent.consented ? .green : .red)
                Spacer()
                if let version = consent.appVersion {
                    Text("App: \(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let ts = consent.consentedAt {
                let date = Date(timeIntervalSince1970: ts / 1000)
                InfoRow(icon: "clock", label: "Date", value: date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "CRITICAL": return .red
        case "HIGH":     return .orange
        case "MEDIUM":   return .yellow
        default:         return .secondary
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            detail = try await geoAPI.employeeDetail(staffId: staffId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        GeoTrackEmployeeDetailView(staffId: "preview-id", staffName: "Jane Doe")
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
    }
}
