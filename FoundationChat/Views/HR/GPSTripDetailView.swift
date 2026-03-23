import MapKit
import SwiftUI

struct GPSTripDetailView: View {
    let tripId: Int
    let tripSummary: APIGPSTrip

    @State private var detail: APIGPSTripDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var mapPosition: MapCameraPosition = .automatic

    private let api = HRAPIService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Map
                mapSection

                // Trip info
                infoSection

                // Waypoints list
                if let waypoints = detail?.waypoints, !waypoints.isEmpty {
                    waypointsList(waypoints)
                }
            }
            .padding()
        }
        .navigationTitle("Trip #\(tripSummary.refNo ?? "\(tripId)")")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
    }

    private var mapSection: some View {
        Group {
            if isLoading {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .frame(height: 300)
                    .overlay { ProgressView() }
            } else if let waypoints = detail?.waypoints, !waypoints.isEmpty {
                Map(position: $mapPosition) {
                    // Route polyline
                    let coords = waypoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    MapPolyline(coordinates: coords)
                        .stroke(.blue, lineWidth: 3)

                    // Start marker
                    if let first = waypoints.first {
                        Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)) {
                            Image(systemName: "flag.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                    }

                    // End marker
                    if let last = waypoints.last, waypoints.count > 1 {
                        Annotation("End", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                            Image(systemName: "flag.checkered.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .frame(height: 200)
                    .overlay {
                        VStack {
                            Image(systemName: "map")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No waypoints recorded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
    }

    private var infoSection: some View {
        VStack(spacing: 12) {
            InfoRow(icon: "person", label: "Staff", value: tripSummary.displayName)
            if let purpose = tripSummary.purpose {
                InfoRow(icon: "tag", label: "Purpose", value: purpose)
            }
            if let duration = detail?.totalDuration ?? tripSummary.totalDuration {
                InfoRow(icon: "clock", label: "Duration", value: duration)
            }
            if let start = detail?.startingDateAndTime ?? tripSummary.startingDateAndTime {
                InfoRow(icon: "play.circle", label: "Started", value: start.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
            }
            if let end = detail?.endingDateAndTime ?? tripSummary.endingDateAndTime {
                InfoRow(icon: "stop.circle", label: "Ended", value: end.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
            }
            if let count = detail?.waypoints.count {
                InfoRow(icon: "mappin.and.ellipse", label: "Waypoints", value: "\(count)")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func waypointsList(_ waypoints: [APIWaypoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WAYPOINTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(waypoints.enumerated()), id: \.offset) { index, wp in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(index == 0 ? Color.green : (index == waypoints.count - 1 ? Color.red : Color.blue))
                            .frame(width: 24, height: 24)
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.6f, %.6f", wp.latitude, wp.longitude))
                            .font(.caption.monospaced())
                        if let desc = wp.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if wp.isManuallyCaptured == true {
                        Image(systemName: "hand.tap")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            detail = try await api.fetchGPSTripDetail(siteVisitGPSId: tripId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
