import SwiftUI

struct StaffListView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var staff: [ConvexStaffListItem] = []
    @State private var cursor: String? = nil
    @State private var isDone: Bool = false
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage: String?

    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var searchResults: [ConvexStaffListItem] = []
    @State private var searchTask: Task<Void, Never>?

    private let pageSize = 25
    private let debounceMillis: UInt64 = 400

    private var displayedStaff: [ConvexStaffListItem] {
        isSearching ? searchResults : staff
    }

    var body: some View {
        List {
            if displayedStaff.isEmpty && !isLoading {
                ContentUnavailableView(
                    isSearching ? "No matches" : "No Staff",
                    systemImage: "person.2.slash",
                    description: Text(isSearching ? "Try a different search term." : "Directory is empty.")
                )
            }

            ForEach(displayedStaff) { item in
                NavigationLink(value: item._id) {
                    StaffRow(item: item)
                }
            }

            if !isSearching, !isDone, !staff.isEmpty {
                HStack {
                    Spacer()
                    if isLoadingMore {
                        ProgressView()
                    } else {
                        Button("Load More") { Task { await loadMore() } }
                            .font(.subheadline.weight(.medium))
                    }
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)
                .onAppear { Task { await loadMore() } }
            }
        }
        .navigationTitle("Staff")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search staff")
        .onChange(of: searchText) { _, newValue in
            scheduleSearch(query: newValue)
        }
        .navigationDestination(for: String.self) { staffId in
            StaffDetailView(staffId: staffId)
        }
        .overlay {
            if isLoading && staff.isEmpty {
                ProgressView()
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .refreshable { await reload() }
        .task {
            if staff.isEmpty { await reload() }
        }
    }

    private func reload() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await HRConvexAPIService.getStaffPaginated(
                token: token, numItems: pageSize, cursor: nil
            )
            staff = result.page
            cursor = result.continueCursor
            isDone = result.isDone
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let token = authStore.currentSession?.token,
              !isLoadingMore, !isDone else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await HRConvexAPIService.getStaffPaginated(
                token: token, numItems: pageSize, cursor: cursor
            )
            staff.append(contentsOf: result.page)
            cursor = result.continueCursor
            isDone = result.isDone
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isSearching = false
            searchResults = []
            return
        }
        isSearching = true
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceMillis * 1_000_000)
            if Task.isCancelled { return }
            await runSearch(query: trimmed)
        }
    }

    private func runSearch(query: String) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            let results = try await HRConvexAPIService.searchStaff(token: token, query: query)
            if !Task.isCancelled {
                searchResults = results
            }
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct StaffRow: View {
    let item: ConvexStaffListItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                Text(item.initials)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let phone = item.formattedPhone {
                    Text(phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusBadge
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(item.isActive ? "Active" : "Inactive")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((item.isActive ? Color.green : Color.red).opacity(0.15), in: Capsule())
            .foregroundStyle(item.isActive ? Color.green : Color.red)
    }
}

#Preview {
    NavigationStack {
        StaffListView()
    }
}
