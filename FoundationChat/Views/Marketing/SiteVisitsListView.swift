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
    @State private var searchText = ""
    @State private var selectedFilter: SiteVisitListFilter = .all
    @State private var showingDateFilter = false
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var filteredVisits: [ConvexSiteVisit] {
        visits
            .filter { ($0.tripType ?? "").lowercased() != "client_place" && $0.clientPlaceVisitId == nil }
            .filter { selectedFilter.matches($0) }
            .filter { visit in
                let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !needle.isEmpty else { return true }
                return [
                    visit.leadName,
                    visit.placeName,
                    visit.placeAddress
                ]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(needle) }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterPills
            content
        }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("Site Visits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
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
                                visit: visit,
                                bdoName: authStore.currentSession?.user.siteVisitListDisplayName ?? "—"
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

    private var searchBar: some View {
        HStack(spacing: 10) {
            TextField("Search SV", text: $searchText)
                .font(.system(size: 16, weight: .regular))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color(hex: 0x101828))
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SiteVisitListFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .medium))
                            .foregroundStyle(selectedFilter == filter ? .white : Color(hex: 0x475467))
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(
                                selectedFilter == filter ? Color(hex: 0x0B61CA) : Color.white,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(selectedFilter == filter ? Color.clear : Color(hex: 0xEAECF0), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    private var emptyTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Matches Found"
        }
        switch selectedFilter {
        case .all, .scheduled:
            return "No Site Visits Yet"
        case .clientStarted:
            return "No Visits In Progress"
        case .pickedUp:
            return "No Picked Up Visits"
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
        guard let token = authStore.currentSession?.token else {
            loadFailed = true
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        loadFailed = false
        errorMessage = nil
        defer { isLoading = false; hasLoadedOnce = true }

        let fromDateText = Self.dateFormatter.string(from: min(fromDate, toDate))
        let toDateText = Self.dateFormatter.string(from: max(fromDate, toDate))

        do {
            let result = try await HRConvexAPIService.getMySiteVisits(
                token: token,
                fromDate: fromDateText,
                toDate: toDateText
            )
            visits = result
                .filter { ($0.tripType ?? "").lowercased() != "client_place" && $0.clientPlaceVisitId == nil }
                .sorted {
                    let left = $0.creationTime ?? 0
                    let right = $1.creationTime ?? 0
                    if left != right { return left > right }
                    return ($0.scheduledDate ?? "") > ($1.scheduledDate ?? "")
                }
        } catch {
            loadFailed = true
            errorMessage = error.localizedDescription
        }
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
                .fill(Color(hex: 0xEAECF0))
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
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
    let bdoName: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            dateBlock

            Rectangle()
                .fill(Color(hex: 0xEAECF0))
                .frame(width: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(visit.leadName?.nilIfBlank ?? "—")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1D2939))
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

                HStack(spacing: 12) {
                    footerItem(icon: "person", title: bdoName, subtitle: "BDO")
                    footerItem(icon: "mappin", title: visit.destinationTitle, subtitle: "ORIGIN")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var dateBlock: some View {
        VStack(spacing: 8) {
            VStack(spacing: 3) {
                Text(visit.androidDayText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
                    .lineLimit(1)

                Text(visit.androidDateText)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1D2939))
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
                    .foregroundStyle(Color(hex: 0x344054))
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
                    .foregroundStyle(Color(hex: 0xEAECF0))
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
    case cancelled

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var isInProgress: Bool {
        switch self {
        case .clientStarted, .pickedUp, .onSite, .dropped, .inProgress:
            return true
        case .start, .completed, .cancelled:
            return false
        }
    }
}

private enum SiteVisitListFilter: String, CaseIterable, Identifiable {
    case all
    case scheduled
    case clientStarted
    case pickedUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .scheduled: return "Scheduled"
        case .clientStarted: return "Client Started"
        case .pickedUp: return "Picked Up"
        }
    }

    func matches(_ visit: ConvexSiteVisit) -> Bool {
        switch self {
        case .all:
            return true
        case .scheduled:
            return visit.siteVisitStatus == .start
        case .clientStarted:
            return visit.siteVisitStatus.isInProgress
        case .pickedUp:
            return visit.siteVisitStatus == .pickedUp
        }
    }
}

private extension ConvexSiteVisit {
    var siteVisitStatus: AndroidSiteVisitRowStatus {
        let value = (status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch value {
        case "completed", "complete", "done", "closed":
            return .completed
        case "cancelled", "canceled", "no_show":
            return .cancelled
        case "client_started", "started":
            return .clientStarted
        case "picked_up":
            return .pickedUp
        case "on_site", "site_reached":
            return .onSite
        case "dropped":
            return .dropped
        case "in_progress", "ongoing", "active", "arrived":
            return .inProgress
        default:
            return .start
        }
    }

    var rowStatus: (title: String, foreground: Color, background: Color) {
        switch siteVisitStatus {
        case .start:
            return ("Scheduled", Color(hex: 0xB54708), Color(hex: 0xFFFAEB))
        case .clientStarted:
            return ("Client Started", Color(hex: 0xB54708), Color(hex: 0xFFFAEB))
        case .pickedUp:
            return ("Picked up", Color(hex: 0xB54708), Color(hex: 0xFFFAEB))
        case .onSite:
            return ("On site", Color(hex: 0xB54708), Color(hex: 0xFFFAEB))
        case .dropped:
            return ("Dropped", Color(hex: 0xB54708), Color(hex: 0xFFFAEB))
        case .inProgress:
            let value = (status ?? "").normalizedSiteVisitValue
            if value == "arrived" {
                return ("Arrived", Color(hex: 0xB54708), Color(hex: 0xFFFAEB))
            }
            return ("Enroute", Color(hex: 0xB54708), Color(hex: 0xFFFAEB))
        case .completed:
            return ("Completed", Color(hex: 0x027A48), Color(hex: 0xECFDF3))
        case .cancelled:
            return ("Cancelled", Color(hex: 0xB42318), Color(hex: 0xFEF3F2))
        }
    }

    var vehiclePill: (title: String, foreground: Color, background: Color) {
        if isOwnVehicleForList {
            return ("Own Vehicle", Color(hex: 0x175CD3), Color(hex: 0xEFF8FF))
        }
        if isVehicleAssignedForList {
            return ("Vehicle Assigned", Color(hex: 0x027A48), Color(hex: 0xECFDF3))
        }
        return ("No Vehicle Assigned", Color(hex: 0xF04438), Color(hex: 0xFEF3F2))
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
                            .foregroundStyle(Color(hex: 0x667085))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))
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
                    bottomTintCard(title: "Notes", value: notesText, tint: Color(hex: 0x92400E), bg: Color(hex: 0xFFF8E1))
                }

                outcomeButtons
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .background(Color.white)
        .task { await loadEnrichedDetail() }
        .sheet(item: $selectedOutcome) { outcome in
            SiteVisitOutcomeSheet(siteVisitId: visit.id, initialOutcome: outcome.rawValue, locksOutcome: true) {
                onChanged()
                dismiss()
            }
            .appLibraryNativeSheet([.large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(overviewTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
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
                    .foregroundStyle(Color(hex: 0x344054))
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
            }

            HStack {
                Label(displayDateTime, systemImage: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x475467))
                Spacer()
                Label(visitTypeTitle, systemImage: "mappin")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x475467))
            }
        }
    }

    private var progressStepper: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(0..<(stepItems.count - 1), id: \.self) { index in
                    Rectangle()
                        .fill(index < currentStepIndex ? Color(hex: 0x0B61CA) : Color(hex: 0xEAECF0))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 15)
            .zIndex(0)

            HStack(spacing: 0) {
                ForEach(Array(stepItems.enumerated()), id: \.offset) { index, step in
                    VStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(index <= currentStepIndex ? Color(hex: 0x0B61CA) : Color.white)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color(hex: 0xEAECF0), lineWidth: index <= currentStepIndex ? 0 : 1))

                            Image(systemName: step.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(index <= currentStepIndex ? .white : Color(hex: 0x98A2B3))
                        }

                        Text(step.title)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(index <= currentStepIndex ? Color(hex: 0x0B61CA) : Color(hex: 0x98A2B3))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
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
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                if isVisitClosed {
                    Text("Completed")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: 0xEAF3FF), in: Capsule())
                }
            }

            HStack(spacing: 10) {
                outcomeButton("Booking", icon: "briefcase.fill", tint: Color(hex: 0x16A34A), outcome: .booking)
                outcomeButton("Client Not Interested", icon: "hand.thumbsdown.fill", tint: Color(hex: 0xDC2626), outcome: .notInterested)
                outcomeButton("Its Been Postponed", icon: "calendar.badge.clock", tint: Color(hex: 0xD97706), outcome: .postponed)
            }

            if isVisitClosed {
                Label("This site visit outcome is already completed.", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
            } else if !isOutcomeEnabled {
                Label("Outcome buttons will activate once you reach on site.", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
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
            .background((isOutcomeEnabled ? tint.opacity(0.10) : Color(hex: 0xF2F4F7)), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!isOutcomeEnabled)
        .opacity(isOutcomeEnabled ? 1.0 : 0.4)
    }

    private func overviewCard(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1D2939))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 82)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
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
                    .foregroundStyle(Color(hex: 0x344054))
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
    }

    private func bottomTintCard(title: String, value: String, tint: Color, bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x475467))
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .background(bg, in: RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func loadEnrichedDetail() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }

        async let detailTask: CpVisitDetail? = {
            do {
                return try await MarketingConvexAPIService.getCpVisitDetail(token: token, id: visit.id)
            } catch {
                return nil
            }
        }()

        async let staffTask: [ConvexStaffListItem] = {
            do {
                return try await HRConvexAPIService.listAllStaff(token: token)
            } catch {
                return []
            }
        }()

        async let projectTask: [MarketingProject] = {
            do {
                return try await MarketingConvexAPIService.getMarketingProjects(token: token)
            } catch {
                return []
            }
        }()

        detail = await detailTask
        staffDirectory = await staffTask
        projectDirectory = await projectTask
    }

    private var clientName: String {
        detail?.client?.clientName?.nilIfBlank
            ?? detail?.lead?.contactName?.nilIfBlank
            ?? detail?.clientPlace?.name?.nilIfBlank
            ?? visit.leadName?.nilIfBlank
            ?? "—"
    }

    private var clientPhone: String {
        detail?.client?.mobileNumber?.nilIfBlank
            ?? detail?.lead?.mobileNumber?.nilIfBlank
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
            ?? detail?.telecaller?.displayName
            ?? "—"
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
        visit.hasLockedOutcome
            || detail?.convertedBookingId?.nilIfBlank != nil
            || detail?.outcome?.nilIfBlank != nil
            || detail?.completedAt != nil
            || detail?.cancelledAt != nil
            || ["completed", "complete", "done", "closed", "cancelled", "canceled"].contains(normalizedStatus)
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

    private var stepItems: [(title: String, icon: String)] {
        if isOwnVehicle {
            return [
                ("SCHEDULED", "checkmark"),
                ("CLIENT DEPARTURE", "car.fill"),
                ("ON SITE", "building.2.fill"),
                ("DONE", "checkmark.circle.fill")
            ]
        }
        return [
            ("SCHEDULED", "checkmark"),
            ("ASSIGNED", "car.fill"),
            ("PICKED UP", "house.fill"),
            ("ON SITE", "building.2.fill"),
            ("DROPPED", "mappin.circle.fill"),
            ("DONE", "checkmark.circle.fill")
        ]
    }

    private var currentStepIndex: Int {
        let proposed = detail?.proposedSiteVisit
        if isOwnVehicle {
            var ownIndex: Int
            switch normalizedStatus {
            case "completed", "complete", "done", "closed":
                ownIndex = 3
            case "dropped", "on_site", "arrived", "site_reached":
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
            cabIndex = 5
        case "dropped":
            cabIndex = 4
        case "on_site", "arrived", "site_reached":
            cabIndex = 3
        case "picked_up":
            cabIndex = 2
        case "client_started", "started", "client_departure", "departed":
            cabIndex = 2
        case "assigned":
            cabIndex = 1
        default:
            cabIndex = 0
        }

        if proposed?.travelDeskEndedAt != nil || proposed?.droppedAt != nil || proposed?.completedAt != nil {
            cabIndex = max(cabIndex, 4)
        }
        if proposed?.travelDeskOnSiteAt != nil || proposed?.arrivedSiteAt != nil {
            cabIndex = max(cabIndex, 3)
        }
        if proposed?.travelDeskStartedAt != nil || proposed?.pickedUpAt != nil {
            cabIndex = max(cabIndex, 2)
        }
        if cabIndex == 0 && (proposed?.vehicleId?.nilIfBlank != nil || proposed?.travelAgencyId?.nilIfBlank != nil) {
            cabIndex = 1
        }

        return min(cabIndex, stepItems.count - 1)
    }

    private var isOutcomeEnabled: Bool {
        guard !isVisitClosed else { return false }
        let onSiteIndex = isOwnVehicle ? 2 : 3
        return currentStepIndex >= onSiteIndex
    }
}

private enum SiteVisitOverviewOutcome: String, Identifiable {
    case booking = "converted_to_booking"
    case notInterested = "not_interested"
    case postponed = "postponed"

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
