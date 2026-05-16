import CoreLocation
import SwiftUI

struct CpVisitsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var visits: [ConvexSiteVisit] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var searchText = ""
    @State private var selectedFilter: CpVisitFilter = .scheduled
    @State private var isClockedIn = false

    private var filteredVisits: [ConvexSiteVisit] {
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
                        if visit.isOpenableCpVisit {
                            NavigationLink {
                                TripNavigationView(
                                    visitId: visit.id,
                                    placeName: visit.placeName ?? visit.leadName ?? "CP Visit",
                                    placeAddress: visit.placeAddress,
                                    destination: coordinate(for: visit),
                                    initialStatus: visit.status,
                                    tripType: visit.tripType,
                                    clientPlaceVisitId: visit.clientPlaceVisitId,
                                    cpClientMet: visit.cpVisit?.clientMet,
                                    cpOutcome: visit.cpVisit?.outcome,
                                    onTripChanged: {
                                        Task { await load() }
                                    }
                                )
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
        .navigationTitle("Cp Visits")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Client Places"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
        .task { if !hasLoaded { await load() } }
        .sheet(isPresented: $showCreateSheet) {
            NavigationStack {
                CreateCpVisitSheet {
                    showCreateSheet = false
                    Task { await load() }
                }
            }
        }
    }

    private var topBar: some View {
        ZStack {
            Text("Cp Visits")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Spacer()

                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 56)
        .background(.white)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            TextField("Search Client Places", text: $searchText)
                .font(.system(size: 14))
                .textInputAutocapitalization(.words)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 12)
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
        case .scheduled: return "No Cp Visits Yet"
        case .postponed: return "Nothing Postponed"
        case .inProgress: return "No Visits In Progress"
        case .completed: return "No Completed Visits"
        case .cancelled: return "No Cancelled Visits"
        case .all: return "No Cp Visits Yet"
        }
    }

    private var emptySubtitle: String {
        if let errorMessage { return errorMessage }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different search term or switch filters to see other client place visits."
        }
        return "Stay organized by creating or joining teams. Groups help you manage tasks, track progress, and collaborate with your team in one place."
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
            async let visitsRequest = HRConvexAPIService.getMySiteVisits(
                token: token,
                fromDate: AppModuleFormatters.ymd.string(from: from),
                toDate: AppModuleFormatters.ymd.string(from: to)
            )
            async let attendanceRequest = loadClockInState(token: token)
            let all = try await visitsRequest
            isClockedIn = await attendanceRequest
            visits = all
                .filter { $0.tripType == "client_place" || $0.clientPlaceVisitId != nil }
                .sorted { ($0.scheduledDate ?? "") > ($1.scheduledDate ?? "") }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadClockInState(token: String) async -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        async let attendance = try? HRConvexAPIService.getTodayAttendance(token: token)
        async let sessions = try? HRConvexAPIService.getDaySessions(token: token, date: today)
        let todayAttendance = await attendance
        let daySessions = await sessions
        return todayAttendance?.isOpen == true || daySessions?.hasOpenSession == true
    }

    private func coordinate(for visit: ConvexSiteVisit) -> CLLocationCoordinate2D? {
        guard let lat = visit.placeLat, let lng = visit.placeLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

private struct CpVisitCard: View {
    let visit: ConvexSiteVisit
    let isClockedIn: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
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

    private var statsGrid: some View {
        HStack(spacing: 12) {
            VStack(spacing: 16) {
                statRow(icon: "building.2", label: "Site/Client", value: title)
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
        if let startDate = start.flatMap(Self.parseVisitDate) {
            let date = Self.visitDateFormatter.string(from: startDate)
            let time = Self.visitTimeFormatter.string(from: startDate)
            return "\(date) \(time)"
        }
        if let scheduledDate = visit.scheduledDate.flatMap(Self.parseVisitDate) {
            return Self.visitDateFormatter.string(from: scheduledDate)
        }
        if let start, !start.isEmpty, let end, !end.isEmpty {
            return "\(start) - \(end)"
        }
        return start?.blankToNil ?? visit.scheduledDate ?? "-"
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
        if normalizedStatus.isCompleted { return "Completed" }
        if visit.needsCpDetails { return "Reaching" }
        if normalizedStatus.isInProgress { return normalizedStatus == "arrived" ? "Reaching" : "Enroute" }
        if visit.isPostponedCpVisit { return "Postponed" }
        return isClockedIn ? "Ready" : "Ready"
    }

    private var actionTitle: String {
        if normalizedStatus.isCancelled { return "Cancelled" }
        if normalizedStatus.isCompleted { return "Completed" }
        if visit.needsCpDetails { return "Complete Trip" }
        if normalizedStatus == "arrived" { return "Complete Trip" }
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
        if normalizedStatus.isCompleted { return Color(red: 0.09, green: 0.61, blue: 0.18) }
        if visit.isPostponedCpVisit { return textSecondary }
        return Color(red: 0.09, green: 0.61, blue: 0.18)
    }

    private var statusBackground: Color {
        if normalizedStatus.isCancelled { return Color(hex: 0xFEE4E2) }
        if normalizedStatus.isInProgress { return Color(red: 1.0, green: 0.96, blue: 0.90) }
        if normalizedStatus.isCompleted || visit.isPostponedCpVisit { return Color(red: 0.95, green: 0.96, blue: 0.97) }
        return Color(red: 0.90, green: 0.96, blue: 0.92)
    }

    private var actionForeground: Color {
        if normalizedStatus.isCancelled { return Color(hex: 0x7A0F0A) }
        if normalizedStatus.isInProgress { return Color(red: 0.71, green: 0.28, blue: 0.03) }
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

    func matches(_ visit: ConvexSiteVisit) -> Bool {
        let status = (visit.status ?? "").lowercased()
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

private struct CreateCpVisitSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    @State private var clientName = ""
    @State private var phone = ""
    @State private var date = Date()
    @State private var time = ""
    @State private var address = ""
    @State private var mapsLink = ""
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Client") {
                TextField("Client name", text: $clientName)
                    .textContentType(.name)
                TextField("10 digit phone", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }

            Section("Visit") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Time (optional)", text: $time)
                TextField("Address", text: $address, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Google Maps link", text: $mapsLink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .navigationTitle("Create CP Visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting { ProgressView() } else { Text("Create") }
                }
                .disabled(isSubmitting)
            }
        }
        .alert("CP Visit", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func submit() async {
        let normalizedPhone = AppModuleFormatters.normalizePhone(phone)
        guard normalizedPhone.count == 10 else { errorMessage = "Enter 10 digit phone"; return }
        let staffId = authStore.currentSession?.user.staffId ?? authStore.currentSession?.user._id
        guard let staffId, !staffId.isEmpty else { errorMessage = "Staff session missing"; return }
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { errorMessage = "Address is required"; return }
        guard let token = authStore.currentSession?.token else { return }

        let request = CreateCpVisitRequest(
            leadId: nil,
            clientName: clientName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            mobileNumber: normalizedPhone,
            assignedStaffId: staffId,
            scheduledDate: AppModuleFormatters.ymd.string(from: date),
            scheduledTime: time.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            visitAddress: trimmedAddress,
            visitLat: nil,
            visitLng: nil,
            googleMapsLink: mapsLink.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var blankToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isInProgress: Bool {
        ["in-progress", "in_progress", "ongoing", "started", "active", "arrived"].contains(self)
    }

    var isCompleted: Bool {
        ["completed", "complete", "done", "closed"].contains(self)
    }

    var isCancelled: Bool {
        ["cancelled", "canceled"].contains(self)
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
