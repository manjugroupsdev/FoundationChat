import CoreLocation
import SwiftUI

struct FleetMyTripsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var visits: [GeoTrackTodayVisit] = []
    @State private var selectedFilter: FleetTripFilter = .all
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var futureTripMessage: String?
    @State private var emptyStateMessage: String?
    @State private var searchText = ""
    @State private var visitToNavigate: GeoTrackTodayVisit?
    @State private var locationProvider = FleetTripLocationProvider()

    private var filteredVisits: [GeoTrackTodayVisit] {
        let today = Self.todayString()
        let tabFiltered: [GeoTrackTodayVisit]
        switch selectedFilter {
        case .all:
            tabFiltered = visits
        case .upcoming:
            tabFiltered = visits.filter { !$0.fleetIsCompleted && $0.scheduledDate > today }
        case .completed:
            tabFiltered = visits.filter(\.fleetIsCompleted)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tabFiltered }
        return tabFiltered.filter { visit in
            [
                visit.placeName,
                visit.leadName,
                visit.placeAddress,
                visit.leadPhone,
                visit.tripType
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            tripTabs
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xF8F9FC).ignoresSafeArea())
        .navigationTitle("My Trips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    futureTripMessage = "Calendar filter coming soon"
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Calendar filter")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task { if !hasLoaded { await load() } }
        .onAppear { locationProvider.start() }
        .navigationDestination(item: $visitToNavigate) { visit in
            TripNavigationView(
                visitId: visit.id,
                placeId: nil,
                placeName: visit.fleetDisplayName,
                placeAddress: visit.placeAddress,
                destination: coordinate(for: visit),
                initialStatus: visit.status,
                tripType: visit.tripType,
                clientPlaceVisitId: visit.clientPlaceVisitId,
                cpClientMet: visit.cpVisit?.clientMet,
                cpOutcome: visit.cpVisit?.outcome,
                requiresOpenAttendance: true,
                onTripChanged: {
                    Task { await load() }
                }
            )
        }
        .alert("Fleet", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Fleet", isPresented: Binding(get: { futureTripMessage != nil }, set: { if !$0 { futureTripMessage = nil } })) {
            Button("OK", role: .cancel) { futureTripMessage = nil }
        } message: {
            Text(futureTripMessage ?? "")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            TextField("Search Trips", text: $searchText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: 0x111827))
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x667085))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tripTabs: some View {
        HStack(spacing: 0) {
            ForEach(FleetTripFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selectedFilter == filter ? .white : Color(hex: 0x667085))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            selectedFilter == filter ? Color(hex: 0x0B61CA) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 38)
        .background(Color(hex: 0xEEF2F7), in: Capsule())
        .sensoryFeedback(.selection, trigger: selectedFilter)
    }

    private var content: some View {
        ZStack(alignment: .bottom) {
            if isLoading && !hasLoaded {
                AppModuleLoadingRows()
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if filteredVisits.isEmpty {
                FleetTripsEmptyState(title: selectedFilter.emptyTitle, description: emptyDescription)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredVisits) { visit in
                            FleetVisitCard(
                                visit: visit,
                                user: authStore.currentSession?.user,
                                origin: locationProvider.lastLocation?.coordinate,
                                today: Self.todayString()
                            ) {
                                open(visit)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                    .refreshable { await load() }
                }

                LinearGradient(
                    colors: [Color(hex: 0xF8F9FC).opacity(0), Color(hex: 0xF8F9FC)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDescription: String {
        emptyStateMessage ?? "There are no trips matching your search or filter."
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            visits = []
            emptyStateMessage = "Not signed in."
            hasLoaded = true
            return
        }
        isLoading = true
        emptyStateMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            GeoTrackAPIService.shared.tokenProvider = { token }
            let driverTrips = try await FleetConvexAPIService.listDriverTrips(token: token)
            visits = driverTrips
                .compactMap { $0.toTodayVisitOrNil() }
                .sorted { lhs, rhs in
                    if lhs.fleetIsCompleted != rhs.fleetIsCompleted {
                        return !lhs.fleetIsCompleted
                    }
                    return lhs.scheduledDate > rhs.scheduledDate
                }
            if driverTrips.isEmpty {
                emptyStateMessage = "No fleet trips found for your phone. Make sure the dispatcher assigned the vehicle to this driver's phone number."
            } else if visits.isEmpty {
                emptyStateMessage = "Fleet trips were found, but they are missing scheduled dates."
            }
        } catch {
            visits = []
            emptyStateMessage = "Driver trips couldn't load: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func open(_ visit: GeoTrackTodayVisit) {
        if visit.scheduledDate > Self.todayString(), !visit.fleetIsCompleted {
            futureTripMessage = "This trip is scheduled for a future date."
            return
        }
        visitToNavigate = visit
    }

    private func coordinate(for visit: GeoTrackTodayVisit) -> CLLocationCoordinate2D? {
        guard let lat = visit.placeLat, let lng = visit.placeLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private enum FleetTripFilter: String, CaseIterable, Identifiable {
    case all, upcoming, completed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        }
    }
    var emptyTitle: String {
        switch self {
        case .all: return "No Trips"
        case .upcoming: return "No Upcoming Trips"
        case .completed: return "No Completed Trips"
        }
    }
}

struct FleetHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 24)
            .padding(.top, 42)
        }
        .frame(height: 188)
    }
}

private struct FleetVisitCard: View {
    let visit: GeoTrackTodayVisit
    let user: AuthUser?
    let origin: CLLocationCoordinate2D?
    let today: String
    let onOpen: () -> Void

    private var statusState: FleetTripCardState {
        FleetTripCardState(visit: visit, today: today)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow

                Rectangle()
                    .fill(Color(hex: 0xE5E7EB))
                    .frame(height: 1)
                    .padding(.vertical, 16)

                detailGrid

                actionButton
                    .padding(.top, 20)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text(userInitial)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
                .frame(width: 44, height: 44)
                .background(Color(hex: 0xF2F4F7), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(user?.name?.nonBlank ?? "Donald Trump")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x111827))
                    .lineLimit(1)

                Text("\(driverPrefix):\(user?.employeeId?.nonBlank ?? "38212")")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: 0x667085))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusState.dotColor)
                    .frame(width: 6, height: 6)
                Text(statusState.statusTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusState.statusTextColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(statusState.statusBackground, in: Capsule())
        }
    }

    private var detailGrid: some View {
        HStack(spacing: 12) {
            VStack(spacing: 12) {
                detailItem(icon: "building.2", label: "Site/Client", value: visit.fleetDisplayName)
                detailItem(icon: "point.topleft.down.curvedto.point.bottomright.up", label: "Distance", value: distanceText)
            }

            Rectangle()
                .fill(Color(hex: 0xE5E7EB))
                .frame(width: 1, height: 80)

            VStack(spacing: 12) {
                if statusState.isUpcoming {
                    detailItem(icon: "clock", label: "Time", value: visit.scheduledStartTime?.nonBlank ?? "09:30 AM")
                    detailItem(icon: "timer", label: "ETA", value: "25 Mins")
                } else {
                    detailItem(icon: "phone", label: "Phone Number", value: visit.leadPhone?.nonBlank ?? "9874827382")
                    detailItem(icon: "clock", label: "Time", value: visit.scheduledStartTime?.nonBlank ?? "09:30 AM")
                }
            }
        }
    }

    private func detailItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0BCAB4))
                .frame(width: 36, height: 36)
                .background(Color(hex: 0xF2F4F7), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(hex: 0x667085))
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x111827))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionButton: some View {
        HStack(spacing: 8) {
            if let icon = statusState.actionIcon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusState.actionTextColor)
            }
            Text(statusState.actionTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusState.actionTextColor)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(statusState.actionBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var userInitial: String {
        String((user?.name?.nonBlank ?? "M").prefix(1)).uppercased()
    }

    private var driverPrefix: String {
        user?.isFleetDriverMode == true ? "Driver ID" : "Field Executive ID"
    }

    private var distanceText: String {
        guard let destLat = visit.placeLat, let destLng = visit.placeLng else {
            return "Not mapped"
        }
        guard let origin else {
            return "Locating..."
        }
        let dest = CLLocation(latitude: destLat, longitude: destLng)
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let rendered = Self.formatDistance(from.distance(from: dest))
        if statusState.isCompleted { return rendered }
        if statusState.isInProgress { return "\(rendered) to go" }
        return "\(rendered) away"
    }

    private static func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }
}

private struct FleetTripsEmptyState: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "car.rear.road.lane")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color(hex: 0x98A2B3))

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: 0x111827))

            Text(description)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FleetTripCardState {
    let visit: GeoTrackTodayVisit
    let today: String

    private var normalizedStatus: String {
        visit.status.lowercased()
    }

    var isCompleted: Bool {
        ["completed", "complete", "done", "closed"].contains(normalizedStatus)
    }

    var isInProgress: Bool {
        ["in-progress", "in_progress", "ongoing", "started", "active", "arrived", "arrival_verified", "arrival-verified"].contains(normalizedStatus)
    }

    var isUpcoming: Bool {
        visit.scheduledDate > today && !isCompleted
    }

    var statusTitle: String {
        if isCompleted { return "Completed" }
        if isInProgress { return normalizedStatus == "arrived" ? "Reaching" : "Enroute" }
        if isUpcoming { return "Upcoming" }
        return "Ready"
    }

    var statusTextColor: Color {
        if isCompleted { return Color(hex: 0x475467) }
        if isInProgress { return Color(hex: 0xB54708) }
        if isUpcoming { return Color(hex: 0x0B63C6) }
        return Color(hex: 0x169B2F)
    }

    var statusBackground: Color {
        if isCompleted { return Color(hex: 0xF2F4F7) }
        if isInProgress { return Color(hex: 0xFFFAEB) }
        if isUpcoming { return Color(hex: 0xEAF3FF) }
        return Color(hex: 0xECFDF3)
    }

    var dotColor: Color { statusTextColor }

    var actionTitle: String {
        if isCompleted { return "Completed" }
        if isInProgress { return normalizedStatus == "arrived" ? "Complete Trip" : "Enroute" }
        if isUpcoming { return "Upcoming Trip" }
        return "Start Trip"
    }

    var actionIcon: String? {
        if isCompleted || isInProgress { return nil }
        if isUpcoming { return "calendar" }
        return "play.fill"
    }

    var actionBackground: Color {
        if isCompleted { return Color(hex: 0xF2F4F7) }
        if isUpcoming { return Color(hex: 0xEAF3FF) }
        return Color(hex: 0x1BCA0B)
    }

    var actionTextColor: Color {
        if isCompleted { return Color(hex: 0x667085) }
        if isUpcoming { return Color(hex: 0x0B63C6) }
        return .white
    }
}

private extension FleetDriverTrip {
    func toTodayVisitOrNil() -> GeoTrackTodayVisit? {
        guard let scheduled = scheduledDate?.nonBlank else { return nil }
        let normalizedPhase = (phase ?? "").lowercased()
        let status: String
        switch normalizedPhase {
        case "completed":
            status = "completed"
        case "on_site":
            status = "on_site"
        case "in_progress":
            status = "in-progress"
        default:
            status = "scheduled"
        }

        let title = project?.name?.nonBlank
            ?? vehicle?.vehicleNumber?.nonBlank
            ?? "Driver trip"

        return GeoTrackTodayVisit(
            id: id,
            clientPlaceId: project?.id?.nonBlank ?? id,
            scheduledDate: scheduled,
            status: status,
            mobileStatus: status,
            reachingRadiusMeters: nil,
            placeName: title,
            placeAddress: pickupAddress?.nonBlank,
            placeType: "project",
            placeLat: nil,
            placeLng: nil,
            tripType: "site_visit",
            clientPlaceVisitId: nil,
            leadName: nil,
            leadPhone: driverPhone?.nonBlank,
            cpVisit: nil,
            scheduledStartTime: scheduledTime?.nonBlank ?? pickupTime?.nonBlank,
            scheduledEndTime: nil,
            visitCategory: "site_visit",
            travelMode: "cab",
            vehiclePreference: vehicle?.vehicleNumber?.nonBlank,
            vehicleAssigned: true,
            creationTime: nil
        )
    }
}

@MainActor
@Observable
private final class FleetTripLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var lastLocation: CLLocation?
    private var didStart = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
        }
    }
}

private extension GeoTrackTodayVisit {
    var fleetDisplayName: String {
        placeName?.nonBlank ?? leadName?.nonBlank ?? "Scheduled Visit"
    }
    
    var fleetIsCompleted: Bool {
        ["completed", "complete", "done", "closed"].contains(status.lowercased())
    }

    var fleetStatusTitle: String {
        status.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
    }

    var primaryTripActionTitle: String {
        if fleetIsCompleted { return "View Completed Trip" }
        let normalized = status.lowercased()
        if ["in-progress", "in_progress", "ongoing", "started", "active", "arrived", "arrival_verified", "arrival-verified"].contains(normalized) {
            return "Resume Trip"
        }
        return "Start Trip"
    }
}
