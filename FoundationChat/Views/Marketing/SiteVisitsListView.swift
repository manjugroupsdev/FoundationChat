import SwiftUI

/// Marketing > Site Visits list. Mirrors the Android `SiteVisitsListFragment`:
/// pulls scheduled visits across a ±30-day window from
/// `GET /api/sitevisits/my`, sorts newest scheduled date first, and lets the
/// user filter by status bucket and free-text search by place / address.
struct SiteVisitsListView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var visits: [ConvexSiteVisit] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var selectedStatus: SiteVisitStatus = .all
    @State private var searchText = ""
    @State private var hasLoadedOnce = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var filteredVisits: [ConvexSiteVisit] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return visits.filter { visit in
            let matchesStatus = selectedStatus == .all || visit.statusBucket == selectedStatus
            let matchesQuery: Bool = {
                guard !trimmed.isEmpty else { return true }
                let haystacks = [visit.placeName, visit.placeAddress, visit.placeType, visit.status]
                return haystacks.contains { $0?.lowercased().contains(trimmed) == true }
            }()
            return matchesStatus && matchesQuery
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusFilterBar
            content
        }
        .navigationTitle("Site Visits")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search place or address")
        .refreshable { await load() }
        .task {
            if !hasLoadedOnce { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && visits.isEmpty {
            ProgressView("Loading visits…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed && visits.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load visits", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage ?? "Please try again.")
            } actions: {
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if filteredVisits.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "mappin.slash")
            } description: {
                Text(emptyDescription)
            }
        } else {
            List {
                ForEach(filteredVisits) { visit in
                    SiteVisitRow(visit: visit)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyTitle: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "No matches"
        }
        return selectedStatus == .all ? "No site visits" : "No \(selectedStatus.title.lowercased()) visits"
    }

    private var emptyDescription: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Try a different place name or address."
        }
        return "Scheduled visits in the last 30 days will appear here."
    }

    private var statusFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SiteVisitStatus.allCases) { status in
                    let count = countFor(status: status)
                    Button {
                        selectedStatus = status
                    } label: {
                        HStack(spacing: 6) {
                            Text(status.title)
                            if status != .all && count > 0 {
                                Text("\(count)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.white.opacity(0.25), in: Capsule())
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(selectedStatus == status ? Color.white : Color.primary)
                        .background(
                            selectedStatus == status
                                ? (status == .all ? Color.accentColor : status.tint)
                                : Color(.systemGray5),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func countFor(status: SiteVisitStatus) -> Int {
        guard status != .all else { return visits.count }
        return visits.filter { $0.statusBucket == status }.count
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            loadFailed = true
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        loadFailed = false
        errorMessage = nil
        defer { isLoading = false; hasLoadedOnce = true }

        let calendar = Calendar.current
        let today = Date()
        let from = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 30, to: today) ?? today
        let fromDate = Self.dateFormatter.string(from: from)
        let toDate = Self.dateFormatter.string(from: to)

        do {
            let result = try await HRConvexAPIService.getMySiteVisits(
                token: token,
                fromDate: fromDate,
                toDate: toDate
            )
            visits = result.sorted { ($0.scheduledDate ?? "") > ($1.scheduledDate ?? "") }
        } catch {
            loadFailed = true
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row

struct SiteVisitRow: View {
    let visit: ConvexSiteVisit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(visit.placeName ?? "Unknown place")
                        .font(.headline)
                        .lineLimit(2)
                    if let address = visit.placeAddress, !address.isEmpty {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                StatusPill(bucket: visit.statusBucket)
            }

            HStack(spacing: 12) {
                if let scheduled = formattedDate(visit.scheduledDate) {
                    Label(scheduled, systemImage: "calendar")
                }
                if let timeRange = formattedTimeRange() {
                    Label(timeRange, systemImage: "clock")
                }
                if let type = visit.placeType, !type.isEmpty {
                    Label(type, systemImage: "tag")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func formattedDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formattedTimeRange() -> String? {
        let start = visit.scheduledStartTime?.trimmingCharacters(in: .whitespaces)
        let end = visit.scheduledEndTime?.trimmingCharacters(in: .whitespaces)
        switch (start?.isEmpty == false ? start : nil, end?.isEmpty == false ? end : nil) {
        case (let s?, let e?): return "\(s) – \(e)"
        case (let s?, nil): return s
        case (nil, let e?): return e
        default: return nil
        }
    }
}

private struct StatusPill: View {
    let bucket: SiteVisitStatus

    var body: some View {
        Text(bucket.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bucket.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(bucket.tint)
    }
}

#Preview {
    NavigationStack {
        SiteVisitsListView()
    }
    .environment(AuthStore())
}
