import SwiftUI

struct PermissionListView: View {
    @State private var permissions: [APIPermission] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showNewForm = false
    @State private var errorMessage: String?

    private let api = HRAPIService.shared

    private var filteredPermissions: [APIPermission] {
        if searchText.isEmpty { return permissions }
        return permissions.filter {
            ($0.reason ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.employeeName ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if filteredPermissions.isEmpty {
                ContentUnavailableView("No Permissions", systemImage: "calendar.badge.clock",
                    description: Text("Your leave requests will appear here."))
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredPermissions) { permission in
                    APIPermissionRow(permission: permission)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by reason")
        .navigationTitle("Permission")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewForm = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNewForm) {
            PermissionFormView { await loadPermissions() }
        }
        .task { await loadPermissions() }
        .refreshable { await loadPermissions() }
    }

    private func loadPermissions() async {
        isLoading = true
        errorMessage = nil
        do {
            permissions = try await api.fetchPermissions()
            permissions.sort { ($0.permissionDate ?? .distantPast) > ($1.permissionDate ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct APIPermissionRow: View {
    let permission: APIPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let date = permission.permissionDate {
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                if permission.permissionStatus == .pending {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(Color(.systemIndigo))
                }
            }

            HStack(spacing: 4) {
                if let from = permission.beginningDateTime {
                    Text(from, format: .dateTime.hour().minute())
                }
                if let to = permission.endingDateTime {
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(to, format: .dateTime.hour().minute())
                }
                Text("(\(permission.durationFormatted))")
                    .foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text(permission.reason ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(permission.permissionStatus.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(permission.permissionStatus).opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor(permission.permissionStatus))
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}
