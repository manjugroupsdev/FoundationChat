import CoreLocation
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
    @State private var isClockedIn = false
    @State private var selectedOutcomeVisit: CpListVisit?

    private var filteredVisits: [CpListVisit] {
        visits.filter { visit in
            selectedFilter.matches(visit)
                && (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || visit.matchesCpSearch(searchText))
        }
    }

    var body: some View {
        ScrollView {
            filterPills

            if isLoading && visits.isEmpty {
                skeletonList
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else if filteredVisits.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredVisits) { visit in
                        if visit.isPendingOutcomeCpVisit {
                            Button {
                                selectedOutcomeVisit = visit
                            } label: {
                                CpVisitCard(visit: visit, isClockedIn: isClockedIn)
                            }
                            .buttonStyle(.plain)
                        } else if visit.isOpenableCpVisit {
                            NavigationLink {
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
                                    onTripChanged: {
                                        Task { await load() }
                                    }
                                )
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .refreshable { await load() }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("CP Visits")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Client Places"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("CP Visits")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
            }

            // GM out-of-geofence CP completion approval queue. Android launches
            // this only from the "CP completion needs approval" push and the
            // backend scopes the feed to the resolved approver; there is no
            // client-side permission constant, so the entry is shown for all
            // (non-approvers just see an empty queue). See VERIFY notes.
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
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                }
                .accessibilityLabel("Create CP visit")
            }
        }
        .task { if !hasLoaded { await load() } }
        .sheet(isPresented: $showCreateSheet) {
            CreateCpVisitSheet {
                showCreateSheet = false
                Task { await load() }
            }
            .appFormActivity()
            .appLibraryNativeSheet([.height(720), .large])
            .presentationBackground(Color.white)
        }
        .sheet(item: $selectedOutcomeVisit) { visit in
            CompleteCpVisitSheet(
                cpVisitId: visit.clientPlaceVisitId,
                initialOutcome: visit.outcome,
                cpType: visit.cpType,
                onCompleted: {
                    selectedOutcomeVisit = nil
                    Task { await load() }
                }
            )
            .environment(authStore)
        }
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CpVisitFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: selectedFilter == filter ? .semibold : .medium))
                            .foregroundStyle(selectedFilter == filter ? .white : Color(hex: 0x475467))
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(
                                selectedFilter == filter ? Color(hex: 0x0B61CA) : .white,
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
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.top, 16)
            Text(emptySubtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x667085))
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
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        let calendar = Calendar.current
        let today = Date()
        let from = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 30, to: today) ?? today
        do {
            async let visitsRequest = MarketingConvexAPIService.getMyMarketingCpVisits(
                token: token,
                fromDate: AppModuleFormatters.ymd.string(from: from),
                toDate: AppModuleFormatters.ymd.string(from: to)
            )
            async let attendanceRequest = loadClockInState(token: token)
            let all = try await visitsRequest
            isClockedIn = await attendanceRequest
            visits = all
                .compactMap(CpListVisit.init(detail:))
                .sorted(by: CpListVisit.androidOrder)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadClockInState(token: String) async -> Bool {
        await AttendanceTrackingGate.hasOpenSessionForToday(token: token)
    }

    private func coordinate(for visit: CpListVisit) -> CLLocationCoordinate2D? {
        guard let lat = visit.placeLat, let lng = visit.placeLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
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
        self.id = detail.fieldVisitId?.blankToNil ?? detail.id
        self.fieldVisitId = detail.fieldVisitId
        self.clientPlaceVisitId = detail.id
        self.clientPlaceId = detail.clientPlaceId
        self.scheduledDate = detail.scheduledDate
        self.scheduledStartTime = detail.scheduledTime
        self.scheduledEndTime = nil
        let fieldStatus = detail.fieldVisit?.status?.blankToNil
        self.status = fieldStatus ?? detail.status
        self.placeName = detail.client?.clientName?.blankToNil
            ?? detail.lead?.contactName?.blankToNil
            ?? detail.clientPlace?.name?.blankToNil
            ?? "CP visit"
        self.placeAddress = detail.clientPlace?.formattedAddress?.blankToNil
            ?? detail.clientPlace?.address?.blankToNil
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
        self.leadName = detail.lead?.contactName?.blankToNil ?? detail.client?.clientName?.blankToNil
        self.leadPhone = detail.lead?.mobileNumber?.blankToNil
            ?? detail.client?.mobileNumber?.blankToNil
            ?? detail.clientPlace?.contactPhone?.blankToNil
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
        !normalizedStatus.isCompleted && !normalizedStatus.isCancelled
    }

    var isCompletedCpVisit: Bool {
        normalizedStatus.isCompleted
    }

    var isPendingOutcomeCpVisit: Bool {
        normalizedStatus.isCompleted && outcome?.blankToNil == nil
    }

    var typeLabel: String {
        if let cpTypeLabel { return cpTypeLabel }
        return visitCategory == "sv_cum_cp" ? "SV Confirmation CP" : "Direct CP"
    }

    private var cpTypeLabel: String? {
        switch cpType?.normalizedMarker {
        case "collection_cp": return "Collection CP"
        case "old_client": return "Old Client CP"
        case "gift_distribution": return "Gift Distribution"
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
            cpType
        ]
        .compactMap { $0?.lowercased() }
        .contains { $0.contains(needle) }
    }

    static func androidOrder(_ lhs: CpListVisit, _ rhs: CpListVisit) -> Bool {
        if lhs.sortGroup != rhs.sortGroup { return lhs.sortGroup < rhs.sortGroup }
        let leftDate = lhs.scheduledDate ?? ""
        let rightDate = rhs.scheduledDate ?? ""
        if leftDate != rightDate { return leftDate > rightDate }
        return (lhs.detail.createdAt ?? 0) > (rhs.detail.createdAt ?? 0)
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

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.13, green: 0.73, blue: 0.30))
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
        if isLive && d.clientUnavailableWarning == true {
            noticeRow(text: "⚠ Client unavailable — last 3 visits missed")
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
                    .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.10))
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

    private var initial: String {
        title.first.map { String($0).uppercased() } ?? "C"
    }

    private var routeText: String {
        (visit.placeLat != nil && visit.placeLng != nil) ? "Open route" : "Not mapped"
    }

    private var timeText: String {
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
        if visit.isPostponedCpVisit { return "Postponed" }
        if normalizedStatus.isCancelled { return "Cancelled" }
        if normalizedStatus.isCompleted { return "Complete" }
        if normalizedStatus == "arrived" { return "At client place" }
        if normalizedStatus.isInProgress { return "Tracking" }
        return "After start"
    }

    private var statusTitle: String {
        if normalizedStatus.isCancelled { return "Cancelled" }
        if normalizedStatus.isCompleted && visit.outcome?.blankToNil == nil { return "Pending" }
        if normalizedStatus.isCompleted { return "Completed" }
        if visit.needsCpDetails { return "Reaching" }
        if normalizedStatus.isInProgress { return normalizedStatus == "arrived" ? "Reaching" : "Enroute" }
        if visit.isPostponedCpVisit { return "Postponed" }
        return isClockedIn ? "Ready" : "Ready"
    }

    private var actionTitle: String {
        if normalizedStatus.isCancelled { return "Cancelled" }
        if normalizedStatus.isCompleted && visit.outcome?.blankToNil == nil { return "Pending" }
        if normalizedStatus.isCompleted { return "Completed" }
        if visit.needsCpDetails { return visit.cpCompletionActionTitle }
        if normalizedStatus == "arrived" { return visit.cpCompletionActionTitle }
        if normalizedStatus.isInProgress { return "Enroute" }
        if visit.isPostponedCpVisit { return "Reschedule" }
        if !isClockedIn { return "Need to Clock In" }
        return "Start Trip"
    }

    private var showsPlayIcon: Bool {
        if normalizedStatus.isCompleted || normalizedStatus.isCancelled || normalizedStatus.isInProgress { return false }
        return true
    }

    private var statusTextColor: Color {
        if normalizedStatus.isCancelled { return Color(hex: 0xB42318) }
        if normalizedStatus.isInProgress { return Color(red: 0.71, green: 0.28, blue: 0.03) }
        if normalizedStatus.isCompleted && visit.outcome?.blankToNil == nil { return Color(hex: 0xB54708) }
        if normalizedStatus.isCompleted { return Color(red: 0.09, green: 0.61, blue: 0.18) }
        if visit.isPostponedCpVisit { return textSecondary }
        return Color(red: 0.09, green: 0.61, blue: 0.18)
    }

    private var statusBackground: Color {
        if normalizedStatus.isCancelled { return Color(hex: 0xFEE4E2) }
        if normalizedStatus.isInProgress { return Color(red: 1.0, green: 0.96, blue: 0.90) }
        if normalizedStatus.isCompleted && visit.outcome?.blankToNil == nil { return Color(hex: 0xFEF0C7) }
        if normalizedStatus.isCompleted || visit.isPostponedCpVisit { return Color(red: 0.95, green: 0.96, blue: 0.97) }
        return Color(red: 0.90, green: 0.96, blue: 0.92)
    }

    private var actionForeground: Color {
        if normalizedStatus.isCancelled { return Color(hex: 0x7A0F0A) }
        if normalizedStatus.isInProgress { return Color(red: 0.71, green: 0.28, blue: 0.03) }
        if normalizedStatus.isCompleted && visit.outcome?.blankToNil == nil { return Color(hex: 0xB54708) }
        if normalizedStatus.isCompleted { return Color(hex: 0x1F7A3F) }
        return .white
    }

    private var actionBackground: some ShapeStyle {
        if normalizedStatus.isCancelled {
            return AnyShapeStyle(Color(hex: 0xFEE4E2))
        }
        if normalizedStatus.isInProgress {
            return AnyShapeStyle(Color(red: 1.0, green: 0.96, blue: 0.90))
        }
        if normalizedStatus.isCompleted {
            return AnyShapeStyle(Color(red: 0.89, green: 0.91, blue: 0.93))
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

    private var textPrimary: Color { Color(red: 0.06, green: 0.09, blue: 0.16) }
    private var textSecondary: Color { Color(red: 0.40, green: 0.44, blue: 0.52) }

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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .scheduled: return "Scheduled"
        case .postponed: return "Postponed"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
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
            return status.isCompleted
        case .cancelled:
            return status.isCancelled
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
                            .foregroundStyle(Color(hex: 0x667085))
                    }
                    .padding(.horizontal, 16)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xFEE4E2), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(16)
        }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
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
                        .foregroundStyle(Color(hex: 0x101828))
                    Text(primaryPhone)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                    Text(primaryAddress)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0x667085))
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
                .foregroundStyle(Color(hex: 0x667085))
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
                .foregroundStyle(Color(hex: 0x101828))
            twoColumnRow("Date", formattedDate(summary.scheduledDate), "Time", formattedTime)
            twoColumnRow("Trip Type", tripTypeTitle, "Location", isGeoMapped ? "Geo-mapped" : "Not mapped")
            if let notes = detail?.notes?.blankToNil, !isBookingOutcome {
                Divider()
                Text(notes)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x475467))
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
                .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))
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
                        Color(hex: 0xF2F4F7).overlay(Image(systemName: "photo"))
                    default:
                        Color(hex: 0xF2F4F7).overlay(ProgressView())
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
                        .foregroundStyle(Color(hex: 0x667085))
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
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x667085))
            Spacer()
            Text(value?.blankToNil ?? "-")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x101828))
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
        detail?.client?.clientName?.blankToNil
            ?? detail?.lead?.contactName?.blankToNil
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
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
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
    @State private var selectedCpType: CpVisitCreateType = .direct
    @State private var bookingGatePhone: String?
    @State private var bookingGateCount = 0
    @State private var isCheckingBookingGate = false
    @State private var projects: [MarketingProject] = []
    @State private var selectedProject: MarketingProject?
    @State private var staff: [ConvexStaffListItem] = []
    @State private var selectedStaff: ConvexStaffListItem?
    @State private var leadMatches: [TelecallerLeadSearchData] = []
    @State private var selectedLead: TelecallerLeadSearchData?
    @State private var isLoadingProjects = false
    @State private var isLoadingStaff = false
    @State private var isSearchingLead = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showStaffPicker = false
    @State private var showProjectPicker = false

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
                        .foregroundStyle(Color(hex: 0x667085))
                        .padding(.bottom, 2)

                    cpTextField("Client Phone Number *", placeholder: "Enter Client Number", text: $phone, systemImage: "phone", keyboard: .phonePad)
                        .onChange(of: phone) { _, _ in
                            selectedLead = nil
                            leadMatches = []
                            bookingGatePhone = nil
                            bookingGateCount = 0
                        }

                    cpTextField("Client Name", placeholder: "Enter Client Name", text: $clientName, systemImage: "person")

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
                        .foregroundStyle(Color(hex: 0x475467))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(hex: 0xF3F4F6), in: Capsule())
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
                                    .foregroundStyle(Color(hex: 0x101828))
                                Text(lead.mobileNumber ?? "No mobile")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: 0x667085))
                                if let area = lead.suggestedVisitAddress?.blankToNil ?? lead.locationPreferred?.blankToNil {
                                    Text(area)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(hex: 0x667085))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: 0xF9FAFB), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }

                    staffPicker
                    projectPicker
                    cpTypePicker
                    cpDatePicker

                    cpTextField("Door / Plot No", placeholder: "Enter Door / Plot No", text: $doorNo, systemImage: "house")
                    cpTextField("Street", placeholder: "Enter Street", text: $street, systemImage: "road.lanes")
                    cpTextField("Address Line 1 *", placeholder: "Enter Address", text: $addressLine1, systemImage: "mappin.and.ellipse", axis: .vertical)
                    cpTextField("Landmark / Address Line 2", placeholder: "Enter Landmark", text: $addressLine2, systemImage: "signpost.right")
                    cpTextField("City *", placeholder: "Enter City", text: $city, systemImage: "building")
                    cpTextField("State", placeholder: "Enter State", text: $state, systemImage: "map.fill")
                    cpTextField("Pincode *", placeholder: "6 digits", text: $pincode, systemImage: "checkmark.circle", keyboard: .numberPad)

                    cpTextField("Google Map Link (Optional)", placeholder: "Skip if you only have the address", text: $mapsLink, systemImage: "link", keyboard: .URL)

                    HStack(alignment: .top, spacing: 10) {
                        cpTextField("Latitude (Optional)", placeholder: "Latitude", text: $latitude, systemImage: "location.north", keyboard: .decimalPad)
                        cpTextField("Longitude (Optional)", placeholder: "Longitude", text: $longitude, systemImage: "location.north.line", keyboard: .decimalPad)
                    }

                    cpTextField("Notes", placeholder: "Enter Notes", text: $notes, systemImage: "note.text", axis: .vertical)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 104)
            }

            VStack(spacing: 0) {
                Divider()
                    .overlay(Color(hex: 0xEAECF0))

                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x475467))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white, in: Capsule())
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
                .background(Color.white)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .appCompactSheetCTAContainer()
        .alert("CP Visit", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showStaffPicker) {
            NativeSearchableSelectionSheet(
                title: "Select Staff",
                prompt: "Search staff",
                items: staff,
                selectedId: selectedStaff?.id,
                searchText: { item in
                    [item.displayName, item.designation, item.phone].compactMap(\.self).joined(separator: " ")
                },
                rowContent: { item, isSelected in
                    staffSelectionRow(item, isSelected: isSelected)
                },
                onSelect: { item in
                    selectedStaff = item
                    showStaffPicker = false
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
        .task { await loadBootstrapData() }
    }

    private func selectedInfo(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
        }
        .padding(12)
        .background(Color(hex: 0xF9FAFB), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .foregroundStyle(Color(hex: 0x344054))
            HStack(alignment: axis == .vertical ? .top : .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
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
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func staffSelectionRow(_ item: ConvexStaffListItem, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                if let designation = item.designation, !designation.isEmpty {
                    Text(designation)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
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
                    .foregroundStyle(Color(hex: 0x101828))
                if let location = project.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
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
            Menu {
                ForEach(CpVisitCreateType.allCases) { type in
                    Button {
                        Task { await selectCpType(type) }
                    } label: {
                        Label(type.title, systemImage: selectedCpType == type ? "checkmark" : "circle")
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCpType.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: 0x101828))
                            .lineLimit(1)
                        Text(selectedCpType.subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: 0x667085))
                            .lineLimit(1)
                    }
                    Spacer()
                    if isCheckingBookingGate {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x667085))
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
        }
    }

    private func pickerShell<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x344054))
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 20)
                content()
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .foregroundStyle(Color(hex: 0x667085))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var cpDatePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date & Time")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x344054))
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
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
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
            )
        }
        .padding(.top, 16)
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
            let allStaff = try await HRConvexAPIService.listAllStaff(token: token)
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
            leadMatches = try await MarketingConvexAPIService.searchTelecallerLeadsByPhone(token: token, phone: normalizedPhone)
            if leadMatches.count == 1, let lead = leadMatches.first {
                applyLead(lead)
            } else if leadMatches.isEmpty {
                errorMessage = "No existing client found. You can create with manual details."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyLead(_ lead: TelecallerLeadSearchData) {
        selectedLead = lead
        fillIfBlank($clientName, lead.displayName)
        phone = AppModuleFormatters.normalizePhone(lead.mobileNumber ?? phone)

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
        }

        leadMatches = []
    }

    private func fillIfBlank(_ binding: Binding<String>, _ value: String?) {
        guard let value = value?.blankToNil else { return }
        if binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            binding.wrappedValue = value
        }
    }

    @MainActor
    private func selectCpType(_ type: CpVisitCreateType) async {
        if !type.requiresConfirmedBooking {
            selectedCpType = type
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        let normalizedPhone = AppModuleFormatters.normalizePhone(phone)
        guard normalizedPhone.count == 10 else { errorMessage = "Enter 10 digit phone"; return }
        let staffId = selectedStaff?.id ?? authStore.currentSession?.user.staffId ?? authStore.currentSession?.user._id
        guard let staffId, !staffId.isEmpty else { errorMessage = "Staff session missing"; return }
        guard selectedProject != nil else { errorMessage = "Project is required"; return }
        guard selectedStaff != nil || !(staffId.isEmpty) else { errorMessage = "Field staff is required"; return }
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
        guard normalizedPincode.count == 6 else {
            errorMessage = "Pincode must be 6 digits"
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
        if selectedCpType.requiresConfirmedBooking {
            let cachedPhone = bookingGatePhone ?? ""
            if cachedPhone != normalizedPhone || bookingGateCount == 0 {
                errorMessage = "\(selectedCpType.title) needs a confirmed booking for this mobile. Re-pick the CP type to verify."
                return
            }
        }

        let request = CreateCpVisitRequest(
            leadId: selectedLead?.id,
            projectId: selectedProject?.id,
            clientName: clientName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            mobileNumber: normalizedPhone,
            assignedStaffId: staffId,
            scheduledDate: AppModuleFormatters.ymd.string(from: date),
            scheduledTime: Self.timeFormatter.string(from: date),
            cpType: selectedCpType.payloadValue,
            visitAddress: trimmedAddress,
            visitLat: coordinateValue(latitude),
            visitLng: coordinateValue(longitude),
            googleMapsLink: mapsLink.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: serializedNotes
        )

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await MarketingConvexAPIService.createCpVisit(token: token, request: request)
            onCreated()
        } catch {
            errorMessage = error.localizedDescription
        }
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
            "client_started", "ongoing", "started", "active", "arrived"
        ].contains(self)
    }

    var isCompleted: Bool {
        ["completed", "complete", "done", "closed"].contains(self)
    }

    var isCancelled: Bool {
        ["cancelled", "canceled", "no_show"].contains(self)
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

private enum CpVisitCreateType: String, CaseIterable, Identifiable {
    case direct = "direct_cp"
    case svCumCp = "sv_cum_cp"
    case followUp = "follow_up"
    case bookingCp = "booking_cp"
    case collectionCp = "collection_cp"
    case oldClient = "old_client"
    case giftDistribution = "gift_distribution"

    var id: String { rawValue }

    var payloadValue: String? {
        self == .direct ? nil : rawValue
    }

    var requiresConfirmedBooking: Bool {
        self == .collectionCp || self == .bookingCp
    }

    var title: String {
        switch self {
        case .direct: return "Direct CP"
        case .svCumCp: return "SV cum CP"
        case .followUp: return "Follow-up"
        case .bookingCp: return "Booking CP"
        case .collectionCp: return "Collection CP"
        case .oldClient: return "Old Client"
        case .giftDistribution: return "Gift Distribution"
        }
    }

    var subtitle: String {
        switch self {
        case .direct: return "Regular client-place visit"
        case .svCumCp: return "Confirm a site visit"
        case .followUp: return "Continue a postponed client"
        case .bookingCp: return "Paperwork for active booking"
        case .collectionCp: return "Collect payment at client place"
        case .oldClient: return "Re-engage previous client"
        case .giftDistribution: return "Drop loyalty gift"
        }
    }
}
