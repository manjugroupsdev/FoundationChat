import SwiftUI

struct LeavesListView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var leaves: [ConvexLeave] = []
    @State private var pendingLeaves: [ConvexLeave] = []
    @State private var allLeaves: [ConvexLeave] = []
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
    @State private var isReportingManager = false
    @State private var showAdvancedFilter = false
    @State private var advancedFilter: AdvancedFilterState = {
        var state = AdvancedFilterState()
        state.setSelected(["review"], for: "status")
        return state
    }()

    private var canManageTeamLeaves: Bool {
        isReportingManager || authStore.hasPermission("leaves.approve")
    }

    private var canViewAllLeaves: Bool {
        authStore.hasPermission("leaves.viewAll")
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Blue base fills the top safe area (status-bar strip) so there is no
            // white gap above the header; the grey page background is kept OUT of
            // the top safe area so it can't repaint the status bar. Matches header.
            Color(hex: 0x0B61CA)
                .ignoresSafeArea(edges: .top)

            Color(hex: 0xF1F3F8)
                .ignoresSafeArea(edges: .bottom)
            leaveHeader
                .ignoresSafeArea(edges: .top)

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 174)

                    VStack(spacing: 0) {
                        leaveBalanceCard
                        leaveFilterRow
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        leaveHistorySection
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                    }
                    .background(Color(hex: 0xF1F3F8))
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 30, bottomLeading: 0, bottomTrailing: 0, topTrailing: 30),
                            style: .continuous
                        )
                    )
                    .padding(.bottom, 112)
                }
            }
            .refreshable { loadData() }
            .ignoresSafeArea(edges: .top)

            if let cancelingLeave {
                cancelLeaveDialog(for: cancelingLeave)
                    .zIndex(20)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showApplySheet = true
            } label: {
                Text("Apply Leave")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
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
            .blur(radius: cancelingLeave == nil ? 0 : 2)
            .disabled(cancelingLeave != nil)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Color(hex: 0xF1F3F8).opacity(0.96)
                    if cancelingLeave != nil {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Color.black.opacity(0.34))
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
        }
        .sheet(isPresented: $showApplySheet) {
            ApplyLeaveView {
                loadData()
            }
            .appLibraryNativeSheet([.height(620), .large])
        }
        .fullScreenCover(isPresented: $showAdvancedFilter) {
            AdvancedListFilterView(
                title: "Filter Leaves",
                categories: leaveFilterCategories,
                state: advancedFilter,
                resultCount: { state in scopedLeaves.filter { matchesLeave($0, state: state) }.count },
                onApply: { state in
                    advancedFilter = state
                    if let status = state.selected("status").first {
                        historyFilter = leaveHistoryFilter(status)
                    }
                    loadData()
                }
            )
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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await resolveReportingScope()
            loadData()
        }
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
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    Text("Apply Leave")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(.top, 12)
                Spacer()
                leaveBannerArtwork
                    .frame(width: 166, height: 112)
                    .offset(x: 4, y: -2)
            }
            .padding(.leading, 28)
            .padding(.trailing, 14)
            .padding(.top, 58)
        }
        .frame(height: 232)
    }

    private var leaveBannerArtwork: some View {
        ZStack {
            Image(systemName: "airplane")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x7FB3FF))
                .rotationEffect(.degrees(-16))
                .offset(x: 48, y: -42)

            Image(systemName: "cloud.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: 0x9FCBFF))
                .offset(x: -62, y: -24)

            Image(systemName: "cloud.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: 0x9FCBFF))
                .offset(x: 69, y: -14)

            Path { path in
                path.move(to: CGPoint(x: 31, y: 72))
                path.addCurve(to: CGPoint(x: 84, y: 29), control1: CGPoint(x: 38, y: 28), control2: CGPoint(x: 59, y: 30))
                path.addCurve(to: CGPoint(x: 124, y: 18), control1: CGPoint(x: 96, y: 29), control2: CGPoint(x: 107, y: 22))
            }
            .stroke(Color(hex: 0x8EBEFF).opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 7]))
            .frame(width: 150, height: 102)
            .offset(x: 2, y: 3)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: 0x1357B2).opacity(0.95))
                .frame(width: 30, height: 54)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color(hex: 0xD6E7FF), lineWidth: 3)
                        .frame(width: 16, height: 10)
                        .offset(y: -4)
                }
                .overlay {
                    VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: 0x5A94DE))
                                .frame(width: 18, height: 4)
                        }
                    }
                    .offset(y: 6)
                }
                .offset(x: -42, y: 24)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 64, height: 76)
                .overlay(alignment: .top) {
                    Text("LEAVE")
                        .font(.system(size: 8, weight: .black))
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
                                    .frame(width: 31, height: 4)
                            }
                        }
                    }
                    .padding(.top, 15)
                }
                .rotationEffect(.degrees(-7))
                .offset(x: 3, y: -1)

            Circle()
                .fill(Color(hex: 0xD9E7FF))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                }
                .offset(x: 33, y: 30)

            VStack(spacing: 0) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: 0x83A8E8))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hex: 0x6A8FD5))
                    .frame(width: 14, height: 36)
            }
            .rotationEffect(.degrees(20))
            .offset(x: 68, y: 28)
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
                Menu {
                    ForEach(availableScopes) { scope in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                activeScope = scope
                                historyFilter = .review
                                advancedFilter.setSelected([], for: "staff")
                                advancedFilter.setSelected(["review"], for: "status")
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
                    HStack(spacing: 8) {
                        Text(activeScope.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: 0x061D3D))
                    .frame(width: 122, height: 48)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: 0xE5E7EB), lineWidth: 2)
                    }
                    .shadow(color: Color.black.opacity(0.02), radius: 4, y: 1)
                }
                .disabled(availableScopes.count <= 1)
            }

            HStack(spacing: 12) {
                leaveMetric("Available", value: Int(totalLeaveAvailable), dot: Color(hex: 0x22C55E))
                leaveMetric("Leave Used", value: Int(totalLeaveUsed), dot: Color(hex: 0x0B61CA))
            }
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
                leaveEmptyState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 44)
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
                        advancedFilter.setSelected([leaveStatusID(filter)], for: "status")
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
            Button { showAdvancedFilter = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 34, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter leaves")
        }
        .padding(3)
        .background(Color(hex: 0xE9EDF5), in: Capsule())
    }

    private func cancelLeaveDialog(for leave: ConvexLeave) -> some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.34))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Circle()
                    .fill(Color(hex: 0xEF4444))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "trash")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text("Are you sure?")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1D2939))
                    .padding(.top, 20)

                Text("This leave request will be cancelled and removed from your visible leave history.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(hex: 0x475467))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 12)

                HStack(spacing: 12) {
                    Button {
                        cancelingLeave = nil
                    } label: {
                        Text("No, Go Back")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x344054))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(actionInFlightId != nil)

                    Button {
                        cancelLeave(leave)
                    } label: {
                        Text(actionInFlightId == leave._id ? "Cancelling..." : "Confirm")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(hex: 0xEF4444), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(actionInFlightId != nil)
                }
                .padding(.top, 24)
            }
            .padding(24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private var availableScopes: [LeaveScope] {
        var scopes: [LeaveScope] = [.my]
        if canManageTeamLeaves { scopes.append(.team) }
        if canViewAllLeaves { scopes.append(.all) }
        return scopes
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
        scopedLeaves.filter {
            historyFilter.contains(status: $0.status ?? "pending") && matchesLeave($0, state: advancedFilter)
        }
    }

    private var scopedLeaves: [ConvexLeave] {
        switch activeScope {
        case .my:
            return leaves
        case .team:
            return pendingLeaves
        case .all:
            return allLeaves
        }
    }

    private var isApprovalScope: Bool {
        switch activeScope {
        case .my:
            return false
        case .team:
            return canManageTeamLeaves
        case .all:
            return canViewAllLeaves
        }
    }

    private var emptyTitle: String {
        isApprovalScope ? "No Leave Approvals" : "No Leave Submitted!"
    }

    private var emptyDescription: String {
        isApprovalScope ? "There are no pending leave requests in review right now." : "Ready to catch some fresh air? Click \"Apply Leave\" and take that well-deserved break!"
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
        .frame(height: 104)
        .padding(.horizontal, 16)
        .background(Color(hex: 0xF8F9FC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var leaveEmptyState: some View {
        VStack(spacing: 14) {
            leaveEmptyArtwork
                .frame(width: 142, height: 142)

            Text(emptyTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Text(emptyDescription)
                .font(.system(size: 15, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x98A2B3))
                .lineSpacing(2)
                .padding(.horizontal, 24)
        }
    }

    private var leaveEmptyArtwork: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color(hex: 0xDCE8FF) : Color.white)
                    .frame(width: index.isMultiple(of: 2) ? 7 : 5, height: index.isMultiple(of: 2) ? 7 : 5)
                    .offset(x: CGFloat([-56, -38, -16, 22, 48, 58, -50, 36, 4][index]), y: CGFloat([-42, 36, -60, -48, 28, -8, 2, -65, 54][index]))
            }

            Image(systemName: "paperplane.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0xAEC8FF))
                .rotationEffect(.degrees(22))
                .offset(x: 52, y: -34)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xCFDCFF), Color(hex: 0xAFC3FA)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 72, height: 92)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color(hex: 0xBCD0FF), lineWidth: 7)
                        .frame(width: 34, height: 22)
                        .offset(y: -12)
                }
                .overlay {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(hex: 0x9FB4EC).opacity(0.85))
                                .frame(width: 8, height: 64)
                        }
                    }
                    .offset(y: 6)
                }
                .shadow(color: Color(hex: 0x9FB4EC).opacity(0.35), radius: 16, y: 10)

            Circle()
                .fill(Color(hex: 0x8FA7E8))
                .frame(width: 12, height: 12)
                .offset(x: -22, y: 52)
            Circle()
                .fill(Color(hex: 0x8FA7E8))
                .frame(width: 12, height: 12)
                .offset(x: 22, y: 52)
        }
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
                    Button {
                        cancelingLeave = leave
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
                    Text(leaveTypeLabel(for: leave))
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
        // A half-day always counts as 0.5, matching Android's leave card.
        if leave.isHalfDayLeave { return "0.5 Day" }
        let days = Int(leave.days ?? 0)
        return "\(days) Day\(days == 1 ? "" : "s")"
    }

    /// Leave type label with the "Half-day (Session)" suffix for half-day
    /// leaves, mirroring Android's `leaveTypeDisplay` in LeavesFragment.
    private func leaveTypeLabel(for leave: ConvexLeave) -> String {
        guard leave.isHalfDayLeave else { return leave.leaveTypeLabel }
        let rawType = (leave.leaveType ?? "")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        let base = rawType.isEmpty ? "Leave" : rawType
        let rawSession = leave.halfDaySession?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rawSession.isEmpty {
            let session = rawSession.prefix(1).uppercased() + rawSession.dropFirst().lowercased()
            return "\(base) Half-day (\(session)) Leave"
        }
        return "\(base) Half-day Leave"
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

    private var leavesCacheKey: String {
        let staff = authStore.currentSession?.user.staffId?.nonBlank
            ?? authStore.currentSession?.user._id.nonBlank
            ?? "anon"
        return "leaves.my.\(staff).\(leaveFacetCacheKey)"
    }

    private var leaveFacetCacheKey: String {
        let ids = ["status", "leaveType", "staff"]
            .map { advancedFilter.selected($0).sorted().joined(separator: ",") }
            .joined(separator: "|")
        return "\(advancedFilter.fromDate?.timeIntervalSince1970 ?? 0)-\(advancedFilter.toDate?.timeIntervalSince1970 ?? 0)-\(ids)"
    }

    private var teamLeavesCacheKey: String {
        let staff = authStore.currentSession?.user.staffId?.nonBlank
            ?? authStore.currentSession?.user._id.nonBlank
            ?? "anon"
        return "leaves.team.pending.\(staff).\(leaveFacetCacheKey)"
    }

    private var allLeavesCacheKey: String {
        let staff = authStore.currentSession?.user.staffId?.nonBlank
            ?? authStore.currentSession?.user._id.nonBlank
            ?? "anon"
        return "leaves.all.pending.\(staff).\(leaveFacetCacheKey)"
    }

    private func loadData() {
        guard let token = authStore.currentSession?.token else { return }

        // Cache-first: paint the last-known "My Leaves" snapshot (list + balance)
        // INSTANTLY on a cold open so the skeleton only shows on a true first
        // load with nothing cached (Android LocalCache parity).
        if leaves.isEmpty,
           let cached = LocalCache.get(leavesCacheKey, as: LeavesCacheSnapshot.self) {
            leaves = cached.leaves
            if let cachedBalance = cached.balance { balance = cachedBalance }
        }
        if pendingLeaves.isEmpty,
           let cached = LocalCache.get(teamLeavesCacheKey, as: [ConvexLeave].self) {
            pendingLeaves = cached
        }
        if allLeaves.isEmpty,
           let cached = LocalCache.get(allLeavesCacheKey, as: [ConvexLeave].self) {
            allLeaves = cached
        }

        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let year = Calendar.current.component(.year, from: Date())
                let fromDate = advancedFilter.fromDate.map { AppModuleFormatters.ymd.string(from: $0) }
                let toDate = (advancedFilter.toDate ?? advancedFilter.fromDate).map { AppModuleFormatters.ymd.string(from: $0) }
                let leaveType = advancedFilter.selected("leaveType").first
                let staffId = advancedFilter.selected("staff").first
                let selectedStatus = advancedFilter.selected("status").first
                let apiStatus = selectedStatus == "review" ? "pending" : selectedStatus
                async let leavesReq = HRConvexAPIService.getMyLeaves(
                    token: token,
                    fromDate: fromDate,
                    toDate: toDate,
                    status: apiStatus,
                    leaveType: leaveType,
                    staffId: staffId,
                    pageSize: 200
                )
                async let balanceReq = HRConvexAPIService.getLeaveBalance(token: token, year: year)
                async let pendingReq: [ConvexLeave] = canManageTeamLeaves
                    ? HRConvexAPIService.getPendingLeaveApprovals(
                        token: token,
                        teamOnly: true,
                        scope: "direct",
                        viewerStaffId: authStore.currentSession?.user._id,
                        fromDate: fromDate,
                        toDate: toDate,
                        status: apiStatus,
                        leaveType: leaveType,
                        staffId: staffId,
                        pageSize: 200
                    )
                    : []
                async let allReq: [ConvexLeave] = canViewAllLeaves
                    ? HRConvexAPIService.getPendingLeaveApprovals(
                        token: token,
                        fromDate: fromDate,
                        toDate: toDate,
                        status: apiStatus,
                        leaveType: leaveType,
                        staffId: staffId,
                        pageSize: 200
                    )
                    : []
                leaves = try await leavesReq
                // Offline-keep: never null out a cached balance on a transient
                // balance-endpoint failure.
                if let freshBalance = try? await balanceReq { balance = freshBalance }
                if let loadedPending = try? await pendingReq {
                    pendingLeaves = loadedPending
                    LocalCache.put(teamLeavesCacheKey, loadedPending)
                }
                if let loadedAll = try? await allReq {
                    allLeaves = loadedAll
                    LocalCache.put(allLeavesCacheKey, loadedAll)
                }
                LocalCache.put(leavesCacheKey, LeavesCacheSnapshot(leaves: leaves, balance: balance))
            } catch {
                if Self.isCancellation(error) { return }
                // Offline-keep: keep cached rows on screen; only surface an error
                // when there is nothing to show.
                if leaves.isEmpty {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func resolveReportingScope() async {
        guard let token = authStore.currentSession?.token else { return }
        isReportingManager = (try? await HRConvexAPIService.hasReportingTeam(token: token)) ?? false
    }

    private func cancelLeave(_ leave: ConvexLeave) {
        guard let token = authStore.currentSession?.token else { return }
        actionInFlightId = leave._id
        Task {
            defer { actionInFlightId = nil }
            do {
                try await HRConvexAPIService.cancelLeave(token: token, id: leave._id)
                cancelingLeave = nil
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

    private var leaveFilterCategories: [AdvancedFilterCategory] {
        var categories = [
            AdvancedFilterCategory(id: "date", title: "Date", showsDateRange: true),
            AdvancedFilterCategory(
                id: "status",
                title: "Status",
                options: [
                    AdvancedFilterOption(id: "review", label: "Review"),
                    AdvancedFilterOption(id: "approved", label: "Approved"),
                    AdvancedFilterOption(id: "rejected", label: "Rejected")
                ],
                selectionMode: .single
            ),
            AdvancedFilterCategory(id: "leaveType", title: "Leave Type", options: uniqueLeaveOptions { leave in
                guard let id = leave.leaveType?.nonBlank else { return nil }
                return AdvancedFilterOption(id: id.lowercased(), label: leave.leaveTypeLabel)
            })
        ]
        if activeScope != .my {
            categories.append(AdvancedFilterCategory(id: "staff", title: "Staff", options: uniqueLeaveOptions { leave in
                guard let id = leave.staffId?.nonBlank, let name = leave.staffName?.nonBlank else { return nil }
                return AdvancedFilterOption(id: id, label: name)
            }))
        }
        return categories
    }

    private func uniqueLeaveOptions(_ transform: (ConvexLeave) -> AdvancedFilterOption?) -> [AdvancedFilterOption] {
        var seen = Set<String>()
        return scopedLeaves.compactMap(transform).filter { seen.insert($0.id).inserted }.sorted { $0.label < $1.label }
    }

    private func matchesLeave(_ leave: ConvexLeave, state: AdvancedFilterState) -> Bool {
        if let from = state.fromDate, (leave.toDate ?? leave.fromDate ?? "") < AppModuleFormatters.ymd.string(from: from) { return false }
        if let to = state.toDate, (leave.fromDate ?? "") > AppModuleFormatters.ymd.string(from: to) { return false }
        let selectedStatus = state.selected("status").first
        let statusFilter = selectedStatus.map(leaveHistoryFilter) ?? historyFilter
        if !statusFilter.contains(status: leave.status ?? "pending") { return false }
        let types = state.selected("leaveType")
        if !types.isEmpty && !types.contains(leave.leaveType?.lowercased() ?? "") { return false }
        let staff = state.selected("staff")
        if !staff.isEmpty && !staff.contains(leave.staffId ?? "") { return false }
        return true
    }

    private func leaveStatusID(_ filter: LeaveHistoryFilter) -> String {
        switch filter {
        case .review: return "review"
        case .approved: return "approved"
        case .rejected: return "rejected"
        }
    }

    private func leaveHistoryFilter(_ id: String) -> LeaveHistoryFilter {
        switch id {
        case "approved": return .approved
        case "rejected": return .rejected
        default: return .review
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as NSError).code == NSURLErrorCancelled
    }
}

/// Codable snapshot of the "My Leaves" scope (list + balance) cached for
/// instant cold-open paint and offline resilience.
private struct LeavesCacheSnapshot: Codable {
    let leaves: [ConvexLeave]
    let balance: ConvexLeaveBalance?
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
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "cancelled" || normalized == "canceled" {
            return false
        }
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
        case "rejected":
            return .rejected
        default:
            return .review
        }
    }
}
