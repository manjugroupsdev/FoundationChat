import SwiftUI

struct ConvexPermissionListView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var permissions: [ConvexPermission] = []
    @State private var pendingPermissions: [ConvexPermission] = []
    @State private var allPermissions: [ConvexPermission] = []
    @State private var usage: ConvexPermissionUsage?
    @State private var isLoading = false
    @State private var teamLoading = false
    @State private var allLoading = false
    @State private var loadTask: Task<Void, Never>?
    @State private var loadKey: String?
    @State private var loadGeneration = 0
    @State private var errorMessage: String?
    @State private var showApplySheet = false
    @State private var historyFilter: PermissionHistoryFilter = .review
    @State private var activeScope: PermissionScope = .my
    @State private var rejectingPermission: ConvexPermission?
    @State private var cancelingPermission: ConvexPermission?
    @State private var rejectReason = ""
    @State private var actionInFlightId: String?
    @State private var isReportingManager = false
    @State private var showAdvancedFilter = false
    @State private var advancedFilter: AdvancedFilterState = {
        var state = AdvancedFilterState()
        state.setSelected(["review"], for: "status")
        return state
    }()

    private var canManageTeamPermissions: Bool {
        isReportingManager || authStore.hasPermission("permissions.approve")
    }

    private var canViewAllPermissions: Bool {
        authStore.hasPermission("permissions.viewAll")
    }

    private var availableScopes: [PermissionScope] {
        var scopes: [PermissionScope] = [.my]
        if canManageTeamPermissions { scopes.append(.team) }
        if canViewAllPermissions { scopes.append(.all) }
        return scopes
    }

    private var scopedPermissions: [ConvexPermission] {
        switch activeScope {
        case .my:
            return permissions
        case .team:
            return pendingPermissions
        case .all:
            return allPermissions
        }
    }

    private var filteredPermissions: [ConvexPermission] {
        scopedPermissions.filter {
            historyFilter.contains(status: $0.status ?? "pending") && matchesPermission($0, state: advancedFilter)
        }
    }

    private var shouldShowApprovalActions: Bool {
        switch activeScope {
        case .my:
            return false
        case .team:
            return canManageTeamPermissions
        case .all:
            return canViewAllPermissions
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Blue base fills the top safe area (status-bar strip) so there is no
            // white gap above the header; the grey page background is kept OUT of
            // the top safe area so it can't repaint the status bar. Matches header.
            Color(hex: 0x0B61CA)
                .ignoresSafeArea(edges: .top)

            Color.appScreenBackground
                .ignoresSafeArea(edges: .bottom)
            permissionHeader
                .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 174)

                    VStack(spacing: 0) {
                        balanceCard
                        filterRow
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        permissionsSection
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                    }
                    .background(Color.appScreenBackground)
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

            if let cancelingPermission {
                cancelPermissionDialog(for: cancelingPermission)
                    .zIndex(20)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showApplySheet = true
            } label: {
                Text("Apply Permission")
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
            .blur(radius: cancelingPermission == nil ? 0 : 2)
            .disabled(cancelingPermission != nil)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Color.appScreenBackground.opacity(0.96)
                    if cancelingPermission != nil {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Color.black.opacity(0.34))
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
        }
        .sheet(isPresented: $showApplySheet) {
            ApplyPermissionView {
                loadData(force: true)
            }
            .appLibraryNativeSheet([.height(590), .large])
        }
        .fullScreenCover(isPresented: $showAdvancedFilter) {
            AdvancedListFilterView(
                title: "Filter Permissions",
                categories: permissionFilterCategories,
                state: advancedFilter,
                resultCount: { state in scopedPermissions.filter { matchesPermission($0, state: state) }.count },
                onApply: { state in
                    advancedFilter = state
                    if let status = state.selected("status").first {
                        historyFilter = permissionHistoryFilter(status)
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
        .alert("Reject Permission", isPresented: .init(
            get: { rejectingPermission != nil },
            set: { if !$0 { rejectingPermission = nil } }
        )) {
            TextField("Reason", text: $rejectReason)
            Button("Reject", role: .destructive) {
                if let rejectingPermission {
                    rejectPermission(rejectingPermission)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a reason for rejection")
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            loadData()
            let previouslyManaged = canManageTeamPermissions
            await resolveReportingScope()
            if canManageTeamPermissions != previouslyManaged { loadData() }
        }
        .onDisappear { loadGeneration += 1; loadTask?.cancel(); loadTask = nil }
    }

    private var permissionHeader: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x0353B8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permission Summary")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text("Submit Permission")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
                Image("PermissionHeaderArt")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 104)
                    .offset(x: 2, y: -2)
            }
            .padding(.leading, 28)
            .padding(.trailing, 14)
            .padding(.top, 58)
        }
        .frame(height: 232)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeScope.balanceTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText)
                    Text("Period 1 Jan \(Calendar.current.component(.year, from: Date())) - 30 Dec \(Calendar.current.component(.year, from: Date()))")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.appSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if availableScopes.count > 1 {
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
                                if scope == .team, pendingPermissions.count > 0 {
                                    Text("\(scope.title) (\(pendingPermissions.count))")
                                } else {
                                    Text(scope.title)
                                }
                            }
                        }
                    } label: {
                        scopeChip
                    }
                }
            }

            HStack(spacing: 12) {
                permissionMetric("Available Permission", value: availablePermissionText, dot: Color(hex: 0x22C55E))
                permissionMetric("Used Permission", value: usedPermissionText, dot: Color(hex: 0x0B61CA))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 30, bottomLeading: 0, bottomTrailing: 0, topTrailing: 30),
                style: .continuous
            )
            .fill(Color.appSurface)
        }
    }

    private var scopeChip: some View {
        HStack(spacing: 8) {
            Text(activeScope.title)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(Color(hex: 0x061D3D))
        .frame(width: 156, height: 48)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appSeparator, lineWidth: 2)
        }
        .shadow(color: Color.black.opacity(0.02), radius: 4, y: 1)
    }

    private func permissionMetric(_ title: String, value: String, dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.appPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var filterRow: some View {
        HStack(spacing: 0) {
            ForEach(PermissionHistoryFilter.allCases) { filter in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        historyFilter = filter
                        advancedFilter.setSelected([permissionStatusID(filter)], for: "status")
                    }
                } label: {
                    Text(filter.title(with: scopedPermissions))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(historyFilter == filter ? .white : Color.appSecondaryText)
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
            .accessibilityLabel("Filter permissions")
        }
        .padding(3)
        .background(Color(hex: 0xE9EEF6), in: Capsule())
    }

    private func cancelPermissionDialog(for permission: ConvexPermission) -> some View {
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

                Text("This permission request will be cancelled and removed from your visible permission history.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 12)

                HStack(spacing: 12) {
                    Button {
                        cancelingPermission = nil
                    } label: {
                        Text("No, Go Back")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.appPrimaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.appSeparator, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(actionInFlightId != nil)

                    Button {
                        cancelPermission(permission)
                    } label: {
                        Text(actionInFlightId == permission._id ? "Cancelling..." : "Confirm")
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
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private var permissionsSection: some View {
        LazyVStack(spacing: 8) {
            if scopeLoading && scopedPermissions.isEmpty {
                permissionSkeleton
                permissionSkeleton
            } else if filteredPermissions.isEmpty {
                emptyState
            } else {
                ForEach(filteredPermissions) { permission in
                    permissionCard(permission, approvalMode: shouldShowApprovalActions)
                }
            }
        }
    }

    private var permissionSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.appSeparator)
                .frame(width: 140, height: 16)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appSeparator)
                .frame(height: 110)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("PermissionEmptyState")
                .resizable()
                .scaledToFit()
                .frame(width: 182, height: 142)
                .opacity(0.78)
            Text("No Permission Submitted!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.appPrimaryText)
                .multilineTextAlignment(.center)
            Text("Ready to catch some fresh air? Click “Submit Permission” and take that well-deserved break!")
                .font(.system(size: 15))
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func permissionCard(_ permission: ConvexPermission, approvalMode: Bool) -> some View {
        let bucket = PermissionHistoryFilter.bucket(for: permission.status ?? "pending")

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                Text(dateHeading(for: permission))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.appPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if !approvalMode && activeScope == .my && bucket == .review {
                    Button(role: .destructive) {
                        cancelingPermission = permission
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xEF4444))
                            .frame(width: 34, height: 34)
                            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    Text(permission.reason?.nonBlank ?? "Permission Time")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                    Text(permission.timeRange.replacingOccurrences(of: "–", with: "-"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.appPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Spacer(minLength: 10)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total Hours")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appSecondaryText)
                    Text(hoursText(for: permission))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.appPrimaryText)
                }
                .frame(width: 88, alignment: .leading)
            }
            .padding(12)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appSeparator, lineWidth: 1)
            }

            HStack(spacing: 7) {
                statusInline(permission.status ?? "pending")
                Spacer(minLength: 8)
                Text("By")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appPrimaryText)
                Circle()
                    .fill(Color.appFieldBackground)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text(authorName(for: permission).prefix(1).uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.appTertiaryText)
                    }
                Text(authorName(for: permission))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if approvalMode && bucket == .review && permission.staffName?.nonBlank != nil {
                permissionApprovalActions(for: permission)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusInline(_ status: String) -> some View {
        let bucket = PermissionHistoryFilter.bucket(for: status)
        return HStack(spacing: 5) {
            Image(systemName: bucket.statusIcon)
                .font(.system(size: 14, weight: .semibold))
            Text(bucket.statusNote)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(bucket.statusColor)
    }

    private func permissionApprovalActions(for permission: ConvexPermission) -> some View {
        HStack(spacing: 12) {
            Button {
                rejectingPermission = permission
                rejectReason = ""
            } label: {
                Label("Reject", systemImage: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xD92D20))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.appSurface, in: Capsule())
                    .overlay {
                        Capsule().stroke(Color(hex: 0xFCA5A5), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(actionInFlightId != nil)

            Button {
                approvePermission(permission)
            } label: {
                Label(actionInFlightId == permission._id ? "Working..." : "Accept", systemImage: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x22C55E), Color(hex: 0x16A34A)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(actionInFlightId != nil)
        }
        .padding(.top, 2)
    }

    private var availablePermissionText: String {
        guard let usage else { return "--" }
        return formatHours(usage.remainingHours ?? max((usage.limitHours ?? 2) - (usage.usedHours ?? 0), 0))
    }

    private var usedPermissionText: String {
        guard let usage else { return "--" }
        return formatHours(usage.usedHours ?? 0)
    }

    private var emptyTitle: String {
        if activeScope == .team { return "No Team Permissions" }
        switch historyFilter {
        case .review: return "No Permissions Yet!"
        case .approved: return "No Approved Permissions"
        case .rejected: return "No Rejected Permissions"
        }
    }

    private var emptyDescription: String {
        if activeScope == .team { return "No pending permission requests from your team." }
        switch historyFilter {
        case .review: return "Need a short break? Tap 'Apply Permission' and we'll handle the rest!"
        case .approved: return "Your approved permission requests will appear here."
        case .rejected: return "If any permission gets rejected, you'll find it listed here."
        }
    }

    private var permissionsCacheKey: String {
        let staff = authStore.currentSession?.user.staffId?.nonBlank
            ?? authStore.currentSession?.user._id.nonBlank
            ?? "anon"
        return "permissions.my.\(staff).\(permissionFacetCacheKey)"
    }

    private var permissionFacetCacheKey: String {
        let ids = ["status", "staff"]
            .map { advancedFilter.selected($0).sorted().joined(separator: ",") }
            .joined(separator: "|")
        return "\(advancedFilter.fromDate?.timeIntervalSince1970 ?? 0)-\(advancedFilter.toDate?.timeIntervalSince1970 ?? 0)-\(ids)"
    }

    private var teamPermissionsCacheKey: String {
        let staff = authStore.currentSession?.user.staffId?.nonBlank
            ?? authStore.currentSession?.user._id.nonBlank
            ?? "anon"
        return "permissions.team.pending.\(staff).\(permissionFacetCacheKey)"
    }

    private var allPermissionsCacheKey: String {
        let staff = authStore.currentSession?.user.staffId?.nonBlank
            ?? authStore.currentSession?.user._id.nonBlank
            ?? "anon"
        return "permissions.all.pending.\(staff).\(permissionFacetCacheKey)"
    }

    private func loadData(force: Bool = false) {
        guard let token = authStore.currentSession?.token else { return }
        let key = "\(token)|\(permissionsCacheKey)|\(canManageTeamPermissions)|\(canViewAllPermissions)"
        if !force && key == loadKey && loadTask != nil && isLoading { return }
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadKey = key

        // Cache-first: paint the last-known "My Permissions" snapshot INSTANTLY
        // on a cold open so the skeleton only shows on a true first load with
        // nothing cached (Android LocalCache parity).
        if permissions.isEmpty,
           let cached = LocalCache.get(permissionsCacheKey, as: PermissionsCacheSnapshot.self) {
            permissions = cached.permissions
            if let cachedUsage = cached.usage { usage = cachedUsage }
        }
        if pendingPermissions.isEmpty,
           let cached = LocalCache.get(teamPermissionsCacheKey, as: [ConvexPermission].self) {
            pendingPermissions = cached
        }
        if allPermissions.isEmpty,
           let cached = LocalCache.get(allPermissionsCacheKey, as: [ConvexPermission].self) {
            allPermissions = cached
        }

        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let month = Calendar.current.component(.month, from: now)
        let fromDate = advancedFilter.fromDate.map { AppModuleFormatters.ymd.string(from: $0) }
        let toDate = (advancedFilter.toDate ?? advancedFilter.fromDate).map { AppModuleFormatters.ymd.string(from: $0) }
        let staffId = advancedFilter.selected("staff").first
        let status = advancedFilter.selected("status").first
        let apiStatus = status == "review" ? "pending" : status
        let mineKey = permissionsCacheKey
        let teamKey = teamPermissionsCacheKey
        let allKey = allPermissionsCacheKey
        let viewer = authStore.currentSession?.user._id
        let loadTeam = canManageTeamPermissions
        let loadAll = canViewAllPermissions
        isLoading = true
        teamLoading = loadTeam
        allLoading = loadAll
        errorMessage = nil
        loadTask = Task {
            async let mine: Void = refreshMyPermissions(token: token, generation: generation,
                staffId: staffId, fromDate: fromDate, toDate: toDate, status: apiStatus, cacheKey: mineKey)
            async let totals: Void = refreshPermissionUsage(token: token, generation: generation, year: year, month: month, cacheKey: mineKey)
            async let team: Void = refreshPermissionApprovals(token: token, generation: generation, enabled: loadTeam,
                all: false, viewer: viewer, staffId: staffId, fromDate: fromDate, toDate: toDate, status: apiStatus, cacheKey: teamKey)
            async let all: Void = refreshPermissionApprovals(token: token, generation: generation, enabled: loadAll,
                all: true, viewer: viewer, staffId: staffId, fromDate: fromDate, toDate: toDate, status: apiStatus, cacheKey: allKey)
            _ = await (mine, totals, team, all)
            if isCurrentLoad(generation, token: token) { loadTask = nil }
        }
    }

    private var scopeLoading: Bool {
        switch activeScope { case .my: return isLoading; case .team: return teamLoading; case .all: return allLoading }
    }

    private func isCurrentLoad(_ generation: Int, token: String) -> Bool {
        !Task.isCancelled && generation == loadGeneration && authStore.currentSession?.token == token
    }

    @MainActor private func refreshMyPermissions(token: String, generation: Int, staffId: String?, fromDate: String?, toDate: String?, status: String?, cacheKey: String) async {
        defer { if isCurrentLoad(generation, token: token) { isLoading = false } }
        do {
            let rows = try await HRConvexAPIService.listPermissions(token: token, staffId: staffId,
                status: status, fromDate: fromDate, toDate: toDate, pageSize: 100)
            guard isCurrentLoad(generation, token: token) else { return }
            permissions = rows
            LocalCache.put(cacheKey, PermissionsCacheSnapshot(permissions: rows, usage: usage))
        } catch {
            if isCurrentLoad(generation, token: token) && permissions.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    @MainActor private func refreshPermissionUsage(token: String, generation: Int, year: Int, month: Int, cacheKey: String) async {
        guard let fresh = try? await HRConvexAPIService.getMonthlyPermissionUsage(token: token, year: year, month: month),
              isCurrentLoad(generation, token: token) else { return }
        usage = fresh
        LocalCache.put(cacheKey, PermissionsCacheSnapshot(permissions: permissions, usage: fresh))
    }

    @MainActor private func refreshPermissionApprovals(token: String, generation: Int, enabled: Bool, all: Bool, viewer: String?, staffId: String?, fromDate: String?, toDate: String?, status: String?, cacheKey: String) async {
        guard enabled else { return }
        defer {
            if isCurrentLoad(generation, token: token) {
                if all { allLoading = false } else { teamLoading = false }
            }
        }
        guard let rows = try? await HRConvexAPIService.getPendingPermissionApprovals(token: token,
            scope: all ? nil : "direct", all: all ? true : nil, viewerStaffId: all ? nil : viewer,
            fromDate: fromDate, toDate: toDate, status: status, staffId: staffId, pageSize: 100),
              isCurrentLoad(generation, token: token) else { return }
        if all { allPermissions = rows } else { pendingPermissions = rows }
        LocalCache.put(cacheKey, rows)
    }

    @MainActor
    private func resolveReportingScope() async {
        guard let token = authStore.currentSession?.token else { return }
        isReportingManager = (try? await HRConvexAPIService.hasReportingTeam(token: token)) ?? false
    }

    private func approvePermission(_ permission: ConvexPermission) {
        guard let token = authStore.currentSession?.token else { return }
        actionInFlightId = permission._id
        Task {
            defer { actionInFlightId = nil }
            do {
                try await HRConvexAPIService.approvePermission(token: token, id: permission._id)
                loadData(force: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rejectPermission(_ permission: ConvexPermission) {
        guard let token = authStore.currentSession?.token else { return }
        let trimmedReason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            errorMessage = "Please enter a rejection reason."
            return
        }

        actionInFlightId = permission._id
        Task {
            defer {
                actionInFlightId = nil
                rejectingPermission = nil
                rejectReason = ""
            }
            do {
                try await HRConvexAPIService.rejectPermission(token: token, id: permission._id, reason: trimmedReason)
                loadData(force: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelPermission(_ permission: ConvexPermission) {
        guard let token = authStore.currentSession?.token else { return }
        actionInFlightId = permission._id
        Task {
            defer { actionInFlightId = nil }
            do {
                try await HRConvexAPIService.cancelPermission(token: token, id: permission._id)
                cancelingPermission = nil
                loadData(force: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func dateHeading(for permission: ConvexPermission) -> String {
        guard let raw = permission.date?.nonBlank else { return "Permission Date" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private func hoursText(for permission: ConvexPermission) -> String {
        if let hours = permission.durationHours {
            return formatHours(hours)
        }
        return "--"
    }

    private func formatHours(_ hours: Double) -> String {
        if abs(hours.rounded() - hours) < 0.01 {
            let whole = Int(hours.rounded())
            return "\(whole) Hr\(whole == 1 ? "" : "s")"
        }
        return String(format: "%.1f Hrs", hours)
    }

    private var permissionFilterCategories: [AdvancedFilterCategory] {
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
            )
        ]
        if activeScope != .my {
            categories.append(AdvancedFilterCategory(id: "staff", title: "Staff", options: uniquePermissionOptions { permission in
                guard let id = permission.staffId?.nonBlank, let name = permission.staffName?.nonBlank else { return nil }
                return AdvancedFilterOption(id: id, label: name)
            }))
        }
        return categories
    }

    private func uniquePermissionOptions(_ transform: (ConvexPermission) -> AdvancedFilterOption?) -> [AdvancedFilterOption] {
        var seen = Set<String>()
        return scopedPermissions.compactMap(transform).filter { seen.insert($0.id).inserted }.sorted { $0.label < $1.label }
    }

    private func matchesPermission(_ permission: ConvexPermission, state: AdvancedFilterState) -> Bool {
        if let from = state.fromDate, (permission.date ?? "") < AppModuleFormatters.ymd.string(from: from) { return false }
        if let to = state.toDate, (permission.date ?? "") > AppModuleFormatters.ymd.string(from: to) { return false }
        let selectedStatus = state.selected("status").first
        let statusFilter = selectedStatus.map(permissionHistoryFilter) ?? historyFilter
        if !statusFilter.contains(status: permission.status ?? "pending") { return false }
        let staff = state.selected("staff")
        if !staff.isEmpty && !staff.contains(permission.staffId ?? "") { return false }
        return true
    }

    private func permissionStatusID(_ filter: PermissionHistoryFilter) -> String {
        switch filter {
        case .review: return "review"
        case .approved: return "approved"
        case .rejected: return "rejected"
        }
    }

    private func permissionHistoryFilter(_ id: String) -> PermissionHistoryFilter {
        switch id {
        case "approved": return .approved
        case "rejected": return .rejected
        default: return .review
        }
    }

    private func authorName(for permission: ConvexPermission) -> String {
        permission.staffName?.nonBlank ?? "Self"
    }
}

/// Codable snapshot of the "My Permissions" scope (list + usage) cached for
/// instant cold-open paint and offline resilience.
private struct PermissionsCacheSnapshot: Codable {
    let permissions: [ConvexPermission]
    let usage: ConvexPermissionUsage?
}

private enum PermissionScope: CaseIterable, Identifiable {
    case my
    case team
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .my: return "My Permission"
        case .team: return "Team Permission"
        case .all: return "All Permission"
        }
    }

    var balanceTitle: String {
        switch self {
        case .my, .all: return "Total Permission"
        case .team: return "Team Permission"
        }
    }
}

private enum PermissionHistoryFilter: CaseIterable, Identifiable {
    case review
    case approved
    case rejected

    var id: Self { self }

    func title(with permissions: [ConvexPermission]) -> String {
        let count = permissions.filter { contains(status: $0.status ?? "pending") }.count
        switch self {
        case .review: return "Review (\(count))"
        case .approved: return "Approved (\(count))"
        case .rejected: return "Rejected (\(count))"
        }
    }

    func contains(status: String) -> Bool {
        Self.bucket(for: status) == self
    }

    static func bucket(for status: String) -> Self {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "approved":
            return .approved
        case "rejected", "cancelled", "canceled":
            return .rejected
        default:
            return .review
        }
    }

    var statusNote: String {
        switch self {
        case .review: return "In Review"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        }
    }

    var statusIcon: String {
        switch self {
        case .review: return "clock.badge.questionmark"
        case .approved: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        }
    }

    var statusColor: Color {
        switch self {
        case .review: return Color(hex: 0x0B61CA)
        case .approved: return Color(hex: 0x22C55E)
        case .rejected: return Color(hex: 0xD92D20)
        }
    }
}

private extension Array where Element == ConvexPermission {
    func uniquedById() -> [ConvexPermission] {
        var seen = Set<String>()
        return filter { seen.insert($0._id).inserted }
    }
}
