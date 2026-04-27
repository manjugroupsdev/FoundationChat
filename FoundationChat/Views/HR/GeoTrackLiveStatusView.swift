import MapKit
import SwiftUI

// MARK: - GeoTrackLiveStatusView

struct GeoTrackLiveStatusView: View {
    @State private var entries: [GeoTrackLiveStatusEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showMap = false
    @State private var searchText = ""

    private let geoAPI = GeoTrackAPIService.shared

    private var filtered: [GeoTrackLiveStatusEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            ($0.staffName ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.department ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.designation ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var trackingEntries: [GeoTrackLiveStatusEntry] {
        filtered.filter { $0.isTracking == true }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showMap {
                liveMap
            } else {
                staffList
            }
        }
        .navigationTitle("Live Status")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showMap.toggle()
                } label: {
                    Image(systemName: showMap ? "list.bullet" : "map.fill")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search staff")
        .refreshable { await load() }
        .task { await load() }
    }

    private var liveMap: some View {
        Map(position: $mapPosition) {
            ForEach(trackingEntries, id: \.staffId) { entry in
                if let lat = entry.lat, let lng = entry.lng {
                    Annotation(entry.staffName ?? entry.staffId, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                        ZStack {
                            Circle()
                                .fill(activityColor(entry.activity))
                                .frame(width: 20, height: 20)
                            Circle()
                                .strokeBorder(.white, lineWidth: 2)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if isLoading {
                ProgressView().padding()
            }
        }
    }

    private var staffList: some View {
        Group {
            if isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if filtered.isEmpty {
                ContentUnavailableView("No Staff", systemImage: "person.2", description: Text("No active staff data."))
            } else {
                List {
                    let tracking = filtered.filter { $0.isTracking == true }
                    let offline  = filtered.filter { $0.isTracking != true }

                    if !tracking.isEmpty {
                        Section("Tracking (\(tracking.count))") {
                            ForEach(tracking, id: \.staffId) { entry in
                                NavigationLink {
                                    GeoTrackEmployeeDetailView(staffId: entry.staffId, staffName: entry.staffName)
                                } label: {
                                    LiveStatusRow(entry: entry)
                                }
                            }
                        }
                    }

                    if !offline.isEmpty {
                        Section("Offline (\(offline.count))") {
                            ForEach(offline, id: \.staffId) { entry in
                                NavigationLink {
                                    GeoTrackEmployeeDetailView(staffId: entry.staffId, staffName: entry.staffName)
                                } label: {
                                    LiveStatusRow(entry: entry)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await geoAPI.liveStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func activityColor(_ activity: String?) -> Color {
        switch activity {
        case "IN_VEHICLE":  return .blue
        case "ON_BICYCLE":  return .green
        case "RUNNING":     return .orange
        case "WALKING":     return .yellow
        default:            return .gray
        }
    }
}

// MARK: - LiveStatusRow

private struct LiveStatusRow: View {
    let entry: GeoTrackLiveStatusEntry

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(entry.isTracking == true ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.staffName ?? entry.staffId)
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    if let designation = entry.designation {
                        Text(designation).font(.caption).foregroundStyle(.secondary)
                    }
                    if let dept = entry.department {
                        Text("• \(dept)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if entry.isTracking == true {
                    HStack(spacing: 8) {
                        if let activity = entry.activity, activity != "STILL" {
                            Label(activityLabel(activity), systemImage: activityIcon(activity))
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        if let speed = entry.speed, speed > 0 {
                            Text(String(format: "%.0f km/h", speed * 3.6))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let battery = entry.batteryPct {
                            Label("\(battery)%", systemImage: batteryIcon(battery))
                                .font(.caption2)
                                .foregroundStyle(battery < 20 ? .red : .secondary)
                        }
                    }
                } else if let lastSeen = entry.lastSeenAt {
                    let date = Date(timeIntervalSince1970: lastSeen / 1000)
                    Text("Last seen \(date, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if entry.hasTamperAlert == true {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private func activityLabel(_ activity: String) -> String {
        switch activity {
        case "IN_VEHICLE":  return "Driving"
        case "ON_BICYCLE":  return "Cycling"
        case "RUNNING":     return "Running"
        case "WALKING":     return "Walking"
        default:            return activity
        }
    }

    private func activityIcon(_ activity: String) -> String {
        switch activity {
        case "IN_VEHICLE":  return "car.fill"
        case "ON_BICYCLE":  return "bicycle"
        case "RUNNING":     return "figure.run"
        case "WALKING":     return "figure.walk"
        default:            return "location.fill"
        }
    }

    private func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case 0..<20:  return "battery.25"
        case 20..<50: return "battery.50"
        case 50..<80: return "battery.75"
        default:      return "battery.100"
        }
    }
}

#Preview {
    NavigationStack {
        GeoTrackLiveStatusView()
    }
}
