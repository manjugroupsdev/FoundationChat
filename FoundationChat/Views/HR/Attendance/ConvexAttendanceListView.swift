import MapKit
import SwiftUI

private enum AttendanceListTab: String, CaseIterable, Identifiable {
    case my
    case team
    case approval
    case allApproval
    case hrReview
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .my:
            return "My Attendance"
        case .team:
            return "Team Attendance"
        case .approval:
            return "Team Approval"
        case .allApproval:
            return "All Approval"
        case .hrReview:
            return "HR Review"
        case .all:
            return "All"
        }
    }
}

private enum AttendanceApprovalSubTab: String, CaseIterable, Identifiable {
    case attendance
    case request

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attendance: return "Attendance"
        case .request: return "Request"
        }
    }
}

struct ConvexAttendanceListView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var records: [ConvexAttendanceRecord] = []
    @State private var teamRecords: [ConvexAttendanceRecord] = []
    @State private var approvalRecords: [ConvexAttendanceRecord] = []
    @State private var allApprovalRecords: [ConvexAttendanceRecord] = []
    @State private var hrReviewRecords: [ConvexAttendanceRecord] = []
    @State private var allRecords: [ConvexAttendanceRecord] = []
    @State private var isLoading = false
    @State private var loadingTabs: Set<AttendanceListTab> = []
    @State private var loadedTabs: Set<AttendanceListTab> = []
    @State private var refreshedTabs: Set<AttendanceListTab> = []
    @State private var errorMessage: String?
    @State private var filter: AttendanceFilter = .currentMonth()
    @State private var advancedFilter: AdvancedFilterState = {
        let current = AttendanceFilter.currentMonth()
        return AdvancedFilterState(fromDate: current.fromDate, toDate: current.toDate)
    }()
    @State private var selectedTab: AttendanceListTab = .my
    @State private var isReportingOfficer = false
    @State private var approvalSubTab: AttendanceApprovalSubTab = .attendance
    @State private var showFilter = false
    @State private var searchText = ""
    @State private var selectedRecord: ConvexAttendanceRecord?
    @State private var approvalReviewRecord: ConvexAttendanceRecord?
    @State private var requestReviewRecord: ConvexAttendanceRecord?
    @State private var displayedMyAttendanceCacheKey: String?

    private var visibleTabs: [AttendanceListTab] {
        var tabs: [AttendanceListTab] = [.my]
        let canApproveTeam = authStore.hasPermission("attendance.teamApprove")
            || authStore.hasPermission("attendance.approve")
        let canViewAllApprovals = authStore.hasPermission("attendance.viewAllApprovals")
        let canReviewForHR = authStore.hasPermission("attendance.hrReview")
            || authStore.hasPermission("attendance.viewAllApprovals")

        if canApproveTeam || isReportingOfficer {
            tabs.append(contentsOf: [.team, .approval])
        }
        if canViewAllApprovals {
            tabs.append(.allApproval)
        }
        if canReviewForHR {
            tabs.append(.hrReview)
        }
        if authStore.hasPermission("attendance.viewAll") {
            tabs.append(.all)
        }
        return tabs
    }

    private var filteredRecords: [ConvexAttendanceRecord] {
        myAttendanceRows.filter { filter.matches(status: $0.approvedAttendance ?? $0.status) && matchesAttendanceStaff($0, state: advancedFilter) }
    }

    private var filteredTeamRecords: [ConvexAttendanceRecord] {
        teamRecords.filter { filter.matches(status: $0.approvedAttendance ?? $0.status) && matchesAttendanceStaff($0, state: advancedFilter) }
    }

    private var filteredApprovalRecords: [ConvexAttendanceRecord] {
        approvalRecords
            .filter { record in
                let isRequest = isAttendanceRequest(record)
                return approvalSubTab == .request
                    ? isRequest
                    : !isRequest && !isRequestLinkedAttendance(record)
            }
            .filter { filter.matches(status: $0.approvedAttendance ?? $0.status) }
            .filter { matchesAttendanceStaff($0, state: advancedFilter) }
    }

    private var filteredAllApprovalRecords: [ConvexAttendanceRecord] {
        allApprovalRecords
            .filter { !isAttendanceRequest($0) && !isRequestLinkedAttendance($0) }
            .filter { filter.matches(status: $0.approvedAttendance ?? $0.status) }
            .filter { matchesAttendanceStaff($0, state: advancedFilter) }
    }

    private var filteredHrReviewRecords: [ConvexAttendanceRecord] {
        hrReviewRecords
            .filter { record in
                let isRequest = isAttendanceRequest(record)
                return approvalSubTab == .request
                    ? isRequest
                    : !isRequest && !isRequestLinkedAttendance(record)
            }
            .filter { filter.matches(status: $0.approvedAttendance ?? $0.status) }
            .filter { matchesAttendanceStaff($0, state: advancedFilter) }
    }

    private var filteredAllRecords: [ConvexAttendanceRecord] {
        allRecords.filter { filter.matches(status: $0.approvedAttendance ?? $0.status) && matchesAttendanceStaff($0, state: advancedFilter) }
    }

    private var myAttendanceRows: [ConvexAttendanceRecord] {
        fillAbsentDays(records, fromDate: filter.apiRange.from, toDate: filter.apiRange.to)
    }

    private var activeRecords: [ConvexAttendanceRecord] {
        let records: [ConvexAttendanceRecord] = switch selectedTab {
        case .my:
            filteredRecords
        case .team:
            filteredTeamRecords
        case .approval:
            filteredApprovalRecords
        case .allApproval:
            filteredAllApprovalRecords
        case .hrReview:
            filteredHrReviewRecords
        case .all:
            filteredAllRecords
        }
        return searchFiltered(records)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var allServerQueryKey: String {
        let range = filter.apiRange
        return "\(selectedTab.rawValue)|\(range.from)|\(range.to)|\(normalizedSearchText)"
    }

    private var myAttendanceCacheKey: String? {
        guard let user = authStore.currentSession?.user else { return nil }
        let userKey = user.staffId?.nilIfBlank ?? user._id
        let range = filter.apiRange
        return "hr.attendance.my.\(userKey).\(range.from).\(range.to).\(attendanceFacetCacheKey)"
    }

    private var attendanceFacetCacheKey: String {
        let status = advancedFilter.selected("status").sorted().joined(separator: ",")
        let staff = advancedFilter.selected("staff").sorted().joined(separator: ",")
        return "\(status)|\(staff)|\(normalizedSearchText)"
    }

    private func attendanceCacheKey(for tab: AttendanceListTab) -> String? {
        guard let user = authStore.currentSession?.user else { return nil }
        let userKey = user.staffId?.nilIfBlank ?? user._id
        let range = filter.apiRange
        switch tab {
        case .my:
            return myAttendanceCacheKey
        case .team:
            return "hr.attendance.team.\(userKey).\(range.from).\(range.to).\(attendanceFacetCacheKey)"
        case .approval:
            return "hr.attendance.approval.direct.requests.\(userKey).\(attendanceFacetCacheKey)"
        case .allApproval:
            return "hr.attendance.approval.all.\(userKey).\(attendanceFacetCacheKey)"
        case .hrReview:
            return "hr.attendance.hrReview.\(userKey).allTime.\(attendanceFacetCacheKey)"
        case .all:
            return "hr.attendance.all.\(userKey).\(range.from).\(range.to).\(normalizedSearchText)"
        }
    }

    private var presentDays: Int {
        let today = Self.dateKeyFormatter.string(from: Date())
        return records.filter { record in
            if record.date == today { return false }
            let approved = record.approvedAttendance?.lowercased()
            switch approved {
            case "absent", "weekoff", "holiday":
                return false
            case "present", "half-day":
                return true
            default:
                return (record.totalMinutes ?? record.cumulativeMinutes ?? 0) > 0
            }
        }.count
    }

    private var totalMinutes: Int {
        records.reduce(0) { $0 + ($1.totalMinutes ?? $1.cumulativeMinutes ?? 0) }
    }

    private var totalHoursLabel: String {
        String(format: "%02d:%02d Hrs", totalMinutes / 60, totalMinutes % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterStatusBar
            summaryStats
            if visibleTabs.count > 1 {
                attendanceTabStrip
            }
            if selectedTab == .approval || selectedTab == .hrReview {
                approvalSubTabStrip
            }
            content
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .navigationTitle("Attendance")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search members"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbarBackground(Color.appElevatedSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Attendance")
                        .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                    Text(filter.rangeLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: 0xF5F8FF), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter attendance")
            }
        }
        .fullScreenCover(isPresented: $showFilter) {
            AdvancedListFilterView(
                title: "Filter Attendance",
                categories: attendanceFilterCategories,
                state: advancedFilter,
                resultCount: { state in attendanceSourceRecords.filter { matchesAttendance($0, state: state) }.count },
                onApply: { state in
                    let previousRange = filter.apiRange
                    advancedFilter = state
                    filter.fromDate = state.fromDate ?? filter.fromDate
                    filter.toDate = state.toDate ?? state.fromDate ?? filter.toDate
                    filter.statuses = state.selected("status")
                    let updatedRange = filter.apiRange
                    if previousRange.from == updatedRange.from && previousRange.to == updatedRange.to {
                        Task { await loadDataAsync() }
                    }
                }
            )
        }
        .sheet(item: $selectedRecord) { record in
            PunchLogSheet(record: record)
                .appLibraryNativeSheet([.medium, .large])
        }
        .sheet(item: $approvalReviewRecord) { record in
            AttendanceApprovalReviewSheet(record: record) {
                await loadDataAsync()
            }
            .appLibraryNativeSheet([.large])
        }
        .sheet(item: $requestReviewRecord) { record in
            AttendanceRequestReviewSheet(record: record) {
                await loadDataAsync()
            }
            .appLibraryNativeSheet([.medium, .large])
        }
        .task(id: filter.apiRange.from + "_" + filter.apiRange.to) {
            await loadDataAsync()
        }
        .task(id: allServerQueryKey) {
            guard selectedTab == .all else { return }
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            await loadAllAttendance()
        }
        .task {
            await authStore.refreshIAMPermissions()
            await resolveAttendanceTeamScope()
        }
        .onChange(of: selectedTab) { _, tab in
            advancedFilter.setSelected([], for: "staff")
            if tab == .approval || tab == .hrReview {
                approvalSubTab = .attendance
            }
            if tab != .all {
                loadTabIfNeeded(tab)
            }
        }
        .onChange(of: visibleTabs) { _, tabs in
            guard !tabs.contains(selectedTab) else { return }
            selectedTab = .my
        }
    }

    @ViewBuilder
    private var filterStatusBar: some View {
        if !filter.statuses.isEmpty {
            HStack(spacing: 8) {
                Text("Status: \(filter.statuses.map { $0.capitalized }.sorted().joined(separator: ", "))")
                    .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                Button("Clear") {
                    filter.statuses.removeAll()
                    advancedFilter.setSelected([], for: "status")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(Color.appSurface)
        }
    }

    private var summaryStats: some View {
        HStack(spacing: 12) {
            statCard(value: "\(presentDays)", label: "Present", icon: "calendar", tint: Color(hex: 0x16A34A))
            statCard(value: totalHoursLabel, label: "Total Hours", icon: "clock", tint: Color(hex: 0x16A34A))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.appScreenBackground)
    }

    private func statCard(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var attendanceTabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleTabs) { tab in
                    Button {
                        selectedTab = tab
                        loadTabIfNeeded(tab)
                    } label: {
                        attendanceTab(title: tab.title, count: count(for: tab), isSelected: selectedTab == tab)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 42)
        .background(Color.appFieldBackground)
    }

    private var approvalSubTabStrip: some View {
        HStack(spacing: 0) {
            ForEach(AttendanceApprovalSubTab.allCases) { tab in
                Button {
                    approvalSubTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text("\(approvalSubTabCount(for: tab))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(approvalSubTab == tab ? Color(hex: 0x0B61CA) : .white)
                            .padding(.horizontal, 5)
                            .frame(height: 15)
                            .background(approvalSubTab == tab ? Color.white : Color(hex: 0x0B61CA), in: Capsule())
                    }
                    .foregroundStyle(approvalSubTab == tab ? .white : Color(hex: 0x344054))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        approvalSubTab == tab ? Color(hex: 0x0B61CA) : Color.white,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appFieldBackground)
    }

    private func approvalSubTabCount(for tab: AttendanceApprovalSubTab) -> Int {
        let source = selectedTab == .approval ? approvalRecords : hrReviewRecords
        return source.filter { record in
            let isRequest = isAttendanceRequest(record)
            return tab == .request
                ? isRequest
                : !isRequest && !isRequestLinkedAttendance(record)
        }.count
    }

    private func isAttendanceRequest(_ record: ConvexAttendanceRecord) -> Bool {
        // HR review also contains attendance rows linked to a request. Only
        // real attendanceRequests documents carry requestStage and can be
        // sent through the request approval/rejection mutations.
        record.requestStage?.nilIfBlank != nil
    }

    private func isRequestLinkedAttendance(_ record: ConvexAttendanceRecord) -> Bool {
        guard !isAttendanceRequest(record) else { return false }
        let type = record.requestType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return type == "remarks" || type == "correction"
    }

    private func count(for tab: AttendanceListTab) -> Int {
        switch tab {
        case .my:
            return filteredRecords.count
        case .team:
            return filteredTeamRecords.count
        case .approval:
            return filteredApprovalRecords.count
        case .allApproval:
            return filteredAllApprovalRecords.count
        case .hrReview:
            return hrReviewRecords.count
        case .all:
            return filteredAllRecords.count
        }
    }

    private func attendanceTab(title: String, count: Int?, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if let count {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : .white)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(isSelected ? Color.white : Color(hex: 0x0B61CA), in: Capsule())
            }
        }
        .foregroundStyle(isSelected ? .white : Color(hex: 0x344054))
        .frame(height: 33)
        .padding(.horizontal, 12)
        .background(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0xE4EAF2), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var shouldShowLoadingSkeleton: Bool {
        guard errorMessage == nil, normalizedSearchText.isEmpty else { return false }
        if selectedTab == .my, !records.isEmpty {
            return false
        }
        return isTabLoading(selectedTab) || !loadedTabs.contains(selectedTab)
    }

    @ViewBuilder
    private var content: some View {
        if shouldShowLoadingSkeleton {
            AttendanceLoadingSkeleton()
        } else if activeRecords.isEmpty {
            ContentUnavailableView {
                Label(emptyStateTitle, systemImage: "clock")
            } description: {
                Text(filter.statuses.isEmpty ? emptyStateDescription : "No records match the selected filters.")
            } actions: {
                if !filter.statuses.isEmpty {
                    Button("Clear Filters") {
                        filter.statuses.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color(hex: 0xB42318))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(hex: 0xFEF3F2), in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(activeRecords) { record in
                        switch selectedTab {
                        case .my:
                            AttendanceHistoryCard(record: record)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedRecord = record
                            }
                        case .team, .all:
                            TeamAttendanceCard(record: record)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedRecord = record
                                }
                        case .approval:
                            if approvalSubTab == .request {
                                TeamAttendanceCard(
                                    record: record,
                                    actionStyle: .hrReview,
                                    onPrimary: {
                                        requestReviewRecord = record
                                    }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    requestReviewRecord = record
                                }
                            } else {
                                approvalCard(record)
                            }
                        case .allApproval:
                            approvalCard(record)
                        case .hrReview:
                            if approvalSubTab == .request {
                                TeamAttendanceCard(
                                    record: record,
                                    actionStyle: .hrReview,
                                    onPrimary: {
                                        requestReviewRecord = record
                                    }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    requestReviewRecord = record
                                }
                            } else {
                                TeamAttendanceCard(
                                    record: record,
                                    actionStyle: .reviewReject,
                                    onPrimary: {
                                        approvalReviewRecord = record
                                    },
                                    onSecondary: {
                                        approvalReviewRecord = record
                                    }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    approvalReviewRecord = record
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 15)
                .padding(.bottom, 24)
            }
            .refreshable { await loadDataAsync() }
        }
    }

    private func approvalCard(_ record: ConvexAttendanceRecord) -> some View {
        TeamAttendanceCard(
            record: record,
            actionStyle: .reviewReject,
            onPrimary: {
                approvalReviewRecord = record
            },
            onSecondary: {
                approvalReviewRecord = record
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            approvalReviewRecord = record
        }
    }

    private var emptyStateTitle: String {
        switch selectedTab {
        case .my:
            return "No attendance records"
        case .team:
            return "No team attendance"
        case .approval:
            return "No attendance to review"
        case .allApproval:
            return "No attendance to review"
        case .hrReview:
            return "No attendance to review"
        case .all:
            return "No team attendance"
        }
    }

    private var emptyStateDescription: String {
        switch selectedTab {
        case .my:
            return "Your attendance history for this period is empty."
        case .team:
            return "No team attendance records for this period."
        case .approval:
            return "Pending punches from your team will land here."
        case .allApproval:
            return "Company-wide pending approvals will land here."
        case .hrReview:
            return "HR review attendance requests will land here."
        case .all:
            return "No company attendance records for this period."
        }
    }

    @MainActor
    private func loadDataAsync() async {
        guard let token = authStore.currentSession?.token else { return }
        let (from, to) = filter.apiRange
        loadedTabs.removeAll()
        refreshedTabs.removeAll()
        loadingTabs.removeAll()
        teamRecords = []
        approvalRecords = []
        allApprovalRecords = []
        hrReviewRecords = []
        allRecords = []
        hydrateMyAttendanceCacheIfNeeded()
        isLoading = true
        do {
            let loadedRecords = try await HRConvexAPIService.getMyAttendance(
                token: token,
                fromDate: from,
                toDate: to,
                status: advancedFilter.selected("status").first,
                staffId: advancedFilter.selected("staff").first,
                search: normalizedSearchText.nilIfBlank,
                pageSize: 200
            )
            records = loadedRecords
            if let cacheKey = myAttendanceCacheKey {
                LocalCache.put(cacheKey, loadedRecords)
            }
            loadedTabs.insert(.my)
            refreshedTabs.insert(.my)
            errorMessage = nil
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                isLoading = false
                return
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
        if selectedTab != .all {
            loadTabIfNeeded(selectedTab)
        }
    }

    @MainActor
    private func hydrateMyAttendanceCacheIfNeeded() {
        guard let cacheKey = myAttendanceCacheKey,
              displayedMyAttendanceCacheKey != cacheKey
        else { return }

        displayedMyAttendanceCacheKey = cacheKey
        guard let cached = LocalCache.get(cacheKey, as: [ConvexAttendanceRecord].self) else {
            records = []
            return
        }

        records = cached
        loadedTabs.insert(.my)
        errorMessage = nil
    }

    @MainActor
    private func resolveAttendanceTeamScope() async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            isReportingOfficer = try await HRConvexAPIService.hasAttendanceTeamScope(token: token)
        } catch {
            isReportingOfficer = false
        }
    }

    private func isTabLoading(_ tab: AttendanceListTab) -> Bool {
        tab == .my ? isLoading : loadingTabs.contains(tab)
    }

    private func loadTabIfNeeded(_ tab: AttendanceListTab) {
        guard visibleTabs.contains(tab),
              tab != .my,
              !loadingTabs.contains(tab),
              !refreshedTabs.contains(tab),
              let token = authStore.currentSession?.token
        else { return }

        hydrateAttendanceTabCache(tab)
        let (from, to) = filter.apiRange
        loadingTabs.insert(tab)
        Task {
            do {
                let loadedRecords: [ConvexAttendanceRecord]
                switch tab {
                case .my:
                    loadedRecords = []
                case .team:
                    loadedRecords = try await HRConvexAPIService.getTeamAttendance(
                        token: token,
                        fromDate: from,
                        toDate: to,
                        status: advancedFilter.selected("status").first,
                        staffId: advancedFilter.selected("staff").first,
                        search: normalizedSearchText.nilIfBlank,
                        pageSize: 200
                    )
                case .approval:
                    loadedRecords = try await HRConvexAPIService.getPendingAttendanceApprovals(
                        token: token,
                        scope: "direct",
                        includeRequests: true,
                        fromDate: from,
                        toDate: to,
                        status: advancedFilter.selected("status").first,
                        staffId: advancedFilter.selected("staff").first,
                        search: normalizedSearchText.nilIfBlank,
                        pageSize: 200
                    )
                case .allApproval:
                    loadedRecords = try await HRConvexAPIService.getPendingAttendanceApprovals(
                        token: token,
                        all: true,
                        fromDate: from,
                        toDate: to,
                        status: advancedFilter.selected("status").first,
                        staffId: advancedFilter.selected("staff").first,
                        search: normalizedSearchText.nilIfBlank,
                        pageSize: 200
                    )
                case .hrReview:
                    loadedRecords = try await HRConvexAPIService.getHrReview(
                        token: token,
                        fromDate: Self.allTimeReviewRange.from,
                        toDate: Self.allTimeReviewRange.to,
                        status: advancedFilter.selected("status").first,
                        staffId: advancedFilter.selected("staff").first,
                        search: normalizedSearchText.nilIfBlank,
                        pageSize: 200
                    )
                case .all:
                    loadedRecords = try await HRConvexAPIService.getAllAttendance(
                        token: token,
                        fromDate: from,
                        toDate: to,
                        search: normalizedSearchText.nilIfBlank,
                        status: advancedFilter.selected("status").first,
                        staffId: advancedFilter.selected("staff").first,
                        pageSize: 200
                    )
                }

                await MainActor.run {
                    assignAttendanceRecords(loadedRecords, to: tab)
                    if let cacheKey = attendanceCacheKey(for: tab) {
                        LocalCache.put(cacheKey, loadedRecords)
                    }
                    loadedTabs.insert(tab)
                    refreshedTabs.insert(tab)
                    errorMessage = nil
                }
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    await MainActor.run {
                        _ = loadingTabs.remove(tab)
                    }
                    return
                }
                await MainActor.run {
                    if !loadedTabs.contains(tab) {
                        errorMessage = error.localizedDescription
                    }
                }
            }

            await MainActor.run {
                _ = loadingTabs.remove(tab)
            }
        }
    }

    @MainActor
    private func loadAllAttendance() async {
        guard selectedTab == .all,
              let token = authStore.currentSession?.token
        else { return }

        let range = filter.apiRange
        let query = normalizedSearchText.nilIfBlank
        hydrateAttendanceTabCache(.all)
        loadingTabs.insert(.all)
        do {
            let loadedRecords = try await HRConvexAPIService.getAllAttendance(
                token: token,
                fromDate: range.from,
                toDate: range.to,
                search: query
            )
            guard !Task.isCancelled else { return }
            allRecords = loadedRecords
            if let cacheKey = attendanceCacheKey(for: .all) {
                LocalCache.put(cacheKey, loadedRecords)
            }
            loadedTabs.insert(.all)
            refreshedTabs.insert(.all)
            errorMessage = nil
        } catch {
            guard !(error is CancellationError),
                  (error as NSError).code != NSURLErrorCancelled
            else { return }
            if !loadedTabs.contains(.all) {
                errorMessage = error.localizedDescription
            }
        }
        _ = loadingTabs.remove(.all)
    }

    @MainActor
    private func hydrateAttendanceTabCache(_ tab: AttendanceListTab) {
        guard let cacheKey = attendanceCacheKey(for: tab),
              !loadedTabs.contains(tab),
              let cached = LocalCache.get(cacheKey, as: [ConvexAttendanceRecord].self)
        else { return }
        assignAttendanceRecords(cached, to: tab)
        loadedTabs.insert(tab)
    }

    @MainActor
    private func assignAttendanceRecords(_ loadedRecords: [ConvexAttendanceRecord], to tab: AttendanceListTab) {
        switch tab {
        case .my:
            records = loadedRecords
        case .team:
            teamRecords = loadedRecords
        case .approval:
            approvalRecords = loadedRecords
        case .allApproval:
            allApprovalRecords = loadedRecords
        case .hrReview:
            hrReviewRecords = loadedRecords
        case .all:
            allRecords = loadedRecords
        }
    }

    private func searchFiltered(_ rows: [ConvexAttendanceRecord]) -> [ConvexAttendanceRecord] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return rows }
        return rows.filter { record in
            [
                record.staffName,
                record.designation,
                record.employeeId,
                record.date,
                record.source,
                record.status,
                record.approvedAttendance
            ]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    private func fillAbsentDays(_ source: [ConvexAttendanceRecord], fromDate: String, toDate: String) -> [ConvexAttendanceRecord] {
        guard let from = Self.dateKeyFormatter.date(from: fromDate),
              var to = Self.dateKeyFormatter.date(from: toDate)
        else { return source }

        let todayKey = Self.dateKeyFormatter.string(from: Date())
        let today = Self.dateKeyFormatter.date(from: todayKey) ?? Date()
        if to > today { to = today }
        guard to >= from else { return source }

        var byDate: [String: ConvexAttendanceRecord] = [:]
        for record in source {
            guard let date = record.date, byDate[date] == nil else { continue }
            byDate[date] = record
        }

        var output: [ConvexAttendanceRecord] = []
        var cursor = to
        while cursor >= from {
            let key = Self.dateKeyFormatter.string(from: cursor)
            if let existing = byDate[key] {
                output.append(existing)
            } else if cursor < today {
                output.append(.placeholder(date: key))
            }
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return output
    }

    private var attendanceSourceRecords: [ConvexAttendanceRecord] {
        switch selectedTab {
        case .my: return myAttendanceRows
        case .team: return teamRecords
        case .approval:
            return approvalRecords.filter { approvalSubTab == .request ? isAttendanceRequest($0) : !isAttendanceRequest($0) && !isRequestLinkedAttendance($0) }
        case .allApproval: return allApprovalRecords.filter { !isAttendanceRequest($0) && !isRequestLinkedAttendance($0) }
        case .hrReview:
            return hrReviewRecords.filter { approvalSubTab == .request ? isAttendanceRequest($0) : !isAttendanceRequest($0) && !isRequestLinkedAttendance($0) }
        case .all: return allRecords
        }
    }

    private var attendanceFilterCategories: [AdvancedFilterCategory] {
        var categories = [
            AdvancedFilterCategory(id: "date", title: "Date", showsDateRange: true),
            AdvancedFilterCategory(
                id: "status",
                title: "Status",
                options: attendanceStatusOptions,
                selectionMode: .multiple
            )
        ]
        if selectedTab != .my {
            categories.append(AdvancedFilterCategory(id: "staff", title: "Staff", options: attendanceStaffOptions))
        }
        return categories
    }

    private var attendanceStatusOptions: [AdvancedFilterOption] {
        let standard = ["present", "approved", "half-day", "absent", "weekoff", "holiday", "pending", "rejected"]
        let values = Set(standard + attendanceSourceRecords.compactMap { normalizedAttendanceStatus($0) })
        return values.sorted().map {
            AdvancedFilterOption(id: $0, label: $0.replacingOccurrences(of: "-", with: " ").capitalized)
        }
    }

    private var attendanceStaffOptions: [AdvancedFilterOption] {
        var seen = Set<String>()
        return attendanceSourceRecords.compactMap { record -> AdvancedFilterOption? in
            guard let id = record.staffId?.nilIfBlank, let name = record.staffName?.nilIfBlank else { return nil }
            return AdvancedFilterOption(id: id, label: name, subtitle: record.employeeId?.nilIfBlank)
        }.filter { seen.insert($0.id).inserted }.sorted { $0.label < $1.label }
    }

    private func normalizedAttendanceStatus(_ record: ConvexAttendanceRecord) -> String? {
        let raw = (record.approvedAttendance ?? record.status)?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return raw == "auto-approved" ? "approved" : raw
    }

    private func matchesAttendanceStaff(_ record: ConvexAttendanceRecord, state: AdvancedFilterState) -> Bool {
        let selected = state.selected("staff")
        return selected.isEmpty || selected.contains(record.staffId ?? "")
    }

    private func matchesAttendance(_ record: ConvexAttendanceRecord, state: AdvancedFilterState) -> Bool {
        if let from = state.fromDate, (record.date ?? "") < Self.dateKeyFormatter.string(from: from) { return false }
        if let to = state.toDate, (record.date ?? "") > Self.dateKeyFormatter.string(from: to) { return false }
        let statuses = state.selected("status")
        if !statuses.isEmpty && !statuses.contains(normalizedAttendanceStatus(record) ?? "") { return false }
        return matchesAttendanceStaff(record, state: state)
    }

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let allTimeReviewRange = (from: "2000-01-01", to: "2100-12-31")
}

private struct AttendanceHistoryCard: View {
    let record: ConvexAttendanceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))

                Text(displayDate)
                    .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

                Spacer()

                if let badge = statusBadge {
                    HStack(spacing: 4) {
                        if record.hasAbsentPenalty {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text(badge.title)
                    }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(badge.color.opacity(0.12), in: Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                }

                // Attendance remark + time-correction feature removed: no pencil
                // edit icon and no "remark submitted" badge on attendance rows.
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Hours")
                        .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                    Text(totalHoursHMS)
                        .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Clock in & Out")
                        .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                    Text(clockRange)
                        .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))

            if let penaltyReason = record.resolvedPenaltyReason {
                AttendancePenaltyNotice(reason: penaltyReason)
            }

            if let lateFine = lateFineBanner {
                fineBanner(icon: "clock.fill", title: "Late by \(lateFine.minutes)mins", amount: lateFine.amount, tint: Color(hex: 0xD92D20), background: Color(hex: 0xFEF3F2))
            }

            ForEach(record.otherFines?.filter { ($0.amount ?? 0) > 0 } ?? []) { fine in
                fineBanner(icon: "exclamationmark.circle.fill", title: fine.typeName?.nilIfBlank ?? "Other Fine", amount: fine.amount ?? 0, tint: Color(hex: 0x0B61CA), background: Color(hex: 0xEFF8FF))
            }

            if let footer = decisionFooter {
                HStack(spacing: 5) {
                    Image(systemName: footer.isApproved ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(footer.color)
                    Text(footer.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(footer.color)
                        .lineLimit(1)
                    Spacer()
                    Text("By")
                        .font(.system(size: 12))
                .foregroundStyle(.primary)
                    Text(approverInitial)
                        .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .background(Color(hex: 0xF2F4F7), in: Circle())
                    Text(record.approvedByName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "HR")
                        .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func fineBanner(icon: String, title: String, amount: Double, tint: Color, background: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("Fine : \(AppModuleFormatters.rupees(amount))")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var displayDate: String {
        guard let raw = record.date, let date = Self.ymd.date(from: raw) else {
            return record.date ?? ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private var totalHoursHMS: String {
        let mins = record.totalMinutes ?? record.cumulativeMinutes ?? 0
        return String(format: "%02d:%02d:00 hrs", mins / 60, mins % 60)
    }

    private var clockRange: String {
        let firstIn = record.firstPunchIn ?? record.sessions?.first?.punchInTime
        let inLabel = firstIn.flatMap(Self.formatTime) ?? "--"
        let resolvedOut = resolvedPunchOut
        let outLabel: String
        if let resolvedOut, let formatted = Self.formatTime(resolvedOut) {
            outLabel = formatted
        } else if hasOpenSession {
            outLabel = "---"
        } else if firstIn != nil {
            outLabel = "Not Punched Out"
        } else {
            outLabel = "--"
        }
        return "\(inLabel) · \(outLabel)"
    }

    private var resolvedPunchOut: String? {
        let firstIn = record.firstPunchIn ?? record.sessions?.first?.punchInTime
        guard !hasOpenSession else { return nil }
        let candidate = record.lastPunchOut ?? record.sessions?.last?.punchOutTime
        guard let candidate, candidate != firstIn else { return nil }
        return candidate
    }

    private var statusBadge: (title: String, color: Color)? {
        if record.hasAbsentPenalty {
            return ("Absent · Penalty", Color(hex: 0xB42318))
        }
        guard !Self.isToday(record.date) else { return nil }
        let raw = (record.approvedAttendance ?? record.status)?.lowercased()
        switch raw {
        case "present", "approved", "auto-approved":
            return ("Present", Color(hex: 0x169B2F))
        case "half-day":
            return ("Half Day", Color(hex: 0xB54708))
        case "absent", "rejected":
            return ("Absent", Color(hex: 0xB42318))
        case "weekoff":
            return ("Weekoff", Color(hex: 0x475467))
        case "holiday":
            return ("Holiday", Color(hex: 0x0B61CA))
        default:
            let mins = record.totalMinutes ?? record.cumulativeMinutes ?? 0
            return mins > 0 ? ("Pending", Color(hex: 0xB54708)) : nil
        }
    }

    private var lateFineBanner: (minutes: Int, amount: Double)? {
        let minutes = record.lateMinutes ?? 0
        let amount = record.lateFineDeduction ?? record.fineAmount ?? 0
        guard minutes > 0, amount > 0 else { return nil }
        return (minutes, amount)
    }

    private var hasOpenSession: Bool {
        if record.hasOpenSession == true { return true }
        return record.sessions?.contains { session in
            session.punchInTime != nil && session.punchOutTime == nil
        } == true
    }

    private var decisionFooter: (text: String, color: Color, isApproved: Bool)? {
        let status = record.status?.lowercased() ?? ""
        guard status == "approved" || status == "rejected" else { return nil }
        let isApproved = status == "approved"
        let verb = isApproved ? "Approved" : "Rejected"
        let dateText = record.approvedOn.flatMap(Self.formatDecisionDate)
        let text = dateText.map { "\(verb) at \($0)" } ?? verb
        return (text, isApproved ? Color(hex: 0x169B2F) : Color(hex: 0xB42318), isApproved)
    }

    private var approverInitial: String {
        let name = record.approvedByName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "HR"
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    private static let ymd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func formatTime(_ raw: String) -> String? {
        if let date = parseISO(raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "hh:mm a"
            return formatter.string(from: date)
        }
        return raw.isEmpty ? nil : raw
    }

    private static func formatDecisionDate(_ raw: String) -> String? {
        let date = parseISO(raw) ?? ymd.date(from: raw)
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private static func parseISO(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func isToday(_ raw: String?) -> Bool {
        guard let raw, let date = ymd.date(from: raw) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}

private struct AttendancePenaltyNotice: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0xB42318))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.72), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Absent attendance penalty")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xB42318))
                Text("Reason: \(reason)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x7A271A))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0xFEF3F2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: 0xFECDCA), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct AttendanceLateFineNotice: View {
    let minutes: Int
    let amount: Double

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0xB42318))

            Text(minutes > 0 ? "Late by \(minutes) min" : "Late attendance fine")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x7A271A))

            Spacer(minLength: 8)

            Text(AppModuleFormatters.rupees(amount))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0xB42318))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0xFEF3F2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: 0xFECDCA), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Late fine \(AppModuleFormatters.rupees(amount))")
    }
}

private struct AttendanceLoadingSkeleton: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { index in
                    AttendanceSkeletonCard(showAvatar: index > 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 15)
            .padding(.bottom, 24)
        }
        .allowsHitTesting(false)
    }
}

private struct AttendanceSkeletonCard: View {
    let showAvatar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                if showAvatar {
                    Circle()
                        .fill(Color(hex: 0xEFF4FB))
                        .frame(width: 40, height: 40)
                }

                VStack(alignment: .leading, spacing: 7) {
                    skeletonBlock(width: showAvatar ? 140 : 150, height: 15)
                    skeletonBlock(width: showAvatar ? 210 : 110, height: 10)
                }

                Spacer()

                skeletonBlock(width: 74, height: 22, radius: 11)
            }

            HStack(spacing: 6) {
                skeletonBlock(width: 14, height: 14, radius: 4)
                skeletonBlock(width: 120, height: 14)
                Spacer()
            }

            HStack(alignment: .top, spacing: 14) {
                metricSkeleton
                metricSkeleton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .redacted(reason: .placeholder)
    }

    private var metricSkeleton: some View {
        VStack(alignment: .leading, spacing: 7) {
            skeletonBlock(width: 84, height: 11)
            skeletonBlock(width: 112, height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skeletonBlock(width: CGFloat, height: CGFloat, radius: CGFloat = 5) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(hex: 0xE9EEF5))
            .frame(width: width, height: height)
    }
}

private enum AttendanceCardActionStyle {
    case none
    case reviewReject
    case hrReview
}

private struct TeamAttendanceCard: View {
    let record: ConvexAttendanceRecord
    var actionStyle: AttendanceCardActionStyle = .none
    var onPrimary: (() -> Void)? = nil
    var onSecondary: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                staffAvatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(staffName)
                        .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(staffMeta)
                        .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let badge = statusBadge {
                    HStack(spacing: 4) {
                        if record.hasAbsentPenalty {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text(badge.title)
                    }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(badge.color.opacity(0.12), in: Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                Text(displayDate)
                    .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                Spacer()
            }

            HStack(alignment: .top, spacing: 14) {
                metric(title: "Total Hours", value: totalHoursHMS)
                metric(title: "Clock in & Out", value: clockRange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))

            if let lateFine = lateFineBanner {
                AttendanceLateFineNotice(minutes: lateFine.minutes, amount: lateFine.amount)
            }

            if let penaltyReason = record.resolvedPenaltyReason {
                AttendancePenaltyNotice(reason: penaltyReason)
            }

            if actionStyle != .none {
                HStack(spacing: 10) {
                    Button {
                        onPrimary?()
                    } label: {
                        Text(primaryActionTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(primaryActionColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if actionStyle == .reviewReject {
                        Button {
                            onSecondary?()
                        } label: {
                            Text("Reject")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xB42318))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(Color(hex: 0xFEF3F2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var staffAvatar: some View {
        Text(staffInitial)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color(hex: 0x0B61CA))
            .frame(width: 40, height: 40)
            .background(Color(hex: 0xEFF8FF), in: Circle())
    }

    private var primaryActionTitle: String {
        switch actionStyle {
        case .none, .reviewReject:
            return "Review"
        case .hrReview:
            return "HR Review"
        }
    }

    private var primaryActionColor: Color {
        switch actionStyle {
        case .none, .reviewReject:
            return Color(hex: 0x0B61CA)
        case .hrReview:
            return Color(hex: 0x14B800)
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var staffName: String {
        record.staffName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Staff"
    }

    private var staffInitial: String {
        staffName.first.map { String($0).uppercased() } ?? "S"
    }

    private var staffMeta: String {
        [record.designation?.nilIfBlank, record.employeeId?.nilIfBlank, record.source?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " • ")
    }

    private var displayDate: String {
        guard let raw = record.date, let date = Self.ymd.date(from: raw) else {
            return record.date ?? "—"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private var totalHoursHMS: String {
        let mins = record.totalMinutes ?? record.cumulativeMinutes ?? 0
        return mins > 0 ? String(format: "%02d:%02d:00 hrs", mins / 60, mins % 60) : "—"
    }

    private var clockRange: String {
        let firstIn = record.firstPunchIn ?? record.sessions?.first?.punchInTime
        let inLabel = firstIn.flatMap(Self.formatTime) ?? "--"
        let outLabel = record.resolvedPunchOut.flatMap(Self.formatTime) ?? (record.hasOpenSession == true ? "---" : "--")
        return "\(inLabel) — \(outLabel)"
    }

    private var lateFineBanner: (minutes: Int, amount: Double)? {
        let amount = record.lateFineDeduction ?? record.fineAmount ?? 0
        guard amount > 0 else { return nil }
        return (record.lateMinutes ?? 0, amount)
    }

    private var statusBadge: (title: String, color: Color)? {
        if record.hasAbsentPenalty {
            return ("Absent · Penalty", Color(hex: 0xB42318))
        }
        let raw = (record.approvedAttendance ?? record.status)?.lowercased()
        switch raw {
        case "present", "approved", "auto-approved":
            return ("Present", Color(hex: 0x169B2F))
        case "half-day":
            return ("Half Day", Color(hex: 0xB54708))
        case "absent", "rejected":
            return ("Absent", Color(hex: 0xB42318))
        case "weekoff":
            return ("Weekoff", Color(hex: 0x475467))
        case "holiday":
            return ("Holiday", Color(hex: 0x0B61CA))
        default:
            return nil
        }
    }

    private static let ymd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func formatTime(_ raw: String) -> String? {
        if let date = parseISO(raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "hh:mm a"
            return formatter.string(from: date)
        }
        return raw.isEmpty ? nil : raw
    }

    private static func parseISO(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

private struct AttendanceApprovalReviewSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let record: ConvexAttendanceRecord
    let onCompleted: () async -> Void

    @State private var selectedTab = 0
    @State private var isSubmitting = false
    @State private var showRejectReason = false
    @State private var rejectionReason = ""
    @State private var showHoldReason = false
    @State private var holdReason = ""
    @State private var errorMessage: String?
    @State private var routeData: GeoTrackSessionRouteData?
    @State private var isRouteLoading = false
    @State private var isReplayExpanded = false
    @State private var isReplayPlaying = false
    @State private var replayIndex = 0
    @State private var replaySpeed = 1.0
    @State private var replayTask: Task<Void, Never>?
    @State private var showPunchCorrection = false

    private var canCorrectPunchTimes: Bool {
        guard authStore.hasPermission("attendance.correctPunchTimes") else { return false }
        let user = authStore.currentSession?.user
        let currentIds = [user?.staffId, user?._id].compactMap { $0 }
        guard let targetId = record.staffId?.nilIfBlank else { return false }
        return !currentIds.contains(targetId)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            reviewTabs(proxy: proxy)
                            punchSummary
                                .id("summary")
                            travelSummary
                            routePreview
                                .id("route")
                            punchTimeline
                                .id("timeline")

                            if showRejectReason {
                                rejectionEditor
                            }

                            if showHoldReason {
                                holdEditor
                            }

                            if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(hex: 0xB42318))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                        .onChange(of: selectedTab) { _, tab in
                            let target = tab == 0 ? "summary" : (tab == 1 ? "route" : "timeline")
                            withAnimation(.snappy(duration: 0.35)) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        }
                    }
                }

                decisionButtons
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background {
                        Color.white.ignoresSafeArea(.container, edges: .bottom)
                    }
            }
            .background(Color.appSurface)
            .navigationTitle("Attendance Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                if canCorrectPunchTimes {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Correct", systemImage: "clock.badge.checkmark") {
                            showPunchCorrection = true
                        }
                        .disabled(isSubmitting)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .task(id: "\(record.staffId ?? "")-\(record.date ?? "")") {
            await loadRouteData()
        }
        .onDisappear {
            replayTask?.cancel()
        }
        .sheet(isPresented: $showPunchCorrection) {
            AttendancePunchCorrectionSheet(record: record) {
                await onCompleted()
                dismiss()
            }
            .environment(authStore)
            .appLibraryNativeSheet([.medium, .large])
        }
    }

    private var header: some View {
        HStack {
            Text(AttendanceSheetFormat.displayDate(record.date, style: .reviewSubtitle))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: 0x12B76A))
                .frame(width: 7, height: 7)
            Text("Present")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color(hex: 0x169B2F))
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(Color(hex: 0xECFDF3), in: Capsule())
    }

    private func reviewTabs(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(["Summary", "Route", "Timeline"].enumerated()), id: \.offset) { index, title in
                Button {
                    selectedTab = index
                    let target = index == 0 ? "summary" : (index == 1 ? "route" : "timeline")
                    withAnimation(.snappy(duration: 0.35)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                } label: {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedTab == index ? Color(hex: 0x0B61CA) : Color(hex: 0x667085))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(selectedTab == index ? Color(hex: 0xEAF2FF) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(hex: 0xF2F4F7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var punchSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            sheetSectionTitle("Punch Summary", icon: "briefcase")
            twoByTwoGrid([
                ("clock", "Check In", AttendanceSheetFormat.time(record.firstPunchIn ?? record.sessions?.first?.punchInTime) ?? "--", Color(hex: 0x16A34A)),
                ("clock", "Check Out", AttendanceSheetFormat.time(record.resolvedPunchOut) ?? "--", Color(hex: 0xF04438)),
                ("timer", "Duration", AttendanceSheetFormat.hours(record.totalMinutes ?? record.cumulativeMinutes), Color(hex: 0x0B61CA)),
                ("iphone", "Source", AttendanceSheetFormat.source(record.source), Color(hex: 0x0B61CA))
            ])
        }
    }

    private var travelSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            sheetSectionTitle("Travel Summary", icon: "point.topleft.down.curvedto.point.bottomright.up")
            twoByTwoGrid([
                ("mappin.circle", "Distance", routeDistanceLabel, Color(hex: 0x101828)),
                ("car", "Trips", "\(routeData?.trips.count ?? 0)", Color(hex: 0x101828)),
                ("antenna.radiowaves.left.and.right", "GPS Points", "\(routeData?.timeline.count ?? 0)", Color(hex: 0x101828)),
                ("clock", "Active Time", AttendanceSheetFormat.compactDuration(record.totalMinutes ?? record.cumulativeMinutes), Color(hex: 0x101828))
            ])
        }
    }

    private var routePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            sheetSectionTitle("Live Route (Preview)", icon: "point.3.connected.trianglepath.dotted")
            VStack(spacing: 0) {
                if let routeData, !routeCoordinates(for: routeData).isEmpty {
                    AttendanceRouteMapView(routeData: routeData, replayIndex: replayIndex)
                        .frame(height: 180)
                } else {
                    RoutePreviewCard(isLoading: isRouteLoading)
                        .frame(height: 150)
                }
                HStack(spacing: 8) {
                    Button {
                        toggleReplay()
                    } label: {
                        Image(systemName: isReplayPlaying ? "pause.circle.fill" : "play.circle")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(routeData == nil)
                    Text(routeData == nil ? "No trips recorded" : "Replay Journey")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if routeData != nil {
                        Text("Live")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x16A34A))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Color(hex: 0xECFDF3), in: Capsule())
                    }
                }
                .foregroundStyle(Color(hex: 0x0B61CA))
                .padding(14)
            .background(Color.appSurface)

                if routeData != nil && isReplayExpanded {
                    VStack(spacing: 14) {
                        Slider(
                            value: Binding(
                                get: { Double(replayIndex) },
                                set: { replayIndex = Int($0.rounded()) }
                            ),
                            in: 0...Double(max(routePointCount - 1, 0)),
                            step: 1
                        )

                        HStack {
                            Button {
                                stepReplay(-10)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("10s")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                toggleReplay()
                            } label: {
                                Image(systemName: isReplayPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 34, weight: .semibold))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                stepReplay(10)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("10s")
                                        .font(.system(size: 11, weight: .medium))
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(Color(hex: 0x0B61CA))

                        HStack(spacing: 8) {
                            speedButton("0.5x", speed: 0.5)
                            speedButton("1x", speed: 1.0)
                            speedButton("2x", speed: 2.0)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            .background(Color.appSurface)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }

    private func speedButton(_ title: String, speed: Double) -> some View {
        Button {
            replaySpeed = speed
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(replaySpeed == speed ? Color(hex: 0x0B61CA) : Color(hex: 0x667085))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(replaySpeed == speed ? Color(hex: 0xEAF2FF) : Color(hex: 0xF2F4F7), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var punchTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            sheetSectionTitle("Punch Timeline (Today)", icon: "calendar.badge.clock")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(timelineRows.enumerated()), id: \.offset) { index, row in
                    timelineRow(
                        time: row.time,
                        title: row.title,
                        subtitle: row.trailing,
                        color: row.color,
                        showLine: index < timelineRows.count - 1
                    )
                }
            }
            .padding(14)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }

    private var rejectionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rejection Reason")
                .font(.system(size: 14, weight: .semibold))
            TextEditor(text: $rejectionReason)
                .font(.system(size: 14))
                .frame(height: 88)
                .padding(8)
                .scrollContentBackground(.hidden)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }

    private var holdEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reason for Holding")
                .font(.system(size: 14, weight: .semibold))
            TextEditor(text: $holdReason)
                .font(.system(size: 14))
                .frame(height: 88)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }

    private var decisionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                decisionButton("Present", status: "present", style: .greenGradient)
                decisionButton("Half-day", status: "half-day", style: .plain)
            }
            HStack(spacing: 8) {
                decisionButton("Absent", status: "absent", style: .plain)
                holdDecisionButton
            }
            rejectDecisionButton
        }
        .padding(8)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
    }

    private func decisionButton(_ title: String, status: String, icon: String? = nil, style: AttendanceDecisionButtonStyle) -> some View {
        Button {
            approve(status)
        } label: {
            decisionButtonLabel(title, icon: icon, style: style)
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.68 : 1)
    }

    private var rejectDecisionButton: some View {
        Button {
            if showRejectReason {
                reject()
            } else {
                showRejectReason = true
                showHoldReason = false
            }
        } label: {
            decisionButtonLabel("Reject", icon: "xmark.circle", style: .outlined(Color(hex: 0xF04438)))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.68 : 1)
    }

    private var holdDecisionButton: some View {
        Button {
            if showHoldReason {
                hold()
            } else {
                showHoldReason = true
                showRejectReason = false
            }
        } label: {
            decisionButtonLabel("Hold", icon: "pause.circle", style: .outlined(Color(hex: 0xB86B14)))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.68 : 1)
    }

    private func decisionButtonLabel(_ title: String, icon: String?, style: AttendanceDecisionButtonStyle) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(style.foreground)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(style.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.border, lineWidth: 1))
    }

    private func sheetSectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    private func twoByTwoGrid(_ items: [(String, String, String, Color)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Image(systemName: item.0)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: 0xEFF8FF), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.1)
                            .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                        Text(item.2)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(item.3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(minHeight: 72)
            .background(Color.appSurface)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(hex: 0xE4E7EC), lineWidth: 0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
    }

    private func timelineRow(time: String, title: String, subtitle: String, color: Color, showLine: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                if showLine {
                    Rectangle()
                        .fill(Color(hex: 0xD0D5DD))
                        .frame(width: 1, height: 42)
                }
            }
            Text(time)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 78, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var routeDistanceLabel: String {
        guard let routeData else { return "—" }
        let meters = routeData.distanceMeters ?? routeData.trips.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
        return AttendanceSheetFormat.distance(meters)
    }

    private var routePointCount: Int {
        guard let routeData else { return 0 }
        return max(routeCoordinates(for: routeData).count, 1)
    }

    private var timelineRows: [AttendanceReviewTimelineRow] {
        var rows: [AttendanceReviewTimelineRow] = []
        if let punchIn = record.firstPunchIn ?? record.sessions?.first?.punchInTime {
            rows.append(.init(timestamp: AttendanceSheetFormat.timestampMillis(from: punchIn), time: AttendanceSheetFormat.time(punchIn) ?? "--", title: "Check In", trailing: "", color: Color(hex: 0x12B76A)))
        }
        if let routeData {
            if let firstPoint = routeData.timeline.first {
                rows.append(.init(timestamp: firstPoint.recordedAt, time: AttendanceSheetFormat.time(firstPoint.recordedAt), title: "Tracking Started", trailing: "", color: Color(hex: 0x12B76A)))
            }
            rows.append(contentsOf: buildMovementRows(from: routeData.timeline))
            rows.append(contentsOf: routeData.stops.map { stop in
                AttendanceReviewTimelineRow(
                    timestamp: stop.arrivedAt,
                    time: AttendanceSheetFormat.time(stop.arrivedAt),
                    title: "Stopped",
                    trailing: "\(stop.durationMinutes ?? 0) min",
                    color: Color(hex: 0x667085)
                )
            })
        }
        if let punchOut = record.resolvedPunchOut {
            rows.append(.init(timestamp: AttendanceSheetFormat.timestampMillis(from: punchOut), time: AttendanceSheetFormat.time(punchOut) ?? "--", title: "Check Out", trailing: "", color: Color(hex: 0xF04438)))
        }
        if rows.isEmpty {
            return [.init(timestamp: nil, time: "--", title: "No timeline data", trailing: "", color: Color(hex: 0x98A2B3))]
        }
        return rows.sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
    }

    private func buildMovementRows(from points: [GeoTrackTimelinePoint]) -> [AttendanceReviewTimelineRow] {
        guard points.count > 1 else { return [] }
        var rows: [AttendanceReviewTimelineRow] = []
        var currentMode = AttendanceSheetFormat.normalizedMode(points[0].movementMode)
        var segmentStart = 0
        var segmentDistance = 0.0

        for index in 1..<points.count {
            let previous = points[index - 1]
            let point = points[index]
            segmentDistance += AttendanceSheetFormat.distanceMeters(
                fromLat: previous.lat,
                fromLng: previous.lng,
                toLat: point.lat,
                toLng: point.lng
            )
            let mode = AttendanceSheetFormat.normalizedMode(point.movementMode)
            if mode != currentMode {
                rows.append(movementRow(mode: currentMode, start: points[segmentStart], end: previous, distance: segmentDistance))
                currentMode = mode
                segmentStart = index
                segmentDistance = 0
            }
        }
        rows.append(movementRow(mode: currentMode, start: points[segmentStart], end: points[points.count - 1], distance: segmentDistance))
        return rows.filter { $0.title != "Stationary" || !$0.trailing.isEmpty }
    }

    private func movementRow(mode: String, start: GeoTrackTimelinePoint, end: GeoTrackTimelinePoint, distance: Double) -> AttendanceReviewTimelineRow {
        let seconds = max(0, Int((end.recordedAt - start.recordedAt) / 1000))
        return AttendanceReviewTimelineRow(
            timestamp: start.recordedAt,
            time: AttendanceSheetFormat.time(start.recordedAt),
            title: AttendanceSheetFormat.modeLabel(mode),
            trailing: "\(AttendanceSheetFormat.distance(distance)) · \(AttendanceSheetFormat.duration(seconds))",
            color: AttendanceSheetFormat.modeColor(mode)
        )
    }

    private func routeCoordinates(for data: GeoTrackSessionRouteData) -> [CLLocationCoordinate2D] {
        AttendanceSheetFormat.routeCoordinates(for: data)
    }

    private func toggleReplay() {
        guard routePointCount > 1 else { return }
        isReplayExpanded = true
        if isReplayPlaying {
            isReplayPlaying = false
            replayTask?.cancel()
        } else {
            startReplay()
        }
    }

    private func startReplay() {
        replayTask?.cancel()
        if replayIndex >= routePointCount - 1 {
            replayIndex = 0
        }
        isReplayPlaying = true
        replayTask = Task { @MainActor in
            while !Task.isCancelled && isReplayPlaying {
                try? await Task.sleep(nanoseconds: UInt64(650_000_000 / replaySpeed))
                if replayIndex >= routePointCount - 1 {
                    isReplayPlaying = false
                    replayTask?.cancel()
                    break
                }
                replayIndex += 1
            }
        }
    }

    private func stepReplay(_ delta: Int) {
        guard routePointCount > 1 else { return }
        isReplayExpanded = true
        replayIndex = min(max(replayIndex + delta, 0), routePointCount - 1)
    }

    private func loadRouteData() async {
        guard let token = authStore.currentSession?.token,
              let staffId = record.staffId?.nilIfBlank,
              let date = record.date?.nilIfBlank,
              let range = AttendanceSheetFormat.dayRangeMillis(for: date)
        else { return }

        isRouteLoading = true
        GeoTrackAPIService.shared.tokenProvider = { token }
        do {
            let data = try await GeoTrackAPIService.shared.sessionRoute(
                staffId: staffId,
                dayStart: range.start,
                dayEnd: range.end,
                minStopMinutes: 30
            )
            routeData = data
            replayIndex = 0
            isReplayPlaying = false
            replayTask?.cancel()
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
        isRouteLoading = false
    }

    private func approve(_ status: String) {
        guard let token = authStore.currentSession?.token else { return }
        isSubmitting = true
        Task {
            do {
                try await HRConvexAPIService.approveAttendance(token: token, id: record.id, approvedAttendance: status)
                await onCompleted()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }

    private func reject() {
        guard let token = authStore.currentSession?.token else { return }
        let reason = rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            errorMessage = "Enter rejection reason."
            return
        }
        isSubmitting = true
        Task {
            do {
                try await HRConvexAPIService.rejectAttendance(token: token, id: record.id, reason: reason)
                await onCompleted()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }

    private func hold() {
        guard let token = authStore.currentSession?.token else { return }
        let reason = holdReason.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        Task {
            do {
                try await HRConvexAPIService.holdAttendance(
                    token: token,
                    id: record.id,
                    reason: reason.isEmpty ? "On hold" : reason
                )
                await onCompleted()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

private struct AttendancePunchCorrectionSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let record: ConvexAttendanceRecord
    let onCorrected: () async -> Void

    @State private var correctPunchIn = true
    @State private var correctPunchOut = true
    @State private var punchIn = Date()
    @State private var punchOut = Date()
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSeedValues = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Attendance") {
                    LabeledContent("Staff", value: record.staffName?.nilIfBlank ?? "Staff")
                    LabeledContent("Date", value: record.date?.nilIfBlank ?? "-")
                }

                Section("Correct Times") {
                    Toggle("Correct punch in", isOn: $correctPunchIn)
                    if correctPunchIn {
                        DatePicker("Punch In", selection: $punchIn, displayedComponents: .hourAndMinute)
                    }

                    Toggle("Correct punch out", isOn: $correctPunchOut)
                    if correctPunchOut {
                        DatePicker("Punch Out", selection: $punchOut, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Reason") {
                    TextField("Reason (optional)", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Correct Punch Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving..." : "Save") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || (!correctPunchIn && !correctPunchOut))
                }
            }
            .onAppear { seedValuesIfNeeded() }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func seedValuesIfNeeded() {
        guard !didSeedValues else { return }
        didSeedValues = true
        if let value = parseTimestamp(record.firstPunchIn ?? record.sessions?.first?.punchInTime) {
            punchIn = value
        }
        if let value = parseTimestamp(record.resolvedPunchOut) {
            punchOut = value
        } else {
            correctPunchOut = false
        }
    }

    @MainActor
    private func submit() async {
        guard let token = authStore.currentSession?.token else { return }
        guard correctPunchIn || correctPunchOut else {
            errorMessage = "Choose at least one punch time to correct."
            return
        }
        if correctPunchIn, correctPunchOut, punchOut <= punchIn {
            errorMessage = "Punch out must be later than punch in."
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            try await HRConvexAPIService.correctAttendancePunchTimes(
                token: token,
                id: record.id,
                correctedPunchIn: correctPunchIn ? timestamp(onRecordDate: punchIn) : nil,
                correctedPunchOut: correctPunchOut ? timestamp(onRecordDate: punchOut) : nil,
                reason: trimmedReason.isEmpty ? nil : trimmedReason
            )
            await onCorrected()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func timestamp(onRecordDate time: Date) -> String {
        let calendar = Calendar.current
        let day = record.date.flatMap { Self.dayFormatter.date(from: $0) } ?? time
        let components = calendar.dateComponents([.hour, .minute, .second], from: time)
        let combined = calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: day
        ) ?? time
        return Self.isoFormatter.string(from: combined)
    }

    private func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw = raw?.nilIfBlank else { return nil }
        return Self.fractionalIsoFormatter.date(from: raw)
            ?? Self.isoFormatter.date(from: raw)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let fractionalIsoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct AttendanceRequestReviewSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let record: ConvexAttendanceRecord
    let onCompleted: () async -> Void

    @State private var showRejectReason = false
    @State private var showApprovalOptions = false
    @State private var rejectionReason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    staffHeader

                    LabeledContent("Request type", value: requestTypeLabel)
                    LabeledContent("Submitted", value: submittedValue)
                }

                Section("Recorded (Actual)") {
                    attendanceTimes(
                        leftTitle: "Punch In",
                        leftValue: AttendanceSheetFormat.time(actualPunchIn) ?? "--",
                        rightTitle: "Punch Out",
                        rightValue: AttendanceSheetFormat.time(actualPunchOut) ?? "--"
                    )
                }

                requestDetails
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .alert("Reject Attendance Request", isPresented: $showRejectReason) {
            TextField("Reason", text: $rejectionReason)
            Button("Cancel", role: .cancel) {}
            Button("Reject", role: .destructive) {
                reject()
            }
            .disabled(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a reason. It will be visible in the attendance request history.")
        }
        .sheet(isPresented: $showApprovalOptions) {
            AttendanceApprovalStatusSheet { status in
                showApprovalOptions = false
                approve(status)
            }
            .appLibraryNativeSheet([.height(330)])
        }
        .onChange(of: rejectionReason) { _, value in
            if value.count > 200 {
                rejectionReason = String(value.prefix(200))
            }
        }
    }

    private var staffHeader: some View {
        HStack(spacing: 12) {
            Text(staffInitial)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(record.staffName?.nilIfBlank ?? "Staff")
                    .font(.headline)
                    .lineLimit(1)
                Text(AttendanceSheetFormat.displayDate(record.date, style: .weekdayDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Label("Present", systemImage: "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder
    private var requestDetails: some View {
        if hasCorrectionDetails {
            Section("Requested Correction") {
                attendanceTimes(
                    leftTitle: "Punch In",
                    leftValue: AttendanceSheetFormat.time(record.requestedPunchIn) ?? "--",
                    rightTitle: "Punch Out",
                    rightValue: AttendanceSheetFormat.time(record.requestedPunchOut) ?? "--"
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Reason")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(requestReasonText)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        } else {
            Section("Submitted Remark") {
                Text(requestReasonText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    showRejectReason = true
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showApprovalOptions = true
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle")
                        }
                        Text(isSubmitting ? "Saving" : "Approve")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .disabled(isSubmitting)
    }

    private func attendanceTimes(leftTitle: String, leftValue: String, rightTitle: String, rightValue: String) -> some View {
        HStack(spacing: 16) {
            timeMetric(title: leftTitle, value: leftValue)
            Divider()
            timeMetric(title: rightTitle, value: rightValue)
        }
        .padding(.vertical, 2)
    }

    private func timeMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label {
                Text(value)
                    .font(.headline)
            } icon: {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var staffInitial: String {
        (record.staffName?.nilIfBlank ?? "Staff").first.map { String($0).uppercased() } ?? "S"
    }

    private var actualPunchIn: String? {
        record.punchInTime?.nilIfBlank ?? record.firstPunchIn?.nilIfBlank ?? record.sessions?.first?.punchInTime?.nilIfBlank
    }

    private var actualPunchOut: String? {
        record.punchOutTime?.nilIfBlank ?? record.lastPunchOut?.nilIfBlank ?? record.sessions?.last?.punchOutTime?.nilIfBlank
    }

    private var hasCorrectionDetails: Bool {
        record.requestedPunchIn?.nilIfBlank != nil ||
        record.requestedPunchOut?.nilIfBlank != nil ||
        requestType == "correction"
    }

    private var requestType: String {
        record.requestType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var requestReasonText: String {
        record.requestReason?.nilIfBlank ?? "—"
    }

    private var requestTypeLabel: String {
        switch requestType {
        case "correction":
            return "Correction"
        case "remark", "remarks":
            return "Remark"
        default:
            return AttendanceSheetFormat.source(record.source)
        }
    }

    private var submittedValue: String {
        if let created = record._creationTime {
            return Self.formatCreationTime(created)
        }
        return AttendanceSheetFormat.displayDate(record.date, style: .numeric)
    }

    private static func formatCreationTime(_ value: Double) -> String {
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy, hh:mm a"
        return formatter.string(from: date)
    }

    private func approve(_ status: String) {
        guard let token = authStore.currentSession?.token,
              let requestID = attendanceRequestID
        else {
            errorMessage = "This attendance request could not be identified. Refresh and try again."
            return
        }
        isSubmitting = true
        Task {
            do {
                try await HRConvexAPIService.approveAttendance(token: token, id: requestID, approvedAttendance: status, isRequest: true)
                await onCompleted()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }

    private func reject() {
        guard let token = authStore.currentSession?.token,
              let requestID = attendanceRequestID
        else {
            errorMessage = "This attendance request could not be identified. Refresh and try again."
            return
        }
        let reason = rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            errorMessage = "Enter rejection reason."
            return
        }
        isSubmitting = true
        Task {
            do {
                try await HRConvexAPIService.rejectAttendance(token: token, id: requestID, reason: reason, isRequest: true)
                await onCompleted()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }

    private var attendanceRequestID: String? {
        guard record.requestStage?.nilIfBlank != nil else { return nil }
        return record._id?.nilIfBlank
    }
}

private struct AttendanceApprovalStatusSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Choose the final attendance status") {
                    statusRow(
                        title: "Present",
                        subtitle: "Approve the request as a full working day",
                        icon: "checkmark.circle.fill",
                        tint: .green,
                        status: "present"
                    )
                    statusRow(
                        title: "Absent",
                        subtitle: "Mark this attendance record as absent",
                        icon: "person.crop.circle.badge.xmark",
                        tint: .red,
                        status: "absent"
                    )
                    statusRow(
                        title: "Time Correction",
                        subtitle: "Apply the requested punch-time correction",
                        icon: "clock.arrow.circlepath",
                        tint: .blue,
                        status: "time-correction"
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Approve Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func statusRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        status: String
    ) -> some View {
        Button {
            dismiss()
            onSelect(status)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AttendanceReviewTimelineRow {
    let timestamp: Double?
    let time: String
    let title: String
    let trailing: String
    let color: Color
}

private enum AttendanceDecisionButtonStyle {
    case filled(Color)
    case greenGradient
    case outlined(Color)
    case plain

    var foreground: Color {
        switch self {
        case .filled, .greenGradient:
            return .white
        case .outlined(let color):
            return color
        case .plain:
            return Color(hex: 0x101828)
        }
    }

    var background: AnyShapeStyle {
        switch self {
        case .filled(let color):
            return AnyShapeStyle(color)
        case .greenGradient:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: 0x1BCA0B), Color(hex: 0x3D9D02)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .outlined, .plain:
            return AnyShapeStyle(Color.white)
        }
    }

    var border: Color {
        switch self {
        case .filled(let color):
            return color
        case .greenGradient:
            return Color(hex: 0x1BCA0B)
        case .outlined(let color):
            return color.opacity(0.55)
        case .plain:
            return Color(hex: 0xD0D5DD)
        }
    }
}

private struct AttendanceRouteMapView: View {
    let routeData: GeoTrackSessionRouteData
    let replayIndex: Int
    @State private var position: MapCameraPosition = .automatic

    private var coordinates: [CLLocationCoordinate2D] {
        AttendanceSheetFormat.routeCoordinates(for: routeData)
    }

    private var replayCoordinate: CLLocationCoordinate2D? {
        guard !coordinates.isEmpty else { return nil }
        return coordinates[min(max(replayIndex, 0), coordinates.count - 1)]
    }

    private var replayMode: String {
        guard !routeData.timeline.isEmpty else { return "two_wheeler" }
        let point = routeData.timeline[min(max(replayIndex, 0), routeData.timeline.count - 1)]
        return AttendanceSheetFormat.normalizedMode(point.movementMode)
    }

    var body: some View {
        Map(position: $position) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.white, lineWidth: 9)
                MapPolyline(coordinates: coordinates)
                    .stroke(Color(hex: 0x0B61CA), lineWidth: 4)
            }

            if let first = coordinates.first {
                Annotation("", coordinate: first) {
                    routePin(icon: "play.fill", fill: Color(hex: 0x16A34A))
                }
            }

            if let last = coordinates.last {
                Annotation("", coordinate: last) {
                    routePin(icon: "mappin", fill: Color(hex: 0xF04438))
                }
            }

            ForEach(Array(routeData.stops.enumerated()), id: \.offset) { _, stop in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng)) {
                    Circle()
                        .fill(Color(hex: 0x667085))
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }

            if let replayCoordinate {
                Annotation("", coordinate: replayCoordinate) {
                    replayMarker(mode: replayMode)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .onAppear {
            position = AttendanceSheetFormat.mapPosition(for: coordinates)
        }
    }

    private func routePin(icon: String, fill: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(fill, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }

    private func replayMarker(mode: String) -> some View {
        ZStack {
            Circle()
                .fill(mode == "walking" ? Color(hex: 0x16A34A) : Color(hex: 0x111827))
                .frame(width: 42, height: 42)
                .overlay(Circle().stroke(.white, lineWidth: 4))
                .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 3)
            Image(systemName: mode == "walking" ? "figure.walk" : "bicycle")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct RoutePreviewCard: View {
    let isLoading: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xF8FAFC), Color(hex: 0xEAF2FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Path { path in
                path.move(to: CGPoint(x: 18, y: 82))
                path.addCurve(to: CGPoint(x: 116, y: 70), control1: CGPoint(x: 52, y: 98), control2: CGPoint(x: 74, y: 45))
                path.addCurve(to: CGPoint(x: 206, y: 52), control1: CGPoint(x: 144, y: 86), control2: CGPoint(x: 168, y: 38))
                path.addCurve(to: CGPoint(x: 310, y: 78), control1: CGPoint(x: 246, y: 66), control2: CGPoint(x: 268, y: 22))
            }
            .stroke(Color(hex: 0x0B61CA), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(hex: 0x16A34A), in: Circle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color(hex: 0xF04438))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 22)
            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }
}

private enum AttendanceDateStyle {
    case reviewSubtitle
    case weekdayDate
    case numeric
}

private enum AttendanceSheetFormat {
    static func time(_ millis: Double) -> String {
        let date = Date(timeIntervalSince1970: millis / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: date)
    }

    static func time(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = parseISO(raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "hh:mm a"
            return formatter.string(from: date)
        }
        let formats = ["HH:mm:ss", "HH:mm"]
        for pattern in formats {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = pattern
            if let date = parser.date(from: raw) {
                let formatter = DateFormatter()
                formatter.dateFormat = "hh:mm a"
                return formatter.string(from: date)
            }
        }
        return raw
    }

    static func timestampMillis(from raw: String?) -> Double? {
        guard let raw else { return nil }
        if let date = parseISO(raw) {
            return date.timeIntervalSince1970 * 1000
        }
        return nil
    }

    static func hours(_ minutes: Int?) -> String {
        let value = minutes ?? 0
        return String(format: "%02d:%02d hrs", value / 60, value % 60)
    }

    static func compactDuration(_ minutes: Int?) -> String {
        let value = minutes ?? 0
        guard value > 0 else { return "—" }
        return "\(value / 60)h \(value % 60)m"
    }

    static func source(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "mobile":
            return "Mobile App"
        case "biometric":
            return "Biometric"
        case "manual":
            return "Manual"
        default:
        return raw?.nilIfBlank ?? "Mobile App"
        }
    }

    static func distance(_ meters: Double) -> String {
        guard meters > 0 else { return "—" }
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    static func duration(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
        if seconds >= 60 {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
        return "\(seconds)s"
    }

    static func normalizedMode(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "stationary" }
        return raw == "vehicle" ? "two_wheeler" : raw
    }

    static func modeLabel(_ mode: String) -> String {
        switch normalizedMode(mode) {
        case "walking": return "Walking"
        case "running": return "Running"
        case "two_wheeler": return "Two-wheeler"
        case "four_wheeler": return "Four-wheeler"
        case "cycling": return "Cycling"
        default: return "Stationary"
        }
    }

    static func modeColor(_ mode: String) -> Color {
        switch normalizedMode(mode) {
        case "walking": return Color(hex: 0x22C55E)
        case "running": return Color(hex: 0x16A34A)
        case "two_wheeler": return Color(hex: 0xEAB308)
        case "four_wheeler": return Color(hex: 0x3B82F6)
        case "cycling": return Color(hex: 0x14B8A6)
        default: return Color(hex: 0x667085)
        }
    }

    static func dayRangeMillis(for dateString: String) -> (start: Int64, end: Int64)? {
        guard let date = ymd.date(from: dateString) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
    }

    static func routeCoordinates(for data: GeoTrackSessionRouteData) -> [CLLocationCoordinate2D] {
        let tripPath = data.trips.flatMap { trip -> [CLLocationCoordinate2D] in
            if let snapped = trip.snappedPath, !snapped.isEmpty {
                return snapped.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            }
            if let startLat = trip.startLat,
               let startLng = trip.startLng,
               let endLat = trip.endLat,
               let endLng = trip.endLng {
                return [
                    CLLocationCoordinate2D(latitude: startLat, longitude: startLng),
                    CLLocationCoordinate2D(latitude: endLat, longitude: endLng)
                ]
            }
            return []
        }
        if tripPath.count >= 2 {
            return tripPath
        }
        return data.timeline.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    static func mapPosition(for coordinates: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard !coordinates.isEmpty else { return .automatic }
        let minLat = coordinates.map(\.latitude).min() ?? 0
        let maxLat = coordinates.map(\.latitude).max() ?? 0
        let minLng = coordinates.map(\.longitude).min() ?? 0
        let maxLng = coordinates.map(\.longitude).max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let spanMeters = max(
            distanceMeters(fromLat: minLat, fromLng: minLng, toLat: maxLat, toLng: maxLng),
            700
        )
        return .camera(MapCamera(centerCoordinate: center, distance: spanMeters * 1.8))
    }

    static func distanceMeters(fromLat: Double, fromLng: Double, toLat: Double, toLng: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (toLat - fromLat) * .pi / 180
        let dLng = (toLng - fromLng) * .pi / 180
        let lat1 = fromLat * .pi / 180
        let lat2 = toLat * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    static func displayDate(_ raw: String?, style: AttendanceDateStyle) -> String {
        guard let raw, let date = ymd.date(from: raw) else { return raw ?? "—" }
        let formatter = DateFormatter()
        switch style {
        case .reviewSubtitle:
            formatter.dateFormat = "d MMMM yyyy • EEEE"
        case .weekdayDate:
            formatter.dateFormat = "EEE, d MMM yyyy"
        case .numeric:
            formatter.dateFormat = "dd/MM/yyyy"
        }
        return formatter.string(from: date)
    }

    private static let ymd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func parseISO(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
