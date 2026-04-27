import SwiftUI

struct LeavesListView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var leaves: [ConvexLeave] = []
    @State private var balance: ConvexLeaveBalance?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showApplySheet = false

    var body: some View {
        List {
            if let balance {
                balanceSection(balance)
            }

            if leaves.isEmpty && !isLoading {
                ContentUnavailableView("No Leaves", systemImage: "calendar.badge.minus", description: Text("You haven't applied for any leaves yet."))
            }

            ForEach(leaves) { leave in
                leaveRow(leave)
                    .swipeActions(edge: .trailing) {
                        if leave.status == "pending" {
                            Button("Cancel", role: .destructive) {
                                cancelLeave(leave)
                            }
                        }
                    }
            }
        }
        .navigationTitle("My Leaves")
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
                ApplyLeaveView {
                    loadData()
                }
            }
        }
        .refreshable { loadData() }
        .overlay {
            if isLoading && leaves.isEmpty {
                ProgressView()
            }
        }
        .task { loadData() }
    }

    private func balanceSection(_ balance: ConvexLeaveBalance) -> some View {
        Section("Leave Balance") {
            HStack(spacing: 16) {
                balanceChip("Casual", remaining: balance.casualRemaining, total: balance.casual ?? 0, color: .blue)
                balanceChip("Sick", remaining: balance.sickRemaining, total: balance.sick ?? 0, color: .orange)
                balanceChip("Earned", remaining: balance.earnedRemaining, total: balance.earned ?? 0, color: .green)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }

    private func balanceChip(_ label: String, remaining: Double, total: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(remaining))")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text("/ \(Int(total))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func leaveRow(_ leave: ConvexLeave) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(leave.leaveTypeLabel)
                    .font(.headline)
                Spacer()
                statusBadge(leave.status ?? "pending")
            }
            HStack {
                Label(leave.fromDate ?? "--", systemImage: "calendar")
                if let to = leave.toDate, to != leave.fromDate {
                    Text("→ \(to)")
                }
                Spacer()
                if let days = leave.days {
                    Text("\(Int(days)) day\(days > 1 ? "s" : "")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let reason = leave.reason, !reason.isEmpty {
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
                let year = Calendar.current.component(.year, from: Date())
                async let leavesReq = HRConvexAPIService.getMyLeaves(token: token)
                async let balanceReq = HRConvexAPIService.getLeaveBalance(token: token, year: year)
                leaves = try await leavesReq
                balance = try? await balanceReq
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelLeave(_ leave: ConvexLeave) {
        guard let token = authStore.currentSession?.token else { return }
        Task {
            do {
                try await HRConvexAPIService.cancelLeave(token: token, id: leave._id)
                loadData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
