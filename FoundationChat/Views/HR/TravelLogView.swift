import SwiftUI

struct TravelLogView: View {
    @State private var logs: [APITravelLog] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let api = HRAPIService.shared

    private var filteredLogs: [APITravelLog] {
        if searchText.isEmpty { return logs }
        return logs.filter {
            ($0.clientName ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.nameOfProject ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.vehicleNumber ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if filteredLogs.isEmpty {
                ContentUnavailableView("No Travel Logs", systemImage: "car",
                    description: Text("Travel logs will appear here.")).listRowSeparator(.hidden)
            } else {
                ForEach(filteredLogs) { log in
                    TravelLogRow(log: log)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by client or project")
        .navigationTitle("Travel Log")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLogs() }
        .refreshable { await loadLogs() }
    }

    private func loadLogs() async {
        isLoading = true
        errorMessage = nil
        do {
            logs = try await api.fetchTravelLog()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct TravelLogRow: View {
    let log: APITravelLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(log.clientName ?? "Unknown Client")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let km = log.totalKM, km > 0 {
                    Text("\(Int(km)) km")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }

            if let project = log.nameOfProject, !project.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "building.2").font(.caption2)
                    Text(project)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let date = log.siteVisitDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption2)
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                    if let time = log.pickupTime, !time.isEmpty {
                        Text("at \(time)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                if let pickup = log.pickupLocation, !pickup.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin").font(.caption2)
                        Text(pickup)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let vehicle = log.vehicleNumber, !vehicle.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "car").font(.caption2)
                        Text(vehicle)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let incharge = log.siteIncharge, !incharge.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person").font(.caption2)
                    Text(incharge)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
