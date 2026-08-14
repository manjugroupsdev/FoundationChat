import CoreLocation
import SwiftUI

// MARK: - GeoTrackTodayVisitsView

struct GeoTrackTodayVisitsView: View {
    @State private var visits: [GeoTrackTodayVisit] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var visitToNavigate: GeoTrackTodayVisit?

    private let geoAPI = GeoTrackAPIService.shared

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading visits…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if visits.isEmpty {
                ContentUnavailableView(
                    "No Visits Today",
                    systemImage: "calendar.badge.clock",
                    description: Text("Scheduled visits for today will appear here.")
                )
            } else {
                List(visits) { visit in
                    VisitRow(
                        visit: visit,
                        onNavigate: { visitToNavigate = visit }
                    )
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Today's Visits")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .fullScreenCover(item: $visitToNavigate, onDismiss: { Task { await load() } }) { visit in
            TripNavigationView(
                visitId: visit.id,
                placeName: visit.placeName ?? "Destination",
                placeAddress: visit.placeAddress,
                destination: coordinate(for: visit),
                initialStatus: visit.status,
                tripType: visit.tripType,
                travelMode: visit.travelMode,
                vehiclePreference: visit.vehiclePreference,
                clientPlaceVisitId: visit.clientPlaceVisitId,
                cpClientMet: visit.cpVisit?.clientMet,
                cpOutcome: visit.cpVisit?.outcome,
                cpVisitCategory: visit.visitCategory,
                cpType: visit.cpVisit?.cpType,
                requiresOpenAttendance: true,
                onTripChanged: {
                    Task { await load() }
                }
            )
        }
    }

    private func coordinate(for visit: GeoTrackTodayVisit) -> CLLocationCoordinate2D? {
        guard let lat = visit.placeLat, let lng = visit.placeLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            visits = try await geoAPI.todayVisits(date: df.string(from: Date()))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - VisitRow

private struct VisitRow: View {
    let visit: GeoTrackTodayVisit
    let onNavigate: () -> Void

    private var normalizedStatus: String {
        visit.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    private var canNavigate: Bool {
        switch normalizedStatus {
        case "scheduled", "in_progress", "started", "ongoing", "active", "arrived", "arrival_verified":
            return true
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.placeName ?? "Unknown Place")
                        .font(.subheadline.weight(.semibold))
                    if let address = visit.placeAddress {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                StatusBadge(status: visit.status)
            }

            if let type = visit.placeType {
                Label(type, systemImage: "tag")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if canNavigate {
                Button(action: onNavigate) {
                    Label(
                        normalizedStatus == "scheduled" ? "Start Trip" : "Resume Trip",
                        systemImage: "location.north.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(normalizedStatus == "scheduled" ? .green : .blue)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let status: String

    private var normalizedStatus: String {
        status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    var color: Color {
        switch normalizedStatus {
        case "scheduled": return .orange
        case "in_progress", "started", "ongoing", "active", "arrived", "arrival_verified": return .blue
        case "completed", "complete", "done": return .green
        case "cancelled", "canceled": return .red
        default: return .secondary
        }
    }

    var label: String {
        switch normalizedStatus {
        case "scheduled": return "Scheduled"
        case "in_progress", "started", "ongoing", "active": return "In Progress"
        case "arrived", "arrival_verified": return "Arrived"
        case "completed", "complete", "done": return "Completed"
        case "cancelled", "canceled": return "Cancelled"
        default: return status
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - GeoTrackTodayVisit Identifiable

extension GeoTrackTodayVisit: Identifiable {}

#Preview {
    NavigationStack {
        GeoTrackTodayVisitsView()
    }
}
