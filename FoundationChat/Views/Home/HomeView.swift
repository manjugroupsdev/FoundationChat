import CoreLocation
import SwiftUI

/// Home tab cloned from Android `HomeFragment`, adapted to SwiftUI.
///
/// Scope note: this view owns the Home surface only.
struct HomeView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var todayVisits: [GeoTrackTodayVisit] = []
    @State private var assignedPlaces: [GeoTrackAssignedPlace] = []
    @State private var hasOpenSession = false
    @State private var unreadCount = 0
    @State private var isLoading = true
    @State private var isVisitsLoading = false
    @State private var loadError: String?
    @State private var visitToOpen: GeoTrackTodayVisit?
    @State private var appeared = false

    private let geoAPI = GeoTrackAPIService.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                HomePalette.pageBackground.ignoresSafeArea()

                headerTopFill

                ScrollView {
                    VStack(spacing: 0) {
                        blueHeader
                            .offset(y: appeared ? 0 : -260)
                            .animation(.smooth(duration: 0.62), value: appeared)

                        contentArea
                    }
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .refreshable { await reload() }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $visitToOpen) { visit in
                TripNavigationView(
                    visitId: visit.id,
                    placeId: nil,
                    placeName: visit.displayName,
                    placeAddress: visit.placeAddress,
                    destination: coordinate(for: visit),
                    initialStatus: visit.status,
                    tripType: visit.tripType,
                    clientPlaceVisitId: visit.clientPlaceVisitId,
                    cpClientMet: visit.cpVisit?.clientMet,
                    cpOutcome: visit.cpVisit?.outcome,
                    requiresOpenAttendance: true,
                    onTripChanged: {
                        Task { await reload() }
                    }
                )
            }
            .task {
                await reload()
                appeared = true
            }
            .onAppear {
                guard appeared else { return }
                Task { await reload() }
            }
        }
    }

    // MARK: - Header

    private var headerTopFill: some View {
        HomePalette.headerBlue
        .frame(height: 120)
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private var blueHeader: some View {
        VStack(spacing: 0) {
            summaryBanner
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [HomePalette.headerBlue, HomePalette.headerBlueDark],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        )
    }

    private var summaryBanner: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Plan, Visit & Achieve")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 58)

                Text("Track your tasks, visits and\nattendance in one place.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.93, green: 0.92, blue: 1.0))
                    .lineSpacing(2)
                    .padding(.top, 7)

                Spacer()

                Button {
                    // Android keeps this as a Home banner affordance; the
                    // summary data is already integrated into Home refresh.
                } label: {
                    Text("View My Summary")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HomePalette.headerBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.92), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)

            homeHeaderActions
                .padding(.top, 16)
                .padding(.trailing, 12)

            decorativeStars

            Image("HomeBannerCamera")
                .resizable()
                .scaledToFit()
                .frame(width: 118, height: 100)
                .padding(.top, 58)
                .padding(.trailing, 6)
                .accessibilityHidden(true)
        }
        .frame(height: 184)
        .clipped()
    }

    private var homeHeaderActions: some View {
        HStack(spacing: 6) {
            NavigationLink {
                NotificationsListView()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.14), in: Circle())

                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : String(unreadCount))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red, in: Capsule())
                            .offset(x: 2, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                ProfileView()
            } label: {
                ProfileAvatarView(label: authStore.currentUserLabel)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(Color.white.opacity(0.18), in: Capsule())
    }

    private var decorativeStars: some View {
        ZStack {
            ForEach(HomeStar.allCases) { star in
                Image(systemName: "sparkle")
                    .font(.system(size: star.size, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(star.opacity))
                    .rotationEffect(.degrees(star.rotation))
                    .offset(x: star.x, y: star.y)
            }
        }
        .frame(width: 120, height: 100)
        .padding(.top, 46)
        .padding(.trailing, 22)
        .accessibilityHidden(true)
    }

    // MARK: - Content

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Text("Today's Trip")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HomePalette.textPrimary)

                Image("HomeTodayTripGlobe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                if !visibleVisits.isEmpty {
                    Text("\(visibleVisits.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HomePalette.badgePurple)
                        .frame(width: 20, height: 20)
                        .background(Color(red: 0.95, green: 0.93, blue: 1.0), in: Circle())
                }

                Spacer()
            }
            .padding(.top, 28)

            if isLoading {
                skeletonList
            } else if visibleVisits.isEmpty {
                emptyTripCard
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleVisits) { visit in
                        HomeTripCard(
                            title: visit.displayName,
                            time: formatVisitTimeOrDate(visit),
                            distance: visit.hasMappedLocation ? "Open route" : "Not mapped",
                            state: tripState(for: visit),
                            etaText: etaText(for: visit),
                            canOpen: canOpen(visit)
                        ) {
                            guard canOpen(visit) else { return }
                            visitToOpen = visit
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let loadError, visibleVisits.isEmpty {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.pageBackground)
    }

    private var emptyTripCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Trip")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HomePalette.textPrimary)

                Text("Your schedule for the day")
                    .font(.system(size: 12))
                    .foregroundStyle(HomePalette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(spacing: 0) {
                Image("HomeEmptyTrips")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 152, height: 142)
                    .opacity(0.56)
                    .accessibilityHidden(true)
                    .padding(.top, 12)

                Text("No Trips Available")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.09, green: 0.11, blue: 0.14))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                Text("It looks like you don't have any meetings scheduled at the moment. This space will be updated as new meetings are added!")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.47, green: 0.50, blue: 0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .background(cardBackground)
    }

    private var skeletonList: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(HomePalette.skeleton)
                        .frame(width: index == 0 ? 170 : 140, height: 14)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(HomePalette.skeleton)
                        .frame(width: index == 0 ? 110 : 90, height: 10)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(HomePalette.skeleton)
                        .frame(width: 74, height: 10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(12)
                .frame(height: 86)
                .background(cardBackground)
                .redacted(reason: .placeholder)
            }
        }
    }

    private var cardBackground: some ShapeStyle {
        .white.shadow(.drop(color: .black.opacity(0.03), radius: 1, x: 0, y: 1))
    }

    // MARK: - Data Mapping

    private var visibleVisits: [GeoTrackTodayVisit] {
        todayVisits.filter { !["cancelled", "canceled"].contains($0.status.lowercased()) }
    }

    private func tripState(for visit: GeoTrackTodayVisit) -> HomeTripState {
        let status = visit.status.lowercased()
        if ["completed", "complete", "done", "closed"].contains(status) {
            return .complete
        }
        if visit.needsCpOutcomeDetails {
            return .reaching
        }
        if ["in-progress", "in_progress", "ongoing", "started", "active", "arrived"].contains(status) {
            return status == "arrived" ? .reaching : .enroute
        }
        if !hasOpenSession {
            return .clockInFirst
        }
        return .ready
    }

    private func canOpen(_ visit: GeoTrackTodayVisit) -> Bool {
        let state = tripState(for: visit)
        return state != .complete && state != .clockInFirst
    }

    private func etaText(for visit: GeoTrackTodayVisit) -> String {
        if visit.needsCpOutcomeDetails {
            return "Within \(visit.reachingRadiusMeters ?? 500)m"
        }
        return tripState(for: visit).eta
    }

    private func coordinate(for visit: GeoTrackTodayVisit) -> CLLocationCoordinate2D? {
        guard let lat = visit.placeLat, let lng = visit.placeLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: - Loading

    @MainActor
    private func reload() async {
        isLoading = true
        isVisitsLoading = true
        defer {
            isLoading = false
            isVisitsLoading = false
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadTodayVisits() }
            group.addTask { await self.loadAssignedPlaces() }
            group.addTask { await self.loadAttendanceGate() }
            group.addTask { await self.loadUnread() }
        }
    }

    @MainActor
    private func loadTodayVisits() async {
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            todayVisits = try await geoAPI.todayVisits(date: formatter.string(from: Date()))
            loadError = nil
        } catch {
            todayVisits = []
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func loadAssignedPlaces() async {
        assignedPlaces = (try? await geoAPI.assignedPlaces()) ?? []
    }

    @MainActor
    private func loadAttendanceGate() async {
        guard let token = authStore.currentSession?.token else {
            hasOpenSession = false
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        async let attendance = try? HRConvexAPIService.getTodayAttendance(token: token)
        async let sessions = try? HRConvexAPIService.getDaySessions(token: token, date: today)
        let todayAttendance = await attendance
        let daySessions = await sessions
        hasOpenSession = (todayAttendance ?? nil)?.isOpen == true || (daySessions ?? nil)?.hasOpenSession == true
    }

    @MainActor
    private func loadUnread() async {
        unreadCount = (try? await authStore.fetchUnreadNotificationCount()) ?? 0
    }

    // MARK: - Formatting

    private func formatVisitTimeOrDate(_ visit: GeoTrackTodayVisit) -> String {
        let start = visit.scheduledStartTime.flatMap(formatTimeValue)
        let end = visit.scheduledEndTime.flatMap(formatTimeValue)
        if let start, let end { return "\(start) - \(end)" }
        if let start { return start }
        if let end { return end }
        if let time = formatTimeValue(visit.scheduledDate) {
            return time
        }
        return formatVisitDate(visit.scheduledDate)
    }

    private func formatVisitDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Today" }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) {
            return visitDateFormatter.string(from: date)
        }

        let plain = DateFormatter()
        plain.dateFormat = "yyyy-MM-dd"
        if let date = plain.date(from: String(trimmed.prefix(10))) {
            return visitDateFormatter.string(from: date)
        }

        return "Today"
    }

    private func formatTimeValue(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) {
            return visitTimeFormatter.string(from: date)
        }

        let noFraction = ISO8601DateFormatter()
        noFraction.formatOptions = [.withInternetDateTime]
        if let date = noFraction.date(from: trimmed) {
            return visitTimeFormatter.string(from: date)
        }

        return nil
    }

    private var visitDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }

    private var visitTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return formatter
    }

}

private struct HomeTripCard: View {
    let title: String
    let time: String
    let distance: String
    let state: HomeTripState
    let etaText: String
    let canOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(initial)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HomePalette.textSecondary)
                .frame(width: 44, height: 44)
                .background(Color(red: 0.95, green: 0.96, blue: 0.98), in: Circle())

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HomePalette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(HomePalette.statusDot)
                .frame(width: 6, height: 6)
            Text(state.statusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(state.statusTextColor)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(state.statusBackground, in: Capsule())
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            VStack(spacing: 16) {
                statRow(icon: "building.2", label: "Site/Client", value: title)
                statRow(icon: "point.topleft.down.curvedto.point.bottomright.up", label: "Distance", value: distance)
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
                statRow(icon: "clock", label: "Time", value: time)
                statRow(icon: "timer", label: "ETA", value: etaText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(HomePalette.headerBlue)
                .frame(width: 40, height: 40)
                .background(Color(red: 0.95, green: 0.97, blue: 1.0), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(HomePalette.textSecondary)
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
            if state.showsPlayIcon {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
            }

            Text(state.actionLabel)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(state.actionForeground)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(state.actionBackground, in: Capsule())
        .overlay {
            if state == .enroute {
                Capsule().stroke(Color(red: 0.97, green: 0.56, blue: 0.04), lineWidth: 1)
            }
        }
    }

    private var initial: String {
        title.first.map { String($0).uppercased() } ?? "M"
    }
}

private enum HomeTripState: Equatable {
    case ready
    case enroute
    case reaching
    case complete
    case clockInFirst

    var statusLabel: String {
        switch self {
        case .ready: return "Start"
        case .enroute: return "Enroute"
        case .reaching: return "Reaching"
        case .complete: return "Complete"
        case .clockInFirst: return "Clock in"
        }
    }

    var actionLabel: String {
        switch self {
        case .ready: return "Start Trip"
        case .enroute: return "Enroute"
        case .reaching: return "Complete Trip"
        case .complete: return "Complete"
        case .clockInFirst: return "Clock In First"
        }
    }

    var eta: String {
        switch self {
        case .ready: return "After start"
        case .enroute: return "Tracking"
        case .reaching: return "At client place"
        case .complete: return "Complete"
        case .clockInFirst: return "After clock in"
        }
    }

    var showsPlayIcon: Bool {
        self == .ready || self == .reaching
    }

    var statusTextColor: Color {
        switch self {
        case .ready: return Color(red: 0.09, green: 0.61, blue: 0.18)
        case .enroute, .reaching: return Color(red: 0.71, green: 0.28, blue: 0.03)
        case .complete, .clockInFirst: return HomePalette.textSecondary
        }
    }

    var statusBackground: Color {
        switch self {
        case .ready: return Color(red: 0.90, green: 0.96, blue: 0.92)
        case .enroute, .reaching: return Color(red: 1.0, green: 0.96, blue: 0.90)
        case .complete, .clockInFirst: return Color(red: 0.95, green: 0.96, blue: 0.97)
        }
    }

    var actionForeground: Color {
        switch self {
        case .ready, .reaching: return .white
        case .enroute: return Color(red: 0.71, green: 0.28, blue: 0.03)
        case .complete, .clockInFirst: return HomePalette.textSecondary
        }
    }

    var actionBackground: some ShapeStyle {
        switch self {
        case .ready, .reaching:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 0.11, green: 0.79, blue: 0.04), Color(red: 0.24, green: 0.62, blue: 0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .enroute:
            return AnyShapeStyle(Color(red: 1.0, green: 0.96, blue: 0.90))
        case .complete, .clockInFirst:
            return AnyShapeStyle(Color(red: 0.89, green: 0.91, blue: 0.93))
        }
    }
}

private enum HomePalette {
    static let pageBackground = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let headerBlue = Color(hex: 0x0B61CA)
    static let headerBlueDark = Color(hex: 0x02499D)
    static let textPrimary = Color(red: 0.06, green: 0.09, blue: 0.16)
    static let textSecondary = Color(red: 0.40, green: 0.44, blue: 0.52)
    static let badgePurple = Color(red: 0.48, green: 0.35, blue: 0.97)
    static let statusDot = Color(red: 0.13, green: 0.73, blue: 0.30)
    static let skeleton = Color(red: 0.90, green: 0.92, blue: 0.95)
}

private enum HomeStar: CaseIterable, Identifiable {
    case largeLower, mediumTop, smallLower, smallTop, tinyTop, tinyLower

    var id: Self { self }

    var size: CGFloat {
        switch self {
        case .largeLower: return 20
        case .mediumTop: return 16
        case .smallLower, .smallTop: return 8
        case .tinyTop, .tinyLower: return 5
        }
    }

    var x: CGFloat {
        switch self {
        case .largeLower: return -28
        case .mediumTop: return 3
        case .smallLower: return -8
        case .smallTop: return 20
        case .tinyTop: return -16
        case .tinyLower: return 12
        }
    }

    var y: CGFloat {
        switch self {
        case .largeLower: return 26
        case .mediumTop: return -2
        case .smallLower: return 52
        case .smallTop: return 5
        case .tinyTop: return 18
        case .tinyLower: return 58
        }
    }

    var rotation: Double {
        switch self {
        case .largeLower: return 30
        case .mediumTop: return -19
        case .smallLower: return 18
        case .smallTop: return -9
        case .tinyTop, .tinyLower: return -20
        }
    }

    var opacity: Double {
        switch self {
        case .largeLower, .mediumTop: return 0.95
        default: return 0.82
        }
    }
}

private extension GeoTrackTodayVisit {
    var displayName: String {
        placeName?.nilIfBlank
            ?? leadName?.nilIfBlank
            ?? "Scheduled Visit"
    }

    var hasMappedLocation: Bool {
        placeLat != nil && placeLng != nil
    }

    var needsCpOutcomeDetails: Bool {
        clientPlaceVisitId?.nilIfBlank != nil
            && status.lowercased() == "arrived"
            && cpVisit?.outcome?.nilIfBlank == nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension GeoTrackTodayVisit: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: GeoTrackTodayVisit, rhs: GeoTrackTodayVisit) -> Bool { lhs.id == rhs.id }
}

#Preview {
    HomeView()
        .environment(AuthStore())
}
