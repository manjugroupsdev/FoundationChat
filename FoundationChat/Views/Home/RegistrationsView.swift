import SwiftUI

/// VP-dashboard "Registrations" drill-down — today's completed registrations.
/// Ports the Android RegistrationsFragment.
struct RegistrationsView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var registrations: [DashboardRegistrationRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var cacheKey: String {
        let staffId = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        let day = AppModuleFormatters.ymd.string(from: Date())
        return "dashboard.registrations.\(staffId).\(day)"
    }

    var body: some View {
        List {
            if isLoading && registrations.isEmpty {
                ForEach(0..<5, id: \.self) { _ in
                    DashboardDrilldownSkeletonRow()
                }
            } else if let errorMessage, registrations.isEmpty {
                centeredRow {
                    VStack(spacing: 10) {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                }
            } else if registrations.isEmpty {
                centeredRow {
                    Label("No registrations completed today", systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(registrations) { row in
                    registrationRow(row)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Registrations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(forceRefresh: true) }
    }

    private func registrationRow(_ row: DashboardRegistrationRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x059669))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.clientName?.nonBlank ?? "Registration")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let owner = row.ownerName?.nonBlank {
                        Text(owner).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if let status = row.status?.nonBlank {
                        Text(status.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(hex: 0x059669).opacity(0.12), in: Capsule())
                            .foregroundStyle(Color(hex: 0x059669))
                    }
                }
                if let notes = row.notes?.nonBlank {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if let date = (row.completedDate ?? row.scheduledDate)?.nonBlank {
                Text(date)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func centeredRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { Spacer(); content(); Spacer() }
            .padding(.vertical, 32)
            .listRowSeparator(.hidden)
    }

    @MainActor
    private func load(forceRefresh: Bool = false) async {
        if !forceRefresh, registrations.isEmpty,
           let cached = LocalCache.get(cacheKey, as: [DashboardRegistrationRow].self) {
            registrations = cached
        }
        guard let token = authStore.currentSession?.token else {
            if registrations.isEmpty { errorMessage = "Not signed in." }
            return
        }
        isLoading = registrations.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            let refreshed = try await DashboardConvexAPIService.getDashboardRegistrations(
                token: token, date: nil
            )
            registrations = refreshed
            LocalCache.put(cacheKey, refreshed)
        } catch {
            if registrations.isEmpty { errorMessage = error.localizedDescription }
        }
    }
}
