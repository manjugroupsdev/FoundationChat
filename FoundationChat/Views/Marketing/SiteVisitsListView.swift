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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var filteredVisits: [ConvexSiteVisit] {
        visits.filter { ($0.tripType ?? "").lowercased() != "client_place" && $0.clientPlaceVisitId == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerCount
            content
        }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("Site Visits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Site Visits")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
            }
        }
        .refreshable { await load() }
        .task {
            if !hasLoadedOnce { await load() }
        }
        .sheet(item: $selectedVisit) { visit in
            SiteVisitOverviewSheet(visit: visit) {
                Task { await load() }
            }
            .presentationDetents([.fraction(0.78), .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && visits.isEmpty {
            ProgressView("Loading visits…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Label("No site visits", systemImage: "mappin.slash")
            } description: {
                Text("No site visits assigned to you yet.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(filteredVisits) { visit in
                        Button {
                            guard !visit.siteVisitStatus.isCancelled else { return }
                            selectedVisit = visit
                        } label: {
                            SiteVisitRow(visit: visit)
                        }
                        .buttonStyle(.plain)
                        .disabled(visit.siteVisitStatus.isCancelled)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private var headerCount: some View {
        HStack(spacing: 8) {
            Text("Assigned Site Visits")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
            Spacer()
            Text("\(filteredVisits.count)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .background(Color(hex: 0xF1F3F8))
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

        let calendar = Calendar.current
        let today = Date()
        let from = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 30, to: today) ?? today
        let fromDate = Self.dateFormatter.string(from: from)
        let toDate = Self.dateFormatter.string(from: to)

        do {
            let result = try await HRConvexAPIService.getMySiteVisits(
                token: token,
                fromDate: fromDate,
                toDate: toDate
            )
            visits = result
                .filter { ($0.tripType ?? "").lowercased() != "client_place" && $0.clientPlaceVisitId == nil }
                .sorted { ($0.scheduledDate ?? "") > ($1.scheduledDate ?? "") }
        } catch {
            loadFailed = true
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row

struct SiteVisitRow: View {
    let visit: ConvexSiteVisit

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 42, height: 42)
                .background(Color(hex: 0xEAF3FF), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                Text(visit.placeName?.nilIfBlank ?? "Site visit")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)

                Text(visit.androidWhenText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(visit.androidActionTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(visit.androidActionForeground)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(visit.androidActionBackground, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
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
    case inProgress
    case completed
    case cancelled

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
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
        case "in_progress", "ongoing", "active", "arrived", "on_site", "picked_up", "client_started", "started":
            return .inProgress
        default:
            return .start
        }
    }

    var androidActionTitle: String {
        switch siteVisitStatus {
        case .start: return "Start Trip"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var androidActionForeground: Color {
        switch siteVisitStatus {
        case .start: return .white
        case .inProgress: return Color(hex: 0xB45309)
        case .completed, .cancelled: return Color(hex: 0x667085)
        }
    }

    var androidActionBackground: Color {
        switch siteVisitStatus {
        case .start: return Color(hex: 0x10C400)
        case .inProgress: return Color(hex: 0xFFF4DB)
        case .completed, .cancelled: return Color(hex: 0xEEF0F4)
        }
    }

    var androidWhenText: String {
        let time = scheduledStartTime?.nilIfBlank.map { SiteVisitDateFormatter.displayTime($0) } ?? ""
        guard let date = scheduledDate?.nilIfBlank else {
            return time.isEmpty ? "Available Today" : "Available Today · \(time)"
        }

        let prefix = SiteVisitDateFormatter.isToday(date) ? "Available Today" : SiteVisitDateFormatter.dayMonth(date)
        return time.isEmpty ? prefix : "\(prefix) · \(time)"
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

    static func displayDate(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }

    static func displayTime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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

    @State private var selectedOutcome: SiteVisitOverviewOutcome?
    @State private var detail: CpVisitDetail?
    @State private var staffDirectory: [ConvexStaffListItem] = []
    @State private var isLoadingDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(Color(hex: 0xD0D5DD))
                    .frame(width: 48, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

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
            .padding(.bottom, 24)
        }
        .background(Color.white)
        .task { await loadEnrichedDetail() }
        .sheet(item: $selectedOutcome) { outcome in
            SiteVisitOutcomeSheet(siteVisitId: visit.id, initialOutcome: outcome.rawValue, locksOutcome: true) {
                onChanged()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(visit.placeName?.nilIfBlank ?? "Site Visit")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: 0x0B61CA))
                            .frame(width: 8, height: 8)
                        Text(androidStatusTitle.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                    }
                }

                Spacer()

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
        HStack(spacing: 0) {
            ForEach(Array(stepItems.enumerated()), id: \.offset) { index, step in
                VStack(spacing: 7) {
                    Image(systemName: step.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(index <= currentStepIndex ? .white : Color(hex: 0x98A2B3))
                        .frame(width: 32, height: 32)
                        .background(index <= currentStepIndex ? Color(hex: 0x0B61CA) : Color.white, in: Circle())
                        .overlay(Circle().stroke(Color(hex: 0xEAECF0), lineWidth: index <= currentStepIndex ? 0 : 1))

                    Text(step.title)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(index <= currentStepIndex ? Color(hex: 0x0B61CA) : Color(hex: 0x98A2B3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .center) {
                    if index < stepItems.count - 1 {
                        Rectangle()
                            .fill(index < currentStepIndex ? Color(hex: 0x0B61CA) : Color(hex: 0xEAECF0))
                            .frame(height: 2)
                            .offset(x: 32, y: -12)
                    }
                }
            }
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

        detail = await detailTask
        staffDirectory = await staffTask
    }

    private var clientName: String {
        detail?.lead?.contactName?.nilIfBlank
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

    private var projectName: String {
        detail?.project?.name?.nilIfBlank
            ?? visit.placeName?.nilIfBlank
            ?? "—"
    }

    private var staffName: String {
        detail?.assignedStaff?.displayName
            ?? detail?.telecaller?.displayName
            ?? "—"
    }

    private var pickupAddress: String {
        detail?.clientPlace?.formattedAddress?.nilIfBlank
            ?? detail?.clientPlace?.address?.nilIfBlank
            ?? visit.placeAddress?.nilIfBlank
            ?? "—"
    }

    private var attendeeCountText: String {
        if let count = detail?.expectedAttendeeCount, count > 0 { return "\(count)" }
        if let count = detail?.attendees?.count, count > 0 { return "\(count)" }
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
            attendee.name?.nilIfBlank,
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
        let value = normalizedStatus.replacingOccurrences(of: "_", with: " ")
        return value.isEmpty ? "Scheduled" : value.capitalized
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
            || detail?.convertedSiteVisitId?.nilIfBlank != nil
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

        if isOwnVehicle {
            switch cabIndex {
            case ...1: return 0
            case 2: return 1
            case 3...4: return 2
            default: return 3
            }
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
}

private extension CpVisitStaff {
    var displayName: String? {
        staffName?.nilIfBlank ?? staffCode?.nilIfBlank
    }
}

#Preview {
    NavigationStack {
        SiteVisitsListView()
    }
    .environment(AuthStore())
}
