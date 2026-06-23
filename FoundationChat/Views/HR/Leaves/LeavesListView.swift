import SwiftUI

struct LeavesListView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var leaves: [ConvexLeave] = []
    @State private var pendingLeaves: [ConvexLeave] = []
    @State private var balance: ConvexLeaveBalance?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showApplySheet = false
    @State private var historyFilter: LeaveHistoryFilter = .review
    @State private var activeScope: LeaveScope = .my
    @State private var rejectingLeave: ConvexLeave?
    @State private var cancelingLeave: ConvexLeave?
    @State private var rejectReason = ""
    @State private var actionInFlightId: String?

    private var canReviewLeaves: Bool {
        authStore.hasPermission("leaves.approve") || authStore.hasPermission("leaves.viewAll")
    }

    var body: some View {
        ZStack {
            Color(hex: 0xF1F3F8).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    leaveHeader
                    VStack(spacing: 0) {
                        leaveBalanceCard
                        leaveFilterRow
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        leaveHistorySection
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                    }
                    .padding(.top, -58)
                    .padding(.bottom, 112)
                }
            }
            .refreshable { loadData() }
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button {
                showApplySheet = true
            } label: {
                Text("Submit Leave")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Color(hex: 0xF1F3F8).opacity(0.96))
        }
        .sheet(isPresented: $showApplySheet) {
            ApplyLeaveView {
                loadData()
            }
            .presentationDetents([.height(390), .large])
            .presentationDragIndicator(.hidden)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .alert("Reject Leave", isPresented: .init(
            get: { rejectingLeave != nil },
            set: { if !$0 { rejectingLeave = nil } }
        )) {
            TextField("Reason", text: $rejectReason)
            Button("Reject", role: .destructive) {
                if let leave = rejectingLeave {
                    rejectLeave(leave, reason: rejectReason)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a reason for rejection")
        }
        .alert("Cancel Leave", isPresented: .init(
            get: { cancelingLeave != nil },
            set: { if !$0 { cancelingLeave = nil } }
        )) {
            Button("Cancel Leave", role: .destructive) {
                if let leave = cancelingLeave {
                    cancelLeave(leave)
                }
                cancelingLeave = nil
            }
            Button("Keep Leave", role: .cancel) {
                cancelingLeave = nil
            }
        } message: {
            Text("Are you sure you want to cancel this approved leave?")
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
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    Text("Submit Leave")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
                leaveBannerArtwork
                    .frame(width: 118, height: 88)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.top, 58)
        }
        .frame(height: 232)
    }

    private var leaveBannerArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: 0x1B63C7).opacity(0.95))
                .frame(width: 26, height: 42)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color(hex: 0xD6E7FF), lineWidth: 3)
                        .frame(width: 14, height: 9)
                        .offset(y: -4)
                }
                .offset(x: -43, y: 21)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 58, height: 68)
                .overlay(alignment: .top) {
                    Text("LEAVE")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .offset(y: 8)
                }
                .overlay {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.square.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x0B61CA))
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color(hex: 0xA7C8F7))
                                    .frame(width: 27, height: 4)
                            }
                        }
                    }
                    .padding(.top, 15)
                }
                .rotationEffect(.degrees(-7))
                .offset(x: 7, y: 4)

            Circle()
                .fill(Color(hex: 0xD9E7FF))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                }
                .offset(x: 31, y: 26)
        }
    }

    private var leaveBalanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeScope.balanceTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text("Period 1 Jan \(Calendar.current.component(.year, from: Date())) - 30 Dec \(Calendar.current.component(.year, from: Date()))")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if canReviewLeaves {
                    Menu {
                        ForEach(LeaveScope.allCases) { scope in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    activeScope = scope
                                    historyFilter = .review
                                }
                            } label: {
                                if scope == .team, pendingLeaves.count > 0 {
                                    Text("\(scope.title) (\(pendingLeaves.count))")
                                } else {
                                    Text(scope.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(activeScope.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if pendingLeaves.count > 0 {
                                Circle()
                                    .fill(Color(hex: 0xEF4444))
                                    .frame(width: 7, height: 7)
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: 0x061D3D))
                            .frame(width: 136, height: 37)
                            .background(Color(hex: 0xE5E7EB), in: Capsule())
                    }
                }
            }

            leaveMetric("Leave Used", value: Int(totalLeaveUsed), dot: Color(hex: 0x0B61CA))
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 28)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 30, bottomLeading: 0, bottomTrailing: 0, topTrailing: 30),
                style: .continuous
            )
                .fill(Color.white)
        }
    }

    private var leaveHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading && scopedLeaves.isEmpty {
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .frame(height: 142)
                            .redacted(reason: .placeholder)
                    }
                }
            } else if scopedLeaves.isEmpty || filteredLeaves.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "calendar.badge.minus", description: Text(emptyDescription))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredLeaves) { leave in
                        androidLeaveCard(leave, approvalMode: isApprovalScope)
                    }
                }
            }
        }
    }

    private var leaveFilterRow: some View {
        HStack(spacing: 0) {
            ForEach(LeaveHistoryFilter.allCases) { filter in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        historyFilter = filter
                    }
                } label: {
                    Text(filter.title(with: scopedLeaves))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(historyFilter == filter ? .white : Color(hex: 0x667085))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if historyFilter == filter {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: 0x0B61CA), Color(hex: 0x0353B8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(hex: 0xE9EDF5), in: Capsule())
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

    private var filteredLeaves: [ConvexLeave] {
        scopedLeaves.filter { historyFilter.contains(status: $0.status ?? "pending") }
    }

    private var scopedLeaves: [ConvexLeave] {
        switch activeScope {
        case .my:
            return leaves
        case .team:
            return pendingLeaves
        case .all:
            return leaves
        }
    }

    private var isApprovalScope: Bool {
        canReviewLeaves && activeScope == .team
    }

    private var emptyTitle: String {
        isApprovalScope ? "No Leave Approvals" : "No Leave Submitted!"
    }

    private var emptyDescription: String {
        isApprovalScope ? "There are no pending leave requests in review right now." : "Ready to catch some fresh air? Click \"Submit Leave\" and take that well-deserved break!"
    }

    private func leaveMetric(_ title: String, value: Int, dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
            }
            Text("\(value)")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(hex: 0xF8F9FC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func balanceTypeChip(_ title: String, remaining: Double, total: Double) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x667085))
            Text("\(Int(remaining))/\(Int(total))")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(hex: 0xF4F6FB), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func androidLeaveCard(_ leave: ConvexLeave, approvalMode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                Text(dateHeading(for: leave))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer()
                if !approvalMode && historyFilter == .approved {
                    Button {
                        cancelingLeave = leave
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xEF4444))
                            .frame(width: 72, height: 34)
                            .background(Color(hex: 0xFEF2F2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(hex: 0xFCA5A5), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                } else if !approvalMode && historyFilter != .rejected {
                    Button(role: .destructive) {
                        cancelLeave(leave)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xEF4444))
                            .frame(width: 34, height: 34)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(hex: 0xFCA5A5), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cleanReason(for: leave))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(shortRange(for: leave))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(leave.leaveTypeLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Text(dayCountText(for: leave))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                }
            }
            .padding(12)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }

            HStack(spacing: 8) {
                statusInline(leave.status ?? "pending")
                Spacer(minLength: 8)
                Text("By")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                Circle()
                    .fill(Color(hex: 0xF2F4F7))
                    .frame(width: 26, height: 26)
                    .overlay {
                        Text(authorName(for: leave, approvalMode: approvalMode).prefix(1).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: 0x667085))
                    }
                Text(authorName(for: leave, approvalMode: approvalMode))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if approvalMode {
                approvalActions(for: leave)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func approvalActions(for leave: ConvexLeave) -> some View {
        if historyFilter == .review {
            HStack(spacing: 10) {
                Button {
                    approveLeave(leave)
                } label: {
                    Text(actionInFlightId == leave._id ? "Working..." : "Approve")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(hex: 0x22C55E), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(actionInFlightId != nil)

                Button {
                    rejectingLeave = leave
                    rejectReason = ""
                } label: {
                    Text("Reject")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(hex: 0xEF4444), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(actionInFlightId != nil)
            }
        }
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

    private func statusInline(_ status: String) -> some View {
        HStack(spacing: 5) {
            if LeaveHistoryFilter.review.contains(status: status) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(statusColor(status))
            } else {
                Circle()
                    .fill(statusColor(status))
                    .frame(width: 7, height: 7)
            }
            Text(statusText(status))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(statusColor(status))
                .lineLimit(1)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "approved": return .green
        case "rejected": return .red
        case "cancelled": return .gray
        default: return .orange
        }
    }

    private func statusText(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "approved":
            return "Approved"
        case "rejected":
            return "Rejected"
        case "cancelled", "canceled":
            return "Cancelled"
        default:
            return "In Review"
        }
    }

    private func cleanReason(for leave: ConvexLeave) -> String {
        let reason = leave.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reason.isEmpty ? leave.leaveTypeLabel : reason
    }

    private func dayCountText(for leave: ConvexLeave) -> String {
        let days = Int(leave.days ?? 0)
        return "\(days) Day\(days == 1 ? "" : "s")"
    }

    private func authorName(for leave: ConvexLeave, approvalMode: Bool) -> String {
        if let staffName = leave.staffName, !staffName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return staffName
        }
        if approvalMode {
            return "Team Member"
        }
        return "Self"
    }

    private func dateHeading(for leave: ConvexLeave) -> String {
        fullDate(leave.fromDate) ?? shortDate(leave.fromDate) ?? leave.fromDate ?? "--"
    }

    private func shortRange(for leave: ConvexLeave) -> String {
        let from = shortDateWithoutYear(leave.fromDate) ?? shortDate(leave.fromDate) ?? leave.fromDate ?? "--"
        let to = shortDateWithoutYear(leave.toDate) ?? shortDate(leave.toDate) ?? leave.toDate ?? "--"
        return leave.toDate == nil || leave.toDate == leave.fromDate ? from : "\(from) - \(to)"
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

    private func shortDateWithoutYear(_ raw: String?) -> String? {
        parseDate(raw).map { Self.dayMonthFormatter.string(from: $0) }
    }

    private func fullDate(_ raw: String?) -> String? {
        parseDate(raw).map { Self.fullDayFormatter.string(from: $0) }
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) {
            return date
        }
        return Self.ymdFormatter.date(from: raw)
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

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
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
                async let pendingReq: [ConvexLeave] = canReviewLeaves ? HRConvexAPIService.getPendingLeaveApprovals(token: token) : []
                leaves = try await leavesReq
                balance = try? await balanceReq
                pendingLeaves = (try? await pendingReq) ?? []
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

    private func approveLeave(_ leave: ConvexLeave) {
        guard let token = authStore.currentSession?.token else { return }
        actionInFlightId = leave._id
        Task {
            defer { actionInFlightId = nil }
            do {
                try await HRConvexAPIService.approveLeave(token: token, id: leave._id)
                loadData()
            } catch {
                if Self.isCancellation(error) { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rejectLeave(_ leave: ConvexLeave, reason: String) {
        guard let token = authStore.currentSession?.token else { return }
        actionInFlightId = leave._id
        Task {
            defer {
                actionInFlightId = nil
                rejectingLeave = nil
                rejectReason = ""
            }
            do {
                try await HRConvexAPIService.rejectLeave(token: token, id: leave._id, reason: reason)
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

private enum LeaveScope: CaseIterable, Identifiable {
    case my
    case team
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .my: return "My Leaves"
        case .team: return "Team Leaves"
        case .all: return "All Leaves"
        }
    }

    var balanceTitle: String {
        switch self {
        case .my, .all: return "Total Leave"
        case .team: return "Team Leaves"
        }
    }
}

private enum LeaveHistoryFilter: CaseIterable, Identifiable {
    case review
    case approved
    case rejected

    var id: Self { self }

    func title(with leaves: [ConvexLeave]) -> String {
        let count = leaves.filter { contains(status: $0.status ?? "pending") }.count
        switch self {
        case .review:
            return "Review (\(count))"
        case .approved:
            return "Approved (\(count))"
        case .rejected:
            return "Rejected (\(count))"
        }
    }

    func contains(status: String) -> Bool {
        switch bucket(for: status) {
        case .review:
            return self == .review
        case .approved:
            return self == .approved
        case .rejected:
            return self == .rejected
        }
    }

    private func bucket(for status: String) -> Self {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "approved":
            return .approved
        case "rejected", "cancelled", "canceled":
            return .rejected
        default:
            return .review
        }
    }
}
