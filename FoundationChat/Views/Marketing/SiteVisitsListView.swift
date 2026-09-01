import CoreLocation
import SwiftUI

/// Marketing > Site Visits list. Mirrors the Android `SiteVisitsListFragment`:
/// pulls scheduled visits across a ±30-day window from
/// `GET /api/sitevisits/my`, sorts newest scheduled date first, and opens the
/// Android-parity overview sheet before outcome capture.
struct SiteVisitsListView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var visits: [ConvexSiteVisit] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var hasLoadedOnce = false
    @State private var selectedVisit: ConvexSiteVisit?
    @State private var bdoNamesByVisitId: [String: String] = [:]
    @State private var searchText = ""
    @State private var selectedFilter: SiteVisitListFilter = .all
    @State private var showingDateFilter = false
    @State private var showingCreateVisit = false
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

    private var canCreateSiteVisit: Bool {
        authStore.hasPermission("marketing.siteVisits.create")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var filteredVisits: [ConvexSiteVisit] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return visits
            // A confirmed SV-cum-CP remains linked to its verification CP.
            // Classify by trip type; the link itself does not make it a CP row.
            .filter { ($0.tripType ?? "").lowercased() != "client_place" }
            .filter { selectedFilter.matches($0) }
            .filter { visit in
                guard !needle.isEmpty else { return true }
                return [
                    visit.leadName,
                    visit.placeName,
                    visit.placeAddress
                ]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(needle) }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterPills
            content
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .navigationTitle("Site Visits")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search SV"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbarBackground(Color.appElevatedSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if canCreateSiteVisit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCreateVisit = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Schedule site visit")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingDateFilter = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Filter site visits by date")
            }
        }
        .refreshable { await load() }
        .task {
            if !hasLoadedOnce { await load() }
        }
        .sheet(isPresented: $showingDateFilter) {
            SiteVisitDateFilterSheet(fromDate: $fromDate, toDate: $toDate) {
                Task { await load() }
            }
            .appLibraryNativeSheet([.medium])
        }
        .sheet(isPresented: $showingCreateVisit) {
            CreateSiteVisitSheet {
                showingCreateVisit = false
                Task { await load() }
            }
            .appLibraryNativeSheet([.large])
        }
        .sheet(item: $selectedVisit) { visit in
            SiteVisitOverviewSheet(visit: visit) {
                Task { await load() }
            }
            .appLibraryNativeSheet([.fraction(0.78), .large])
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && visits.isEmpty {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        SiteVisitSkeletonRow()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        } else if loadFailed && visits.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load visits", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage ?? "Please try again.")
            } actions: {
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if filteredVisits.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mappin.slash" : "magnifyingglass")
            } description: {
                Text(emptySubtitle)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(filteredVisits) { visit in
                        Button {
                            selectedVisit = visit
                        } label: {
                            SiteVisitRow(
                                // The visit's OWN assigned BDO, not the signed-in
                                // viewer — the old session-user value made every row
                                // read as the logged-in staffer. Em-dash when the
                                // backend has no BDO on the row.
                                visit: visit,
                                resolvedBdoName: bdoNamesByVisitId[visit.id]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private var filterPills: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SiteVisitListFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .medium))
                            .foregroundStyle(selectedFilter == filter ? .white : .primary)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(
                                selectedFilter == filter ? Color(hex: 0x0B61CA) : Color.appSurface,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(selectedFilter == filter ? Color.clear : Color.appSeparator, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 16)
    }

    private var emptyTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Matches Found"
        }
        switch selectedFilter {
        case .all, .scheduled:
            return "No Site Visits Yet"
        case .fixed:
            return "No Fixed Visits"
        case .enroute:
            return "No Enroute Visits"
        case .onsite:
            return "No Onsite Visits"
        case .returningHome:
            return "No Returning Visits"
        case .completed:
            return "No Completed Visits"
        case .cancelled:
            return "No Cancelled Visits"
        case .postponed:
            return "No Postponed Visits"
        }
    }

    private var emptySubtitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different search term or switch filters to see other site visits."
        }
        return "Site visits scheduled for you will appear here once they're booked from the web."
    }

    private func coordinate(for visit: ConvexSiteVisit) -> CLLocationCoordinate2D? {
        guard let lat = visit.placeLat, let lng = visit.placeLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    @MainActor
    private func load() async {
        guard let session = authStore.currentSession else {
            loadFailed = true
            errorMessage = "Not signed in."
            return
        }
        let fromDateText = Self.dateFormatter.string(from: min(fromDate, toDate))
        let toDateText = Self.dateFormatter.string(from: max(fromDate, toDate))
        let key = cacheKey(fromDate: fromDateText, toDate: toDateText)
        if visits.isEmpty, let cached = LocalCache.get(key, as: [ConvexSiteVisit].self) {
            visits = cached
            loadFailed = false
            errorMessage = nil
            Task { await hydrateBdoNames(for: cached, token: session.token) }
        }

        isLoading = visits.isEmpty
        loadFailed = false
        errorMessage = nil
        defer { isLoading = false; hasLoadedOnce = true }

        do {
            let result = try await HRConvexAPIService.getMySiteVisits(
                token: session.token,
                fromDate: fromDateText,
                toDate: toDateText
            )
            let normalized = result
                .filter { ($0.tripType ?? "").lowercased() != "client_place" }
                .sorted {
                    let left = $0.creationTime ?? 0
                    let right = $1.creationTime ?? 0
                    if left != right { return left > right }
                    return ($0.scheduledDate ?? "") > ($1.scheduledDate ?? "")
                }
            visits = normalized
            LocalCache.put(key, normalized)
            Task { await hydrateBdoNames(for: normalized, token: session.token) }
        } catch {
            loadFailed = visits.isEmpty
            errorMessage = error.localizedDescription
        }
    }

    private func cacheKey(fromDate: String, toDate: String) -> String {
        let user = authStore.currentSession?.user
        let staffId = user?.staffId ?? user?._id ?? "unknown"
        return "marketing.site-visits.my.\(staffId).\(fromDate).\(toDate)"
    }

    @MainActor
    private func hydrateBdoNames(for visits: [ConvexSiteVisit], token: String) async {
        var resolved = bdoNamesByVisitId
        for visit in visits {
            if let name = visit.bdoName?.nilIfBlank {
                resolved[visit.id] = name
            }
        }
        bdoNamesByVisitId = resolved

        let unresolved = visits.filter { resolved[$0.id] == nil }
        guard !unresolved.isEmpty else { return }

        var detailsByVisitId: [String: CpVisitDetail] = [:]
        var needsRemoteDetail: [ConvexSiteVisit] = []
        for visit in unresolved {
            let key = "marketing.site-visit.detail.\(visit.id)"
            if let cached = LocalCache.get(key, as: CpVisitDetail.self) {
                detailsByVisitId[visit.id] = cached
            } else {
                needsRemoteDetail.append(visit)
            }
        }

        // Keep the list responsive and avoid issuing an unbounded request burst.
        let remoteDetailIds = needsRemoteDetail.map(\.id)
        for start in stride(from: 0, to: remoteDetailIds.count, by: 6) {
            let end = min(start + 6, remoteDetailIds.count)
            let batch = Array(remoteDetailIds[start..<end])
            let fetched = await withTaskGroup(of: (String, CpVisitDetail?).self) { group in
                for id in batch {
                    group.addTask {
                        let detail = try? await MarketingConvexAPIService.getCpVisitDetail(token: token, id: id)
                        return (id, detail)
                    }
                }
                var values: [(String, CpVisitDetail?)] = []
                for await value in group { values.append(value) }
                return values
            }
            for (id, detail) in fetched {
                guard let detail else { continue }
                detailsByVisitId[id] = detail
                LocalCache.put("marketing.site-visit.detail.\(id)", detail)
            }
        }

        let needsDirectory = detailsByVisitId.values.contains { detail in
            detail.proposedSiteVisit?.bdoStaffId?.nilIfBlank != nil
                || detail.assignedStaffId?.nilIfBlank != nil
        }
        let directory = needsDirectory
            ? ((try? await HRConvexAPIService.listAllStaff(token: token)) ?? [])
            : []

        for visit in unresolved {
            guard let detail = detailsByVisitId[visit.id] else { continue }
            let bdoId = detail.proposedSiteVisit?.bdoStaffId?.nilIfBlank
            let assignedId = detail.assignedStaffId?.nilIfBlank
            let name = bdoId.flatMap { id in directory.first { $0.id == id }?.displayName.nilIfBlank }
                ?? detail.assignedStaff?.displayName
                ?? assignedId.flatMap { id in directory.first { $0.id == id }?.displayName.nilIfBlank }
            if let name { resolved[visit.id] = name }
        }
        bdoNamesByVisitId = resolved
    }
}

private struct SiteVisitDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fromDate: Date
    @Binding var toDate: Date
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $fromDate, displayedComponents: .date)
                    DatePicker("To", selection: $toDate, displayedComponents: .date)
                }

                if fromDate > toDate {
                    Section {
                        Label("From date must be before To date.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                    }
                }
            }
            .navigationTitle("Filter Site Visits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                    .disabled(fromDate > toDate)
                }
            }
        }
    }
}

// MARK: - Row

private struct SiteVisitSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: 0xE9EEF8))
                    .frame(width: 62, height: 86)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(hex: 0xE4ECFF))
                    .frame(width: 62, height: 24)
            }

            Rectangle()
                .fill(Color.appSeparator)
                .frame(width: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    skeleton(width: 138, height: 18)
                    Spacer()
                    skeleton(width: 92, height: 22)
                }

                HStack {
                    skeleton(width: 132, height: 14)
                    Spacer()
                    skeleton(width: 118, height: 22)
                }

                DashedDivider()

                HStack(spacing: 12) {
                    footerSkeleton
                    footerSkeleton
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16))
        .redacted(reason: .placeholder)
    }

    private var footerSkeleton: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(Color(hex: 0xE5E7EB))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 5) {
                skeleton(width: 82, height: 13)
                skeleton(width: 36, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skeleton(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(hex: 0xE5E7EB))
            .frame(width: width, height: height)
    }
}

struct SiteVisitRow: View {
    let visit: ConvexSiteVisit
    let resolvedBdoName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            dateBlock

            Rectangle()
                .fill(Color.appSeparator)
                .frame(width: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(visit.leadName?.nilIfBlank ?? "—")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    SiteVisitTinyPill(
                        title: visit.rowStatus.title,
                        icon: nil,
                        foreground: visit.rowStatus.foreground,
                        background: visit.rowStatus.background,
                        showsDot: true
                    )
                }

                HStack(spacing: 8) {
                    Label {
                        Text(visit.leadPhone?.nilIfBlank ?? "—")
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x98A2B3))

                    Spacer(minLength: 8)

                    SiteVisitTinyPill(
                        title: visit.vehiclePill.title,
                        icon: "car.fill",
                        foreground: visit.vehiclePill.foreground,
                        background: visit.vehiclePill.background,
                        showsDot: false
                    )
                }

                DashedDivider()

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 12) {
                        footerItem(icon: "person.crop.circle", title: visit.lmoName?.nilIfBlank ?? "—", subtitle: "LMO")
                        footerItem(
                            icon: "person",
                            title: visit.bdoName?.nilIfBlank
                                ?? resolvedBdoName?.nilIfBlank
                                ?? "—",
                            subtitle: "BDO"
                        )
                    }

                    footerItem(icon: "mappin", title: visit.destinationTitle, subtitle: "ORIGIN")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var dateBlock: some View {
        VStack(spacing: 8) {
            VStack(spacing: 3) {
                Text(visit.androidDayText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(visit.androidDateText)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(visit.androidMonthText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .lineLimit(1)
            }
            .frame(width: 62)
            .frame(minHeight: 86)
            .background(Color(hex: 0xEEF4FF), in: RoundedRectangle(cornerRadius: 12))

            Text(visit.androidTimeText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: 0x004EEB))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 62, height: 24)
                .background(Color(hex: 0xE4ECFF), in: RoundedRectangle(cornerRadius: 5))
                .opacity(visit.androidTimeText.isEmpty ? 0 : 1)
        }
        .frame(width: 62)
    }

    private func footerItem(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SiteVisitTinyPill: View {
    let title: String
    let icon: String?
    let foreground: Color
    let background: Color
    let showsDot: Bool

    var body: some View {
        HStack(spacing: 4) {
            if showsDot {
                Circle()
                    .fill(foreground)
                    .frame(width: 6, height: 6)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(background, in: Capsule())
    }
}

private struct DashedDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay {
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Color.appSeparator)
            }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

private struct StatusPill: View {
    let bucket: SiteVisitStatus

    var body: some View {
        Text(bucket.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bucket.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(bucket.tint)
    }
}

private enum AndroidSiteVisitRowStatus {
    case start
    case clientStarted
    case pickedUp
    case onSite
    case dropped
    case inProgress
    case completed
    case postponed
    case cancelled

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var isInProgress: Bool {
        switch self {
        case .clientStarted, .pickedUp, .onSite, .dropped, .inProgress:
            return true
        case .start, .completed, .postponed, .cancelled:
            return false
        }
    }

    var isPickedUpBucket: Bool {
        switch self {
        case .pickedUp, .onSite, .dropped:
            return true
        case .start, .clientStarted, .inProgress, .completed, .postponed, .cancelled:
            return false
        }
    }
}

private enum SiteVisitListFilter: String, CaseIterable, Identifiable {
    case all
    case fixed
    case scheduled
    case enroute
    case onsite
    case returningHome
    case completed
    case cancelled
    case postponed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .fixed: return "Fixed"
        case .scheduled: return "Scheduled"
        case .enroute: return "Enroute"
        case .onsite: return "Onsite"
        case .returningHome: return "Returning home"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .postponed: return "Postponed"
        }
    }

    func matches(_ visit: ConvexSiteVisit) -> Bool {
        switch self {
        case .all:
            return true
        case .fixed:
            return visit.isFixedSiteVisit
        case .scheduled:
            return visit.isScheduledSiteVisit && !visit.isFixedSiteVisit
        case .enroute:
            return visit.isEnrouteSiteVisit
        case .onsite:
            return visit.isOnsiteSiteVisit
        case .returningHome:
            return visit.isReturningHomeSiteVisit
        case .completed:
            return visit.isCompletedSiteVisit
        case .cancelled:
            return visit.isCancelledSiteVisit
        case .postponed:
            return visit.isPostponedSiteVisit
        }
    }
}

private extension ConvexSiteVisit {
    var effectiveSiteVisitStatus: String {
        (rawStatus?.nilIfBlank ?? status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    var siteVisitStatus: AndroidSiteVisitRowStatus {
        let value = effectiveSiteVisitStatus

        switch value {
        case "completed", "complete", "done", "closed":
            return .completed
        case "postponed":
            return .postponed
        case "cancelled", "canceled", "no_show":
            return .cancelled
        case "client_started", "started":
            return .clientStarted
        case "picked_up":
            return .pickedUp
        case "on_site", "site_reached":
            return .onSite
        case "dropped", "picked_from_site":
            return .dropped
        case "consulting", "on_counselling", "arrived":
            return .onSite
        case "in_progress":
            return .clientStarted
        case "ongoing", "active":
            return .inProgress
        default:
            return .start
        }
    }

    var isEnrouteSiteVisit: Bool {
        ["client_started", "started", "in_progress", "picked_up"].contains(effectiveSiteVisitStatus.normalizedSiteVisitValue)
    }

    var isOnsiteSiteVisit: Bool {
        ["on_site", "on_counselling", "consulting", "arrived"].contains(effectiveSiteVisitStatus.normalizedSiteVisitValue)
    }

    var isReturningHomeSiteVisit: Bool {
        ["picked_from_site", "dropped"].contains(effectiveSiteVisitStatus.normalizedSiteVisitValue)
    }

    var isCompletedSiteVisit: Bool {
        ["completed", "complete", "done", "closed"].contains(effectiveSiteVisitStatus.normalizedSiteVisitValue)
    }

    var isCancelledSiteVisit: Bool {
        ["cancelled", "canceled", "no_show"].contains(effectiveSiteVisitStatus.normalizedSiteVisitValue)
    }

    var isPostponedSiteVisit: Bool {
        effectiveSiteVisitStatus.normalizedSiteVisitValue == "postponed"
    }

    var isScheduledSiteVisit: Bool {
        !isEnrouteSiteVisit && !isOnsiteSiteVisit && !isReturningHomeSiteVisit
            && !isCompletedSiteVisit && !isCancelledSiteVisit && !isPostponedSiteVisit
    }

    var isFixedSiteVisit: Bool {
        isScheduledSiteVisit
            && confirmationStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "pending"
    }

    var rowStatus: (title: String, foreground: Color, background: Color) {
        switch siteVisitStatus {
        case .start:
            return ("Scheduled", Color(hex: 0xB54708), Color(hex: 0xB54708).opacity(0.12))
        case .clientStarted:
            return ("Client Started", Color(hex: 0xB54708), Color(hex: 0xB54708).opacity(0.12))
        case .pickedUp:
            return ("Picked up", Color(hex: 0xB54708), Color(hex: 0xB54708).opacity(0.12))
        case .onSite:
            return ("On site", Color(hex: 0xB54708), Color(hex: 0xB54708).opacity(0.12))
        case .dropped:
            return ("Dropped", Color(hex: 0xB54708), Color(hex: 0xB54708).opacity(0.12))
        case .inProgress:
            let value = effectiveSiteVisitStatus.normalizedSiteVisitValue
            if value == "arrived" {
                return ("Reaching", Color(hex: 0xB54708), Color(hex: 0xB54708).opacity(0.12))
            }
            return ("Enroute", Color(hex: 0xB54708), Color(hex: 0xB54708).opacity(0.12))
        case .completed:
            return ("Completed", Color(hex: 0x027A48), Color(hex: 0x027A48).opacity(0.12))
        case .postponed:
            return ("Postponed", Color(hex: 0xB54708), Color(hex: 0xB54708).opacity(0.12))
        case .cancelled:
            return ("Cancelled", Color(hex: 0xB42318), Color(hex: 0xB42318).opacity(0.12))
        }
    }

    var vehiclePill: (title: String, foreground: Color, background: Color) {
        if isOwnVehicleForList {
            return ("Own Vehicle", Color(hex: 0x175CD3), Color(hex: 0x175CD3).opacity(0.12))
        }
        if isVehicleAssignedForList {
            return ("Vehicle Assigned", Color(hex: 0x027A48), Color(hex: 0x027A48).opacity(0.12))
        }
        return ("No Vehicle Assigned", Color(hex: 0xF04438), Color(hex: 0xF04438).opacity(0.12))
    }

    var isOwnVehicleForList: Bool {
        [travelMode, vehiclePreference]
            .compactMap { $0?.normalizedSiteVisitValue }
            .contains("own_vehicle")
    }

    var isVehicleAssignedForList: Bool {
        if vehicleAssigned == true { return true }
        if vehicleAssigned == nil,
           let category = visitCategory?.nilIfBlank,
           category != "direct_cp",
           category != "site_visit" {
            return true
        }
        return false
    }

    var destinationTitle: String {
        placeName?.nilIfBlank ?? placeAddress?.nilIfBlank ?? "—"
    }

    var androidDayText: String {
        scheduledDate?.nilIfBlank.map { SiteVisitDateFormatter.weekday($0) } ?? ""
    }

    var androidDateText: String {
        scheduledDate?.nilIfBlank.map { SiteVisitDateFormatter.dayNumber($0) } ?? "—"
    }

    var androidMonthText: String {
        scheduledDate?.nilIfBlank.map { SiteVisitDateFormatter.month($0) } ?? ""
    }

    var androidTimeText: String {
        scheduledStartTime?.nilIfBlank.map { SiteVisitDateFormatter.displayTime($0) } ?? ""
    }
}

private enum SiteVisitDateFormatter {
    static func isToday(_ raw: String) -> Bool {
        guard let date = parseDate(raw) else { return false }
        return Calendar.current.isDateInToday(date)
    }

    static func dayMonth(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func weekday(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    static func dayNumber(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd"
        return formatter.string(from: date)
    }

    static func month(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: date).uppercased()
    }

    static func displayDate(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }

    static func displayTime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if parseDate(trimmed) != nil || trimmed.range(of: #"^\d{1,2}/\d{1,2}/\d{2,4}$"#, options: .regularExpression) != nil {
            return ""
        }
        let inputFormats = ["HH:mm:ss", "HH:mm", "h:mm a", "hh:mm a"]
        for format in inputFormats {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = format
            if let date = parser.date(from: trimmed.uppercased()) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "h:mm a"
                return formatter.string(from: date)
            }
        }
        return trimmed
    }

    private static func parseDate(_ raw: String) -> Date? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: raw)
    }
}

private struct SiteVisitOverviewSheet: View {
    let visit: ConvexSiteVisit
    let onChanged: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOutcome: SiteVisitOverviewOutcome?
    @State private var showPostponeVisit = false
    @State private var showCancelVisit = false
    @State private var detail: CpVisitDetail?
    @State private var staffDirectory: [ConvexStaffListItem] = []
    @State private var projectDirectory: [MarketingProject] = []
    @State private var isLoadingDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                progressStepper

                if isLoadingDetail {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading visit details...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    overviewCard(icon: "person", tint: Color(hex: 0x0B61CA), label: "CLIENT", value: clientName)
                    overviewCard(icon: "phone", tint: Color(hex: 0x7C3AED), label: "PHONE", value: clientPhone)
                    overviewCard(icon: "building.2", tint: Color(hex: 0xDB2777), label: "PROJECT / PLOT", value: projectName)
                    overviewCard(icon: "person", tint: Color(hex: 0xF97316), label: "BDO / TELECALLER", value: staffName)
                }

                wideCard(
                    icon: "mappin.circle",
                    tint: Color(hex: 0x0B61CA),
                    label: "PICKUP ADDRESS",
                    value: pickupAddress
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    overviewCard(icon: "person.2", tint: Color(hex: 0x667085), label: "ATTENDEES", value: attendeeCountText)
                    overviewCard(icon: "checkmark.circle.fill", tint: Color(hex: 0x475467), label: "SITE INCHARGE", value: inchargeName)
                }

                HStack(spacing: 12) {
                    bottomTintCard(title: "Visitors", value: visitorSummary, tint: Color(hex: 0x0B61CA), bg: Color(hex: 0xEEF4FF))
                    bottomTintCard(title: "Notes", value: notesText, tint: Color.orange, bg: Color.orange.opacity(0.10))
                }

                if let detail {
                    arrivalProofCard(for: detail)
                    visitTimelineCard(for: detail)
                }

                if canPostponeVisit {
                    Button {
                        showPostponeVisit = true
                    } label: {
                        Label("Postpone Site Visit", systemImage: "calendar.badge.clock")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color(hex: 0xD97706))
                }

                if canCancelVisit {
                    Button(role: .destructive) {
                        showCancelVisit = true
                    } label: {
                        Label("Cancel Site Visit", systemImage: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color(hex: 0xD92D20))
                }

                outcomeButtons
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .background(Color.appSurface)
        .task { await loadEnrichedDetail() }
        .sheet(item: $selectedOutcome) { outcome in
            SiteVisitOutcomeSheet(
                siteVisitId: visit.id,
                initialOutcome: outcome.rawValue,
                locksOutcome: true,
                initialClientName: clientName,
                initialClientPhone: clientPhone
            ) {
                onChanged()
                dismiss()
            }
            .appLibraryNativeSheet([.large])
        }
        .sheet(isPresented: $showPostponeVisit) {
            PostponeSiteVisitSheet(siteVisitID: visit.id) {
                showPostponeVisit = false
                onChanged()
                dismiss()
            }
            .appLibraryNativeSheet([.medium])
        }
        .sheet(isPresented: $showCancelVisit) {
            CancelSiteVisitSheet(siteVisitID: visit.id) {
                showCancelVisit = false
                onChanged()
                dismiss()
            }
            .appLibraryNativeSheet([.medium])
        }
    }

    // MARK: - Completed-visit detail: arrival proof + timeline
    // Ports the Android CompletedVisitDetailFragment's arrival-proof card and the
    // synthesized timeline. The data is already loaded in `detail` (CpVisitDetail) —
    // these just render it.

    private static let overviewTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM, h:mm a"
        return f
    }()

    private func overviewTimestamp(_ millis: Int64?) -> String? {
        guard let millis, millis > 0 else { return nil }
        return Self.overviewTimestampFormatter.string(
            from: Date(timeIntervalSince1970: Double(millis) / 1000)
        )
    }

    private func overviewDistance(_ meters: Double?) -> String? {
        guard let meters, meters >= 0 else { return nil }
        if meters >= 1000 {
            return "\((meters / 1000).formatted(.number.precision(.fractionLength(2)))) km"
        }
        return "\(Int(meters.rounded())) m"
    }

    @ViewBuilder
    private func arrivalProofCard(for detail: CpVisitDetail) -> some View {
        if let proof = detail.arrivalProof,
           proof.photoUrl != nil || proof.otpVerifiedAt != nil || proof.distanceFromPlaceMeters != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("ARRIVAL PROOF")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                if let urlString = proof.photoUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Color(hex: 0xF2F4F7).overlay(
                                Image(systemName: "photo").foregroundStyle(.secondary)
                            )
                        default:
                            Color(hex: 0xF2F4F7).overlay(ProgressView())
                        }
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(spacing: 8) {
                    if let t = overviewTimestamp(proof.otpVerifiedAt) {
                        overviewProofRow("OTP verified", t)
                    }
                    if let t = overviewTimestamp(proof.otpRequestedAt) {
                        overviewProofRow("OTP requested", t)
                    }
                    if let lat = proof.gpsLat, let lng = proof.gpsLng {
                        overviewProofRow("Arrival GPS", String(format: "%.5f, %.5f", lat, lng))
                    }
                    if let d = overviewDistance(proof.distanceFromPlaceMeters) {
                        overviewProofRow("Distance from place", d)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func overviewProofRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func visitTimelineCard(for detail: CpVisitDetail) -> some View {
        let events: [(String, Int64?)] = [
            ("Created", detail.createdAt),
            ("Assigned", detail.assignedAt),
            ("Field visit started", detail.fieldVisit?.startedAt),
            ("Arrival OTP verified", detail.arrivalProof?.otpVerifiedAt),
            ("Client met", detail.clientMetAt),
            ("Completed", detail.completedAt)
        ].filter { ($0.1 ?? 0) > 0 }

        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("TIMELINE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle().fill(Color(hex: 0x0B61CA)).frame(width: 9, height: 9)
                                if index < events.count - 1 {
                                    Rectangle().fill(Color(hex: 0xD0D5DD)).frame(width: 2, height: 26)
                                }
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.0)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                if let t = overviewTimestamp(event.1) {
                                    Text(t)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.bottom, index < events.count - 1 ? 10 : 0)
                            Spacer()
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(overviewTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: 0x0B61CA))
                            .frame(width: 8, height: 8)
                        Text(androidStatusTitle.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(vehicleTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
            }

            HStack {
                Label(displayDateTime, systemImage: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Label(visitTypeTitle, systemImage: "mappin")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressStepper: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(0..<(displayedStepItems.count - 1), id: \.self) { index in
                    Rectangle()
                        .fill(index < displayedCurrentStepIndex ? Color(hex: 0x0B61CA) : Color.appSeparator)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 15)
            .zIndex(0)

            HStack(spacing: 0) {
                ForEach(Array(displayedStepItems.enumerated()), id: \.offset) { index, step in
                    VStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(index <= displayedCurrentStepIndex ? Color(hex: 0x0B61CA) : Color.appSurface)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.appSeparator, lineWidth: index <= displayedCurrentStepIndex ? 0 : 1))

                            Image(systemName: step.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(index <= displayedCurrentStepIndex ? .white : Color(hex: 0x98A2B3))
                        }

                        Text(step.title)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(index <= displayedCurrentStepIndex ? Color(hex: 0x0B61CA) : Color(hex: 0x98A2B3))
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .zIndex(1)
        }
        .padding(.top, 8)
    }

    private var outcomeButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Outcome")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if isVisitClosed {
                    Text("Completed")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: 0x0B61CA).opacity(0.10), in: Capsule())
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                outcomeButton("Booking", icon: "briefcase.fill", tint: Color(hex: 0x16A34A), outcome: .booking)
                outcomeButton("Client Not Interested", icon: "hand.thumbsdown.fill", tint: Color(hex: 0xDC2626), outcome: .notInterested)
                outcomeButton("Follow up", icon: "calendar.badge.clock", tint: Color(hex: 0xD97706), outcome: .followUp)
                outcomeButton("Others", icon: "ellipsis.circle.fill", tint: Color(hex: 0x475467), outcome: .other)
            }

            if isVisitClosed {
                Label("This site visit outcome is already completed.", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if !isOutcomeEnabled {
                Label("Scan the client QR and start counselling to record the outcome.", systemImage: "qrcode")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func outcomeButton(_ title: String, icon: String, tint: Color, outcome: SiteVisitOverviewOutcome) -> some View {
        Button {
            guard isOutcomeEnabled else { return }
            selectedOutcome = outcome
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(isOutcomeEnabled ? tint : Color(hex: 0x98A2B3))
            .frame(maxWidth: .infinity, minHeight: 72)
            .background((isOutcomeEnabled ? tint.opacity(0.10) : Color.appFieldBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!isOutcomeEnabled)
        .opacity(isOutcomeEnabled ? 1.0 : 0.4)
    }

    private func overviewCard(icon: String, tint: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())

                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appSeparator, lineWidth: 1))
    }

    private func wideCard(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appSeparator, lineWidth: 1))
    }

    private func bottomTintCard(title: String, value: String, tint: Color, bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .background(bg, in: RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func loadEnrichedDetail() async {
        guard let token = authStore.currentSession?.token else { return }
        let detailCacheKey = "marketing.site-visit.detail.\(visit.id)"
        if detail == nil, let cached = LocalCache.get(detailCacheKey, as: CpVisitDetail.self) {
            detail = cached
        }
        isLoadingDetail = detail == nil

        if let refreshedDetail = await fetchDetailWithTimeout(token: token) {
            detail = refreshedDetail
            LocalCache.put(detailCacheKey, refreshedDetail)
        }
        isLoadingDetail = false

        // Directory lookups are fallbacks only. They must never hold the detail
        // sheet's loading state open after the visit payload has arrived.
        await loadMissingReferenceData(token: token)
    }

    private func fetchDetailWithTimeout(token: String) async -> CpVisitDetail? {
        await withTaskGroup(of: CpVisitDetail?.self) { group in
            group.addTask {
                try? await MarketingConvexAPIService.getCpVisitDetail(token: token, id: visit.id)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    @MainActor
    private func loadMissingReferenceData(token: String) async {
        let needsStaff = detail?.assignedStaff?.displayName == nil
            && (detail?.assignedStaffId?.nilIfBlank != nil
                || detail?.proposedSiteVisit?.bdoStaffId?.nilIfBlank != nil
                || detail?.proposedSiteVisit?.inchargeStaffId?.nilIfBlank != nil)
        let needsProjects = detail?.project?.name?.nilIfBlank == nil
            && detail?.proposedSiteVisit?.projectId?.nilIfBlank != nil

        await withTaskGroup(of: Void.self) { group in
            if needsStaff {
                group.addTask {
                    let values = (try? await HRConvexAPIService.listAllStaff(token: token)) ?? []
                    await MainActor.run { staffDirectory = values }
                }
            }
            if needsProjects {
                group.addTask {
                    let values = (try? await MarketingConvexAPIService.getMarketingProjects(token: token)) ?? []
                    await MainActor.run { projectDirectory = values }
                }
            }
        }
    }

    private var clientName: String {
        detail?.lead?.contactName?.nilIfBlank
            ?? detail?.lead?.manualProfile?.clientName?.nilIfBlank
            ?? detail?.client?.clientName?.nilIfBlank
            ?? visit.leadName?.nilIfBlank
            ?? "—"
    }

    private var clientPhone: String {
        detail?.lead?.mobileNumber?.nilIfBlank
            ?? detail?.client?.mobileNumber?.nilIfBlank
            ?? visit.leadPhone?.nilIfBlank
            ?? "—"
    }

    private var overviewTitle: String {
        let title = projectName.nilIfBlank
            ?? visit.placeName?.nilIfBlank
            ?? "Site Visit"
        return title == "—" ? "Site Visit" : title
    }

    private var projectName: String {
        detail?.project?.name?.nilIfBlank
            ?? resolvedProjectName
            ?? "—"
    }

    private var resolvedProjectName: String? {
        guard let projectId = detail?.proposedSiteVisit?.projectId?.nilIfBlank else { return nil }
        return projectDirectory.first { $0.id == projectId }?.name?.nilIfBlank
    }

    private var staffName: String {
        detail?.assignedStaff?.displayName
            ?? bdoFromDirectory
            ?? visit.bdoName?.nilIfBlank
            ?? "—"
    }

    private var bdoFromDirectory: String? {
        let id = detail?.proposedSiteVisit?.bdoStaffId?.nilIfBlank
            ?? detail?.assignedStaffId?.nilIfBlank
        guard let id else { return nil }
        return staffDirectory.first { $0.id == id }?.displayName
    }

    private var pickupAddress: String {
        formattedClientPlaceAddress?.nilIfBlank
            ?? detail?.clientPlace?.formattedAddress?.nilIfBlank
            ?? visit.placeAddress?.nilIfBlank
            ?? "—"
    }

    private var formattedClientPlaceAddress: String? {
        guard let place = detail?.clientPlace else { return nil }
        let parts = [
            place.address,
            place.landmark,
            place.city,
            place.state,
            place.pincode
        ]
        .compactMap { $0?.nilIfBlank }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private var attendeeCountText: String {
        if let count = detail?.expectedAttendeeCount, count > 0 { return "\(count) Expected" }
        return "—"
    }

    private var inchargeName: String {
        detail?.inchargeStaff?.displayName
            ?? inchargeFromDirectory
            ?? "—"
    }

    private var inchargeFromDirectory: String? {
        guard let id = detail?.proposedSiteVisit?.inchargeStaffId?.nilIfBlank else { return nil }
        return staffDirectory.first { $0.id == id }?.displayName
    }

    private var visitorSummary: String {
        guard let attendee = detail?.attendees?.first else { return "—" }
        let parts = [
            attendee.relation?.nilIfBlank,
            attendee.age?.nilIfBlank.map { "\($0) yrs" },
            attendee.isVeg.map { $0 ? "Veg" : "Non-Veg" }
        ]
        .compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var notesText: String {
        detail?.notes?.nilIfBlank ?? "No notes recorded yet."
    }

    private var visitTypeTitle: String {
        switch (detail?.cpType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sv_cum_cp": return "SV confirmation CP"
        case "direct_cp": return "Direct CP"
        case "site_visit": return "Site Visit"
        default: return "Site Visit"
        }
    }

    private var androidStatusTitle: String {
        switch normalizedStatus {
        case "completed", "complete", "done":
            return "COMPLETED"
        case "cancelled", "canceled", "no_show":
            return "CANCELLED"
        case "picked_up", "client_started":
            return "PICKED UP"
        case "on_site", "arrived":
            return "ON SITE"
        case "consulting", "on_counselling":
            return "ON COUNSELLING"
        case "picked_from_site":
            return "PICKED FROM SITE"
        case "dropped":
            return "DROPPED"
        case "assigned":
            return "ASSIGNED"
        default:
            return "SCHEDULED"
        }
    }

    private var vehicleTitle: String {
        isOwnVehicle ? "Own Vehicle" : "Cab Vehicle"
    }

    private var normalizedTripType: String {
        (visit.tripType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var normalizedStatus: String {
        (detail?.proposedSiteVisit?.status ?? detail?.status ?? visit.status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    private var isOwnVehicle: Bool {
        let mode = (detail?.proposedSiteVisit?.travelMode ?? detail?.vehiclePreference ?? normalizedTripType)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return mode == "own_vehicle"
            || mode == "own"
            || mode == "self"
            || mode == "self_vehicle"
    }

    private var isVisitClosed: Bool {
        if isFleetOutcomePending { return false }
        return siteVisitOutcome?.nilIfBlank != nil
            || siteVisitConvertedBookingID?.nilIfBlank != nil
            || siteVisitCancelledAt != nil
            || [
                "cancelled", "canceled", "no_show", "converted_to_booking",
                "not_interested", "postponed", "other"
            ].contains(normalizedStatus.normalizedSiteVisitValue)
    }

    private var displayDateTime: String {
        let rawDate = detail?.proposedSiteVisit?.scheduledDate?.nilIfBlank
            ?? detail?.scheduledDate?.nilIfBlank
            ?? visit.scheduledDate?.nilIfBlank
        let date = rawDate.map { SiteVisitDateFormatter.displayDate($0) } ?? "—"
        let rawTime = detail?.proposedSiteVisit?.scheduledTime?.nilIfBlank
            ?? detail?.scheduledTime?.nilIfBlank
            ?? visit.scheduledStartTime?.nilIfBlank
        let time = rawTime.map { SiteVisitDateFormatter.displayTime($0) } ?? ""
        return [date, time].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var terminalStepTitle: String? {
        switch normalizedStatus.normalizedSiteVisitValue {
        case "postponed": "POSTPONED"
        case "cancelled", "canceled", "no_show": "CANCELLED"
        default: nil
        }
    }

    private var stepItems: [(title: String, icon: String)] {
        if isOwnVehicle {
            return [
                ("SCHEDULED", "checkmark"),
                ("CLIENT DEPARTURE", "car.fill"),
                ("ON SITE", "building.2.fill"),
                ("CONSULTING", "person.2.fill"),
                ("DONE", "checkmark.circle.fill")
            ]
        }
        return [
            ("SCHEDULED", "checkmark"),
            ("ASSIGNED", "car.fill"),
            ("REACHED CP", "mappin"),
            ("PICKED FROM CP", "house.fill"),
            ("ON SITE", "building.2.fill"),
            ("CONSULTING", "person.2.fill"),
            ("PICKED FROM SITE", "house.fill"),
            ("DROPPED", "mappin.circle.fill"),
            ("DONE", "checkmark.circle.fill")
        ]
    }

    private var displayedStepItems: [(title: String, icon: String)] {
        guard let terminalStepTitle else { return stepItems }
        let reachedCount = min(max(currentStepIndex + 1, 1), max(stepItems.count - 1, 1))
        return Array(stepItems.prefix(reachedCount)) + [(terminalStepTitle, "xmark.circle.fill")]
    }

    private var displayedCurrentStepIndex: Int {
        terminalStepTitle == nil ? currentStepIndex : displayedStepItems.count - 1
    }

    private var currentStepIndex: Int {
        let proposed = detail?.proposedSiteVisit
        if isOwnVehicle {
            var ownIndex: Int
            switch normalizedStatus {
            case "completed", "complete", "done", "closed":
                ownIndex = 4
            case "consulting", "on_counselling", "picked_from_site", "dropped":
                ownIndex = 3
            case "on_site", "arrived", "site_reached":
                ownIndex = 2
            case "picked_up", "client_started", "started", "client_departure", "departed", "assigned":
                ownIndex = 1
            default:
                ownIndex = 0
            }

            if proposed?.travelDeskEndedAt != nil || proposed?.travelDeskOnSiteAt != nil {
                ownIndex = max(ownIndex, 2)
            }
            if proposed?.travelDeskStartedAt != nil {
                ownIndex = max(ownIndex, 1)
            }
            return min(ownIndex, stepItems.count - 1)
        }

        var cabIndex: Int
        switch normalizedStatus {
        case "completed", "complete", "done", "closed":
            cabIndex = 8
        case "dropped":
            cabIndex = 7
        case "picked_from_site":
            cabIndex = 6
        case "consulting", "on_counselling":
            cabIndex = 5
        case "on_site", "arrived", "site_reached":
            cabIndex = 4
        case "picked_up":
            cabIndex = 3
        case "client_started", "started", "client_departure", "departed":
            cabIndex = 3
        case "assigned":
            cabIndex = 1
        default:
            cabIndex = 0
        }

        if proposed?.travelDeskEndedAt != nil {
            cabIndex = max(cabIndex, 7)
        }
        if proposed?.travelDeskPickedFromSiteAt != nil {
            cabIndex = max(cabIndex, 6)
        }
        if proposed?.travelDeskOnSiteAt != nil {
            cabIndex = max(cabIndex, 4)
        }
        if proposed?.travelDeskStartedAt != nil {
            cabIndex = max(cabIndex, 3)
        }
        if proposed?.travelDeskArrivedAt != nil {
            cabIndex = max(cabIndex, 2)
        }
        if cabIndex == 0 && (proposed?.vehicleId?.nilIfBlank != nil || proposed?.travelAgencyId?.nilIfBlank != nil) {
            cabIndex = 1
        }

        return min(cabIndex, stepItems.count - 1)
    }

    private var isOutcomeEnabled: Bool {
        guard !isVisitClosed else { return false }
        return isFleetOutcomePending || [
            "consulting", "on_counselling", "picked_from_site", "dropped",
            "completed", "complete", "done", "closed"
        ].contains(normalizedStatus.normalizedSiteVisitValue)
    }

    private var isFleetOutcomePending: Bool {
        (detail?.completedOffline ?? visit.completedOffline) == true
            && siteVisitOutcome?.nilIfBlank == nil
    }

    private var siteVisitOutcome: String? {
        if detail?.proposedSiteVisit != nil {
            return detail?.proposedSiteVisit?.outcome
        }
        return detail?.outcome ?? visit.outcome
    }

    private var siteVisitConvertedBookingID: String? {
        if detail?.proposedSiteVisit != nil {
            return detail?.proposedSiteVisit?.convertedBookingId
        }
        return detail?.convertedBookingId ?? visit.convertedBookingId
    }

    private var siteVisitCancelledAt: Int64? {
        if detail?.proposedSiteVisit != nil {
            return detail?.proposedSiteVisit?.cancelledAt
        }
        return detail?.cancelledAt
    }

    private var canPostponeVisit: Bool {
        guard authStore.hasPermission("marketing.siteVisits.edit"), !isVisitClosed else { return false }
        let status = normalizedStatus.normalizedSiteVisitValue
        return ![
            "consulting", "on_counselling", "picked_from_site", "dropped",
            "completed", "complete", "done", "closed", "cancelled", "canceled", "no_show"
        ].contains(status)
    }

    private var canCancelVisit: Bool {
        guard authStore.hasPermission("marketing.siteVisits.cancel") else { return false }
        let status = normalizedStatus.normalizedSiteVisitValue
        return ![
            "completed", "complete", "done", "closed",
            "cancelled", "canceled", "no_show", "postponed"
        ].contains(status)
    }
}

private struct CancelSiteVisitSheet: View {
    let siteVisitID: String
    let onCancelled: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "This stops the active site visit and keeps its history for reporting.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0xB42318))
                }

                Section("Reason (optional)") {
                    TextField("Why is this site visit being cancelled?", text: $reason, axis: .vertical)
                        .lineLimit(3...5)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Cancel Site Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep Visit") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancel Visit", role: .destructive) {
                        Task { await cancel() }
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @MainActor
    private func cancel() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Please sign in again."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await MarketingConvexAPIService.cancelSiteVisit(
                token: token,
                request: CancelSiteVisitRequest(id: siteVisitID, reason: reason.nilIfBlank)
            )
            onCancelled()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PostponeSiteVisitSheet: View {
    let siteVisitID: String
    let onSaved: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var scheduledAt = Date()
    @State private var reason = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("New schedule") {
                    DatePicker(
                        "Date & time",
                        selection: $scheduledAt,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                Section("Reason (optional)") {
                    TextField("Why is this SV being postponed?", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Postpone SV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Postpone") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @MainActor
    private func save() async {
        guard let token = authStore.currentSession?.token else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let timeFormatter = DateFormatter()
            timeFormatter.locale = Locale(identifier: "en_US_POSIX")
            timeFormatter.dateFormat = "HH:mm"
            try await MarketingConvexAPIService.postponeSiteVisit(
                token: token,
                request: PostponeSiteVisitRequest(
                    id: siteVisitID,
                    scheduledDate: AppModuleFormatters.ymd.string(from: scheduledAt),
                    scheduledTime: timeFormatter.string(from: scheduledAt),
                    reason: reason.nilIfBlank
                )
            )
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum SiteVisitOverviewOutcome: String, Identifiable {
    case booking = "converted_to_booking"
    case notInterested = "not_interested"
    // Was "postponed" — Android's SV outcome validator only accepts follow_up.
    case followUp = "follow_up"
    case other

    var id: String { rawValue }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedSiteVisitValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

private extension CpVisitStaff {
    var displayName: String? {
        name?.nilIfBlank ?? staffName?.nilIfBlank ?? staffCode?.nilIfBlank
    }
}

private extension AuthUser {
    var siteVisitListDisplayName: String {
        (name?.nilIfBlank ?? employeeId?.nilIfBlank ?? staffId?.nilIfBlank ?? "—").uppercased()
    }
}

#Preview {
    NavigationStack {
        SiteVisitsListView()
    }
    .environment(AuthStore())
}

private struct CreateSiteVisitSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    private enum Routing: String, CaseIterable, Identifiable {
        case direct = "direct_sv"
        case sameArea = "same_area"
        case outstation = "out_of_station"
        case immediate = "immediate_pickup"
        var id: String { rawValue }
        var title: String {
            switch self { case .direct: "Direct SV"; case .sameArea: "Same Area"; case .outstation: "Outstation"; case .immediate: "Immediate SV" }
        }
        var detail: String {
            switch self {
            case .direct: "Client travels directly; no confirmation handoff"
            case .sameArea: "Field staff verifies the client before the visit"
            case .outstation, .immediate: "Requires GM verification"
            }
        }
    }

    private enum StaffField: String, Identifiable {
        case lmo = "LMO", bdo = "BDO", incharge = "Site Incharge", field = "Field Staff"
        case hod = "HOD", avp = "AVP", gm = "GM", senior = "Senior Manager"
        var id: String { rawValue }
    }

    private struct Visitor: Identifiable {
        let id = UUID()
        var name = ""
        var relation = ""
        var age = ""
        var isVeg = true
    }

    let onCreated: () -> Void
    @State private var requestId = UUID().uuidString
    @State private var routing: Routing?
    @State private var origin = "telecaller"
    @State private var phone = ""
    @State private var clientName = ""
    @State private var leadMatches: [TelecallerLeadSearchData] = []
    @State private var selectedLead: TelecallerLeadSearchData?
    @State private var projects: [MarketingProject] = []
    @State private var selectedProject: MarketingProject?
    @State private var staff: [ConvexStaffListItem] = []
    @State private var selectedStaff: [StaffField: ConvexStaffListItem] = [:]
    @State private var activeStaffField: StaffField?
    @State private var showProjectPicker = false
    @State private var scheduledAt = Date().addingTimeInterval(3600)
    @State private var pickupAt = Date().addingTimeInterval(1800)
    @State private var travelMode = "cab"
    @State private var pickupAddress = ""
    @State private var pickupPin: CpMapPinResult?
    @State private var showMapPicker = false
    @State private var visitors: [Visitor] = []
    @State private var notes = ""
    @State private var isLoadingOptions = true
    @State private var isSearchingLead = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var digits: String { String(phone.filter(\.isNumber).suffix(10)) }
    private var requiresPickup: Bool { routing != nil && routing != .direct }
    private var activeStaffItems: [ConvexStaffListItem] {
        guard let field = activeStaffField else { return [] }
        switch field {
        case .lmo, .bdo: return staff.filter(isEligibleLmo)
        case .incharge, .field, .avp, .gm, .senior: return staff.filter(isSalesMarketing)
        case .hod: return staff.filter { $0.isActive }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("SV Type") {
                    Picker("SV Type *", selection: $routing) {
                        Text("Select SV type").tag(Routing?.none)
                        ForEach(Routing.allCases) { item in Text(item.title).tag(Optional(item)) }
                    }
                    if let routing { Text(routing.detail).font(.caption).foregroundStyle(.secondary) }
                }

                Section("Client Details") {
                    TextField("Client phone number *", text: $phone)
                        .keyboardType(.phonePad)
                    if isSearchingLead { ProgressView("Looking up client...") }
                    if !leadMatches.isEmpty {
                        Picker("Linked lead *", selection: $selectedLead) {
                            ForEach(leadMatches) { lead in
                                Text("\(lead.displayName) · \(lead.mobileNumber ?? digits)").tag(Optional(lead))
                            }
                        }
                    } else if digits.count == 10 && !isSearchingLead {
                        TextField("New client's full name *", text: $clientName)
                            .textInputAutocapitalization(.words)
                        Text("No lead found. The backend will create and link the client safely.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Visit Details") {
                    selectionButton("Project *", selectedProject?.name, systemImage: "building.2") { showProjectPicker = true }
                    Picker("Origin", selection: $origin) {
                        Text("Calls").tag("telecaller")
                        Text("Walk-in").tag("walk_in")
                        Text("Campaign").tag("campaign")
                        Text("Referral").tag("referral")
                        Text("Client place visit").tag("client_place_visit")
                    }
                    DatePicker("Scheduled *", selection: $scheduledAt, in: Date()...)
                    if requiresPickup {
                        DatePicker("Pickup time *", selection: $pickupAt, displayedComponents: .hourAndMinute)
                    }
                    Picker("Client travel", selection: $travelMode) {
                        Text("Cab required").tag("cab")
                        Text("Own vehicle").tag("own_vehicle")
                    }
                    .disabled(routing == .direct)
                }

                Section("Assignments") {
                    staffButton(.lmo)
                    staffButton(.bdo)
                    staffButton(.incharge)
                    if routing == .sameArea { staffButton(.field) }
                    staffButton(.hod)
                    staffButton(.avp)
                    staffButton(.gm)
                    staffButton(.senior)
                }

                Section("Pickup Location") {
                    TextField("Pickup address *", text: $pickupAddress, axis: .vertical)
                        .lineLimit(2...5)
                    Button {
                        showMapPicker = true
                    } label: {
                        Label(pickupPin == nil ? "Set pickup pin on map" : "Change pickup pin", systemImage: "map")
                    }
                    if let pin = pickupPin {
                        Text(String(format: "Pinned: %.5f, %.5f", pin.latitude, pin.longitude))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("A precise map pin is required.").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Visitors") {
                    Stepper("Number of visitors: \(visitors.count)", value: visitorCountBinding, in: 0...10)
                    ForEach($visitors) { $visitor in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Visitor \((visitors.firstIndex { $0.id == visitor.id } ?? 0) + 1)").font(.subheadline.weight(.semibold))
                            TextField("Name", text: $visitor.name)
                            TextField("Relation", text: $visitor.relation)
                            TextField("Age", text: $visitor.age).keyboardType(.numberPad)
                            Toggle("Vegetarian", isOn: $visitor.isVeg)
                        }
                        .padding(.vertical, 4)
                    }
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Schedule Site Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSubmitting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Scheduling..." : "Schedule") { Task { await submit() } }
                        .fontWeight(.semibold)
                        .disabled(isSubmitting || isLoadingOptions)
                }
            }
            .task { await loadOptions() }
            .task(id: digits) {
                guard digits.count == 10 else {
                    leadMatches = []; selectedLead = nil; return
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await searchLead()
            }
            .onChange(of: routing) { _, newValue in
                errorMessage = nil
                if newValue == .direct { travelMode = "own_vehicle" }
                if newValue != .sameArea { selectedStaff[.field] = nil }
            }
            .onChange(of: selectedLead) { _, lead in applyLead(lead) }
            .sheet(isPresented: $showProjectPicker) {
                NativeSearchableSelectionSheet(
                    title: "Select Project", prompt: "Search projects", items: projects,
                    selectedId: selectedProject?.id,
                    searchText: { [$0.name, $0.location].compactMap { $0 }.joined(separator: " ") },
                    rowContent: { project, selected in selectionRow(project.name ?? "Unnamed project", project.location, selected) },
                    onSelect: { selectedProject = $0; showProjectPicker = false }
                ).appLibraryNativeSheet([.medium, .large])
            }
            .sheet(item: $activeStaffField) { field in
                NativeSearchableSelectionSheet(
                    title: "Select \(field.rawValue)", prompt: "Search staff", items: activeStaffItems,
                    selectedId: selectedStaff[field]?.id,
                    searchText: { [$0.displayName, $0.employeeId, $0.designation, $0.phone].compactMap { $0 }.joined(separator: " ") },
                    rowContent: { item, selected in selectionRow(item.displayName, item.subtitle, selected) },
                    onSelect: { selectedStaff[field] = $0; activeStaffField = nil }
                ).appLibraryNativeSheet([.medium, .large])
            }
            .sheet(isPresented: $showMapPicker) {
                CpMapPinPicker(
                    initialCoordinate: pickupPin.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    },
                    initialAddress: pickupAddress,
                    onSelect: { result in
                        pickupPin = result
                        if !result.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pickupAddress = result.address }
                        showMapPicker = false
                    }
                )
            }
        }
    }

    private var visitorCountBinding: Binding<Int> {
        Binding(get: { visitors.count }, set: { count in
            while visitors.count < count { visitors.append(Visitor()) }
            if visitors.count > count { visitors.removeLast(visitors.count - count) }
        })
    }

    @ViewBuilder private func selectionButton(_ title: String, _ value: String?, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Label(title, systemImage: systemImage); Spacer(); Text(value ?? "Select").foregroundStyle(value == nil ? .secondary : .primary); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        }.buttonStyle(.plain)
    }

    private func staffButton(_ field: StaffField) -> some View {
        selectionButton(field.rawValue + " *", selectedStaff[field]?.displayName, systemImage: "person") { activeStaffField = field }
    }

    private func selectionRow(_ title: String, _ subtitle: String?, _ selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) { Text(title); if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) } }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x0B61CA)) }
        }
    }

    private func loadOptions() async {
        guard let token = authStore.currentSession?.token else { errorMessage = "Session expired. Please sign in again."; return }
        isLoadingOptions = true
        defer { isLoadingOptions = false }
        do {
            async let projectRequest = MarketingConvexAPIService.getMarketingProjects(token: token)
            async let staffRequest = HRConvexAPIService.listAllStaff(token: token, status: "active")
            let loadedProjects = try await projectRequest
            let loadedStaff = try await staffRequest
            projects = loadedProjects
            staff = loadedStaff.filter(\.isActive)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    private func searchLead() async {
        guard let token = authStore.currentSession?.token else { return }
        isSearchingLead = true
        defer { isSearchingLead = false }
        do {
            leadMatches = try await MarketingConvexAPIService.searchTelecallerLeadsByPhone(token: token, phone: digits)
            selectedLead = leadMatches.first
            if leadMatches.isEmpty { clientName = "" }
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    private func applyLead(_ lead: TelecallerLeadSearchData?) {
        guard let lead else { return }
        clientName = lead.contactName ?? ""
        if let id = lead.projectId, selectedProject == nil { selectedProject = projects.first { $0.id == id } }
        if let id = lead.assignedToStaffId, selectedStaff[.lmo] == nil { selectedStaff[.lmo] = staff.first { $0.id == id && isEligibleLmo($0) } }
        if pickupAddress.isEmpty { pickupAddress = lead.suggestedVisitAddress ?? lead.locationPreferred ?? "" }
        if let lat = lead.suggestedVisitLat, let lng = lead.suggestedVisitLng {
            pickupPin = CpMapPinResult(latitude: lat, longitude: lng, address: pickupAddress)
        }
        if visitors.isEmpty, let name = lead.contactName?.nilIfBlank {
            visitors = [Visitor(name: name, relation: "Self")]
        }
    }

    private func submit() async {
        guard let token = authStore.currentSession?.token else { errorMessage = "Session expired. Please sign in again."; return }
        guard let request = validatedRequest() else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let response = try await MarketingConvexAPIService.createSiteVisit(token: token, request: request)
            requestId = UUID().uuidString
            _ = response
            onCreated()
            dismiss()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    private func validatedRequest() -> CreateSiteVisitRequest? {
        func fail(_ message: String) -> CreateSiteVisitRequest? { errorMessage = message; return nil }
        guard let routing else { return fail("Select SV type.") }
        guard digits.count == 10 else { return fail("Enter the client's 10-digit phone number.") }
        guard selectedLead != nil || !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("Enter the new client's full name.") }
        guard let project = selectedProject else { return fail("Select a project.") }
        guard scheduledAt >= Date() else { return fail("Scheduled date/time cannot be in the past.") }
        if routing == .immediate, !Calendar.current.isDateInToday(scheduledAt) { return fail("Immediate SV must be scheduled for today.") }
        if requiresPickup {
            let pickupClock = Calendar.current.dateComponents([.hour, .minute], from: pickupAt)
            guard let pickupOnVisitDay = Calendar.current.date(
                bySettingHour: pickupClock.hour ?? 0,
                minute: pickupClock.minute ?? 0,
                second: 0,
                of: scheduledAt
            ) else { return fail("Select a valid pickup time.") }
            if pickupOnVisitDay < Date() { return fail("Pickup date/time cannot be in the past.") }
            if pickupOnVisitDay > scheduledAt { return fail("Pickup time can't be after the scheduled site time.") }
        }
        guard let lmo = selectedStaff[.lmo], let bdo = selectedStaff[.bdo], let incharge = selectedStaff[.incharge] else { return fail("Select LMO, BDO, and Site Incharge.") }
        if routing == .sameArea, selectedStaff[.field] == nil { return fail("Select the Same Area verification staff.") }
        guard let hod = selectedStaff[.hod], let avp = selectedStaff[.avp], let gm = selectedStaff[.gm], let senior = selectedStaff[.senior] else { return fail("Complete all required reporting assignments.") }
        let address = pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return fail("Enter the pickup address.") }
        guard let pin = pickupPin else { return fail("Set the client pickup location on the map.") }
        guard pin.latitude.isFinite, pin.longitude.isFinite,
              pin.latitude != 0, pin.longitude != 0,
              (-90...90).contains(pin.latitude), (-180...180).contains(pin.longitude)
        else { return fail("Select a valid pickup location on the map.") }
        let dateFormatter = DateFormatter(); dateFormatter.locale = Locale(identifier: "en_US_POSIX"); dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter(); timeFormatter.locale = Locale(identifier: "en_US_POSIX"); timeFormatter.dateFormat = "HH:mm"
        let attendeeRequests = visitors.map { SiteVisitAttendeeRequest(name: $0.name.nilIfBlank, relation: $0.relation.nilIfBlank, age: $0.age.nilIfBlank, isVeg: $0.isVeg) }
        return CreateSiteVisitRequest(
            requestId: requestId, routing: routing.rawValue, origin: origin,
            leadId: selectedLead?.id, clientName: selectedLead == nil ? clientName.nilIfBlank : nil,
            mobileNumber: digits, projectId: project.id,
            scheduledDate: dateFormatter.string(from: scheduledAt), scheduledTime: timeFormatter.string(from: scheduledAt),
            pickupTime: requiresPickup ? timeFormatter.string(from: pickupAt) : nil,
            travelMode: routing == .direct ? "own_vehicle" : travelMode,
            telecallerId: lmo.id, bdoStaffId: bdo.id, inchargeStaffId: incharge.id,
            fieldStaffId: selectedStaff[.field]?.id, hodStaffId: hod.id, avpStaffId: avp.id,
            gmStaffId: gm.id, seniorManagerStaffId: senior.id,
            pickupAddress: address, pickupLat: pin.latitude, pickupLng: pin.longitude,
            pickupGoogleMapsLink: pin.googleMapsLink,
            expectedAttendeeCount: attendeeRequests.isEmpty ? nil : attendeeRequests.count,
            attendees: attendeeRequests.isEmpty ? nil : attendeeRequests,
            notes: notes.nilIfBlank
        )
    }

    private func isSalesMarketing(_ item: ConvexStaffListItem) -> Bool {
        item.isActive && (item.department ?? "").lowercased().contains("sales") && (item.department ?? "").lowercased().contains("marketing")
    }

    private func isEligibleLmo(_ item: ConvexStaffListItem) -> Bool {
        guard item.isActive else { return false }
        let department = (item.department ?? "").lowercased()
        let designation = (item.designation ?? "").lowercased()
        return (department.contains("telesales") && (designation == "lmo" || designation.contains("lead management") || designation.contains("telecaller")))
            || department.contains("channel partner")
            || (department.contains("sales") && department.contains("marketing") && (designation == "bdo" || designation.contains("business development")))
    }

    private func friendlyError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "No network. Check your connection and try again."
            case .timedOut: return "The server took too long to respond. Please retry."
            default: break
            }
        }
        let message = error.localizedDescription
            .replacingOccurrences(of: "Uncaught Error: ", with: "")
            .split(separator: "\n").first.map(String.init) ?? ""
        return message.isEmpty ? "Couldn't schedule site visit. Please try again." : message
    }
}
