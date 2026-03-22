import SwiftUI

struct SiteVisitListView: View {
    @State private var visits: [APISiteVisit] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let api = HRAPIService.shared

    private var filteredVisits: [APISiteVisit] {
        if searchText.isEmpty { return visits }
        return visits.filter {
            ($0.clientName ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.projectName ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.siteVisitRefNo ?? "").contains(searchText)
        }
    }

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if filteredVisits.isEmpty {
                ContentUnavailableView("No Site Visits", systemImage: "building.2",
                    description: Text("Site visits will appear here."))
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredVisits) { visit in
                    APISiteVisitRow(visit: visit)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by client or project")
        .navigationTitle("Site Visits")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadVisits() }
        .refreshable { await loadVisits() }
    }

    private func loadVisits() async {
        isLoading = true
        errorMessage = nil
        do {
            visits = try await api.fetchSiteVisits()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct APISiteVisitRow: View {
    let visit: APISiteVisit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(visit.displayClient)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(visit.displayStatus)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            if !visit.displayProject.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "building.2").font(.caption2)
                    Text(visit.displayProject)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let date = visit.siteVisitDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption2)
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                    if let time = visit.pickupTime, !time.isEmpty {
                        Text("at \(time)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let incharge = visit.siteIncharge, !incharge.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person").font(.caption2)
                    Text(incharge)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let refNo = visit.siteVisitRefNo {
                Text("Ref: \(refNo)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        let status = visit.displayStatus.lowercased()
        if status.contains("done") || status.contains("completed") || status.contains("reached") { return .green }
        if status.contains("fixed") || status.contains("confirmed") { return .blue }
        if status.contains("cancel") { return .red }
        return .orange
    }
}
