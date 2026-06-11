import CoreLocation
import SwiftUI

/// Marketing > Site Visits list. Mirrors the Android `SiteVisitsListFragment`:
/// pulls scheduled visits across a ±30-day window from
/// `GET /api/sitevisits/my`, sorts newest scheduled date first, and lets the
/// user filter by status bucket and free-text search by place / address.
struct SiteVisitsListView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var visits: [ConvexSiteVisit] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var selectedStatus: SiteVisitStatus = .scheduled
    @State private var searchText = ""
    @State private var isDateFilterEnabled = false
    @State private var selectedDate = Date()
    @State private var hasLoadedOnce = false
    @State private var selectedVisit: ConvexSiteVisit?

    private let visibleStatuses: [SiteVisitStatus] = [.all, .scheduled, .clientStarted, .pickedUp, .completed]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var filteredVisits: [ConvexSiteVisit] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return visits.filter { visit in
            let isProperSiteVisit = (visit.tripType ?? "").lowercased() != "client_place"
                && visit.clientPlaceVisitId == nil
            let matchesStatus = selectedStatus == .all || visit.statusBucket == selectedStatus
            let matchesDate = !isDateFilterEnabled || Self.dateFormatter.string(from: selectedDate) == (visit.scheduledDate ?? "")
            let matchesQuery: Bool = {
                guard !trimmed.isEmpty else { return true }
                let haystacks = [visit.placeName, visit.placeAddress, visit.placeType, visit.status]
                return haystacks.contains { $0?.lowercased().contains(trimmed) == true }
            }()
            return isProperSiteVisit && matchesStatus && matchesDate && matchesQuery
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            androidTopBar
            searchBar
            statusFilterBar
            content
        }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task {
            if !hasLoadedOnce { await load() }
        }
        .sheet(item: $selectedVisit) { visit in
            SiteVisitOverviewSheet(visit: visit) {
                Task { await load() }
            }
            .presentationDetents([.fraction(0.65), .large])
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
                Label(emptyTitle, systemImage: "mappin.slash")
            } description: {
                Text(emptyDescription)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                ForEach(filteredVisits) { visit in
                    Button {
                        selectedVisit = visit
                    } label: {
                        SiteVisitRow(visit: visit)
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

    private var androidTopBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0xF2F6FF), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Site Visits")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            Spacer()

            Button {
                isDateFilterEnabled.toggle()
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0xF2F6FF), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.white)
        .overlay(Rectangle().fill(Color(hex: 0xEEF0F5)).frame(height: 1), alignment: .bottom)
        .overlay(alignment: .bottom) {
            if isDateFilterEnabled {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .padding(.bottom, -44)
                    .opacity(0.01)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            TextField("Search SV", text: $searchText)
                .font(.system(size: 15, weight: .regular))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color(hex: 0x101828))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var emptyTitle: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "No matches"
        }
        return selectedStatus == .all ? "No site visits" : "No \(selectedStatus.title.lowercased()) visits"
    }

    private var emptyDescription: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Try a different place name or address."
        }
        return "Scheduled visits in the last 30 days will appear here."
    }

    private var statusFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleStatuses) { status in
                    let count = countFor(status: status)
                    Button {
                        selectedStatus = status
                    } label: {
                        HStack(spacing: 6) {
                            Text(status.title)
                            if status != .all && count > 0 {
                                Text("\(count)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.white.opacity(0.25), in: Capsule())
                            }
                        }
                        .font(.system(size: 13, weight: selectedStatus == status ? .semibold : .medium))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .foregroundStyle(selectedStatus == status ? Color.white : Color(hex: 0x475467))
                        .background(
                            selectedStatus == status
                                ? Color(hex: 0x0B61CA)
                                : Color.white,
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(Color(hex: 0xE4E7EC), lineWidth: selectedStatus == status ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 2)
        }
        .background(Color(hex: 0xF1F3F8))
    }

    private var dateFilterBar: some View {
        HStack(spacing: 10) {
            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .disabled(!isDateFilterEnabled)

            Button {
                isDateFilterEnabled.toggle()
            } label: {
                Label(isDateFilterEnabled ? "Clear date" : "Filter date", systemImage: isDateFilterEnabled ? "xmark.circle" : "calendar")
            }
            .buttonStyle(.bordered)
            .tint(isDateFilterEnabled ? .red : .accentColor)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(.bar)
    }

    private func countFor(status: SiteVisitStatus) -> Int {
        guard status != .all else { return visits.count }
        return visits.filter { $0.statusBucket == status }.count
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
        HStack(spacing: 12) {
            dateTile

            Rectangle()
                .fill(Color(hex: 0xE4E7EC))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(visit.leadName?.nilIfBlank ?? visit.placeName ?? "Site Visit")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))
                            .lineLimit(1)
                        Label(visit.leadPhone?.nilIfBlank ?? "—", systemImage: "phone.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        statusBadge
                        vehicleBadge
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Divider()
                    .overlay(Color(hex: 0xEAECF0))

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(staffName, systemImage: "person")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: 0x344054))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("BDO")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Label(visit.placeName?.nilIfBlank ?? "—", systemImage: "mappin")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: 0x344054))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("ORIGIN")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
        }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var dateTile: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(dateParts.weekday)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
                Text(dateParts.day)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                Text(dateParts.month)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }
            .frame(width: 58, height: 70)
            .background(Color(hex: 0xEEF4FF), in: RoundedRectangle(cornerRadius: 12))

            Text(formattedTimeRange() ?? "")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 58, height: 28)
                .background(Color(hex: 0xDCEBFF), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(visit.statusBucket.tint)
                .frame(width: 7, height: 7)
            Text(visit.statusBucket.title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color(hex: 0xB45309))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Color(hex: 0xFFF7E6), in: Capsule())
    }

    private var vehicleBadge: some View {
        Label("No Vehicle Assigned", systemImage: "car.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(hex: 0xD92D20))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Color(hex: 0xFFF1F0), in: Capsule())
    }

    private var staffName: String {
        "MANOJ PRABHA..."
    }

    private var dateParts: (weekday: String, day: String, month: String) {
        guard let date = parsedDate(visit.scheduledDate) else { return ("--", "--", "---") }
        let weekday = DateFormatter()
        weekday.dateFormat = "EEE"
        let day = DateFormatter()
        day.dateFormat = "dd"
        let month = DateFormatter()
        month.dateFormat = "MMM"
        return (weekday.string(from: date).uppercased(), day.string(from: date), month.string(from: date).uppercased())
    }

    private func parsedDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        return parser.date(from: raw)
    }

    private func formattedTimeRange() -> String? {
        let start = visit.scheduledStartTime?.trimmingCharacters(in: .whitespaces)
        let end = visit.scheduledEndTime?.trimmingCharacters(in: .whitespaces)
        switch (start?.isEmpty == false ? start : nil, end?.isEmpty == false ? end : nil) {
        case (let s?, let e?): return "\(s) – \(e)"
        case (let s?, nil): return s
        case (nil, let e?): return e
        default: return nil
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

private struct SiteVisitOverviewSheet: View {
    let visit: ConvexSiteVisit
    let onChanged: () -> Void

    @State private var selectedOutcome: SiteVisitOverviewOutcome?

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

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    overviewCard(icon: "person", tint: Color(hex: 0x0B61CA), label: "CLIENT", value: visit.leadName?.nilIfBlank ?? "—")
                    overviewCard(icon: "phone", tint: Color(hex: 0x7C3AED), label: "PHONE", value: visit.leadPhone?.nilIfBlank ?? "—")
                    overviewCard(icon: "building.2", tint: Color(hex: 0xDB2777), label: "PROJECT / PLOT", value: visit.placeName?.nilIfBlank ?? "—")
                    overviewCard(icon: "person", tint: Color(hex: 0xF97316), label: "BDO / TELECALLER", value: "—")
                }

                wideCard(
                    icon: "mappin.circle",
                    tint: Color(hex: 0x0B61CA),
                    label: "PICKUP ADDRESS",
                    value: visit.placeAddress?.nilIfBlank ?? "—"
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    overviewCard(icon: "person.2", tint: Color(hex: 0x667085), label: "ATTENDEES", value: "—")
                    overviewCard(icon: "checkmark.circle.fill", tint: Color(hex: 0x475467), label: "SITE INCHARGE", value: "—")
                }

                HStack(spacing: 12) {
                    bottomTintCard(title: "Visitors", value: visit.leadName?.nilIfBlank ?? "—", tint: Color(hex: 0x0B61CA), bg: Color(hex: 0xEEF4FF))
                    bottomTintCard(title: "Notes", value: "No notes recorded yet.", tint: Color(hex: 0x92400E), bg: Color(hex: 0xFFF8E1))
                }

                outcomeButtons
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.white)
        .sheet(item: $selectedOutcome) { outcome in
            SiteVisitOutcomeSheet(siteVisitId: visit.id, initialOutcome: outcome.rawValue) {
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
                        Text(visit.statusBucket.title.uppercased())
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
                Label("Site Visit", systemImage: "mappin")
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

    private var vehicleTitle: String {
        isOwnVehicle ? "Own Vehicle" : "Cab Vehicle"
    }

    private var normalizedTripType: String {
        (visit.tripType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var normalizedStatus: String {
        (visit.status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var isOwnVehicle: Bool {
        normalizedTripType == "own_vehicle"
            || normalizedTripType == "own vehicle"
            || normalizedTripType == "own"
            || normalizedTripType == "self"
            || normalizedTripType == "self_vehicle"
    }

    private var isVisitClosed: Bool {
        visit.hasLockedOutcome
            || ["completed", "complete", "done", "closed", "cancelled", "canceled"].contains(normalizedStatus)
    }

    private var displayDateTime: String {
        let date = visit.scheduledDate?.nilIfBlank.map { formatDisplayDate($0) } ?? "—"
        let time = visit.scheduledStartTime?.nilIfBlank ?? ""
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
        switch normalizedStatus {
        case "completed", "done": return stepItems.count - 1
        case "dropped": return min(4, stepItems.count - 1)
        case "on_site", "arrived": return isOwnVehicle ? 2 : 3
        case "picked_up": return isOwnVehicle ? 1 : 2
        case "client_started", "started", "client_departure", "departed": return isOwnVehicle ? 1 : 0
        case "assigned": return 1
        default: return 0
        }
    }

    private var isOutcomeEnabled: Bool {
        guard !isVisitClosed else { return false }
        let onSiteIndex = isOwnVehicle ? 2 : 3
        return currentStepIndex >= onSiteIndex
    }

    private func formatDisplayDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
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

#Preview {
    NavigationStack {
        SiteVisitsListView()
    }
    .environment(AuthStore())
}
