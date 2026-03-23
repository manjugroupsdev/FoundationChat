import MapKit
import SwiftUI

struct GPSDayMapView: View {
    @State private var selectedDate = Date()
    @State private var selectedUserId: Int = 0
    @State private var dayMap: APIGPSDayMap?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var mapPosition: MapCameraPosition = .automatic

    private let api = HRAPIService.shared

    private let routeColors: [Color] = [.blue, .red, .green, .purple, .orange, .cyan, .pink, .indigo]

    var body: some View {
        VStack(spacing: 0) {
            // Date & user filter bar
            filterBar

            // Map
            ZStack {
                if isLoading {
                    Color(.systemGray6)
                        .overlay { ProgressView("Loading map...") }
                } else if let dayMap, !dayMap.waypoints.isEmpty {
                    Map(position: $mapPosition) {
                        ForEach(dayMap.waypoints) { wp in
                            Annotation("", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng)) {
                                Circle()
                                    .fill(colorForGPSId(wp.gpsId ?? 0))
                                    .frame(width: 8, height: 8)
                                    .overlay {
                                        Circle().strokeBorder(.white, lineWidth: 1)
                                    }
                            }
                        }

                        // Draw polyline for each segment
                        let groupedByGpsId = Dictionary(grouping: dayMap.waypoints, by: { $0.gpsId ?? 0 })
                        ForEach(Array(groupedByGpsId.keys.sorted()), id: \.self) { gpsId in
                            if let points = groupedByGpsId[gpsId], points.count > 1 {
                                let coords = points
                                    .sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
                                    .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                                MapPolyline(coordinates: coords)
                                    .stroke(colorForGPSId(gpsId), lineWidth: 3)
                            }
                        }
                    }
                } else {
                    Color(.systemGray6)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "map")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No GPS data for this date")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .frame(maxHeight: .infinity)

            // Users summary
            if let users = dayMap?.users, !users.isEmpty {
                usersSummary(users)
            }
        }
        .navigationTitle("Day Map")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDayMap() }
    }

    private var filterBar: some View {
        HStack {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()

            if let users = dayMap?.users, !users.isEmpty {
                Menu {
                    Button("All Users") { selectedUserId = 0; Task { await loadDayMap() } }
                    ForEach(users) { user in
                        Button(user.displayName) {
                            selectedUserId = user.userId
                            Task { await loadDayMap() }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.line.dotted.person")
                        Text(selectedUserId == 0 ? "All Users" : dayMap?.users.first { $0.userId == selectedUserId }?.displayName ?? "User")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5), in: Capsule())
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: selectedDate) { Task { await loadDayMap() } }
    }

    private func usersSummary(_ users: [APIGPSDayUser]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(users) { user in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(.caption.weight(.semibold))
                        HStack(spacing: 8) {
                            if let duration = user.totalDuration {
                                Label(duration, systemImage: "clock")
                            }
                            if let points = user.totalPoints {
                                Label("\(points) pts", systemImage: "mappin")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func colorForGPSId(_ gpsId: Int) -> Color {
        routeColors[abs(gpsId) % routeColors.count]
    }

    private func loadDayMap() async {
        isLoading = true
        errorMessage = nil
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        do {
            dayMap = try await api.fetchGPSDayMap(date: df.string(from: selectedDate), userId: selectedUserId)
            mapPosition = .automatic
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
