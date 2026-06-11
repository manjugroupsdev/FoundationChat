import SwiftUI

struct LeavesListView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var leaves: [ConvexLeave] = []
    @State private var balance: ConvexLeaveBalance?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showApplySheet = false

    private var canReviewLeaves: Bool {
        authStore.hasPermission("leaves.approve") || authStore.hasPermission("leaves.viewAll")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                leaveHeader
                VStack(spacing: 14) {
                    leaveBalanceCard
                    leaveHistorySection
                }
                .padding(.horizontal, 12)
                .padding(.top, -54)
                .padding(.bottom, 100)
            }
        }
        .background(Color(hex: 0xF4F6FB).ignoresSafeArea())
        .navigationTitle("My Leaves")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canReviewLeaves {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        LeaveApprovalsView()
                    } label: {
                        Image(systemName: "checklist.checked")
                    }
                    .accessibilityLabel("Leave approvals")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showApplySheet = true
            } label: {
                Text("Apply Leave")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(hex: 0x0B61CA))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showApplySheet) {
            NavigationStack {
                ApplyLeaveView {
                    loadData()
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .refreshable { loadData() }
        .overlay {
            if isLoading && leaves.isEmpty {
                ProgressView()
            }
        }
        .task { loadData() }
    }

    private var leaveHeader: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x0353B8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leave Summary")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Submit Leave")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 12)
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
        }
        .frame(height: 202)
    }

    private var leaveBalanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Leave")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text("\(Calendar.current.component(.year, from: Date()))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                if canReviewLeaves {
                    NavigationLink {
                        LeaveApprovalsView()
                    } label: {
                        Label("Approvals", systemImage: "checklist.checked")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                leaveMetric("Available", value: Int(totalLeaveAvailable), dot: Color(hex: 0x22C55E))
                leaveMetric("Used", value: Int(totalLeaveUsed), dot: Color(hex: 0x7A5AF8))
            }

            HStack(spacing: 8) {
                balanceTypeChip("Casual", remaining: balance?.casualRemaining ?? 0, total: balance?.casual ?? 0)
                balanceTypeChip("Sick", remaining: balance?.sickRemaining ?? 0, total: balance?.sick ?? 0)
                balanceTypeChip("Earned", remaining: balance?.earnedRemaining ?? 0, total: balance?.earned ?? 0)
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 8)
    }

    private var leaveHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Leave History")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                Text("\(leaves.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
            }

            if isLoading && leaves.isEmpty {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: 0xF8FAFC))
                            .frame(height: 104)
                            .redacted(reason: .placeholder)
                    }
                }
            } else if leaves.isEmpty {
                ContentUnavailableView("No Leaves", systemImage: "calendar.badge.minus", description: Text("You haven't applied for any leaves yet."))
                    .padding(.vertical, 28)
            } else {
                VStack(spacing: 10) {
                    ForEach(leaves) { leave in
                        androidLeaveCard(leave)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var totalLeaveAvailable: Double {
        let casualRemaining = balance?.casualRemaining ?? 0
        let sickRemaining = balance?.sickRemaining ?? 0
        let earnedRemaining = balance?.earnedRemaining ?? 0
        return casualRemaining + sickRemaining + earnedRemaining
    }

    private var totalLeaveUsed: Double {
        let casualUsed = balance?.casualUsed ?? 0
        let sickUsed = balance?.sickUsed ?? 0
        let earnedUsed = balance?.earnedUsed ?? 0
        return casualUsed + sickUsed + earnedUsed
    }

    private func leaveMetric(_ title: String, value: Int, dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x667085))
            }
            Text("\(value)")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14))
    }

    private func balanceTypeChip(_ title: String, remaining: Double, total: Double) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
            Text("\(Int(remaining))/\(Int(total))")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(hex: 0xF4F6FB), in: RoundedRectangle(cornerRadius: 12))
    }

    private func androidLeaveCard(_ leave: ConvexLeave) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(leave.leaveTypeLabel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Label(dateRange(for: leave), systemImage: "calendar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                statusBadge(leave.status ?? "pending")
            }

            HStack(spacing: 10) {
                infoTile("Days", "\(Int(leave.days ?? 0))")
                infoTile("Applied", shortDate(leave.appliedOn) ?? "--")
            }

            if let reason = leave.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(reason)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x667085))
                    .lineLimit(2)
            }

            if leave.status == "pending" {
                Button(role: .destructive) {
                    cancelLeave(leave)
                } label: {
                    Label("Cancel Request", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(14)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
    }

    private func infoTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: 0x98A2B3))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x344054))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
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

    private func dateRange(for leave: ConvexLeave) -> String {
        let from = shortDate(leave.fromDate) ?? leave.fromDate ?? "--"
        let to = shortDate(leave.toDate) ?? leave.toDate ?? "--"
        return leave.toDate == nil || leave.toDate == leave.fromDate ? from : "\(from) - \(to)"
    }

    private func shortDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) {
            return Self.dayFormatter.string(from: date)
        }
        if let date = Self.ymdFormatter.date(from: raw) {
            return Self.dayFormatter.string(from: date)
        }
        return raw
    }

    private static let ymdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

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
                if Self.isCancellation(error) { return }
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
                if Self.isCancellation(error) { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as NSError).code == NSURLErrorCancelled
    }
}
