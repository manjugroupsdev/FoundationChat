import SwiftUI

struct ConvexPermissionListView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var permissions: [ConvexPermission] = []
    @State private var usage: ConvexPermissionUsage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showApplySheet = false

    var body: some View {
        List {
            if let usage {
                usageSection(usage)
            }

            if permissions.isEmpty && !isLoading {
                ContentUnavailableView("No Permissions", systemImage: "clock.badge.questionmark", description: Text("No permission requests found."))
            }

            ForEach(permissions) { perm in
                permissionRow(perm)
                    .swipeActions(edge: .trailing) {
                        if perm.status == "pending" {
                            Button("Cancel", role: .destructive) {
                                cancelPermission(perm)
                            }
                        }
                    }
            }
        }
        .navigationTitle("Permissions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showApplySheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showApplySheet) {
            NavigationStack {
                ApplyPermissionView {
                    loadData()
                }
            }
        }
        .refreshable { loadData() }
        .overlay {
            if isLoading && permissions.isEmpty { ProgressView() }
        }
        .task { loadData() }
    }

    private func usageSection(_ usage: ConvexPermissionUsage) -> some View {
        Section("Monthly Usage") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fh", usage.usedHours ?? 0))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                VStack(alignment: .center, spacing: 4) {
                    Text("Limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0fh", usage.limitHours ?? 2))
                        .font(.title3.weight(.bold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fh", usage.remainingHours ?? 0))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func permissionRow(_ perm: ConvexPermission) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(perm.date ?? "--")
                    .font(.headline)
                Spacer()
                statusBadge(perm.status ?? "pending")
            }
            HStack {
                Label(perm.timeRange, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let mins = perm.durationMinutes {
                    Spacer()
                    Text("\(mins) min")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            if let reason = perm.reason, !reason.isEmpty {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "approved": return .green
        case "rejected": return .red
        case "cancelled": return .gray
        default: return .orange
        }
    }

    private func loadData() {
        guard let token = authStore.currentSession?.token else { return }
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let now = Date()
                let year = Calendar.current.component(.year, from: now)
                let month = Calendar.current.component(.month, from: now)
                async let permsReq = HRConvexAPIService.listPermissions(token: token)
                async let usageReq = HRConvexAPIService.getMonthlyPermissionUsage(token: token, year: year, month: month)
                permissions = try await permsReq
                usage = try? await usageReq
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelPermission(_ perm: ConvexPermission) {
        guard let token = authStore.currentSession?.token else { return }
        Task {
            do {
                try await HRConvexAPIService.cancelPermission(token: token, id: perm._id)
                loadData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
