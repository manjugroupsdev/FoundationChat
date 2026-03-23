import SwiftUI

struct GPSTripListView: View {
    @State private var trips: [APIGPSTrip] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var filterMode = "all" // "all" or "pending"

    private let api = HRAPIService.shared

    private var filteredTrips: [APIGPSTrip] {
        if searchText.isEmpty { return trips }
        return trips.filter {
            ($0.userName ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.refNo ?? "").contains(searchText) ||
            ($0.remarks ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filterMode) {
                Text("All Trips").tag("all")
                Text("Pending").tag("pending")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                } else if let error = errorMessage {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle",
                        description: Text(error)).listRowSeparator(.hidden)
                } else if filteredTrips.isEmpty {
                    ContentUnavailableView("No GPS Trips", systemImage: "location",
                        description: Text("GPS tracking trips will appear here.")).listRowSeparator(.hidden)
                } else {
                    ForEach(filteredTrips) { trip in
                        NavigationLink {
                            GPSTripDetailView(tripId: trip.siteVisitGPSId, tripSummary: trip)
                        } label: {
                            GPSTripRow(trip: trip)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name or ref")
        .navigationTitle("GPS Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    GPSDayMapView()
                } label: {
                    Image(systemName: "map")
                }
            }
        }
        .task { await loadTrips() }
        .onChange(of: filterMode) { Task { await loadTrips() } }
        .refreshable { await loadTrips() }
    }

    private func loadTrips() async {
        isLoading = true
        errorMessage = nil
        do {
            trips = try await api.fetchGPSTrips(mode: filterMode)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct GPSTripRow: View {
    let trip: APIGPSTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trip.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let approved = trip.isApproved {
                    Text(approved ? "Approved" : "Pending")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((approved ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                        .foregroundStyle(approved ? .green : .orange)
                }
            }

            if let start = trip.startingDateAndTime {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption2)
                    Text(start, format: .dateTime.day().month(.abbreviated).hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                if let duration = trip.totalDuration, !duration.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.caption2)
                        Text(duration)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let purpose = trip.purpose, !purpose.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag").font(.caption2)
                        Text(purpose)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let remarks = trip.remarks, !remarks.isEmpty {
                Text(remarks)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(1)
            }

            if let refNo = trip.refNo {
                Text("Ref: \(refNo)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
