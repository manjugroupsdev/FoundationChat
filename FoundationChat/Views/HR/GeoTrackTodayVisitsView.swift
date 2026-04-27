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
                initialStatus: visit.status
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

    private var canNavigate: Bool {
        let s = visit.status.uppercased()
        return s == "SCHEDULED" || s == "IN_PROGRESS"
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
                        visit.status.uppercased() == "IN_PROGRESS" ? "Resume Trip" : "Start Trip",
                        systemImage: "location.north.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(visit.status.uppercased() == "IN_PROGRESS" ? .blue : .green)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let status: String

    var color: Color {
        switch status.uppercased() {
        case "SCHEDULED":  return .orange
        case "IN_PROGRESS": return .blue
        case "COMPLETED":  return .green
        case "CANCELLED":  return .red
        default:           return .secondary
        }
    }

    var label: String {
        switch status.uppercased() {
        case "SCHEDULED":   return "Scheduled"
        case "IN_PROGRESS": return "In Progress"
        case "COMPLETED":   return "Completed"
        case "CANCELLED":   return "Cancelled"
        default:            return status
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
