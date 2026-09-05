import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct CpVisitsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var visits: [CpListVisit] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var searchText = ""
    @State private var selectedFilter: CpVisitFilter = .all
    @State private var filterOptions: CpVisitFilterOptionsResponse?
    @State private var isClockedIn = false
    @State private var selectedOutcomeVisit: CpListVisit?
    @State private var pendingCpRevisit: CpRevisitInfo?
    @State private var showCpRevisitConfirmation = false
    @State private var selectedSpecialOutcomeVisit: CpListVisit?
    @State private var showSpecialOutcome = false
    @State private var showAdvancedFilter = false
    @State private var advancedFilter = AdvancedFilterState()
    @State private var listScope: CpListScope = .mine
    @State private var activeOwnershipScope: CpListScope?
    @State private var didInitializeScope = false
    @State private var canViewDirectTeam = false
    @State private var loadGeneration = 0
    @State private var showPunchIn = false
    @State private var showHomeFenceWarning = false
    @State private var isCheckingHomeFence = false
    @State private var searchTask: Task<Void, Never>?
    @State private var nextCursor: String?
    @State private var hasMoreServerVisits = false
    @State private var isLoadingMore = false

    private var filteredVisits: [CpListVisit] {
        visits.filter { visit in
            selectedFilter.matches(visit)
                && matchesAdvancedFilter(visit, state: advancedFilter)
                && (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || visit.matchesCpSearch(searchText))
        }
    }

    var body: some View {
        visitsContent
            .refreshable { await load() }
            .background(Color.appScreenBackground.ignoresSafeArea())
            .navigationTitle("CP Visits")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Client Places"
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbarBackground(Color.appElevatedSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { navigationToolbar }
            .task {
                if !didInitializeScope {
                    didInitializeScope = true
                    listScope = authStore.isAdmin ? .all : .mine
                }
                if !hasLoaded { await load() }
            }
            .onChange(of: searchText) { _, value in
                scheduleServerSearch(value)
            }
            .onDisappear {
                searchTask?.cancel()
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateCpVisitSheet {
                    showCreateSheet = false
                    Task { await load() }
                }
                .appFormActivity()
                .appLibraryNativeSheet([.height(720), .large])
                .presentationBackground(Color.appElevatedSurface)
            }
            .sheet(item: $selectedOutcomeVisit) { visit in
                CompleteCpVisitSheet(
                    cpVisitId: visit.clientPlaceVisitId,
                    initialOutcome: visit.outcome,
                    cpType: visit.cpType,
                    onCompleted: { revisit in
                        selectedOutcomeVisit = nil
                        pendingCpRevisit = revisit
                        showCpRevisitConfirmation = revisit != nil
                        Task { await load() }
                    }
                )
                .environment(authStore)
            }
            .alert(
                pendingCpRevisit?.dialogTitle ?? "Revisit scheduled",
                isPresented: $showCpRevisitConfirmation
            ) {
                Button("Done") { pendingCpRevisit = nil }
            } message: {
                Text(pendingCpRevisit?.dialogMessage ?? "")
            }
            .fullScreenCover(isPresented: $showAdvancedFilter) {
                AdvancedListFilterView(
                    title: "Filter CP Visits",
                    categories: advancedFilterCategories,
                    state: advancedFilter,
                    resultCount: { state in visits.filter { matchesAdvancedFilter($0, state: state) }.count },
                    onApply: { state in
                        advancedFilter = state
                        activeOwnershipScope = nil
                        listScope = authStore.isAdmin ? .all : .mine
                        selectedFilter = CpVisitFilter(rawValue: state.selected("status").first ?? "") ?? .all
                        Task { await load() }
                    }
                )
            }
            .sheet(isPresented: $showPunchIn) {
                PunchFlowView(mode: .punchIn) {
                    showPunchIn = false
                    Task { await load() }
                }
            }
            .navigationDestination(isPresented: $showSpecialOutcome) {
                if let visit = selectedSpecialOutcomeVisit {
                    tripDestination(for: visit)
                }
            }
            .alert("You are at Home!", isPresented: $showHomeFenceWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Clock in is blocked inside the configured home area.")
            }
    }

    private var visitsContent: some View {
        ScrollView {
            filterPills
            dateFilterChip

            if isLoading && visits.isEmpty {
                skeletonList
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else if filteredVisits.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredVisits) { visit in
                        visitRow(visit)
                            .onAppear {
                                if visit.id == filteredVisits.last?.id {
                                    Task { await loadMoreCpVisits() }
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("CP Visits")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
        }

        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                CpApprovalQueueView()
            } label: {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 19, weight: .semibold))
            }
            .accessibilityLabel("CP approvals")
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                Button { showAdvancedFilter = true } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Filter CP visits")

                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                }
                .accessibilityLabel("Create CP visit")
            }
        }
    }

    @ViewBuilder
    private func visitRow(_ visit: CpListVisit) -> some View {
        if visit.isPendingOutcomeCpVisit && visit.hasSpecialCompletion {
            Button {
                selectedSpecialOutcomeVisit = visit
                showSpecialOutcome = true
            } label: {
                CpVisitCard(visit: visit, isClockedIn: isClockedIn)
            }
            .buttonStyle(.plain)
        } else if visit.isPendingOutcomeCpVisit {
            Button {
                selectedOutcomeVisit = visit
            } label: {
                CpVisitCard(visit: visit, isClockedIn: isClockedIn)
            }
            .buttonStyle(.plain)
        } else if visit.requiresClockIn(isClockedIn: isClockedIn) {
            Button {
                Task { await openClockInRespectingHomeFence() }
            } label: {
                CpVisitCard(visit: visit, isClockedIn: isClockedIn)
            }
            .buttonStyle(.plain)
            .disabled(isCheckingHomeFence)
        } else if visit.isOpenableCpVisit {
            NavigationLink {
                tripDestination(for: visit)
            } label: {
                CpVisitCard(visit: visit, isClockedIn: isClockedIn)
            }
            .buttonStyle(.plain)
        } else if visit.isCompletedCpVisit {
            NavigationLink {
                CompletedCpVisitDetailView(summary: visit)
            } label: {
                CpVisitCard(visit: visit, isClockedIn: isClockedIn)
            }
            .buttonStyle(.plain)
        } else {
            CpVisitCard(visit: visit, isClockedIn: isClockedIn)
        }
    }

    private func tripDestination(for visit: CpListVisit) -> some View {
        TripNavigationView(
            visitId: visit.id,
            placeName: visit.placeName ?? visit.leadName ?? "CP Visit",
            placeAddress: visit.placeAddress,
            destination: coordinate(for: visit),
            initialStatus: visit.status,
            tripType: visit.tripType,
            clientPlaceVisitId: visit.clientPlaceVisitId,
            cpClientMet: visit.clientMet,
            cpOutcome: visit.outcome,
            cpVisitCategory: visit.visitCategory,
            cpType: visit.cpType,
            lmoName: visit.lmoName,
            fieldStaffName: visit.fieldStaffName,
            deadline: visit.deadlineText,
            onTripChanged: {
                Task { await load() }
            }
        )
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if canViewDirectTeam || authStore.isAdmin {
                    scopePill(.mine)
                    scopePill(.direct)
                }
                ForEach(CpVisitFilter.allCases) { filter in
                    Button {
                        let defaultScope: CpListScope = authStore.isAdmin ? .all : .mine
                        let needsReload = listScope != defaultScope
                        activeOwnershipScope = nil
                        listScope = defaultScope
                        selectedFilter = filter
                        advancedFilter.setSelected(filter == .all ? [] : [filter.rawValue], for: "status")
                        if needsReload {
                            visits = []
                            Task { await load() }
                        }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: activeOwnershipScope == nil && selectedFilter == filter ? .semibold : .medium))
                            .foregroundStyle(activeOwnershipScope == nil && selectedFilter == filter ? .white : Color(hex: 0x475467))
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(
                                activeOwnershipScope == nil && selectedFilter == filter ? Color(hex: 0x0B61CA) : .white,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    private func scopePill(_ scope: CpListScope) -> some View {
        let isActive = activeOwnershipScope == scope
        return Button {
            listScope = scope
            activeOwnershipScope = scope
            selectedFilter = .all
            advancedFilter.setSelected([], for: "status")
            visits = []
            Task { await load() }
        } label: {
            Text(scope.title)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : Color(hex: 0x475467))
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(isActive ? Color(hex: 0x0B61CA) : .white, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var dateFilterChip: some View {
        if let from = advancedFilter.fromDate {
            Button {
                advancedFilter.fromDate = nil
                advancedFilter.toDate = nil
                Task { await load() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text(CpDateRangeFilterSheet.label(from: from, to: advancedFilter.toDate))
                    Image(systemName: "xmark.circle.fill")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color(hex: 0x0B61CA).opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image("HomeEmptyTrips")
                .resizable()
                .scaledToFit()
                .frame(width: 182, height: 142)
                .opacity(0.56)
                .padding(.top, 64)
            Text(emptyTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 16)
            Text(emptySubtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyTitle: String {
        if errorMessage != nil { return "Couldn't Load" }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No Matches Found" }
        switch selectedFilter {
        case .scheduled: return "No Scheduled CP Visits"
        case .postponed: return "Nothing Postponed"
        case .inProgress: return "No Visits In Progress"
        case .completed: return "No Completed Visits"
        case .cancelled: return "No Cancelled Visits"
        case .pendingGmApproval: return "No Visits Pending Approval"
        case .all: return "No CP Visits Yet"
        }
    }

    private var emptySubtitle: String {
        if let errorMessage { return errorMessage }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different search term or switch filters to see other client place visits."
        }
        switch selectedFilter {
        case .scheduled:
            return "Scheduled client-place visits assigned to you will appear here."
        case .postponed:
            return "Postponed CP visits will appear here when a follow-up is needed."
        case .inProgress:
            return "Trips you have started or reached will appear here until completion."
        case .completed:
            return "Completed CP visits will appear here with their captured outcome."
        case .cancelled:
            return "Cancelled CP visits will appear here for review."
        case .pendingGmApproval:
            return "CP visits awaiting GM approval will appear here."
        case .all:
            return "Create or receive CP visits to start tracking client-place work."
        }
    }

    private var skeletonList: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: 0xE4E7EC))
                    .frame(height: 92)
                    .redacted(reason: .placeholder)
            }
        }
    }

    @MainActor
    private func load(searchOverride: String? = nil) async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            hasLoaded = true
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        nextCursor = nil
        hasMoreServerVisits = false
        isLoadingMore = false
        let fromDate = advancedFilter.fromDate.map { AppModuleFormatters.ymd.string(from: $0) }
        let effectiveTo = advancedFilter.toDate ?? advancedFilter.fromDate
        let toDate = effectiveTo.map { AppModuleFormatters.ymd.string(from: $0) }
        let query = (searchOverride ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = cpCacheKey(fromDate: fromDate, toDate: toDate, search: query)
        if visits.isEmpty, let cached = LocalCache.get(cacheKey, as: [CpVisitDetail].self) {
            visits = cached.compactMap(CpListVisit.init(detail:)).sorted(by: CpListVisit.androidOrder)
        }

        isLoading = visits.isEmpty
        defer {
            if generation == loadGeneration {
                isLoading = false
                hasLoaded = true
            }
        }
        do {
            Task {
                let clockedIn = await loadClockInState(token: token)
                guard generation == loadGeneration else { return }
                isClockedIn = clockedIn
            }
            Task {
                let options = await fetchCpFilterOptions(
                    token: token,
                    fromDate: fromDate,
                    toDate: toDate
                )
                guard generation == loadGeneration, let options else { return }
                filterOptions = options
            }
            let page = try await fetchCpVisits(
                token: token,
                fromDate: fromDate,
                toDate: toDate,
                search: query
            )
            guard generation == loadGeneration else { return }
            canViewDirectTeam = page.canViewTeam == true
                || page.hasDirectReports == true
                || (page.directReportCount ?? 0) > 0
                || !(page.directReportIds ?? []).isEmpty
            let scoped = scopedCpVisits(page)
            visits = scoped
                .compactMap(CpListVisit.init(detail:))
                .sorted(by: CpListVisit.androidOrder)
            nextCursor = page.nextCursor
            hasMoreServerVisits = page.hasMore == true && page.nextCursor?.isEmpty == false
            LocalCache.put(cacheKey, scoped)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchCpVisits(
        token: String,
        fromDate: String?,
        toDate: String?,
        search: String
    ) async throws -> MyMarketingCpVisitsResponse {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try await MarketingConvexAPIService.getMarketingCpVisitPage(
                    token: token,
                    fromDate: fromDate,
                    toDate: toDate,
                    scope: listScope.apiValue,
                    limit: 200,
                    search: search.nilIfEmpty,
                    assignedStaffId: advancedFilter.selected("fieldStaff").first,
                    telecallerStaffId: advancedFilter.selected("telecaller").first,
                    status: selectedFilter.apiValue,
                    outcome: advancedFilter.selected("outcome").first,
                    cpType: advancedFilter.selected("cpType").first,
                    pageSize: 200
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt == 0 else { break }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        if selectedFilter != .all || !advancedFilter.selected("outcome").isEmpty {
            return try await MarketingConvexAPIService.getMarketingCpVisitPage(
                token: token,
                fromDate: fromDate,
                toDate: toDate,
                scope: listScope.apiValue,
                limit: 200,
                search: search.nilIfEmpty,
                assignedStaffId: advancedFilter.selected("fieldStaff").first,
                telecallerStaffId: advancedFilter.selected("telecaller").first,
                status: nil,
                outcome: nil,
                cpType: advancedFilter.selected("cpType").first,
                pageSize: 200
            )
        }
        throw lastError ?? MarketingAPIError.server("Failed to load CP visits")
    }

    private func cpCacheKey(fromDate: String?, toDate: String?, search: String) -> String {
        let user = authStore.currentSession?.user
        let staffId = user?.staffId ?? user?._id ?? "unknown"
        let range = "\(fromDate ?? "all")-\(toDate ?? "all")"
        let query = search.isEmpty ? "all" : String(search.lowercased().prefix(80))
        let facets = ["status", "outcome", "cpType", "fieldStaff", "telecaller"]
            .map { advancedFilter.selected($0).sorted().joined(separator: ",") }
            .joined(separator: "|")
        return "marketing.cp-visits.\(listScope.rawValue).\(staffId).\(range).\(query).\(facets)"
    }

    @MainActor
    private func scheduleServerSearch(_ rawValue: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load(searchOverride: rawValue)
        }
    }

    private func loadClockInState(token: String) async -> Bool {
        await AttendanceTrackingGate.isClockedInForToday(token: token)
    }

    private func coordinate(for visit: CpListVisit) -> CLLocationCoordinate2D? {
        guard let lat = visit.placeLat, let lng = visit.placeLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    @MainActor
    private func openClockInRespectingHomeFence() async {
        guard let token = authStore.currentSession?.token else { return }
        isCheckingHomeFence = true
        defer { isCheckingHomeFence = false }
        let fence = try? await HRConvexAPIService.getHomeFence(token: token)
        guard let fence, fence.enabled, let lat = fence.lat, let lng = fence.lng else {
            showPunchIn = true
            return
        }
        do {
            let current = try await OneShotLocationReader.requestLocation()
            let home = CLLocation(latitude: lat, longitude: lng)
            if current.distance(from: home) <= Double(fence.radiusMeters) {
                showHomeFenceWarning = true
            } else {
                showPunchIn = true
            }
        } catch {
            showPunchIn = true
        }
    }

    @MainActor
    private func loadMoreCpVisits() async {
        guard !isLoadingMore, hasMoreServerVisits, let cursor = nextCursor,
              let token = authStore.currentSession?.token else { return }
        isLoadingMore = true
        let generation = loadGeneration
        defer { isLoadingMore = false }
        do {
            let effectiveToDate = advancedFilter.toDate ?? advancedFilter.fromDate
            let page = try await MarketingConvexAPIService.getMarketingCpVisitPage(
                token: token,
                fromDate: advancedFilter.fromDate.map { AppModuleFormatters.ymd.string(from: $0) },
                toDate: effectiveToDate.map { AppModuleFormatters.ymd.string(from: $0) },
                scope: listScope.apiValue,
                limit: 200,
                search: searchText.nilIfEmpty,
                assignedStaffId: advancedFilter.selected("fieldStaff").first,
                telecallerStaffId: advancedFilter.selected("telecaller").first,
                status: selectedFilter.apiValue,
                outcome: advancedFilter.selected("outcome").first,
                cpType: advancedFilter.selected("cpType").first,
                cursor: cursor,
                pageSize: 200
            )
            guard generation == loadGeneration else { return }
            let incoming = scopedCpVisits(page).compactMap(CpListVisit.init(detail:))
            var byID = Dictionary(uniqueKeysWithValues: visits.map { ($0.id, $0) })
            incoming.forEach { byID[$0.id] = $0 }
            visits = Array(byID.values).sorted(by: CpListVisit.androidOrder)
            nextCursor = page.nextCursor
            hasMoreServerVisits = page.hasMore == true && page.nextCursor?.isEmpty == false && page.nextCursor != cursor
        } catch {
            // Preserve loaded pages; pull-to-refresh retries from page one.
        }
    }

    private func fetchCpFilterOptions(
        token: String,
        fromDate: String?,
        toDate: String?
    ) async -> CpVisitFilterOptionsResponse? {
        try? await MarketingConvexAPIService.getMarketingCpVisitFilterOptions(
            token: token,
            scope: listScope.apiValue,
            fromDate: fromDate,
            toDate: toDate
        )
    }

    private var advancedFilterCategories: [AdvancedFilterCategory] {
        [
            AdvancedFilterCategory(id: "date", title: "Date", showsDateRange: true),
            AdvancedFilterCategory(
                id: "status",
                title: "Status",
                options: CpVisitFilter.allCases.filter { $0 != .all }.map {
                    AdvancedFilterOption(id: $0.rawValue, label: $0.title)
                },
                selectionMode: .single
            ),
            AdvancedFilterCategory(id: "outcome", title: "Outcome", options: mergeCpOptions(
                Self.cpOutcomeOptions,
                serverCpOptions(filterOptions?.outcomes)
            )),
            AdvancedFilterCategory(id: "cpType", title: "CP Type", options: mergeCpOptions(
                Self.cpTypeOptions,
                serverCpOptions(filterOptions?.cpTypes)
            )),
            AdvancedFilterCategory(id: "fieldStaff", title: "Field Staff", options: mergeCpOptions(
                serverCpOptions(filterOptions?.fieldStaff),
                uniqueCpOptions { visit in
                guard let id = visit.detail.assignedStaffId?.blankToNil,
                      let name = visit.fieldStaffName?.blankToNil else { return nil }
                return AdvancedFilterOption(id: id, label: name)
                }
            )),
            AdvancedFilterCategory(id: "telecaller", title: "Telecaller", options: mergeCpOptions(
                serverCpOptions(filterOptions?.telecallers),
                uniqueCpOptions { visit in
                guard let id = visit.detail.telecallerStaffId?.blankToNil,
                      let name = visit.lmoName?.blankToNil else { return nil }
                return AdvancedFilterOption(id: id, label: name)
                }
            ))
        ]
    }

    private func serverCpOptions(_ values: [CpVisitFilterOption]?) -> [AdvancedFilterOption] {
        values?.compactMap { option in
            guard let id = option.id?.blankToNil else { return nil }
            let label = option.name?.blankToNil ?? option.label?.blankToNil
                ?? id.replacingOccurrences(of: "_", with: " ").capitalized
            let staffDetail = [option.employeeId, option.designation, option.department]
                .compactMap { $0?.blankToNil }
                .joined(separator: " • ")
            return AdvancedFilterOption(
                id: id,
                label: label,
                subtitle: staffDetail.blankToNil ?? option.count.map { "\($0) visits" }
            )
        } ?? []
    }

    private func mergeCpOptions(_ groups: [AdvancedFilterOption]...) -> [AdvancedFilterOption] {
        var seen = Set<String>()
        return groups.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    private static let cpOutcomeOptions = [
        ("interested", "Interested"), ("not_interested", "Not interested"),
        ("postponed", "Follow-up"), ("referral", "Referral"),
        ("converted_to_site_visit", "Converted to Site Visit"),
        ("converted_to_booking", "Converted to Booking"), ("other", "Others"),
        ("rejected", "Rejected"), ("gift_distributed", "Gift Distributed"),
        ("old_client_visited", "Old Client Visited"), ("collection_done", "Collection Done"),
        ("not_collected", "Not Collected")
    ].map { AdvancedFilterOption(id: $0.0, label: $0.1) }

    private static let cpTypeOptions = [
        ("sv_cum_cp", "SV cum CP"), ("follow_up", "Follow-up"),
        ("booking_cp", "Booking CP"), ("collection_cp", "Collection CP"),
        ("old_client", "Old Client"), ("gift_distribution", "Gift Distribution"),
        ("new_client_cp", "New Client CP"), ("other_cp", "Other CP"),
        ("joint_cp", "Joint CP")
    ].map { AdvancedFilterOption(id: $0.0, label: $0.1) }

    private func uniqueCpOptions(_ transform: (CpListVisit) -> AdvancedFilterOption?) -> [AdvancedFilterOption] {
        var seen = Set<String>()
        return visits.compactMap(transform).filter { seen.insert($0.id).inserted }.sorted { $0.label < $1.label }
    }

    private func matchesAdvancedFilter(_ visit: CpListVisit, state: AdvancedFilterState) -> Bool {
        if let from = state.fromDate {
            let lower = AppModuleFormatters.ymd.string(from: from)
            if (visit.scheduledDate ?? "") < lower { return false }
        }
        if let to = state.toDate {
            let upper = AppModuleFormatters.ymd.string(from: to)
            if (visit.scheduledDate ?? "") > upper { return false }
        }
        let statuses = state.selected("status")
        if !statuses.isEmpty && !statuses.contains(where: { CpVisitFilter(rawValue: $0)?.matches(visit) == true }) { return false }
        let outcomes = state.selected("outcome")
        if !outcomes.isEmpty && !outcomes.contains(visit.outcome?.normalizedMarker ?? "") { return false }
        let cpTypes = state.selected("cpType")
        if !cpTypes.isEmpty && !cpTypes.contains(visit.cpType?.normalizedMarker ?? "") { return false }
        let fieldStaff = state.selected("fieldStaff")
        if !fieldStaff.isEmpty && !fieldStaff.contains(visit.detail.assignedStaffId ?? "") { return false }
        let telecallers = state.selected("telecaller")
        if !telecallers.isEmpty && !telecallers.contains(visit.detail.telecallerStaffId ?? "") { return false }
        return true
    }

    private func scopedCpVisits(_ page: MyMarketingCpVisitsResponse) -> [CpVisitDetail] {
        switch listScope {
        case .mine:
            guard let user = authStore.currentSession?.user else { return [] }
            let ownIDs = Set([user.staffId, user._id].compactMap { $0?.blankToNil })
            return page.visits.filter { detail in
                ownIDs.contains(detail.assignedStaffId ?? "")
                    || ownIDs.contains(detail.joint?.leadStaffId ?? "")
                    || (detail.joint?.participants ?? []).contains { ownIDs.contains($0.staffId ?? "") }
            }
        case .direct:
            guard page.scope?.lowercased() == CpListScope.direct.apiValue else { return [] }
            let directIDs = Set(page.directReportIds ?? [])
            guard !directIDs.isEmpty else { return [] }
            return page.visits.filter { detail in
                directIDs.contains(detail.assignedStaffId ?? "")
                    || directIDs.contains(detail.joint?.leadStaffId ?? "")
                    || (detail.joint?.participants ?? []).contains { directIDs.contains($0.staffId ?? "") }
            }
        case .all:
            guard authStore.isAdmin else { return [] }
            return page.visits
        }
    }
}

private enum CpListScope: String, CaseIterable, Identifiable {
    case mine
    case direct
    case all

    var id: String { rawValue }
    var apiValue: String { rawValue }
    var title: String {
        switch self {
        case .mine: "My"
        case .direct: "Team"
        case .all: "All"
        }
    }
}

private struct CpListVisit: Identifiable {
    let id: String
    let fieldVisitId: String?
    let clientPlaceVisitId: String
    let clientPlaceId: String?
    let scheduledDate: String?
    let scheduledStartTime: String?
    let scheduledEndTime: String?
    let status: String?
    let placeName: String?
    let placeAddress: String?
    let placeType: String?
    let placeLat: Double?
    let placeLng: Double?
    let leadName: String?
    let leadPhone: String?
    let lmoName: String?
    let fieldStaffName: String?
    let jointStaffLabel: String?
    let clientMet: Bool?
    let clientMetAt: Int64?
    let clientNoShowReason: String?
    let outcome: String?
    let postponeReasons: [String]
    let convertedBookingId: String?
    let convertedSiteVisitId: String?
    let completedAt: Int64?
    let visitCategory: String
    let cpType: String?
    let detail: CpVisitDetail

    init?(detail: CpVisitDetail) {
        guard detail.id.blankToNil != nil, detail.scheduledDate?.blankToNil != nil else { return nil }
        self.id = detail.id
        self.fieldVisitId = detail.fieldVisitId
        self.clientPlaceVisitId = detail.id
        self.clientPlaceId = detail.clientPlaceId
        self.scheduledStartTime = detail.scheduledTime
        self.scheduledEndTime = nil
        let resolvedStatus = CpVisitStatusPolicy.resolve(
            cpStatus: detail.status,
            fieldVisitStatus: detail.fieldVisit?.status
        )
        self.status = resolvedStatus
        let isCompleted = ["completed", "complete", "done", "closed"].contains(
            resolvedStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
        self.scheduledDate = isCompleted
            ? detail.activityDate?.blankToNil ?? detail.scheduledDate
            : detail.scheduledDate
        let manualClientName = detail.lead?.manualProfile?.clientName?.cpClientName
        let masterClientName = detail.client?.clientName?.cpClientName
        let leadContactName = detail.lead?.contactName?.cpClientName
        let clientPlaceName = detail.clientPlace?.name?.blankToNil
        let fallbackPhone = detail.lead?.mobileNumber?.blankToNil
            ?? detail.client?.mobileNumber?.blankToNil
        self.placeName = leadContactName
            ?? manualClientName
            ?? masterClientName
            ?? clientPlaceName
            ?? fallbackPhone
            ?? "CP Visit"
        self.placeAddress = detail.clientPlace?.address?.blankToNil
            ?? detail.clientPlace?.formattedAddress?.blankToNil
            ?? [
                detail.clientPlace?.landmark,
                detail.clientPlace?.city,
                detail.clientPlace?.state,
                detail.clientPlace?.pincode
            ]
            .compactMap { $0?.blankToNil }
            .joined(separator: ", ")
            .blankToNil
        self.placeType = detail.clientPlace?.contactPerson?.blankToNil
        self.placeLat = detail.clientPlace?.lat
        self.placeLng = detail.clientPlace?.lng
        self.leadName = detail.lead?.contactName?.cpClientName
            ?? detail.lead?.manualProfile?.clientName?.cpClientName
            ?? detail.client?.clientName?.cpClientName
        self.leadPhone = detail.lead?.mobileNumber?.blankToNil
            ?? detail.client?.mobileNumber?.blankToNil
            ?? detail.clientPlace?.contactPhone?.blankToNil
        self.lmoName = detail.telecaller?.name?.blankToNil
            ?? detail.telecaller?.staffName?.blankToNil
        let jointNames = ([detail.joint?.leadStaffName] + (detail.joint?.companionNames ?? []))
            .compactMap { $0?.blankToNil }
        self.jointStaffLabel = jointNames.isEmpty ? nil : jointNames.joined(separator: " & ")
        self.fieldStaffName = self.jointStaffLabel
            ?? detail.assignedStaff?.name?.blankToNil
            ?? detail.assignedStaff?.staffName?.blankToNil
        self.clientMet = detail.clientMet
        self.clientMetAt = detail.clientMetAt
        self.clientNoShowReason = detail.clientNoShowReason
        self.outcome = detail.syntheticOutcome
        self.postponeReasons = detail.postponeReasons ?? []
        self.convertedBookingId = detail.convertedBookingId
        self.convertedSiteVisitId = detail.convertedSiteVisitId
        self.completedAt = detail.completedAt
        self.visitCategory = detail.isSvCumCp ? "sv_cum_cp" : "direct_cp"
        self.cpType = detail.cpType
        self.detail = detail
    }

    var tripType: String { "client_place" }

    var deadlineText: String? {
        guard let rawDate = scheduledDate?.blankToNil else { return nil }
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        let dateText: String
        if let date = input.date(from: rawDate) {
            let output = DateFormatter()
            output.locale = Locale.current
            output.dateFormat = "dd MMM yyyy"
            dateText = output.string(from: date)
        } else {
            dateText = rawDate
        }
        guard let time = scheduledEndTime?.blankToNil ?? scheduledStartTime?.blankToNil else {
            return dateText
        }
        return "\(dateText) · \(time)"
    }

    var normalizedStatus: String {
        (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isPostponedCpVisit: Bool {
        outcome?.lowercased() == "postponed" || !postponeReasons.isEmpty
    }

    var needsCpDetails: Bool {
        normalizedStatus == "arrived" && outcome?.blankToNil == nil
    }

    var isOpenableCpVisit: Bool {
        !normalizedStatus.isCompleted && !normalizedStatus.isCancelled && !isExpired
    }

    var isCompletedCpVisit: Bool {
        normalizedStatus.isCompleted
    }

    var isPendingOutcomeCpVisit: Bool {
        CpVisitStatusPolicy.isOutcomePending(
            cpStatus: detail.status, fieldVisitStatus: detail.fieldVisit?.status, outcome: outcome
        )
    }

    var hasSpecialCompletion: Bool {
        ["collection_cp", "old_client", "gift_distribution"].contains(cpType?.normalizedMarker ?? "")
    }

    var isExpired: Bool {
        false
    }

    func requiresClockIn(isClockedIn: Bool) -> Bool {
        !isClockedIn
            && isOpenableCpVisit
            && !normalizedStatus.isInProgress
            && !needsCpDetails
            && !isPostponedCpVisit
    }

    var typeLabel: String {
        if let cpTypeLabel { return cpTypeLabel }
        return visitCategory == "sv_cum_cp" ? "SV Confirmation CP" : "Direct CP"
    }

    private var cpTypeLabel: String? {
        switch cpType?.normalizedMarker {
        case "sv_cum_cp": return "SV cum CP"
        case "follow_up": return "Follow-up"
        case "booking_cp": return "Booking CP"
        case "collection_cp": return "Collection CP"
        case "old_client": return "Old Client"
        case "gift_distribution": return "Gift Distribution"
        case "new_client_cp": return "New Client CP"
        case "other_cp": return "Other CP"
        // Joint CP is created on web/Android; iOS renders it correctly but is
        // not offered it in the create picker yet, because that needs a second
        // staff and the server requires exactly two.
        case "joint_cp": return "Joint CP"
        case let value? where value.isEmpty == false:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        default:
            return nil
        }
    }

    var cpCompletionActionTitle: String {
        switch cpType?.normalizedMarker {
        case "collection_cp": return "Submit Payment Entry"
        case "old_client": return "Add Visit Remarks"
        case "gift_distribution": return "Confirm Gift Distribution"
        default:
            return visitCategory == "sv_cum_cp" ? "Complete SV details" : "Complete CP details"
        }
    }

    func matchesCpSearch(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return [
            placeName,
            leadName,
            leadPhone,
            placeAddress,
            placeType,
            scheduledDate,
            status,
            outcome,
            typeLabel,
            cpType,
            lmoName,
            fieldStaffName
        ]
        .compactMap { $0?.lowercased() }
        .contains { $0.localizedStandardContains(needle) }
    }

    static func androidOrder(_ lhs: CpListVisit, _ rhs: CpListVisit) -> Bool {
        if lhs.sortGroup != rhs.sortGroup { return lhs.sortGroup < rhs.sortGroup }
        let leftCreated = lhs.detail.createdAt ?? 0
        let rightCreated = rhs.detail.createdAt ?? 0
        if leftCreated != rightCreated { return leftCreated > rightCreated }
        let leftDate = lhs.scheduledDate ?? ""
        let rightDate = rhs.scheduledDate ?? ""
        return leftDate > rightDate
    }

    private var sortGroup: Int {
        if normalizedStatus.isInProgress || needsCpDetails { return 0 }
        if normalizedStatus.isCompleted || normalizedStatus.isCancelled { return 2 }
        return 1
    }

}

private struct CpVisitCard: View {
    let visit: CpListVisit
    let isClockedIn: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if let fieldStaff = visit.fieldStaffName?.blankToNil {
                HStack(spacing: 6) {
                    Image(systemName: visit.jointStaffLabel == nil ? "person" : "person.2")
                    Text("\(visit.jointStaffLabel == nil ? "Field Staff" : "Joint Staff"): \(fieldStaff)")
                        .lineLimit(2)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            }
            if let lmo = visit.lmoName?.blankToNil {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.key")
                    Text("LMO: \(lmo)")
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            }
            notMetNotice
            statsGrid
                .padding(.top, 20)
            actionPill
                .padding(.top, 20)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: 278, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .stroke(Color(red: 0.95, green: 0.96, blue: 0.97), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(initial)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(textSecondary)
                .frame(width: 44, height: 44)
                .background(Color(red: 0.95, green: 0.96, blue: 0.98), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                if let supportText {
                    Text(supportText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(textSecondary)
                        .lineLimit(1)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)

            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 6, height: 6)
            Text(statusTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusTextColor)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(statusBackground, in: Capsule())
    }

    /// Client-not-met notice line. Priority: 3-strike unavailable warning →
    /// "rescheduled Nth time" (only shown while the visit is live/not completed).
    @ViewBuilder
    private var notMetNotice: some View {
        let d = visit.detail
        let isLive = !(normalizedStatus.isCompleted)
        let statusLc = (d.status ?? "").lowercased()
        if isLive && d.clientUnavailableWarning == true {
            noticeRow(text: "⚠ Client unavailable — last 3 visits missed")
        } else if statusLc == "pending_gm_approval" {
            let gm = d.approvalGmName?.blankToNil.map { "Awaiting: \($0)" } ?? "Awaiting GM approval"
            noticeRow(text: gm)
        } else if isLive && d.reassignedFromRejection == true {
            let r = d.rejectRemark?.blankToNil.map { "GM sent back: \($0)" } ?? "Reassigned by GM"
            noticeRow(text: r)
        } else if isLive, let n = d.rescheduleCount, n > 0 {
            let dateSuffix = d.lastNotMetDate.map { " on \($0)" } ?? ""
            noticeRow(text: "Client not met\(dateSuffix) · rescheduled \(ordinalCp(n)) time")
        }
    }

    private func noticeRow(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(hex: 0xB54708))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }

    /// "1st", "2nd", "3rd", "4th"… for the "rescheduled Nth time" notice.
    private func ordinalCp(_ n: Int) -> String {
        let s: String
        if (11...13).contains(n % 100) {
            s = "th"
        } else {
            switch n % 10 {
            case 1: s = "st"
            case 2: s = "nd"
            case 3: s = "rd"
            default: s = "th"
            }
        }
        return "\(n)\(s)"
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            VStack(spacing: 16) {
                statRow(icon: "building.2", label: "Type", value: visit.typeLabel)
                statRow(icon: "point.topleft.down.curvedto.point.bottomright.up", label: "Distance", value: routeText)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(red: 0.90, green: 0.91, blue: 0.94), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1, height: 96)

            VStack(spacing: 16) {
                statRow(icon: "clock", label: "Time", value: timeText)
                statRow(icon: "timer", label: "ETA", value: etaText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 40, height: 40)
                .background(Color(red: 0.95, green: 0.97, blue: 1.0), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(textSecondary)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 40)
    }

    private var actionPill: some View {
        HStack(spacing: 10) {
            if showsPlayIcon {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
            }

            Text(actionTitle)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(actionForeground)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(actionBackground, in: Capsule())
        .overlay {
            if normalizedStatus.isInProgress {
                Capsule().stroke(Color(red: 0.97, green: 0.56, blue: 0.04), lineWidth: 1)
            }
        }
    }

    private var title: String {
        visit.placeName ?? visit.leadName ?? "CP Visit"
    }

    private var supportText: String? {
        visit.placeAddress?.blankToNil
            ?? visit.leadPhone?.blankToNil
            ?? visit.placeType?.blankToNil
            ?? "Client Place"
    }

    private var initial: String {
        title.first.map { String($0).uppercased() } ?? "C"
    }

    private var routeText: String {
        (visit.placeLat != nil && visit.placeLng != nil) ? "Open route" : "Not mapped"
    }

    private var timeText: String {
        if let dateTime = Self.displayVisitDateTime(
            date: visit.scheduledDate,
            time: visit.scheduledStartTime
        ) {
            return dateTime
        }
        let start = visit.scheduledStartTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = visit.scheduledEndTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let startTime = start.flatMap(Self.displayVisitTime) {
            if let endTime = end.flatMap(Self.displayVisitTime), endTime != startTime {
                return "\(startTime) - \(endTime)"
            }
            return startTime
        }
        if let start, !start.isEmpty, let end, !end.isEmpty, !Self.looksLikeDateOnly(start) {
            return "\(start) - \(end)"
        }
        if let start, !start.isEmpty, !Self.looksLikeDateOnly(start) {
            return start
        }
        return "-"
    }

    private var etaText: String {
        if visit.isExpired { return "Expired" }
        if visit.isPostponedCpVisit { return "Postponed" }
        if normalizedStatus.isCancelled { return "Cancelled" }
        if normalizedStatus.isCompleted { return "Complete" }
        if normalizedStatus == "arrived" { return "At client place" }
        if normalizedStatus.isInProgress { return "Tracking" }
        return "After start"
    }

    private var statusTitle: String {
        if visit.isExpired { return "Expired" }
        if normalizedStatus.isCancelled { return "Cancelled" }
        if visit.isPendingOutcomeCpVisit { return "Pending" }
        if normalizedStatus.isCompleted { return "Completed" }
        if visit.needsCpDetails { return "Reaching" }
        if normalizedStatus.isInProgress { return normalizedStatus == "arrived" ? "Reaching" : "Enroute" }
        if visit.isPostponedCpVisit { return "Postponed" }
        return isClockedIn ? "Ready" : "Ready"
    }

    private var actionTitle: String {
        if visit.isExpired { return "Expired" }
        if normalizedStatus.isCancelled { return "Cancelled" }
        if visit.isPendingOutcomeCpVisit { return "Pending" }
        if normalizedStatus.isCompleted { return "Completed" }
        if visit.needsCpDetails { return visit.cpCompletionActionTitle }
        if normalizedStatus == "arrived" { return visit.cpCompletionActionTitle }
        if normalizedStatus.isInProgress { return "Enroute" }
        if visit.isPostponedCpVisit { return "Reschedule" }
        if !isClockedIn { return "Need to Clock In" }
        return "Start Trip"
    }

    private var showsPlayIcon: Bool {
        if visit.isExpired || normalizedStatus.isCompleted || normalizedStatus.isCancelled || normalizedStatus.isInProgress { return false }
        return true
    }

    private var statusTextColor: Color {
        if visit.isExpired { return Color(hex: 0xB42318) }
        if normalizedStatus.isCancelled { return Color(hex: 0xB42318) }
        if normalizedStatus.isInProgress { return Color(red: 0.71, green: 0.28, blue: 0.03) }
        if visit.isPendingOutcomeCpVisit { return Color(hex: 0xB54708) }
        if normalizedStatus.isCompleted { return Color(red: 0.09, green: 0.61, blue: 0.18) }
        if visit.isPostponedCpVisit { return textSecondary }
        return Color(red: 0.09, green: 0.61, blue: 0.18)
    }

    private var statusBackground: Color {
        if visit.isExpired || normalizedStatus.isCancelled { return Color.red.opacity(0.12) }
        if normalizedStatus.isInProgress { return Color.orange.opacity(0.13) }
        if visit.isPendingOutcomeCpVisit { return Color.orange.opacity(0.15) }
        if normalizedStatus.isCompleted || visit.isPostponedCpVisit { return Color.secondary.opacity(0.11) }
        return Color.green.opacity(0.12)
    }

    private var actionForeground: Color {
        if visit.isExpired { return Color(hex: 0x7A0F0A) }
        if normalizedStatus.isCancelled { return Color(hex: 0x7A0F0A) }
        if normalizedStatus.isInProgress { return Color(red: 0.71, green: 0.28, blue: 0.03) }
        if visit.isPendingOutcomeCpVisit { return Color(hex: 0xB54708) }
        if normalizedStatus.isCompleted { return Color(hex: 0x1F7A3F) }
        return .white
    }

    private var actionBackground: some ShapeStyle {
        if visit.isExpired || normalizedStatus.isCancelled {
            return AnyShapeStyle(Color.red.opacity(0.12))
        }
        if normalizedStatus.isInProgress {
            return AnyShapeStyle(Color.orange.opacity(0.13))
        }
        if normalizedStatus.isCompleted {
            return AnyShapeStyle(Color.secondary.opacity(0.14))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.79, blue: 0.04), Color(red: 0.24, green: 0.62, blue: 0.01)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var normalizedStatus: String {
        (visit.status ?? "").lowercased()
    }

    private var statusDotColor: Color {
        if visit.isExpired || normalizedStatus.isCancelled { return Color(hex: 0xD92D20) }
        if normalizedStatus.isInProgress { return Color(hex: 0xF79009) }
        return Color(red: 0.13, green: 0.73, blue: 0.30)
    }

    private var textPrimary: Color { .primary }
    private var textSecondary: Color { .secondary }

    private static func parseVisitDate(_ raw: String) -> Date? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Z", with: "")
            .components(separatedBy: ".")
            .first ?? raw
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ]
        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private static func displayVisitTime(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeDateOnly(trimmed) else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: "Z", with: "")
            .components(separatedBy: ".")
            .first ?? trimmed
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "HH:mm:ss",
            "HH:mm",
            "h:mm a",
            "hh:mm a"
        ]
        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            if let date = formatter.date(from: normalized) {
                return visitTimeFormatter.string(from: date)
            }
        }
        return nil
    }

    private static func displayVisitDateTime(date: String?, time: String?) -> String? {
        guard let date = date?.blankToNil else { return nil }
        let raw = "\(date) \(time?.blankToNil ?? "")".trimmingCharacters(in: .whitespaces)
        for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd h:mm a", "yyyy-MM-dd hh:mm a", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            guard let parsed = formatter.date(from: raw) else { continue }
            let output = DateFormatter()
            output.locale = Locale(identifier: "en_IN")
            output.dateFormat = time?.blankToNil == nil ? "dd/MM/yyyy" : "dd/MM/yyyy hh:mm a"
            return output.string(from: parsed)
        }
        return nil
    }

    private static func looksLikeDateOnly(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":") { return false }
        if parseVisitDate(trimmed) != nil { return true }
        let slashDate = #"^\d{1,2}/\d{1,2}/\d{2,4}$"#
        return trimmed.range(of: slashDate, options: .regularExpression) != nil
    }

    private static let visitDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter
    }()

    private static let visitTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return formatter
    }()
}

private enum CpVisitFilter: String, CaseIterable, Identifiable {
    case all
    case scheduled
    case postponed
    case inProgress
    case completed
    case cancelled
    case pendingGmApproval

    var id: String { rawValue }

    var apiValue: String? {
        switch self {
        case .all: return nil
        case .inProgress: return "in_progress"
        case .pendingGmApproval: return "pending_gm_approval"
        default: return rawValue
        }
    }

    var title: String {
        switch self {
        case .all: return "All"
        case .scheduled: return "Scheduled"
        case .postponed: return "Postponed"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .pendingGmApproval: return "Pending Approval"
        }
    }

    func matches(_ visit: CpListVisit) -> Bool {
        let status = visit.normalizedStatus
        switch self {
        case .all:
            return true
        case .scheduled:
            return !status.isCompleted && !status.isCancelled && !status.isInProgress && !visit.isPostponedCpVisit
        case .postponed:
            return visit.isPostponedCpVisit && !status.isCancelled && !status.isCompleted
        case .inProgress:
            return status.isInProgress && !status.isCancelled && !status.isCompleted
        case .completed:
            return status.isCompleted && !visit.isPendingOutcomeCpVisit
        case .cancelled:
            return status.isCancelled
        case .pendingGmApproval:
            return status == "pending_gm_approval" || status == "pending-gm-approval"
        }
    }
}

private struct CompletedCpVisitDetailView: View {
    @Environment(AuthStore.self) private var authStore

    let summary: CpListVisit

    @State private var detail: CpVisitDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var detailIds: [String] {
        var ids: [String] = []
        ids.append(summary.clientPlaceVisitId)
        if let fieldVisitId = summary.fieldVisitId?.blankToNil {
            ids.append(fieldVisitId)
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                statusCard
                visitInfoCard
                if let detail {
                    enrichedCards(detail)
                }
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading visit proof…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(16)
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .navigationTitle("Completed Visit")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
        .refreshable { await loadDetail(force: true) }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(displayName.first.map { String($0).uppercased() } ?? "C")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 52, height: 52)
                    .background(Color(hex: 0xEAF2FF), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(displayName)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(primaryPhone)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(primaryAddress)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .completedCard()
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(clientMetTitle, systemImage: clientMetIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(clientMetTint)
                Spacer()
                Text(outcomeTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(outcomeTint)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(outcomeTint.opacity(0.12), in: Capsule())
            }
            Text(statusSubtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if let reasons = detail?.postponeReasons ?? (summary.postponeReasons.isEmpty ? nil : summary.postponeReasons), !reasons.isEmpty {
                FlowChipRow(items: reasons, tint: Color(hex: 0xB54708))
            }
        }
        .completedCard()
    }

    private var visitInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visit Information")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            twoColumnRow("Date", formattedDate(summary.scheduledDate), "Time", formattedTime)
            twoColumnRow("Trip Type", tripTypeTitle, "Location", isGeoMapped ? "Geo-mapped" : "Not mapped")
            if let notes = detail?.notes?.blankToNil, !isBookingOutcome {
                Divider()
                Text(notes)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .completedCard()
    }

    @ViewBuilder
    private func enrichedCards(_ detail: CpVisitDetail) -> some View {
        tripDetailsCard(detail)
        if isBookingOutcome, let notes = detail.notes?.blankToNil {
            bookingNotesCard(notes)
        }
        if detail.arrivalProof != nil || detail.fieldVisit != nil {
            proofCard(detail)
        }
        peopleCard(detail)
        timelineCard(detail)
    }

    private func tripDetailsCard(_ detail: CpVisitDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip Details")
                .font(.system(size: 15, weight: .semibold))
            twoColumnRow(
                "Status",
                detail.fieldVisit?.status?.replacingOccurrences(of: "_", with: " ").capitalized ?? detail.status ?? "-",
                "Distance",
                distanceText(detail.fieldVisit?.distanceMeters)
            )
            twoColumnRow(
                "Started",
                formatEpoch(detail.fieldVisit?.startedAt),
                "Completed",
                formatEpoch(detail.fieldVisit?.completedAt ?? detail.completedAt)
            )
            twoColumnRow(
                "Duration",
                durationText(detail.fieldVisit?.durationMinutes),
                "Field Visit ID",
                detail.fieldVisitId?.blankToNil ?? detail.fieldVisit?.id?.blankToNil ?? "-"
            )
        }
        .completedCard()
    }

    private func bookingNotesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Booking Details")
                .font(.system(size: 15, weight: .semibold))
            ForEach(parseNoteSections(notes)) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0369A1))
                    ForEach(section.rows) { row in
                        detailRow(row.label, row.value)
                    }
                }
                .padding(12)
                .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .completedCard()
    }

    private func proofCard(_ detail: CpVisitDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Arrival Proof")
                .font(.system(size: 15, weight: .semibold))
            if let photoUrl = detail.arrivalProof?.photoUrl, let url = URL(string: photoUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color.appFieldBackground.overlay(Image(systemName: "photo"))
                    default:
                        Color.appFieldBackground.overlay(ProgressView())
                    }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            twoColumnRow("OTP Requested", formatEpoch(detail.arrivalProof?.otpRequestedAt), "OTP Verified", formatEpoch(detail.arrivalProof?.otpVerifiedAt))
            twoColumnRow("GPS", gpsText(detail.arrivalProof), "Distance", distanceText(detail.arrivalProof?.distanceFromPlaceMeters))
        }
        .completedCard()
    }

    private func peopleCard(_ detail: CpVisitDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("People")
                .font(.system(size: 15, weight: .semibold))
            detailRow("Assigned Staff", detail.assignedStaff?.staffName ?? detail.assignedStaff?.staffCode)
            detailRow("Telecaller", detail.telecaller?.staffName ?? detail.telecaller?.staffCode)
            detailRow("Origin", detail.origin?.replacingOccurrences(of: "_", with: " ").capitalized)
            detailRow("Lead City", detail.lead?.city)
            detailRow("Preferred Area", detail.lead?.preferredArea)
        }
        .completedCard()
    }

    private func timelineCard(_ detail: CpVisitDetail) -> some View {
        let events: [(String, Int64?)] = [
            ("Created", detail.createdAt),
            ("Assigned", detail.assignedAt),
            ("Field visit started", detail.fieldVisit?.startedAt),
            ("OTP verified", detail.arrivalProof?.otpVerifiedAt),
            ("Client met", detail.clientMetAt),
            ("Completed", detail.completedAt)
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Timeline")
                .font(.system(size: 15, weight: .semibold))
            ForEach(events.filter { $0.1 != nil }, id: \.0) { event in
                HStack {
                    Text(event.0)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(formatEpoch(event.1))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .completedCard()
    }

    private func twoColumnRow(_ leftLabel: String, _ leftValue: String, _ rightLabel: String, _ rightValue: String) -> some View {
        HStack(spacing: 12) {
            detailColumn(leftLabel, leftValue)
            detailColumn(rightLabel, rightValue)
        }
    }

    private func detailColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value?.blankToNil ?? "-")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    @MainActor
    private func loadDetail(force: Bool = false) async {
        guard detail == nil || force else { return }
        guard !detailIds.isEmpty else { return }
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var lastError: Error?
        for id in detailIds {
            do {
                detail = try await MarketingConvexAPIService.getCpVisitDetail(token: token, id: id)
                return
            } catch {
                lastError = error
            }
        }
        if let lastError {
            let message = lastError.localizedDescription
            if !message.contains("404") {
                errorMessage = message
            }
        }
    }

    private var displayName: String {
        detail?.lead?.contactName?.blankToNil
            ?? detail?.lead?.manualProfile?.clientName?.blankToNil
            ?? detail?.client?.clientName?.blankToNil
            ?? detail?.clientPlace?.name?.blankToNil
            ?? summary.leadName?.blankToNil
            ?? summary.placeName?.blankToNil
            ?? "Client"
    }

    private var primaryPhone: String {
        detail?.client?.mobileNumber?.blankToNil
            ?? detail?.lead?.mobileNumber?.blankToNil
            ?? summary.leadPhone?.blankToNil
            ?? "-"
    }

    private var primaryAddress: String {
        [
            detail?.clientPlace?.address,
            detail?.clientPlace?.landmark,
            detail?.clientPlace?.city,
            detail?.clientPlace?.state,
            detail?.clientPlace?.pincode
        ]
        .compactMap { $0?.blankToNil }
        .joined(separator: ", ")
        .blankToNil
            ?? detail?.clientPlace?.formattedAddress?.blankToNil
            ?? summary.placeAddress?.blankToNil
            ?? "Address not mapped"
    }

    private var clientMetTitle: String {
        switch detail?.clientMet ?? summary.clientMet {
        case true: return "Client met"
        case false: return "Client not seen"
        default: return "Visit completed"
        }
    }

    private var clientMetIcon: String {
        (detail?.clientMet ?? summary.clientMet) == false ? "xmark.circle.fill" : "checkmark.seal.fill"
    }

    private var clientMetTint: Color {
        (detail?.clientMet ?? summary.clientMet) == false ? Color(hex: 0xB42318) : Color(hex: 0x1F7A3F)
    }

    private var outcomeTitle: String {
        switch (detail?.syntheticOutcome ?? summary.outcome ?? "").lowercased() {
        case "converted_to_booking": return "Converted to Booking"
        case "converted_to_site_visit": return "Converted to Site Visit"
        case "postponed": return "Postponed"
        case "not_interested": return "Not Interested"
        case "rejected": return "Rejected"
        case "interested": return "Interested"
        default: return "Completed"
        }
    }

    private var outcomeTint: Color {
        switch (detail?.syntheticOutcome ?? summary.outcome ?? "").lowercased() {
        case "postponed": return Color(hex: 0xB54708)
        case "not_interested", "rejected": return Color(hex: 0xB42318)
        default: return Color(hex: 0x0369A1)
        }
    }

    private var isBookingOutcome: Bool {
        (detail?.syntheticOutcome ?? summary.outcome ?? "").lowercased() == "converted_to_booking"
    }

    private var statusSubtitle: String {
        if let at = detail?.clientMetAt ?? summary.clientMetAt {
            return "Outcome recorded on \(formatEpoch(at))"
        }
        return "Outcome captured for this client visit"
    }

    private var formattedTime: String {
        let start = summary.scheduledStartTime?.blankToNil ?? detail?.scheduledTime?.blankToNil
        let end = summary.scheduledEndTime?.blankToNil
        if let start, let end { return "\(start) - \(end)" }
        return start ?? "-"
    }

    private var tripTypeTitle: String {
        switch summary.tripType.lowercased() {
        case "client_place": return "Client place"
        case "internal": return "Internal"
        case "": return "Client visit"
        default: return summary.tripType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var isGeoMapped: Bool {
        summary.placeLat != nil && summary.placeLng != nil
    }

    private func formattedDate(_ raw: String?) -> String {
        guard let raw = raw?.blankToNil else { return "-" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }

    private func formatEpoch(_ millis: Int64?) -> String {
        guard let millis, millis > 0 else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, hh:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(millis) / 1000))
    }

    private func gpsText(_ proof: CpVisitArrivalProof?) -> String {
        guard let lat = proof?.gpsLat, let lng = proof?.gpsLng else { return "-" }
        return String(format: "%.5f, %.5f", lat, lng)
    }

    private func distanceText(_ meters: Double?) -> String {
        guard let meters else { return "-" }
        if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
        return "\(Int(meters.rounded())) m"
    }

    private func durationText(_ minutes: Double?) -> String {
        guard let minutes else { return "-" }
        if minutes >= 60 {
            let hours = Int(minutes / 60)
            let mins = Int(minutes.rounded()) % 60
            return mins == 0 ? "\(hours) hr" : "\(hours) hr \(mins) min"
        }
        return "\(Int(minutes.rounded())) min"
    }

    private func parseNoteSections(_ notes: String) -> [CompletedNoteSection] {
        var sections: [CompletedNoteSection] = []
        var currentTitle = "Details"
        var currentRows: [CompletedNoteRow] = []

        func flush() {
            guard !currentRows.isEmpty else { return }
            sections.append(CompletedNoteSection(title: currentTitle, rows: currentRows))
            currentRows = []
        }

        for rawLine in notes.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush()
                currentTitle = String(line.dropFirst().dropLast())
                continue
            }
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                currentRows.append(CompletedNoteRow(label: parts[0], value: parts[1].trimmingCharacters(in: .whitespaces)))
            } else {
                currentRows.append(CompletedNoteRow(label: "Note", value: line))
            }
        }
        flush()
        if sections.isEmpty {
            return [CompletedNoteSection(title: "Details", rows: [CompletedNoteRow(label: "Notes", value: notes)])]
        }
        return sections
    }
}

private struct CompletedNoteSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [CompletedNoteRow]
}

private struct CompletedNoteRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct FlowChipRow: View {
    let items: [String]
    let tint: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(tint.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

private extension View {
    func completedCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.appSeparator, lineWidth: 1)
            )
    }
}

private struct CreateCpVisitSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    @State private var clientName = ""
    @State private var phone = ""
    @State private var date = Date()
    @State private var doorNo = ""
    @State private var street = ""
    @State private var addressLine1 = ""
    @State private var addressLine2 = ""
    @State private var pincode = ""
    @State private var village = ""
    @State private var taluk = ""
    @State private var district = ""
    @State private var city = ""
    @State private var locality = ""
    @State private var state = ""
    @State private var fullAddress = ""
    @State private var mapsLink = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var notes = ""
    @State private var selectedCpType: CpVisitCreateType?
    @State private var showCpTypePicker = false
    @State private var isJointCp = false
    @State private var selectedReferralSource: NewClientReferralSource?
    @State private var selectedReferringClient: ReferralClientCandidate?
    @State private var showReferringClientPicker = false
    @State private var bookingGatePhone: String?
    @State private var bookingGateCount = 0
    @State private var isCheckingBookingGate = false
    @State private var projects: [MarketingProject] = []
    @State private var selectedProject: MarketingProject?
    @State private var staff: [ConvexStaffListItem] = []
    @State private var selectedStaff: ConvexStaffListItem?
    // Joint CP only: the second staff. Cleared whenever the type moves away, so
    // a stale partner can never ride along on another CP type.
    @State private var selectedJointPartner: ConvexStaffListItem?
    @State private var showJointPartnerPicker = false
    @State private var selectedLmo: ConvexStaffListItem?
    @State private var leadMatches: [TelecallerLeadSearchData] = []
    @State private var selectedLead: TelecallerLeadSearchData?
    @State private var autofilledClientValues: [String: String] = [:]
    @State private var autofilledProjectId: String?
    @State private var autofilledLmoId: String?
    @State private var existingClientProfile: BookingClientProfile?
    @State private var existingClientPhone: String?
    @State private var showExistingClientWarning = false
    @State private var isLoadingProjects = false
    @State private var isLoadingStaff = false
    @State private var isSearchingLead = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showStaffPicker = false
    @State private var showLmoPicker = false
    @State private var showProjectPicker = false
    @State private var showMapPinPicker = false
    @State private var pinnedAddress: String?
    @State private var addressParseStatus: String?
    @State private var leadLookupTask: Task<Void, Never>?
    @State private var addressParseTask: Task<Void, Never>?
    @State private var lastParsedAddressLine1 = ""
    @State private var createRequestId = UUID().uuidString
    @State private var createRequestFingerprint: String?
    private let directionsClient = GeoTrackDirectionsClient()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("CP Creation")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 22)

                    Text("Information about CP")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)

                    jointCpToggle
                    cpTypePicker
                    if isNewClientCpPurpose {
                        referralSourcePicker
                        if selectedReferralSource == .clientReferral {
                            referringClientPicker
                        }
                    }

                    cpTextField("Client Phone Number *", placeholder: "Enter Client Number", text: $phone, systemImage: "phone", keyboard: .phonePad)
                        .onChange(of: phone) { oldValue, newValue in
                            guard AppModuleFormatters.normalizePhone(oldValue) != AppModuleFormatters.normalizePhone(newValue) else { return }
                            clearPreviousClientAutofill()
                            selectedLead = nil
                            leadMatches = []
                            if AppModuleFormatters.normalizePhone(newValue) != existingClientPhone {
                                existingClientProfile = nil
                                existingClientPhone = nil
                            }
                            bookingGatePhone = nil
                            bookingGateCount = 0
                            scheduleAutomaticLeadLookup(for: newValue)
                        }

                    cpTextField("Client Name *", placeholder: "Enter Client Name", text: $clientName, systemImage: "person")

                    Button {
                        Task { await searchLead() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSearchingLead {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            Text("Search existing client")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.appFieldBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSearchingLead || AppModuleFormatters.normalizePhone(phone).count != 10)
                    .opacity(AppModuleFormatters.normalizePhone(phone).count == 10 ? 1 : 0.55)
                    .padding(.top, 12)

                    if let selectedLead {
                        selectedInfo(title: "Selected client", value: selectedLead.displayName)
                            .padding(.top, 10)
                    }

                    ForEach(leadMatches) { lead in
                        Button {
                            applyLead(lead)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lead.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(lead.mobileNumber ?? "No mobile")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                if let area = lead.suggestedVisitAddress?.blankToNil ?? lead.locationPreferred?.blankToNil {
                                    Text(area)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.appSeparator, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }

                    staffPicker
                    lmoPicker
                    projectPicker
                    if isJointCp {
                        jointPartnerPicker
                    }
                    cpDatePicker

                    cpTextField("Door / Plot No", placeholder: "Enter Door / Plot No", text: $doorNo, systemImage: "house")
                    cpTextField("Street", placeholder: "Enter Street", text: $street, systemImage: "road.lanes")
                    cpTextField("Address Line 1 *", placeholder: "Enter Address", text: $addressLine1, systemImage: "mappin.and.ellipse", axis: .vertical)
                        .onChange(of: addressLine1) { _, value in
                            scheduleAddressParse(for: value)
                        }
                    if let addressParseStatus {
                        Text(addressParseStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    cpTextField("Landmark / Address Line 2", placeholder: "Enter Landmark", text: $addressLine2, systemImage: "signpost.right")
                    cpTextField("City *", placeholder: "Enter City", text: $city, systemImage: "building")
                    cpTextField("State", placeholder: "Enter State", text: $state, systemImage: "map.fill")
                    cpTextField("Pincode *", placeholder: "6 digits", text: $pincode, systemImage: "checkmark.circle", keyboard: .numberPad)

                    Button {
                        showMapPinPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
                                .frame(width: 40, height: 40)
                                .background(Color(hex: 0x0B61CA).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(latitude.blankToNil == nil ? "Drop location pin" : "Change location pin")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(pinnedAddress?.blankToNil ?? mapsLink.blankToNil ?? "Search or tap the map to set the client location")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color(hex: 0x98A2B3))
                        }
                        .padding(12)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)

                    cpTextField("Notes", placeholder: "Enter Notes", text: $notes, systemImage: "note.text", axis: .vertical)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 104)
            }

            VStack(spacing: 0) {
                Divider()
                    .overlay(Color.appSeparator)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.appSurface, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                    )

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Create visit")
                        }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(hex: 0x1BCA0B), in: Capsule())
                    .disabled(isSubmitting)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 20)
                .background(Color.appSurface)
            }
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .appCompactSheetCTAContainer()
        .disabled(isSubmitting)
        .alert("CP Visit", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Client already exists", isPresented: $showExistingClientWarning) {
            Button("Choose CP type") {
                DispatchQueue.main.async { showCpTypePicker = true }
            }
        } message: {
            Text("This number already exists as a client. Convert to another type of CP. The existing client details have been filled in.")
        }
        .confirmationDialog("Select CP type", isPresented: $showCpTypePicker, titleVisibility: .visible) {
            ForEach(CpVisitCreateType.allCases.filter {
                $0 != .jointCp
            }) { type in
                Button(type.title) {
                    Task { await selectCpType(type) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showStaffPicker) {
            NativeSearchableSelectionSheet(
                title: "Select Staff",
                prompt: "Search staff",
                items: staff,
                selectedId: selectedStaff?.id,
                searchText: { item in
                    [item.displayName, item.iamTemplateName, item.designation, item.phone].compactMap(\.self).joined(separator: " ")
                },
                rowContent: { item, isSelected in
                    staffSelectionRow(item, isSelected: isSelected)
                },
                onSelect: { item in
                    selectedStaff = item
                    if let partner = selectedJointPartner,
                       jointTemplateValidationError(primary: item, partner: partner) != nil {
                        selectedJointPartner = nil
                    }
                    showStaffPicker = false
                }
            )
            .appLibraryNativeSheet([.medium, .large])
        }
        .sheet(isPresented: $showJointPartnerPicker) {
            NativeSearchableSelectionSheet(
                title: "Select the second staff",
                prompt: "Search staff",
                items: eligibleJointPartners,
                selectedId: selectedJointPartner?.id,
                searchText: { item in
                    [item.displayName, item.designation, item.phone].compactMap(\.self).joined(separator: " ")
                },
                rowContent: { item, isSelected in
                    staffSelectionRow(item, isSelected: isSelected)
                },
                onSelect: { item in
                    selectedJointPartner = item
                    showJointPartnerPicker = false
                }
            )
            .appLibraryNativeSheet([.medium, .large])
        }
        .sheet(isPresented: $showProjectPicker) {
            NativeSearchableSelectionSheet(
                title: "Select Project",
                prompt: "Search projects",
                items: projects,
                selectedId: selectedProject?.id,
                searchText: { project in
                    [project.name, project.location].compactMap(\.self).joined(separator: " ")
                },
                rowContent: { project, isSelected in
                    projectSelectionRow(project, isSelected: isSelected)
                },
                onSelect: { project in
                    selectedProject = project
                    showProjectPicker = false
                }
            )
            .appLibraryNativeSheet([.medium, .large])
        }
        .sheet(isPresented: $showLmoPicker) {
            NativeSearchableSelectionSheet(
                title: "Select LMO / Channel Partner / BDO",
                prompt: "Search eligible staff",
                items: eligibleLmoStaff,
                selectedId: selectedLmo?.id,
                searchText: { item in
                    [item.displayName, item.designation, item.department, item.phone]
                        .compactMap(\.self)
                        .joined(separator: " ")
                },
                rowContent: { item, isSelected in
                    staffSelectionRow(item, isSelected: isSelected)
                },
                onSelect: { item in
                    selectedLmo = item
                    showLmoPicker = false
                }
            )
            .appLibraryNativeSheet([.medium, .large])
        }
        .sheet(isPresented: $showMapPinPicker) {
            CpMapPinPicker(
                initialCoordinate: selectedCoordinate,
                initialAddress: pinnedAddress ?? addressLine1.blankToNil
            ) { result in
                latitude = String(result.latitude)
                longitude = String(result.longitude)
                mapsLink = result.googleMapsLink
                pinnedAddress = result.address
                doorNo = ""
                street = ""
                addressLine2 = ""
                city = ""
                state = ""
                pincode = ""
                lastParsedAddressLine1 = ""
                addressLine1 = result.address
                showMapPinPicker = false
            }
            .appLibraryNativeSheet([.large])
        }
        .sheet(isPresented: $showReferringClientPicker) {
            if let token = authStore.currentSession?.token {
                ReferralClientPickerSheet(
                    token: token,
                    excludingPhone: AppModuleFormatters.normalizePhone(phone),
                    selectedId: selectedReferringClient?.id
                ) { client in
                    selectedReferringClient = client
                    showReferringClientPicker = false
                }
                .appLibraryNativeSheet([.medium, .large])
            }
        }
        .task { await loadBootstrapData() }
        // The lead lookup can resolve before the staff list finishes loading,
        // which would leave the LMO unfilled even though the lead has an
        // owner. Retry the prefill once the list arrives.
        .onChange(of: staff) { _, _ in
            if let selectedLead { prefillLmoFromLead(selectedLead) }
        }
        .onDisappear {
            leadLookupTask?.cancel()
            addressParseTask?.cancel()
        }
    }

    private func selectedInfo(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(12)
        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func cpTextField(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        systemImage: String,
        keyboard: UIKeyboardType = .default,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            HStack(alignment: axis == .vertical ? .top : .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .padding(.top, axis == .vertical ? 3 : 0)
                TextField(placeholder, text: text, axis: axis)
                    .font(.system(size: 14, weight: .medium))
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .URL ? .never : .words)
                    .autocorrectionDisabled(keyboard == .URL)
                    .lineLimit(axis == .vertical ? 3...5 : 1...1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, axis == .vertical ? 10 : 0)
            .frame(minHeight: axis == .vertical ? 72 : 50, alignment: axis == .vertical ? .top : .center)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
            )
        }
        .padding(.top, 16)
    }

    private var staffPicker: some View {
        pickerShell(title: "Field Staff *", icon: "person.badge.key") {
            Button {
                showStaffPicker = true
            } label: {
                pickerLabel(selectedStaff?.displayName ?? "Select Staff")
            }
            .buttonStyle(.plain)
            .disabled(isLoadingStaff || staff.isEmpty)
        }
    }

    /// Second participant, shown only for a Joint CP. Excludes whoever is
    /// already the field staff — the same person twice is not a joint visit and
    /// the server requires two different active staff.
    private var jointPartnerPicker: some View {
        pickerShell(title: "Joint CP Partner *", icon: "person.2") {
            Button {
                showJointPartnerPicker = true
            } label: {
                pickerLabel(selectedJointPartner?.displayName ?? "Select the second staff")
            }
            .buttonStyle(.plain)
            .disabled(isLoadingStaff || staff.isEmpty)
        }
    }

    private var projectPicker: some View {
        pickerShell(title: "Project *", icon: "building.2") {
            Button {
                showProjectPicker = true
            } label: {
                pickerLabel(selectedProject?.name ?? selectedProject?.location ?? "Select Projects")
            }
            .buttonStyle(.plain)
            .disabled(isLoadingProjects || projects.isEmpty)
        }
    }

    private var lmoPicker: some View {
        pickerShell(title: "LMO / Channel Partner / BDO *", icon: "person.2.badge.gearshape") {
            Button {
                showLmoPicker = true
            } label: {
                pickerLabel(selectedLmo?.displayName ?? "Select LMO / CP / BDO")
            }
            .buttonStyle(.plain)
            .disabled(isLoadingStaff || eligibleLmoStaff.isEmpty)
        }
    }

    private var eligibleLmoStaff: [ConvexStaffListItem] {
        staff.filter { item in
            guard (item.status ?? "active").caseInsensitiveCompare("active") == .orderedSame else { return false }
            let department = (item.department ?? "").lowercased()
            let designation = (item.designation ?? "").lowercased()
            let telesalesLmo = department.contains("telesales")
                && (designation == "lmo" || designation.contains("lead management executive") || designation.contains("telecaller"))
            let channelPartner = department.contains("channel partner")
            let salesMarketingBdo = department.contains("sales") && department.contains("marketing")
                && (designation == "bdo" || designation.contains("business development officer") || designation.contains("business development executive"))
            return telesalesLmo || channelPartner || salesMarketingBdo
        }
    }

    private func staffSelectionRow(_ item: ConvexStaffListItem, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                if let designation = item.designation, !designation.isEmpty {
                    Text(designation)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }
        }
        .padding(.vertical, 4)
    }

    private func projectSelectionRow(_ project: MarketingProject, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name ?? project.location ?? "Unnamed project")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                if let location = project.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }
        }
        .padding(.vertical, 4)
    }

    private var cpTypePicker: some View {
        pickerShell(title: "CP Type *", icon: "tag") {
            Button {
                showCpTypePicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCpType?.title ?? "Select CP type")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selectedCpType == nil ? Color(hex: 0x9CA3AF) : Color(hex: 0x101828))
                            .lineLimit(1)
                        // Was "Optional" - it is not, and the server now
                        // rejects an untyped CP.
                        Text(selectedCpType?.subtitle ?? "Required")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isCheckingBookingGate {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
        }
    }

    private var jointCpToggle: some View {
        Toggle(isOn: $isJointCp) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Joint CP")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add a second staff to this visit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .tint(Color(hex: 0x0B61CA))
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appSeparator, lineWidth: 1)
        )
        .padding(.top, 12)
        .onChange(of: isJointCp) { _, enabled in
            if !enabled {
                selectedJointPartner = nil
            }
        }
    }

    /// Template identity is admin-owned and is the only valid way to compare
    /// Joint CP levels. Displayed designation text is deliberately ignored.
    private var eligibleJointPartners: [ConvexStaffListItem] {
        guard let primary = selectedStaff else { return [] }
        return staff.filter { jointTemplateValidationError(primary: primary, partner: $0) == nil }
    }

    private func jointTemplateValidationError(
        primary: ConvexStaffListItem?,
        partner: ConvexStaffListItem?
    ) -> String? {
        guard let primary, let partner else {
            return "Select both staff for this Joint CP"
        }
        guard primary.id != partner.id else {
            return "Pick two different staff for a Joint CP"
        }
        guard let firstTemplate = primary.iamTemplateId?.nonBlank,
              let secondTemplate = partner.iamTemplateId?.nonBlank
        else {
            return "Both staff need an IAM template before creating a Joint CP"
        }
        guard firstTemplate != secondTemplate else {
            let label = primary.iamTemplateName?.nonBlank
                ?? partner.iamTemplateName?.nonBlank
                ?? "the same IAM template"
            return "Joint CP partners cannot both use \(label)"
        }
        guard let firstLevel = primary.iamTemplateLevel,
              let secondLevel = partner.iamTemplateLevel else {
            return "Both IAM templates need a Joint CP level"
        }
        guard firstLevel != secondLevel else {
            return "Joint CP partners cannot be on the same IAM template level"
        }
        let roles = Set([
            primary.jointCpWorkflowRole?.lowercased(),
            partner.jointCpWorkflowRole?.lowercased()
        ].compactMap { $0?.nonBlank })
        guard roles == Set(["outcome_owner", "reviewer"]) else {
            return "Choose one BDO outcome owner and one reviewer from their IAM templates"
        }
        return nil
    }

    private var referralSourcePicker: some View {
        pickerShell(title: "Referral Source *", icon: "person.2") {
            Menu {
                ForEach(NewClientReferralSource.allCases) { source in
                    Button {
                        selectedReferralSource = source
                        if source != .clientReferral {
                            selectedReferringClient = nil
                        }
                    } label: {
                        Label(
                            source.title,
                            systemImage: selectedReferralSource == source ? "checkmark" : "circle"
                        )
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedReferralSource?.title ?? "Select referral source")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selectedReferralSource == nil ? Color(hex: 0x9CA3AF) : Color(hex: 0x101828))
                        Text(selectedReferralSource?.subtitle ?? "Required")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var referringClientPicker: some View {
        pickerShell(title: "Referring Client *", icon: "person.text.rectangle") {
            Button {
                showReferringClientPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedReferringClient?.name ?? "Search client by name or mobile")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selectedReferringClient == nil ? Color(hex: 0x9CA3AF) : Color(hex: 0x101828))
                            .lineLimit(1)
                        Text(selectedReferringClient?.mobileNumber ?? "Existing clients only")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func pickerShell<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                content()
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
            )
        }
        .padding(.top, 16)
    }

    private func pickerLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(text.lowercased().hasPrefix("select") ? Color(hex: 0x9CA3AF) : Color(hex: 0x101828))
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var cpDatePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date & Time")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
            )
        }
        .padding(.top, 16)
    }

    private var selectedCoordinate: CLLocationCoordinate2D? {
        guard let lat = coordinateValue(latitude), let lng = coordinateValue(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    @MainActor
    private func loadBootstrapData() async {
        guard let token = authStore.currentSession?.token else { return }
        async let projectsTask: Void = loadProjects(token: token)
        async let staffTask: Void = loadStaff(token: token)
        _ = await (projectsTask, staffTask)
    }

    @MainActor
    private func loadProjects(token: String) async {
        guard projects.isEmpty, !isLoadingProjects else { return }
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        do {
            projects = try await MarketingConvexAPIService.getMarketingProjects(token: token)
                .filter { ($0.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("ongoing") == .orderedSame }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadStaff(token: String) async {
        guard staff.isEmpty, !isLoadingStaff else { return }
        isLoadingStaff = true
        defer { isLoadingStaff = false }
        do {
            let allStaff = try await HRConvexAPIService.listAllStaff(token: token, status: "active")
            staff = allStaff.filter { ($0.status ?? "active").lowercased() != "inactive" }
            let sessionStaffId = authStore.currentSession?.user.staffId ?? authStore.currentSession?.user._id
            if selectedStaff == nil, let sessionStaffId {
                selectedStaff = staff.first { $0.id == sessionStaffId }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func searchLead() async {
        let normalizedPhone = AppModuleFormatters.normalizePhone(phone)
        guard normalizedPhone.count == 10 else {
            errorMessage = "Enter 10 digit phone"
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        isSearchingLead = true
        defer { isSearchingLead = false }
        do {
            let matches = try await MarketingConvexAPIService.searchTelecallerLeadsByPhone(token: token, phone: normalizedPhone)
            guard !Task.isCancelled, !isSubmitting,
                  AppModuleFormatters.normalizePhone(phone) == normalizedPhone else { return }
            leadMatches = matches.filter { AppModuleFormatters.normalizePhone($0.mobileNumber ?? "") == normalizedPhone }
            if leadMatches.count == 1, let lead = leadMatches.first {
                applyLead(lead)
            } else if leadMatches.isEmpty {
                errorMessage = "No existing client found. You can create with manual details."
            }
        } catch {
            guard !Task.isCancelled, !isSubmitting,
                  AppModuleFormatters.normalizePhone(phone) == normalizedPhone else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func scheduleAutomaticLeadLookup(for rawPhone: String) {
        leadLookupTask?.cancel()
        let normalized = AppModuleFormatters.normalizePhone(rawPhone)
        guard normalized.count == 10 else { return }
        leadLookupTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await automaticLeadLookup(phone: normalized)
        }
    }

    @MainActor
    private func automaticLeadLookup(phone normalizedPhone: String) async {
        guard let token = authStore.currentSession?.token else { return }
        isSearchingLead = true
        defer { isSearchingLead = false }
        async let leadSearch = MarketingConvexAPIService.searchTelecallerLeadsByPhone(
            token: token,
            phone: normalizedPhone
        )
        async let clientSearch = MarketingConvexAPIService.searchClientByPhone(
            token: token,
            phone: normalizedPhone
        )
        let matches = (try? await leadSearch) ?? []
        let existingClient = try? await clientSearch
        guard !Task.isCancelled, !isSubmitting,
              AppModuleFormatters.normalizePhone(phone) == normalizedPhone else { return }
        leadMatches = matches.filter { AppModuleFormatters.normalizePhone($0.mobileNumber ?? "") == normalizedPhone }
        if leadMatches.count == 1, let first = leadMatches.first {
            applyLead(first)
        }
        if let existingClient {
            applyExistingClient(existingClient, phone: normalizedPhone)
            if isNewClientCpPurpose {
                blockNewClientCpForExistingClient()
            }
        }
    }

    @MainActor
    private func scheduleAddressParse(for rawAddress: String) {
        addressParseTask?.cancel()
        let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 25, trimmed != lastParsedAddressLine1 else {
            addressParseStatus = nil
            return
        }
        addressParseTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await parseAddress(trimmed)
        }
    }

    @MainActor
    private func parseAddress(_ rawAddress: String) async {
        guard let token = authStore.currentSession?.token,
              addressLine1.trimmingCharacters(in: .whitespacesAndNewlines) == rawAddress
        else { return }
        lastParsedAddressLine1 = rawAddress
        addressParseStatus = "Splitting address…"
        do {
            let fields = try await MarketingConvexAPIService.parseAddress(token: token, raw: rawAddress)
            guard !Task.isCancelled, !isSubmitting,
                  addressLine1.trimmingCharacters(in: .whitespacesAndNewlines) == rawAddress else { return }
            let tracksClientAutofill = autofilledClientValues["address1"] == rawAddress
            let before = clientAutofillFields.mapValues { $0.wrappedValue }
            defer {
                if tracksClientAutofill { rememberClientAutofill(before: before) }
            }
            fillIfBlank($doorNo, fields.doorNo)
            fillIfBlank($street, fields.street)
            if let parsedLine1 = fields.addressLine1?.blankToNil, parsedLine1 != rawAddress {
                lastParsedAddressLine1 = parsedLine1
                addressLine1 = parsedLine1
            }
            fillIfBlank($addressLine2, fields.addressLine2)
            fillIfBlank($city, fields.city)
            fillIfBlank($state, fields.state)
            fillIfBlank($pincode, fields.pincode)
            addressParseStatus = "Address auto-filled"
        } catch {
            addressParseStatus = "Could not split address"
        }
    }

    @MainActor
    /// Fill the LMO field from the lead's assigned staff, matching the web
    /// form. Never overwrites a choice the user already made, and only accepts
    /// staff who pass the same eligibility rule as the picker — an ineligible
    /// or missing owner leaves the field empty so the required check still
    /// asks the user to pick one.
    private func prefillLmoFromLead(_ lead: TelecallerLeadSearchData) {
        guard selectedLmo == nil,
              let ownerId = lead.assignedToStaffId?.blankToNil,
              let owner = eligibleLmoStaff.first(where: { $0.id == ownerId })
        else { return }
        selectedLmo = owner
        autofilledLmoId = owner.id
    }

    private func applyLead(_ lead: TelecallerLeadSearchData) {
        guard !isSubmitting,
              AppModuleFormatters.normalizePhone(lead.mobileNumber ?? "") == AppModuleFormatters.normalizePhone(phone) else { return }
        let before = clientAutofillFields.mapValues { $0.wrappedValue }
        defer { rememberClientAutofill(before: before) }
        selectedLead = lead
        fillIfBlank($clientName, lead.latestAnalysisProfile?.clientName?.blankToNil ?? lead.contactName?.blankToNil)
        prefillLmoFromLead(lead)

        let analysis = lead.latestAnalysisProfile
        let place = lead.clientPlaceProfile
        let manual = lead.manualProfile
        let fallbackAddress = lead.suggestedVisitAddress?.blankToNil ?? lead.locationPreferred?.blankToNil
        let fallbackPincode = fallbackAddress.flatMap { Self.firstSixDigitPincode(in: $0) }

        fillIfBlank($doorNo, place?.doorNo ?? analysis?.doorNo ?? manual?.doorNo)
        fillIfBlank($street, place?.street ?? analysis?.street ?? manual?.street)
        fillIfBlank($addressLine1, analysis?.address ?? place?.address ?? place?.formattedAddress ?? manual?.address ?? fallbackAddress)
        fillIfBlank($addressLine2, place?.landmark ?? analysis?.landmark ?? manual?.landmark)
        fillIfBlank($city, place?.city ?? lead.clientCity)
        fillIfBlank($state, place?.state ?? analysis?.state ?? manual?.state)
        fillIfBlank($pincode, place?.pincode ?? analysis?.pincode ?? manual?.pincode ?? fallbackPincode)

        if latitude.blankToNil == nil, let lat = lead.suggestedVisitLat {
            latitude = String(lat)
        }
        if longitude.blankToNil == nil, let lng = lead.suggestedVisitLng {
            longitude = String(lng)
        }
        fillIfBlank($mapsLink, lead.suggestedGoogleMapsLink)

        if selectedProject == nil, let projectId = lead.projectId?.blankToNil {
            selectedProject = projects.first { $0.id == projectId }
            autofilledProjectId = selectedProject?.id
        }

        leadMatches = []
    }

    private func applyExistingClient(_ client: BookingClientProfile, phone normalizedPhone: String) {
        guard AppModuleFormatters.normalizePhone(phone) == normalizedPhone,
              AppModuleFormatters.normalizePhone(client.mobileNumber ?? normalizedPhone) == normalizedPhone else { return }
        let before = clientAutofillFields.mapValues { $0.wrappedValue }
        defer { rememberClientAutofill(before: before) }
        fillIfBlank($clientName, client.clientName)
        fillIfBlank($doorNo, client.doorNo)
        fillIfBlank($street, client.streetName)
        fillIfBlank($addressLine1, client.addressLine1 ?? client.homeAddress ?? client.formattedAddress)
        fillIfBlank($addressLine2, client.addressLine2 ?? client.landmark)
        fillIfBlank($city, client.district ?? client.location)
        fillIfBlank($state, client.state)
        fillIfBlank($pincode, client.pincode)
        fillIfBlank($mapsLink, client.googleMapsLink)
        if latitude.blankToNil == nil, let lat = client.lat { latitude = String(lat) }
        if longitude.blankToNil == nil, let lng = client.lng { longitude = String(lng) }
        existingClientProfile = client
        existingClientPhone = normalizedPhone
    }

    private var clientAutofillFields: [String: Binding<String>] {
        ["name": $clientName, "door": $doorNo, "street": $street,
         "address1": $addressLine1, "address2": $addressLine2, "city": $city,
         "state": $state, "pincode": $pincode, "maps": $mapsLink,
         "latitude": $latitude, "longitude": $longitude]
    }

    private func rememberClientAutofill(before: [String: String]) {
        for (key, field) in clientAutofillFields where before[key] != field.wrappedValue {
            autofilledClientValues[key] = field.wrappedValue
        }
    }

    private func clearPreviousClientAutofill() {
        addressParseTask?.cancel()
        addressParseStatus = nil
        lastParsedAddressLine1 = ""
        for (key, value) in autofilledClientValues {
            if let field = clientAutofillFields[key], field.wrappedValue == value {
                field.wrappedValue = ""
            }
        }
        autofilledClientValues = [:]
        if let id = autofilledProjectId, selectedProject?.id == id { selectedProject = nil }
        if let id = autofilledLmoId, selectedLmo?.id == id { selectedLmo = nil }
        autofilledProjectId = nil
        autofilledLmoId = nil
    }

    private var hasCurrentExistingClient: Bool {
        existingClientProfile != nil &&
            existingClientPhone == AppModuleFormatters.normalizePhone(phone)
    }

    private func blockNewClientCpForExistingClient() {
        guard existingClientProfile != nil else { return }
        selectedCpType = nil
        selectedReferralSource = nil
        selectedReferringClient = nil
        showExistingClientWarning = true
    }

    private func fillIfBlank(_ binding: Binding<String>, _ value: String?) {
        guard let value = value?.blankToNil else { return }
        if binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            binding.wrappedValue = value
        }
    }

    @MainActor
    private func selectCpType(_ type: CpVisitCreateType) async {
        guard type != .jointCp else { return }
        if type == .newClientCp, hasCurrentExistingClient {
            blockNewClientCpForExistingClient()
            return
        }
        if !type.requiresConfirmedBooking {
            selectedCpType = type
            clearReferralSourceIfNeeded()
            return
        }
        let normalizedPhone = AppModuleFormatters.normalizePhone(phone)
        guard normalizedPhone.count == 10 else {
            errorMessage = "Enter the client's 10-digit mobile first, then pick \(type.title)."
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        isCheckingBookingGate = true
        defer { isCheckingBookingGate = false }
        do {
            let cases = try await PostSalesConvexAPIService.getCasesByMobile(token: token, mobile: normalizedPhone)
            bookingGatePhone = normalizedPhone
            bookingGateCount = cases.count
            guard !cases.isEmpty else {
                errorMessage = "\(type.title) blocked. This client has no confirmed booking."
                return
            }
            selectedCpType = type
            clearReferralSourceIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        guard !isSubmitting else { return }
        leadLookupTask?.cancel()
        addressParseTask?.cancel()
        isSubmitting = true
        defer { isSubmitting = false }
        let normalizedPhone = AppModuleFormatters.normalizePhone(phone)
        // Must be a real mobile: the arrival OTP is sent here, so a landline
        // would make the CP impossible to complete. Matches the server rule so
        // the rejection surfaces in the form rather than on submit.
        guard normalizedPhone.count == 10,
              let firstDigit = normalizedPhone.first,
              ("6"..."9").contains(String(firstDigit))
        else {
            errorMessage = "Enter a valid 10-digit mobile number"
            return
        }
        let trimmedClientName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientName.isEmpty else { errorMessage = "Client name is required"; return }
        // A "name" that is really the number is how nameless clients reach the
        // Clients tab.
        guard AppModuleFormatters.normalizePhone(trimmedClientName) != normalizedPhone,
              trimmedClientName.contains(where: { $0.isLetter })
        else {
            errorMessage = "Enter the client's name, not their number"
            return
        }
        let staffId = selectedStaff?.id ?? authStore.currentSession?.user.staffId ?? authStore.currentSession?.user._id
        guard let staffId, !staffId.isEmpty else { errorMessage = "Staff session missing"; return }
        guard selectedProject != nil else { errorMessage = "Project is required"; return }
        // CP Type drives the whole post-arrival branch in the trip flow, and an
        // untyped CP shows as a bare dash in every list.
        guard let selectedCpType else { errorMessage = "Select the CP type"; return }
        if isNewClientCpPurpose {
            guard let selectedReferralSource else {
                errorMessage = "Select Own Referral or Client Referral"
                return
            }
            if selectedReferralSource == .clientReferral {
                guard let selectedReferringClient else {
                    errorMessage = "Select the referring client"
                    return
                }
                guard AppModuleFormatters.normalizePhone(selectedReferringClient.mobileNumber) != normalizedPhone else {
                    errorMessage = "A client cannot refer themselves"
                    return
                }
            }
        }
        // A Joint CP is meaningless with one person on it, and the server
        // requires exactly two different active staff.
        if isJointCp {
            if let validationError = jointTemplateValidationError(
                primary: selectedStaff,
                partner: selectedJointPartner
            ) {
                errorMessage = validationError
                return
            }
        }
        let jointParticipantIds: [String]?
        if isJointCp, let primaryId = selectedStaff?.id, let partnerId = selectedJointPartner?.id {
            jointParticipantIds = [primaryId, partnerId]
        } else {
            jointParticipantIds = nil
        }
        guard selectedStaff != nil || !(staffId.isEmpty) else { errorMessage = "Field staff is required"; return }
        guard let lmoStaffId = selectedLmo?.id.nilIfEmpty else {
            errorMessage = "Select the LMO, Channel Partner, or BDO"
            return
        }
        let trimmedAddress = composedAddress
        guard !addressLine1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Address Line 1 is required"
            return
        }
        guard !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "City is required"
            return
        }
        let normalizedPincode = pincode.filter(\.isNumber)
        // No Indian pincode starts with 0, and the server rejects one that
        // does.
        guard normalizedPincode.count == 6, normalizedPincode.first != "0" else {
            errorMessage = "Enter a valid 6-digit pincode"
            return
        }
        guard !trimmedAddress.isEmpty else { errorMessage = "Address is required"; return }
        if let lat = coordinateValue(latitude), !(lat >= -90 && lat <= 90) {
            errorMessage = "Latitude must be between -90 and 90"
            return
        }
        if let lng = coordinateValue(longitude), !(lng >= -180 && lng <= 180) {
            errorMessage = "Longitude must be between -180 and 180"
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        if isNewClientCpPurpose && createRequestFingerprint == nil {
            do {
                if let existing = try await MarketingConvexAPIService.searchClientByPhone(
                    token: token,
                    phone: normalizedPhone
                ) {
                    applyExistingClient(existing, phone: normalizedPhone)
                    blockNewClientCpForExistingClient()
                    return
                }
            } catch {
                errorMessage = "Couldn't verify whether this client already exists. \(error.localizedDescription)"
                return
            }
        }
        let effectiveCpPurpose = selectedCpType
        if effectiveCpPurpose.requiresConfirmedBooking {
            let cachedPhone = bookingGatePhone ?? ""
            if cachedPhone != normalizedPhone || bookingGateCount == 0 {
                errorMessage = "\(effectiveCpPurpose.title) needs a confirmed booking for this mobile. Re-pick the CP type to verify."
                return
            }
        }

        let scheduledDate = AppModuleFormatters.ymd.string(from: date)
        var resolvedLatitude = coordinateValue(latitude)
        var resolvedLongitude = coordinateValue(longitude)
        if resolvedLatitude == nil || resolvedLongitude == nil {
            let plainAddress = [doorNo, street, addressLine1, addressLine2, city, state, normalizedPincode]
                .compactMap(\.blankToNil)
                .joined(separator: ", ")
            guard let geocode = await directionsClient.geocodeAddress(plainAddress) else {
                errorMessage = "Couldn't locate this address on the map. Drop a pin to set the exact client location."
                showMapPinPicker = true
                return
            }
            resolvedLatitude = geocode.coordinate.latitude
            resolvedLongitude = geocode.coordinate.longitude
        }

        let request = CreateCpVisitRequest(
            leadId: selectedLead.flatMap {
                AppModuleFormatters.normalizePhone($0.mobileNumber ?? "") == normalizedPhone ? $0.id : nil
            },
            projectId: selectedProject?.id,
            clientName: trimmedClientName,
            mobileNumber: normalizedPhone,
            assignedStaffId: staffId,
            lmoStaffId: lmoStaffId,
            scheduledDate: scheduledDate,
            scheduledTime: Self.timeFormatter.string(from: date),
            cpType: isJointCp ? CpVisitCreateType.jointCp.rawValue : selectedCpType.rawValue,
            jointCpCategory: isJointCp ? selectedCpType.rawValue : nil,
            referralSourceType: isNewClientCpPurpose ? selectedReferralSource?.rawValue : nil,
            referringClientId: isNewClientCpPurpose && selectedReferralSource == .clientReferral
                ? selectedReferringClient?.id
                : nil,
            visitAddress: trimmedAddress,
            visitLat: resolvedLatitude,
            visitLng: resolvedLongitude,
            googleMapsLink: mapsLink.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: serializedNotes,
            pincode: normalizedPincode,
            // The server requires both unique participants and resolves owner
            // versus reviewer from their effective IAM template snapshots.
            jointStaffIds: jointParticipantIds
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let fingerprint = try encoder.encode(request).base64EncodedString()
            if createRequestFingerprint != fingerprint {
                createRequestId = UUID().uuidString
                createRequestFingerprint = fingerprint
            }
            // Replay of this exact request is not a second CP. The server still
            // enforces uniqueness and idempotency for concurrent creators.
            if let existingVisits = try? await MarketingConvexAPIService.getMyMarketingCpVisits(
                token: token, fromDate: scheduledDate, toDate: scheduledDate,
                scope: "all", limit: 50, search: normalizedPhone
            ) {
                let duplicate = existingVisits.contains { visit in
                    let visitPhone = AppModuleFormatters.normalizePhone(
                        visit.lead?.mobileNumber ?? visit.client?.mobileNumber ?? ""
                    )
                    return visit.scheduledDate == scheduledDate
                        && visitPhone == normalizedPhone
                        && visit.status?.lowercased() != "cancelled"
                        && visit.requestId != createRequestId
                }
                if duplicate {
                    errorMessage = "This client already has a CP visit on \(scheduledDate). Only one CP visit per client is allowed per day. Open the existing visit or choose another date."
                    return
                }
            }
            try Task.checkCancellation()
            let response = try await MarketingConvexAPIService.createCpVisit(
                token: token,
                request: request,
                idempotencyKey: createRequestId
            )
            guard let createdId = response.resolvedId else {
                throw MarketingAPIError.server("The server did not return the created CP. Please retry.")
            }
            guard response.requestId == createRequestId else {
                throw MarketingAPIError.server(
                    "The server did not confirm the created CP. Tap Create visit again to resume safely."
                )
            }
            let expectedType = isJointCp ? CpVisitCreateType.jointCp.rawValue : selectedCpType.rawValue
            let expectedJointCategory = isJointCp ? selectedCpType.rawValue : nil
            switch await verifyCreatedCpType(
                token: token,
                visitId: createdId,
                expectedType: expectedType,
                expectedJointCategory: expectedJointCategory,
                response: response
            ) {
            case .confirmed:
                break
            case .mismatch:
                throw MarketingAPIError.server(
                    "CP was created, but the server did not retain its selected type. Admin repair is required."
                )
            case .unavailable:
                throw MarketingAPIError.server(
                    "CP was created, but its type could not be confirmed from the server. Refresh before continuing."
                )
            }
            createRequestId = UUID().uuidString
            createRequestFingerprint = nil
            onCreated()
        } catch MarketingAPIError.newClientAlreadyExists(let client, _) {
            applyExistingClient(client, phone: normalizedPhone)
            blockNewClientCpForExistingClient()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum CpTypeVerification {
        case confirmed
        case mismatch
        case unavailable
    }

    private func verifyCreatedCpType(
        token: String,
        visitId: String,
        expectedType: String,
        expectedJointCategory: String?,
        response: CreateCpVisitResponse
    ) async -> CpTypeVerification {
        if persistedTypeMatches(
            cpType: response.cpType,
            jointCpCategory: response.jointCpCategory,
            expectedType: expectedType,
            expectedJointCategory: expectedJointCategory
        ) { return .confirmed }
        for attempt in 0..<3 {
            if let visit = try? await MarketingConvexAPIService.getCpVisitDetail(token: token, id: visitId) {
                return persistedTypeMatches(
                    cpType: visit.cpType,
                    jointCpCategory: visit.jointCpCategory,
                    expectedType: expectedType,
                    expectedJointCategory: expectedJointCategory
                ) ? .confirmed : .mismatch
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
            }
        }
        guard response.cpType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .unavailable
        }
        return persistedTypeMatches(
            cpType: response.cpType,
            jointCpCategory: response.jointCpCategory,
            expectedType: expectedType,
            expectedJointCategory: expectedJointCategory
        ) ? .confirmed : .mismatch
    }

    private func persistedTypeMatches(
        cpType: String?,
        jointCpCategory: String?,
        expectedType: String,
        expectedJointCategory: String?
    ) -> Bool {
        guard cpType?.trimmingCharacters(in: .whitespacesAndNewlines) == expectedType else { return false }
        guard expectedType == CpVisitCreateType.jointCp.rawValue else { return true }
        return jointCpCategory?.trimmingCharacters(in: .whitespacesAndNewlines) == expectedJointCategory
    }

    private var isNewClientCpPurpose: Bool {
        selectedCpType == .newClientCp
    }

    private func clearReferralSourceIfNeeded() {
        guard !isNewClientCpPurpose else { return }
        selectedReferralSource = nil
        selectedReferringClient = nil
    }

    private var composedAddress: String {
        return [
            doorNo.blankToNil.map { "Door/Plot No: \($0)" },
            street.blankToNil.map { "Street: \($0)" },
            addressLine1.blankToNil.map { "Address: \($0)" },
            addressLine2.blankToNil.map { "Landmark: \($0)" },
            city.blankToNil.map { "City: \($0)" },
            state.blankToNil.map { "State: \($0)" },
            pincode.filter(\.isNumber).blankToNil.map { "Pincode: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private var serializedNotes: String? {
        let pairs: [(String, String?)] = [
            ("notes", notes.blankToNil),
            ("door_no", doorNo.blankToNil),
            ("street", street.blankToNil),
            ("address_line_1", addressLine1.blankToNil),
            ("address_line_2", addressLine2.blankToNil),
            ("city", city.blankToNil),
            ("state", state.blankToNil),
            ("pincode", pincode.filter(\.isNumber).blankToNil),
            ("google_map_link", mapsLink.blankToNil),
            ("latitude", latitude.blankToNil),
            ("longitude", longitude.blankToNil),
            ("field_staff", selectedStaff?.displayName)
        ]
        let lines = pairs.compactMap { key, value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func coordinateValue(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func firstSixDigitPincode(in text: String) -> String? {
        guard let range = text.range(of: #"\b\d{6}\b"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var blankToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedMarker: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    var isInProgress: Bool {
        [
            "picked_up", "on_site", "dropped", "in-progress", "in_progress",
            "client_started", "ongoing", "started", "active", "arrived",
            "arrival_verified", "arrival-verified", "on-site", "reaching"
        ].contains(self)
    }

    var isCompleted: Bool {
        ["completed", "complete", "done", "closed"].contains(self)
    }

    var isCancelled: Bool {
        ["cancelled", "canceled", "no_show"].contains(self)
    }
}

private extension String {
    var cpClientName: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let digits = value.filter(\.isNumber)
        let nameCharacters = value.filter { $0.isLetter }
        guard !(digits.count >= 8 && nameCharacters.count <= 2) else { return nil }
        return value
    }
}

private struct CpDateRangeFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialFrom: Date?
    let initialTo: Date?
    let onApply: (Date, Date?) -> Void

    @State private var isRange: Bool
    @State private var from: Date
    @State private var to: Date

    init(initialFrom: Date?, initialTo: Date?, onApply: @escaping (Date, Date?) -> Void) {
        self.initialFrom = initialFrom
        self.initialTo = initialTo
        self.onApply = onApply
        let start = initialFrom ?? Date()
        _from = State(initialValue: start)
        _to = State(initialValue: initialTo ?? start)
        _isRange = State(initialValue: initialTo != nil && !Calendar.current.isDate(initialTo ?? start, inSameDayAs: start))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Filter", selection: $isRange) {
                    Text("Single day").tag(false)
                    Text("Date range").tag(true)
                }
                .pickerStyle(.segmented)

                DatePicker(isRange ? "From" : "Date", selection: $from, displayedComponents: .date)
                if isRange {
                    DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                }
            }
            .navigationTitle("Filter by date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(from, isRange ? max(from, to) : nil)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }

    static func label(from: Date, to: Date?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "dd MMM yyyy"
        guard let to, !Calendar.current.isDate(from, inSameDayAs: to) else {
            return formatter.string(from: from)
        }
        return "\(formatter.string(from: from)) – \(formatter.string(from: to))"
    }
}

private extension CpVisitDetail {
    var syntheticOutcome: String? {
        if let outcome = outcome?.blankToNil { return outcome }
        if convertedBookingId?.blankToNil != nil { return "converted_to_booking" }
        if convertedSiteVisitId?.blankToNil != nil { return "converted_to_site_visit" }
        return nil
    }

    var isSvCumCp: Bool {
        if cpType?.normalizedMarker == "sv_cum_cp" { return true }
        if proposedSiteVisit?.isMeaningful == true { return true }
        if lead?.followUpStatus?.normalizedMarker.contains("sv_fixed") == true { return true }
        if (expectedAttendeeCount ?? 0) > 0 { return true }
        if attendees?.isEmpty == false { return true }
        if foodPreferences?.blankToNil != nil { return true }
        if vehiclePreference?.blankToNil != nil { return true }
        if convertedSiteVisitId?.blankToNil != nil { return true }
        if syntheticOutcome?.normalizedMarker == "converted_to_site_visit" { return true }
        return false
    }
}

private extension ConvexSiteVisit {
    var isPostponedCpVisit: Bool {
        cpVisit?.outcome?.lowercased() == "postponed" || !(cpVisit?.postponeReasons ?? []).isEmpty
    }

    var needsCpDetails: Bool {
        ((tripType ?? "").lowercased() == "client_place" || clientPlaceVisitId != nil)
            && (status ?? "").lowercased() == "arrived"
            && (cpVisit?.outcome?.blankToNil == nil)
    }

    var isOpenableCpVisit: Bool {
        let normalizedStatus = (status ?? "").lowercased()
        return !normalizedStatus.isCompleted && !normalizedStatus.isCancelled
    }

    var isCompletedCpVisit: Bool {
        let normalizedStatus = (status ?? "").lowercased()
        return normalizedStatus.isCompleted
            && ((tripType ?? "").lowercased() == "client_place" || clientPlaceVisitId != nil)
    }

    func matchesCpSearch(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return [
            placeName,
            leadName,
            leadPhone,
            placeAddress,
            placeType,
            scheduledDate,
            status,
            cpVisit?.outcome
        ]
        .compactMap { $0?.lowercased() }
        .contains { $0.contains(needle) }
    }
}

private struct IOSGlassCloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .fill(configuration.isPressed ? Color.white.opacity(0.28) : Color.white.opacity(0.08))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.9 : 0.72), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.04 : 0.10),
                radius: configuration.isPressed ? 5 : 12,
                x: 0,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.18, extraBounce: 0.22), value: configuration.isPressed)
    }
}

struct CpMapPinResult {
    let latitude: Double
    let longitude: Double
    let address: String

    var googleMapsLink: String {
        "https://www.google.com/maps?q=\(latitude),\(longitude)"
    }
}

struct CpMapPinPicker: View {
    @Environment(\.dismiss) private var dismiss

    let initialCoordinate: CLLocationCoordinate2D?
    let initialAddress: String?
    let onSelect: (CpMapPinResult) -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedAddress: String
    @State private var searchText = ""
    @State private var searchResults: [CpMapSearchResult] = []
    @State private var isSearching = false
    @State private var isSearchPresented = false
    @State private var searchErrorMessage: String?

    init(
        initialCoordinate: CLLocationCoordinate2D?,
        initialAddress: String?,
        onSelect: @escaping (CpMapPinResult) -> Void
    ) {
        self.initialCoordinate = initialCoordinate
        self.initialAddress = initialAddress
        self.onSelect = onSelect
        _selectedCoordinate = State(initialValue: initialCoordinate)
        _selectedAddress = State(initialValue: initialAddress ?? "")
        if let initialCoordinate {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: initialCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )))
        } else {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 13.0827, longitude: 80.2707),
                span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
            )))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                mapArea
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                selectionFooter
            }
            .navigationTitle("Set client location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search places or addresses"
            )
            .searchSuggestions {
                if isSearching {
                    Label("Searching Manju Maps…", systemImage: "sparkle.magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                if let searchErrorMessage {
                    Label(searchErrorMessage, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.red)
                }
                ForEach(searchResults) { result in
                    Button {
                        choose(result)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: result.symbolName)
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(result.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: searchText) {
                await search()
            }
        }
    }

    private var mapArea: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let selectedCoordinate {
                    Marker("Client location", coordinate: selectedCoordinate)
                        .tint(Color(hex: 0x0B61CA))
                }
            }
            .mapControls {
                MapCompass()
                MapUserLocationButton()
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        selectCoordinate(coordinate)
                    }
            )
        }
    }

    private var selectionFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedCoordinate {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedAddress.blankToNil ?? "Pinned location")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("\(selectedCoordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(selectedCoordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            } else {
                Label("Search above or tap the map to drop a pin.", systemImage: "hand.tap")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                guard let selectedCoordinate else { return }
                onSelect(CpMapPinResult(
                    latitude: selectedCoordinate.latitude,
                    longitude: selectedCoordinate.longitude,
                    address: selectedAddress
                ))
                dismiss()
            } label: {
                Label("Use this location", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Color(hex: 0x1BCA0B))
            .disabled(selectedCoordinate == nil)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    @MainActor
    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            searchErrorMessage = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled else { return }
        isSearching = true
        searchErrorMessage = nil
        defer { isSearching = false }
        do {
            let response = try await MapServiceAPI.search(query: query, limit: 6)
            guard !Task.isCancelled else { return }
            let remoteResults = response.compactMap(CpMapSearchResult.init)
            if remoteResults.isEmpty {
                searchResults = try await nativeSearch(query: query)
            } else {
                searchResults = remoteResults
            }
        } catch {
            do {
                searchResults = try await nativeSearch(query: query)
            } catch {
                searchResults = []
                searchErrorMessage = "No network. Check your connection and try again."
            }
        }
        guard !Task.isCancelled else { return }
        if searchResults.isEmpty, searchErrorMessage == nil {
            searchErrorMessage = "No matching places found. Try a more specific address."
        }
        if let first = searchResults.first {
            cameraPosition = .region(MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ))
        }
    }

    @MainActor
    private func nativeSearch(query: String) async throws -> [CpMapSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: selectedCoordinate ?? CLLocationCoordinate2D(latitude: 13.0827, longitude: 80.2707),
            span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
        )
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(6).map(CpMapSearchResult.init)
    }

    private func choose(_ result: CpMapSearchResult) {
        searchText = ""
        isSearchPresented = false
        searchResults = []
        searchErrorMessage = nil
        selectedCoordinate = result.coordinate
        selectedAddress = [result.title, result.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        cameraPosition = .region(MKCoordinateRegion(
            center: result.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    private func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        selectedCoordinate = coordinate
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
        Task {
            let address = try? await MapServiceAPI.reverseGeocode(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            guard selectedCoordinate?.latitude == coordinate.latitude,
                  selectedCoordinate?.longitude == coordinate.longitude
            else { return }
            selectedAddress = address ?? "Pinned location"
        }
    }
}

struct CpMapSearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let types: [String]

    init?(_ item: MapServiceAddressResult) {
        guard let latitude = item.location?.lat, let longitude = item.location?.lng else { return nil }
        title = item.name?.blankToNil ?? item.address?.blankToNil ?? "Location"
        subtitle = item.address?.blankToNil ?? title
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        types = item.types ?? []
        id = item.placeId?.blankToNil ?? "\(title)|\(latitude)|\(longitude)"
    }

    init(_ item: MKMapItem) {
        coordinate = item.placemark.coordinate
        title = item.name?.blankToNil ?? "Location"
        subtitle = item.placemark.title?.blankToNil ?? title
        types = []
        id = "native|\(title)|\(coordinate.latitude)|\(coordinate.longitude)"
    }

    var symbolName: String {
        if types.contains("real_estate_agency") { return "building.2.crop.circle" }
        if types.contains("general_contractor") { return "hammer.circle" }
        return "mappin.circle"
    }
}

private enum NewClientReferralSource: String, CaseIterable, Identifiable {
    case ownReferral = "own_referral"
    case clientReferral = "client_referral"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ownReferral: return "Own Referral"
        case .clientReferral: return "Client Referral"
        }
    }

    var subtitle: String {
        switch self {
        case .ownReferral: return "Credit the staff who first attends this CP"
        case .clientReferral: return "Credit an existing client"
        }
    }
}

private struct ReferralClientPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let token: String
    let excludingPhone: String
    let selectedId: String?
    let onSelect: (ReferralClientCandidate) -> Void

    @State private var query = ""
    @State private var clients: [ReferralClientCandidate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    ContentUnavailableView(
                        "Find referring client",
                        systemImage: "person.badge.plus",
                        description: Text("Enter at least 2 letters or mobile digits.")
                    )
                } else if isLoading && clients.isEmpty {
                    ProgressView("Searching clients…")
                } else if let errorMessage, clients.isEmpty {
                    ContentUnavailableView(
                        "Search unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if clients.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(clients) { client in
                        Button {
                            onSelect(client)
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(client.name.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x0B61CA))
                                    .frame(width: 42, height: 42)
                                    .background(Color(hex: 0xEAF2FC), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(client.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(client.mobileNumber)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    if let address = client.formattedAddress?.blankToNil {
                                        Text(address)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if client.id == selectedId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(hex: 0x0B61CA))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Referring Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Name or mobile number")
            .task(id: query) {
                await search()
            }
        }
    }

    @MainActor
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            clients = []
            errorMessage = nil
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            let response: [ReferralClientCandidate]
            do {
                let remote = try await MarketingConvexAPIService.searchReferralClientCandidates(
                    token: token,
                    query: trimmed
                )
                response = remote.clients ?? []
            } catch {
                let digits = AppModuleFormatters.normalizePhone(trimmed)
                guard error.localizedDescription.contains("(404)"), digits.count == 10 else {
                    throw error
                }
                if let exact = try await MarketingConvexAPIService.searchClientByPhone(
                    token: token,
                    phone: digits
                ) {
                    response = [ReferralClientCandidate(
                        id: exact.id,
                        name: exact.clientName?.blankToNil ?? "Client",
                        mobileNumber: exact.mobileNumber?.blankToNil ?? digits,
                        formattedAddress: exact.formattedAddress
                            ?? exact.homeAddress
                            ?? exact.addressLine1
                    )]
                } else {
                    response = []
                }
            }
            guard !Task.isCancelled else { return }
            clients = response.filter {
                AppModuleFormatters.normalizePhone($0.mobileNumber) != excludingPhone
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            clients = []
            if error.localizedDescription.contains("(404)") {
                errorMessage = "Client name search is not available yet. Try a full mobile number."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private enum CpVisitCreateType: String, CaseIterable, Identifiable {
    case svCumCp = "sv_cum_cp"
    // "follow_up" remains retired. New Client CP can also be created manually
    // from this native form with the entered client identity and address.
    case newClientCp = "new_client_cp"
    case bookingCp = "booking_cp"
    case collectionCp = "collection_cp"
    case oldClient = "old_client"
    case giftDistribution = "gift_distribution"
    case otherCp = "other_cp"
    case jointCp = "joint_cp"

    var id: String { rawValue }

    var requiresConfirmedBooking: Bool {
        self == .collectionCp || self == .bookingCp
    }

    var title: String {
        switch self {
        case .svCumCp: return "SV cum CP"
        case .newClientCp: return "New Client CP"
        case .bookingCp: return "Booking CP"
        case .collectionCp: return "Collection CP"
        case .oldClient: return "Old Client"
        case .giftDistribution: return "Gift Distribution"
        case .otherCp: return "Other CP"
        case .jointCp: return "Joint CP"
        }
    }

    var subtitle: String {
        switch self {
        case .svCumCp: return "Confirm a site visit"
        case .newClientCp: return "First visit for a manually added client"
        case .bookingCp: return "Paperwork for active booking"
        case .collectionCp: return "Collect payment at client place"
        case .oldClient: return "Re-engage previous client"
        case .giftDistribution: return "Drop loyalty gift"
        case .otherCp: return "Miscellaneous client work"
        case .jointCp: return "Two staff, senior records outcome"
        }
    }
}
