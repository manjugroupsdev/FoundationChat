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
    @State private var searchText = ""
    @State private var visitToNavigate: GeoTrackTodayVisit?

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
        ScrollView {
            VStack(spacing: 0) {
                FleetHeader(
                    title: "My Trips",
                    subtitle: "Driver trips, live route, OTP and completion workflow",
                    systemImage: "steeringwheel"
                )

                Picker("Trip filter", selection: $selectedFilter) {
                    ForEach(FleetTripFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, -34)
                .padding(.bottom, 14)

                content
            }
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My Trips")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search trips")
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
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

    private var content: some View {
        VStack(spacing: 12) {
            if isLoading && !hasLoaded {
                AppModuleLoadingRows()
            } else if filteredVisits.isEmpty {
                ContentUnavailableView(
                    selectedFilter.emptyTitle,
                    systemImage: "car.rear.road.lane",
                    description: Text(emptyDescription)
                )
                .padding(.vertical, 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredVisits) { visit in
                        FleetVisitCard(visit: visit) {
                            open(visit)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var emptyDescription: String {
        let designation = authStore.currentSession?.user.designation?.nonBlank
        if visits.isEmpty, designation?.localizedCaseInsensitiveCompare("Driver") != .orderedSame {
            return "Signed in with designation: \(designation ?? "(empty)"). If this account should be a driver, set the staff designation to Driver."
        }
        return "There are no trips matching your search or filter."
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            hasLoaded = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            GeoTrackAPIService.shared.tokenProvider = { token }
            visits = try await GeoTrackAPIService.shared.todayVisits(date: Self.todayString())
        } catch {
            errorMessage = error.localizedDescription
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
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: 0xEAF3FF), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(visit.fleetDisplayName)
                        .font(AppModuleFont.rowTitle)
                        .foregroundStyle(Color(hex: 0x101828))
                    Text([visit.scheduledDate, visit.scheduledStartTime, visit.leadName].compactMap { $0?.nonBlank }.joined(separator: " · "))
                        .font(AppModuleFont.rowMeta)
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                AppModuleBadge(text: visit.fleetStatusTitle, tint: visit.fleetIsCompleted ? Color(hex: 0x16A34A) : Color(hex: 0x0B61CA))
            }

            if let address = visit.placeAddress?.nonBlank {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(AppModuleFont.rowBody)
                    .foregroundStyle(Color(hex: 0x344054))
                    .lineLimit(2)
            }

            Button(action: onOpen) {
                Label(visit.primaryTripActionTitle, systemImage: visit.fleetIsCompleted ? "checkmark.circle.fill" : "location.north.circle.fill")
                    .font(AppModuleFont.rowMetaSemibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(visit.fleetIsCompleted ? Color(hex: 0x667085) : Color(hex: 0x0B61CA))
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

private extension GeoTrackTodayVisit {
    var fleetDisplayName: String {
        leadName?.nonBlank ?? placeName?.nonBlank ?? "Destination"
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
