import SwiftUI
import UIKit

private enum FleetPortalTab: String, CaseIterable, Identifiable {
    case trips
    case vehicles
    case drivers
    case staff
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trips: "Trips"
        case .vehicles: "Vehicles"
        case .drivers: "Driver"
        case .staff: "Staff"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .trips: "point.topleft.down.to.point.bottomright.curvepath"
        case .vehicles: "car.side.fill"
        case .drivers: "person.fill"
        case .staff: "person.2.fill"
        case .settings: "gearshape"
        }
    }
}

struct FleetPortalExperienceView: View {
    @Environment(AuthStore.self) private var authStore

    let scope: FleetDispatchScope

    @State private var selectedTab: FleetPortalTab = .trips
    @State private var photoURL: URL?
    @State private var showNotifications = false
    @State private var showSettings = false

    init(scope: FleetDispatchScope) {
        self.scope = scope
        Self.configureTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FleetPortalTripsView(
                scope: scope,
                photoURL: photoURL,
                onNotifications: { showNotifications = true },
                onProfile: { showSettings = true }
            )
            .tabItem { Label(FleetPortalTab.trips.title, systemImage: FleetPortalTab.trips.systemImage) }
            .tag(FleetPortalTab.trips)

            FleetPortalVehiclesView(scope: scope)
                .tabItem { Label(FleetPortalTab.vehicles.title, systemImage: FleetPortalTab.vehicles.systemImage) }
                .tag(FleetPortalTab.vehicles)

            FleetPortalDriversView(scope: scope)
                .tabItem { Label(FleetPortalTab.drivers.title, systemImage: FleetPortalTab.drivers.systemImage) }
                .tag(FleetPortalTab.drivers)

            if scope == .agency {
                FleetPortalStaffView()
                    .tabItem { Label(FleetPortalTab.staff.title, systemImage: FleetPortalTab.staff.systemImage) }
                    .tag(FleetPortalTab.staff)
            }

            FleetAgencySettingsView(scope: scope)
                .tabItem { Label(FleetPortalTab.settings.title, systemImage: FleetPortalTab.settings.systemImage) }
                .tag(FleetPortalTab.settings)
        }
        .tint(Color(hex: 0x19C90B))
        .fleetTabBarMinimizeOnScroll()
        .fullScreenCover(isPresented: $showNotifications) {
            NotificationsListView(onClose: { showNotifications = false })
        }
        .fullScreenCover(isPresented: $showSettings) {
            NavigationStack {
                FleetPortalSettingsView(
                    photoURL: photoURL,
                    onBack: { showSettings = false },
                    onProfileUpdated: refreshPhoto
                )
                .navigationBarBackButtonHidden(true)
            }
        }
        .task(id: authStore.currentSession?.user.photo) {
            await refreshPhoto()
        }
    }

    @MainActor
    private func refreshPhoto() async {
        let rawPhoto = authStore.viewer?.photo ?? authStore.currentSession?.user.photo
        photoURL = await authStore.resolveProfilePhotoURL(rawPhoto)
    }

    private static func configureTabBarAppearance() {
        let active = UIColor(red: 0.106, green: 0.792, blue: 0.043, alpha: 1)
        let inactive = UIColor.secondaryLabel
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.68)
        [appearance.stackedLayoutAppearance,
         appearance.inlineLayoutAppearance,
         appearance.compactInlineLayoutAppearance].forEach { itemAppearance in
            itemAppearance.normal.iconColor = inactive
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: inactive]
            itemAppearance.selected.iconColor = active
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: active]
        }
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = active
        tabBar.unselectedItemTintColor = inactive
    }
}

private extension View {
    @ViewBuilder
    func fleetTabBarMinimizeOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

private enum FleetPortalTripFilter: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case assigned = "Assigned"
    case completed = "Completed"

    var id: String { rawValue }
}

private struct FleetPortalTripsView: View {
    @Environment(AuthStore.self) private var authStore

    let scope: FleetDispatchScope
    let photoURL: URL?
    let onNotifications: () -> Void
    let onProfile: () -> Void

    @State private var filter: FleetPortalTripFilter = .pending
    @State private var pendingTrips: [FleetDispatchTrip] = []
    @State private var assignedTrips: [FleetDispatchTrip] = []
    @State private var vehicles: [FleetDispatchVehicle] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var allocationTrip: FleetDispatchTrip?
    @State private var allotTrip: FleetDispatchTrip?
    @State private var unassignTrip: FleetDispatchTrip?
    @State private var offlineTrip: FleetDispatchTrip?
    @State private var mutationTripIDs: Set<String> = []
    @State private var heroHeaderOpacity = 1.0

    private var filteredTrips: [FleetDispatchTrip] {
        switch filter {
        case .pending: pendingTrips
        case .assigned: assignedTrips.filter { !$0.isCompleted }
        case .completed: assignedTrips.filter(\.isCompleted)
        }
    }

    private var activeVehicleCount: Int { vehicles.filter(\.isActive).count }
    private let heroHeight: CGFloat = 310

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.appScreenBackground.ignoresSafeArea()

                FleetPortalHero(
                    topInset: proxy.safeAreaInsets.top,
                    pendingCount: pendingTrips.count,
                    activeVehicleCount: activeVehicleCount,
                    selectedIndex: FleetPortalTripFilter.allCases.firstIndex(of: filter) ?? 0,
                    onSummary: { Task { await load() } }
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .zIndex(1)

                ScrollView(showsIndicators: false) {
                    Color.clear
                        .frame(height: heroHeight)
                        .allowsHitTesting(false)

                    tripContent
                        .frame(minHeight: max(460, proxy.size.height - heroHeight + 50), alignment: .top)
                }
                .ignoresSafeArea(edges: .top)
                .refreshable { await load() }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, scrollY in
                    heroHeaderOpacity = 1 - min(Double(scrollY / 64), 1)
                }
                .zIndex(2)

                FleetPortalHeroHeader(
                    topInset: proxy.safeAreaInsets.top,
                    photoURL: photoURL,
                    onNotifications: onNotifications,
                    onProfile: onProfile
                )
                .opacity(heroHeaderOpacity)
                .allowsHitTesting(heroHeaderOpacity > 0.1)
                .zIndex(4)
            }
        }
        .task {
            guard !hasLoaded else { return }
            await load()
        }
        .sheet(item: $allocationTrip) { trip in
            FleetAllocationSheet(
                token: authStore.currentSession?.token ?? "",
                scope: scope,
                trip: trip,
                vehicles: vehicles.filter(\.isActive)
            ) {
                filter = .assigned
                await load()
            }
            .appFormActivity()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $offlineTrip) { trip in
            FleetOfflineCompletionSheet(
                token: authStore.currentSession?.token ?? "",
                scope: scope,
                trip: trip,
                vehicles: vehicles.filter(\.isActive)
            ) {
                filter = .completed
                await load()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $allotTrip) { trip in
            FleetAllotAgencySheet(
                token: authStore.currentSession?.token ?? "",
                trip: trip
            ) {
                await load()
            }
            .appFormActivity()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Remove this driver assignment?",
            isPresented: Binding(
                get: { unassignTrip != nil },
                set: { if !$0 { unassignTrip = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unassign Driver", role: .destructive) {
                guard let trip = unassignTrip else { return }
                unassignTrip = nil
                Task { await unassign(trip) }
            }
            Button("Cancel", role: .cancel) { unassignTrip = nil }
        } message: {
            Text("The trip returns to Pending so another vehicle and driver can be allocated.")
        }
        .alert("Fleet Trips", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var tripContent: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("Today's Trips")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

            tripFilter

            if isLoading && !hasLoaded {
                FleetPortalLoadingRows()
            } else if filteredTrips.isEmpty {
                ContentUnavailableView(
                    "No \(filter.rawValue) Trips",
                    systemImage: "car.side",
                    description: Text("Trips in this status will appear here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 34)
            } else {
                ForEach(filteredTrips) { trip in
                    FleetPortalTripCard(
                        trip: trip,
                        status: filter,
                        isMutating: mutationTripIDs.contains(trip.id),
                        canCompleteOffline: canCompleteOffline(trip),
                        canAllotAgency: scope == .mms,
                        onAllocate: { allocationTrip = trip },
                        onAllotAgency: { allotTrip = trip },
                        onUnassign: { unassignTrip = trip },
                        onCompleteOffline: { offlineTrip = trip }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.appScreenBackground,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 26,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 26,
                style: .continuous
            )
        )
    }

    private var tripFilter: some View {
        HStack(spacing: 0) {
            ForEach(FleetPortalTripFilter.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        filter = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(filter == item ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(filter == item ? Color(hex: 0x0B61CA) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.appSurface, in: Capsule())
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func canCompleteOffline(_ trip: FleetDispatchTrip) -> Bool {
        let role = authStore.currentSession?.user.role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let permitted = scope == .agency
            || role == "super-admin"
            || authStore.hasPermission("marketing.fleet.completeOffline")
        return permitted && trip.outcome?.nonBlank != nil && !trip.isCompleted
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            async let pending = FleetDispatchAPIService.listPending(token: token, scope: scope)
            async let assigned = FleetDispatchAPIService.listAssigned(token: token, scope: scope)
            async let fleetVehicles = FleetDispatchAPIService.listVehicles(token: token, scope: scope)
            (pendingTrips, assignedTrips, vehicles) = try await (pending, assigned, fleetVehicles)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func unassign(_ trip: FleetDispatchTrip) async {
        guard let token = authStore.currentSession?.token else { return }
        mutationTripIDs.insert(trip.id)
        defer { mutationTripIDs.remove(trip.id) }
        do {
            try await FleetDispatchAPIService.unassign(token: token, scope: scope, tripId: trip.id)
            filter = .pending
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FleetPortalHero: View {
    let topInset: CGFloat
    let pendingCount: Int
    let activeVehicleCount: Int
    let selectedIndex: Int
    let onSummary: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0877E8), Color(hex: 0x034897)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image("FleetPortalCityscape")
                .resizable()
                .scaledToFit()
                .opacity(0.18)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 104)
                .padding(.bottom, 36)
                .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topInset + 56)

                ZStack(alignment: .bottomTrailing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Manage Your Fleet\nwith Ease")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 210, alignment: .leading)

                        Text("Track trips, assign vehicles,\nmanage drivers and keep your\noperations running smoothly.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: onSummary) {
                            HStack(spacing: 7) {
                                Text("View My Summary")
                                Image(systemName: "chevron.right.2")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image("FleetPortalHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 205, height: 146)
                        .offset(x: 7, y: 2)

                    VStack(spacing: 8) {
                        FleetHeroMetric(title: "Today's Trips", value: pendingCount, icon: "point.topleft.down.to.point.bottomright.curvepath", tint: Color(hex: 0x0B61CA))
                        FleetHeroMetric(title: "Active Vehicles", value: activeVehicleCount, icon: "car.fill", tint: Color(hex: 0x16A34A))
                    }
                    .frame(width: 92)
                    .offset(x: 1, y: -8)
                }
                .padding(.top, 18)
                .padding(.horizontal, 18)

                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.32))
                            .frame(width: index == selectedIndex ? 24 : 7, height: 7)
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 310)
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
    }
}

private struct FleetPortalHeroHeader: View {
    @Environment(AuthStore.self) private var authStore

    let topInset: CGFloat
    let photoURL: URL?
    let onNotifications: () -> Void
    let onProfile: () -> Void

    private var user: AuthUser? { authStore.currentSession?.user }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user?.name?.nonBlank ?? "Fleet Administrator")
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    if user?.isAdmin == true || user?.role?.lowercased().contains("admin") == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                    }
                }
                Text([user?.role?.nonBlank, user?.department?.nonBlank].compactMap { $0 }.joined(separator: " • ").nonBlank ?? "Fleet • Administration")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Button(action: onNotifications) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")

                Button(action: onProfile) {
                    FleetPortalAvatar(name: user?.name, photoURL: photoURL, size: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
            }
            .padding(4)
            .background(.white.opacity(0.18), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, topInset + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }
}

private struct FleetHeroMetric: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 5) {
                Text("\(value)")
                    .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 25, height: 25)
                    .background(tint.opacity(0.12), in: Circle())
            }
        }
        .padding(8)
        .frame(height: 59)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 5, y: 3)
    }
}

private struct FleetPortalTripCard: View {
    let trip: FleetDispatchTrip
    let status: FleetPortalTripFilter
    let isMutating: Bool
    let canCompleteOffline: Bool
    let canAllotAgency: Bool
    let onAllocate: () -> Void
    let onAllotAgency: () -> Void
    let onUnassign: () -> Void
    let onCompleteOffline: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: [Color(hex: 0x0877E8), Color(hex: 0x034897)], startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(Color(hex: 0x0B61CA))
                    Text(tripTime)
                        .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    statusBadge
                }

                Text(address)
                    .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    FleetPortalTag(icon: "person.2", text: "\(trip.expectedAttendeeCount ?? 0)")
                    FleetPortalTag(icon: "car.side", text: humanizedVehicleType)
                    Spacer(minLength: 4)
                }

                if status == .pending {
                    HStack(spacing: 10) {
                        Spacer()
                        // MMS dispatchers can hand a pending trip to an external
                        // travel agency instead of an in-house vehicle (mirrors
                        // Android's allocate sheet "External agency" path).
                        if canAllotAgency {
                            Button(action: onAllotAgency) {
                                HStack(spacing: 6) {
                                    Image(systemName: "building.2")
                                    Text("Allot Agency")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(Color(hex: 0x0B61CA).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: onAllocate) {
                            HStack(spacing: 6) {
                                Text("Allocate")
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Color(hex: 0x0B61CA), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                } else if status == .assigned && (!tripHasStarted || canCompleteOffline) {
                    HStack(spacing: 10) {
                        if !tripHasStarted {
                            Button("Unassign", role: .destructive, action: onUnassign)
                                .buttonStyle(.bordered)
                                .tint(.red)
                        }
                        if canCompleteOffline {
                            Button("Complete Details", action: onCompleteOffline)
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: 0x0B61CA))
                        }
                        if isMutating { ProgressView().controlSize(.small) }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .disabled(isMutating)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color(hex: 0x0B61CA).opacity(0.09), radius: 8, y: 5)
    }

    private var statusBadge: some View {
        let color: Color = switch status {
        case .pending: Color(hex: 0xEA580C)
        case .assigned: Color(hex: 0x1D4ED8)
        case .completed: Color(hex: 0x047857)
        }
        return Text(status.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(color.opacity(0.1), in: Capsule())
    }

    private var tripTime: String {
        let date = trip.scheduledDate?.nonBlank ?? "Date pending"
        let time = trip.scheduledTime?.nonBlank ?? trip.pickupTime?.nonBlank
        return time.map { "\(date) • \($0)" } ?? date
    }

    private var address: String {
        trip.pickupAddress?.nonBlank
            ?? trip.project?.name?.nonBlank.map { "Project: \($0)" }
            ?? "Address pending"
    }

    private var humanizedVehicleType: String {
        (trip.vehiclePreference?.nonBlank ?? trip.vehicle?.type?.nonBlank ?? "Vehicle")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var tripHasStarted: Bool {
        trip.travelDeskStartedAt != nil
            || trip.travelDeskOnSiteAt != nil
            || trip.travelDeskPickedFromSiteAt != nil
            || trip.travelDeskEndedAt != nil
    }
}

private struct FleetPortalTag: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
            .overlay { Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 1) }
    }
}

/// MMS-only: allot a pending trip to an external travel agency. The agency then
/// assigns its own cab in Travel Desk, so no vehicle/driver/rate is captured
/// here. Mirrors Android's AllocateVehicleBottomSheet "External agency" path
/// (network/TravelDeskApi.allotMmsAgency). Reuses the already-wired
/// FleetDispatchAPIService.listAgencies / .allotAgency (both MMS routes).
private struct FleetAllotAgencySheet: View {
    @Environment(\.dismiss) private var dismiss

    let token: String
    let trip: FleetDispatchTrip
    let onAllotted: () async -> Void

    @State private var agencies: [FleetDispatchAgency] = []
    @State private var selectedAgencyId = ""
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var activeAgencies: [FleetDispatchAgency] { agencies.filter(\.isActive) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Trip", value: trip.pickupAddress?.nonBlank ?? trip.project?.name?.nonBlank ?? "Site Visit")
                    if let time = trip.scheduledTime?.nonBlank ?? trip.pickupTime?.nonBlank {
                        LabeledContent("Pickup", value: [trip.scheduledDate?.nonBlank, time].compactMap { $0 }.joined(separator: " · "))
                    }
                } footer: {
                    Text("Hand this trip to an external travel agency. The agency then assigns the cab in Travel Desk.")
                }

                Section("Travel Agency") {
                    if isLoading && !hasLoaded {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading agencies…").foregroundStyle(.secondary)
                        }
                    } else if activeAgencies.isEmpty {
                        Text("No travel agencies available yet.").foregroundStyle(.secondary)
                    } else {
                        Picker("Agency", selection: $selectedAgencyId) {
                            Text("Select agency").tag("")
                            ForEach(activeAgencies) { agency in
                                Text(agencyLabel(agency)).tag(agency.id)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Allot Agency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Allot") { Task { await submit() } }
                        .disabled(selectedAgencyId.isEmpty || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .task {
                guard !hasLoaded else { return }
                await load()
            }
        }
    }

    private func agencyLabel(_ agency: FleetDispatchAgency) -> String {
        [agency.name?.nonBlank ?? "Agency", agency.mobileNumber?.nonBlank]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            agencies = try await FleetDispatchAPIService.listAgencies(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        guard !selectedAgencyId.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await FleetDispatchAPIService.allotAgency(
                token: token,
                tripId: trip.id,
                travelAgencyId: selectedAgencyId
            )
            await onAllotted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FleetOfflineCompletionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let token: String
    let scope: FleetDispatchScope
    let trip: FleetDispatchTrip
    let vehicles: [FleetDispatchVehicle]
    let onSaved: @MainActor () async -> Void

    @State private var pricingMode: String
    @State private var vehicleId: String
    @State private var agencyName = ""
    @State private var driverName: String
    @State private var driverPhone: String
    @State private var packageAmount: String
    @State private var kmRate: String
    @State private var distanceKm = ""
    @State private var startKm: String
    @State private var endKm: String
    @State private var beta = ""
    @State private var beta2 = ""
    @State private var tollAmount = ""
    @State private var hillCharge = ""
    @State private var outstationCharge = ""
    @State private var permitCharge = ""
    @State private var permitTax = ""
    @State private var standingCharge = ""
    @State private var standingMinutes = ""
    @State private var standingWithAc = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        token: String,
        scope: FleetDispatchScope,
        trip: FleetDispatchTrip,
        vehicles: [FleetDispatchVehicle],
        onSaved: @escaping @MainActor () async -> Void
    ) {
        self.token = token
        self.scope = scope
        self.trip = trip
        self.vehicles = vehicles
        self.onSaved = onSaved
        _pricingMode = State(initialValue: trip.travelDeskPricingMode == "km" ? "km" : "package")
        _vehicleId = State(initialValue: trip.vehicleId ?? trip.vehicle?.id ?? "")
        _driverName = State(initialValue: trip.driverName ?? "")
        _driverPhone = State(initialValue: trip.driverPhone ?? "")
        _packageAmount = State(initialValue: Self.text(trip.travelDeskPackageAmount))
        _kmRate = State(initialValue: Self.text(trip.travelDeskKmRate))
        _startKm = State(initialValue: Self.text(trip.travelDeskStartKm))
        _endKm = State(initialValue: Self.text(trip.travelDeskEndKm))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Client", value: trip.clientName?.nonBlank ?? "Site Visit")
                    LabeledContent("Visit", value: trip.project?.name?.nonBlank ?? trip.pickupAddress?.nonBlank ?? "—")
                } header: {
                    Text("Trip")
                } footer: {
                    Text("The Site Visit outcome is already recorded. This form saves the remaining fleet and billing details, matching Android.")
                }

                Section(scope == .mms ? "Internal Fleet" : "External Fleet") {
                    if scope == .mms {
                        Picker("Vehicle", selection: $vehicleId) {
                            Text("Select vehicle").tag("")
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.vehicleNumber?.nonBlank ?? vehicle.model?.nonBlank ?? "Vehicle").tag(vehicle.id)
                            }
                        }
                        Picker("Pricing", selection: $pricingMode) {
                            Text("Package").tag("package")
                            Text("Per km").tag("km")
                        }
                        .pickerStyle(.segmented)
                    } else {
                        TextField("Agency name", text: $agencyName)
                    }
                    TextField("Driver name", text: $driverName)
                    TextField("Driver phone", text: $driverPhone)
                        .keyboardType(.phonePad)
                        .onChange(of: driverPhone) { _, value in driverPhone = sanitizedPhone(value) }
                }

                Section("Distance and rate") {
                    if pricingMode == "package" {
                        fleetNumberField("Package amount", text: $packageAmount)
                    } else {
                        fleetNumberField("Rate per km", text: $kmRate)
                        fleetNumberField("Distance (km)", text: $distanceKm)
                    }
                    fleetNumberField("Start odometer", text: $startKm)
                    fleetNumberField("End odometer", text: $endKm)
                }

                Section("Additional charges") {
                    fleetNumberField("Beta", text: $beta)
                    fleetNumberField("Beta 2", text: $beta2)
                    fleetNumberField("Toll", text: $tollAmount)
                    fleetNumberField("Hill charge", text: $hillCharge)
                    fleetNumberField("Outstation charge", text: $outstationCharge)
                    fleetNumberField("Permit charge", text: $permitCharge)
                    fleetNumberField("Permit tax", text: $permitTax)
                    fleetNumberField("Standing charge", text: $standingCharge)
                    fleetNumberField("Standing time (minutes)", text: $standingMinutes)
                    Toggle("Standing with AC", isOn: $standingWithAc)
                        .disabled(standingMinutes.nonBlank == nil)
                }

                Section {
                    LabeledContent("Estimated total") {
                        Text(totalAmount, format: .currency(code: "INR").precision(.fractionLength(0...2)))
                            .fontWeight(.semibold)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Complete Trip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private func fleetNumberField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private var totalAmount: Double {
        let base = pricingMode == "km"
            ? (number(kmRate) ?? 0) * (number(distanceKm) ?? odometerDistance)
            : (number(packageAmount) ?? 0)
        return base + [beta, beta2, tollAmount, hillCharge, outstationCharge, permitCharge, permitTax, standingCharge]
            .compactMap(number)
            .reduce(0, +)
    }

    private var odometerDistance: Double {
        guard let start = number(startKm), let end = number(endKm), end >= start else { return 0 }
        return end - start
    }

    @MainActor
    private func save() async {
        errorMessage = validationMessage
        guard errorMessage == nil else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let draft = FleetOfflineCompletionDraft(
                fleetType: scope == .mms ? "internal" : "external",
                vehicleId: scope == .mms ? vehicleId.nonBlank : nil,
                agencyName: scope == .agency ? agencyName.nonBlank : nil,
                packageAmount: pricingMode == "package" ? number(packageAmount) : nil,
                kmRate: pricingMode == "km" ? number(kmRate) : nil,
                distanceKm: pricingMode == "km" ? (number(distanceKm) ?? odometerDistance) : number(distanceKm),
                driverName: driverName.nonBlank,
                driverPhone: driverPhone.nonBlank,
                beta: number(beta),
                beta2: number(beta2),
                tollAmount: number(tollAmount),
                hillCharge: number(hillCharge),
                outstationCharge: number(outstationCharge),
                permitCharge: number(permitCharge),
                permitTax: number(permitTax),
                standingCharge: number(standingCharge),
                standingTimeMinutes: number(standingMinutes).map(Int.init),
                standingWithAc: standingMinutes.nonBlank == nil ? nil : standingWithAc,
                startKm: number(startKm),
                endKm: number(endKm)
            )
            try await FleetDispatchAPIService.completeOffline(token: token, scope: scope, tripId: trip.id, draft: draft)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var validationMessage: String? {
        if scope == .mms && vehicleId.nonBlank == nil { return "Select the vehicle used for this trip." }
        if scope == .agency && agencyName.nonBlank == nil { return "Enter the travel agency name." }
        if driverName.nonBlank == nil { return "Enter the driver name." }
        if let phone = driverPhone.nonBlank, !isValidMobile(phone) { return "Enter a valid 10-digit driver phone number." }
        if pricingMode == "package", (number(packageAmount) ?? 0) <= 0 { return "Enter a valid package amount." }
        if pricingMode == "km", (number(kmRate) ?? 0) <= 0 { return "Enter a valid per-km rate." }
        if pricingMode == "km", (number(distanceKm) ?? odometerDistance) <= 0 { return "Enter the distance or valid start/end odometer readings." }
        if let start = number(startKm), let end = number(endKm), end < start { return "End odometer cannot be less than start odometer." }
        return nil
    }

    private func number(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.rounded() == value ? String(Int(value)) : String(value)
    }
}

private struct FleetPortalVehiclesView: View {
    @Environment(AuthStore.self) private var authStore

    let scope: FleetDispatchScope

    @State private var vehicles: [FleetDispatchVehicle] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var showCreate = false
    @State private var selectedVehicle: FleetDispatchVehicle?
    @State private var errorMessage: String?

    private var filteredVehicles: [FleetDispatchVehicle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return vehicles }
        return vehicles.filter { vehicle in
            [vehicle.vehicleNumber, vehicle.type, vehicle.defaultDriverName, vehicle.defaultDriverPhone]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            listContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appScreenBackground)
                .navigationTitle("Vehicle List")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search Vehicles"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showCreate = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Create vehicle")
                    }
                }
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .task {
            guard !hasLoaded else { return }
            await load()
        }
        .sheet(isPresented: $showCreate) {
            FleetVehicleFormSheet(
                token: authStore.currentSession?.token ?? "",
                scope: scope,
                actingStaffId: authStore.currentSession?.user._id,
                agencyName: authStore.currentSession?.user.name?.nonBlank ?? "Default Selected"
            ) {
                await load()
            }
            .appFormActivity()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedVehicle) { vehicle in
            FleetVehicleDetailSheet(
                vehicle: vehicle,
                agencyName: authStore.currentSession?.user.name?.nonBlank ?? "Default Selected",
                token: authStore.currentSession?.token ?? "",
                scope: scope,
                actingStaffId: authStore.currentSession?.user._id
            ) {
                await load()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Vehicles", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private var listContent: some View {
        if isLoading && !hasLoaded {
            FleetPortalLoadingRows().padding(.horizontal, 16)
        } else if filteredVehicles.isEmpty {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No Vehicles",
                    systemImage: "car.side",
                    description: Text("Create a vehicle using the Add button.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(filteredVehicles) { vehicle in
                        Button { selectedVehicle = vehicle } label: {
                            FleetPortalVehicleRow(vehicle: vehicle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 112)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load() }
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token, !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            vehicles = try await FleetDispatchAPIService.listVehicles(token: token, scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FleetPortalVehicleRow: View {
    let vehicle: FleetDispatchVehicle

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color(hex: 0x0B61CA), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.vehicleNumber?.nonBlank ?? "Vehicle")
                    .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                    .lineLimit(1)
                Text([vehicle.type?.nonBlank, vehicle.capacity.map { "\($0) seats" }].compactMap { $0 }.joined(separator: " / ").nonBlank ?? "Vehicle details pending")
                    .font(.system(size: 13))
                .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(vehicle.defaultDriverName?.nonBlank ?? "Unassigned", systemImage: "person")
                    if let phone = vehicle.defaultDriverPhone?.nonBlank {
                        Divider().frame(height: 13)
                        Label(phone, systemImage: "phone")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(minHeight: 102)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
    }
}

private struct FleetPortalDriversView: View {
    @Environment(AuthStore.self) private var authStore

    let scope: FleetDispatchScope

    @State private var drivers: [FleetDispatchDriver] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var showCreate = false
    @State private var editingDriver: FleetDispatchDriver?
    @State private var errorMessage: String?

    private var filteredDrivers: [FleetDispatchDriver] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return drivers }
        return drivers.filter {
            $0.name.lowercased().contains(query)
                || ($0.phone ?? "").contains(query)
                || ($0.address ?? "").lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            listContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appScreenBackground)
                .navigationTitle("Drivers List")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search Drivers"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showCreate = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Create driver")
                    }
                }
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .task {
            guard !hasLoaded else { return }
            await load()
        }
        .sheet(isPresented: $showCreate) {
            FleetDriverFormSheet(
                token: authStore.currentSession?.token ?? "",
                scope: scope,
                actingStaffId: authStore.currentSession?.user._id,
                driver: nil
            ) { await load() }
            .appFormActivity()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingDriver) { driver in
            FleetDriverFormSheet(
                token: authStore.currentSession?.token ?? "",
                scope: scope,
                actingStaffId: authStore.currentSession?.user._id,
                driver: driver
            ) { await load() }
            .appFormActivity()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Drivers", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private var listContent: some View {
        if isLoading && !hasLoaded {
            FleetPortalLoadingRows().padding(.horizontal, 16)
        } else if filteredDrivers.isEmpty {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No Drivers",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Create a driver using the Add button.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(filteredDrivers) { driver in
                        Button { editingDriver = driver } label: {
                            FleetPortalDriverRow(driver: driver)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 112)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load() }
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token, !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            drivers = try await FleetDispatchAPIService.listDrivers(token: token, scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FleetPortalDriverRow: View {
    let driver: FleetDispatchDriver

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color(hex: 0x0B61CA), in: Circle())

                Circle()
                    .fill(driver.isActive ? Color(hex: 0x22C55E) : Color(hex: 0xEF4444))
                    .frame(width: 14, height: 14)
                    .overlay { Circle().stroke(.white, lineWidth: 2) }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(driver.name)
                        .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(driver.isActive ? "Active" : "Inactive")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(driver.isActive ? Color(hex: 0x047857) : Color(hex: 0xB42318))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            (driver.isActive ? Color.green : Color.red).opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }

                if let phone = driver.phone?.nonBlank {
                    Label(phone, systemImage: "phone.fill")
                        .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let address = driver.address?.nonBlank {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 11))
                .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(minHeight: 108)
        .contentShape(Rectangle())
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
    }
}

private struct FleetPortalStaffView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var staff: [FleetAgencyStaff] = []
    @State private var editingStaff: FleetAgencyStaff?
    @State private var showCreate = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && staff.isEmpty {
                    ProgressView("Loading staff…")
                } else if staff.isEmpty {
                    ContentUnavailableView("No Staff", systemImage: "person.2", description: Text("Add agency staff who can manage trips and vehicles."))
                } else {
                    List(staff) { member in
                        Button {
                            editingStaff = member
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color(hex: 0x0B61CA))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(member.name).font(.headline).foregroundStyle(.primary)
                                    Text([member.phone.nonBlank, member.whatsapp?.nonBlank].compactMap { $0 }.joined(separator: " · "))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(member.status.capitalized)
                                    .font(.caption.bold())
                                    .foregroundStyle(member.status == "active" ? .green : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appScreenBackground)
            .navigationTitle("Agency Staff")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Staff", systemImage: "plus") { showCreate = true }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCreate) {
            FleetStaffFormSheet(member: nil) { await load() }
        }
        .sheet(item: $editingStaff) { member in
            FleetStaffFormSheet(member: member) { await load() }
        }
        .alert("Fleet Staff", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do { staff = try await FleetDispatchAPIService.listAgencyStaff(token: token) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct FleetStaffFormSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let member: FleetAgencyStaff?
    let onSaved: () async -> Void

    @State private var name: String
    @State private var phone: String
    @State private var whatsapp: String
    @State private var isActive: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(member: FleetAgencyStaff?, onSaved: @escaping () async -> Void) {
        self.member = member
        self.onSaved = onSaved
        _name = State(initialValue: member?.name ?? "")
        _phone = State(initialValue: member?.phone ?? "")
        _whatsapp = State(initialValue: member?.whatsapp ?? "")
        _isActive = State(initialValue: member?.status != "inactive")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Staff details") {
                    TextField("Name", text: $name).textContentType(.name)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                        .onChange(of: phone) { _, value in phone = sanitizedPhone(value) }
                    TextField("WhatsApp", text: $whatsapp).keyboardType(.phonePad)
                        .onChange(of: whatsapp) { _, value in whatsapp = sanitizedPhone(value) }
                    if member != nil { Toggle("Active", isOn: $isActive) }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(member == nil ? "Add Staff" : "Edit Staff")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || name.nonBlank == nil || !isValidMobile(phone))
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let token = authStore.currentSession?.token else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if let member {
                try await FleetDispatchAPIService.updateAgencyStaff(
                    token: token, id: member.id, name: name.nonBlank,
                    phone: sanitizedPhone(phone), whatsapp: whatsapp.nonBlank.map(sanitizedPhone),
                    status: isActive ? "active" : "inactive"
                )
            } else {
                try await FleetDispatchAPIService.createAgencyStaff(
                    token: token, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: sanitizedPhone(phone), whatsapp: whatsapp.nonBlank.map(sanitizedPhone)
                )
            }
            await onSaved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct FleetAgencySettingsView: View {
    @Environment(AuthStore.self) private var authStore
    let scope: FleetDispatchScope

    @State private var settings = FleetAgencySettings.empty
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if scope == .mms {
                    ContentUnavailableView("Managed by MFPL", systemImage: "building.2", description: Text("Internal fleet pricing is managed by the MFPL backend."))
                } else {
                    Form {
                        Section("Base rates") {
                            numberField("Per kilometre", value: $settings.kmRate)
                            numberField("Package amount", value: $settings.packageAmount)
                            numberField("Betta amount", value: $settings.bettaAmount)
                            numberField("Toll charge", value: $settings.tollCharge)
                        }
                        Section("Permit and standing") {
                            numberField("Permit charge", value: $settings.permitCharge)
                            numberField("Permit tax", value: $settings.permitTax)
                            numberField("Standing charge with AC", value: $settings.standingChargeWithAc)
                            numberField("Standing duration (minutes)", value: $settings.standingChargeDurationMinutes)
                        }
                        Section("Allowances") {
                            numberField("Waiting allowance", value: $settings.waitingAllowance)
                            numberField("Cancellation allowance", value: $settings.cancellationAllowance)
                        }
                        if let savedMessage { Section { Label(savedMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
                        if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                    }
                    .disabled(isLoading || isSaving)
                }
            }
            .navigationTitle("Fleet Settings")
            .toolbar {
                if scope == .agency {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                            .disabled(isLoading || isSaving)
                    }
                }
            }
        }
        .task { if scope == .agency { await load() } }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad)
    }

    @MainActor private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true; defer { isLoading = false }
        do { settings = try await FleetDispatchAPIService.getAgencySettings(token: token) }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func save() async {
        guard let token = authStore.currentSession?.token else { return }
        isSaving = true; savedMessage = nil; errorMessage = nil
        defer { isSaving = false }
        do {
            settings = try await FleetDispatchAPIService.updateAgencySettings(token: token, settings: settings)
            savedMessage = "Settings saved"
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct FleetPortalSettingsView: View {
    @Environment(AuthStore.self) private var authStore

    let photoURL: URL?
    let onBack: () -> Void
    let onProfileUpdated: () async -> Void

    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("app.language") private var languagePreference = ProfileLanguage.english.rawValue
    @AppStorage("fleet.rate.per_km") private var ratePerKm = ""
    @AppStorage("fleet.rate.package") private var packageRate = ""

    @State private var showEditProfile = false
    @State private var showLanguage = false
    @State private var showRates = false
    @State private var showLogout = false

    private var user: AuthUser? { authStore.currentSession?.user }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                    FleetPortalAvatar(name: user?.name, photoURL: photoURL, size: 138)
                        .padding(.top, 42)

                    Text(user?.name?.nonBlank ?? "Fleet Administrator")
                        .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.primary)
                        .padding(.top, 18)
                    Text(user?.phone?.nonBlank ?? "—")
                        .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .padding(.bottom, 48)

                    VStack(spacing: 0) {
                        settingsButton("Edit Profile", icon: "person.badge.key") { showEditProfile = true }
                        settingsButton("Language", icon: "character.book.closed") { showLanguage = true }
                        settingsButton("Rate System", icon: "tag") { showRates = true }

                        HStack(spacing: 16) {
                            Image(systemName: "bell")
                                .font(.system(size: 21, weight: .medium))
                                .frame(width: 28)
                            Text("Manage Notification")
                                .font(.system(size: 17))
                            Spacer()
                            Toggle("", isOn: $notificationsEnabled)
                                .labelsHidden()
                                .tint(.black)
                                .onChange(of: notificationsEnabled) { _, enabled in
                                    if enabled { authStore.requestNotificationPermissions() }
                                }
                        }
                .foregroundStyle(.secondary)
                        .frame(height: 58)
                        .overlay(alignment: .bottom) { Divider() }

                        HStack(spacing: 16) {
                            Image(systemName: "app.badge")
                                .font(.system(size: 21, weight: .medium))
                                .frame(width: 28)
                            Text("App Version")
                                .font(.system(size: 17))
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 14))
                        }
                .foregroundStyle(.secondary)
                        .frame(height: 58)
                        .overlay(alignment: .bottom) { Divider() }

                        Button { showLogout = true } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 21, weight: .medium))
                                    .frame(width: 28)
                                Text("Log Out")
                                    .font(.system(size: 17))
                                Spacer()
                            }
                .foregroundStyle(.secondary)
                            .frame(height: 58)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
        .navigationTitle("Profile Overview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("Back")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .background(Color.appScreenBackground.ignoresSafeArea())
        .sheet(isPresented: $showEditProfile) {
            NavigationStack {
                ProfileEditView(onSaved: {
                    Task {
                        _ = try? await authStore.refreshMyStaffProfile()
                        await onProfileUpdated()
                    }
                })
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRates) {
            FleetRateSheet(perKm: $ratePerKm, package: $packageRate)
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Language", isPresented: $showLanguage, titleVisibility: .visible) {
            ForEach(ProfileLanguage.allCases) { language in
                Button(language.title) { languagePreference = language.rawValue }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showLogout) {
            LogoutConfirmationSheet {
                showLogout = false
            } onLogout: {
                showLogout = false
                Task { await authStore.logout() }
            }
            .presentationDetents([.height(270)])
            .presentationDragIndicator(.hidden)
        }
    }

    private func settingsButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 17))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
                .foregroundStyle(.secondary)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "v.\(version?.nonBlank ?? "1.0")"
    }
}

private struct FleetPortalAvatar: View {
    let name: String?
    let photoURL: URL?
    let size: CGFloat

    private var initials: String {
        let letters = (name ?? "Fleet")
            .split(whereSeparator: { !$0.isLetter })
            .prefix(2)
            .compactMap(\.first)
        return String(letters).uppercased().nonBlank ?? "FA"
    }

    var body: some View {
        Group {
            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: size > 80 ? 0 : 2) }
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold))
            .foregroundStyle(Color(hex: 0x0B61CA))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0xEAF3FF))
    }
}

private struct FleetPortalLoadingRows: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.75))
                    .frame(height: 118)
                    .overlay { ProgressView().tint(Color(hex: 0x0B61CA)) }
            }
        }
    }
}

private struct FleetFormField: View {
    let title: String
    let placeholder: String
    let icon: String
    var required = true
    var keyboardType: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var axis: Axis = .horizontal
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(title)
                if required { Text("*").foregroundStyle(.red) }
            }
            .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(alignment: axis == .vertical ? .top : .center, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 22)
                TextField(placeholder, text: $text, axis: axis)
                    .font(.system(size: 15))
                .foregroundStyle(.primary)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(capitalization)
                    .lineLimit(axis == .vertical ? 3...4 : 1...1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, axis == .vertical ? 12 : 0)
            .frame(minHeight: axis == .vertical ? 92 : 50, alignment: .topLeading)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.appSeparator, lineWidth: 1) }
        }
    }
}

private struct FleetReadOnlyField: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 22)
                Text(value)
                    .font(.system(size: 15))
                .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.appSeparator, lineWidth: 1) }
        }
    }
}

private struct FleetVehicleFormSheet: View {
    @Environment(\.dismiss) private var dismiss

    let token: String
    let scope: FleetDispatchScope
    let actingStaffId: String?
    let agencyName: String
    let vehicle: FleetDispatchVehicle?
    let onSaved: () async -> Void

    @State private var number: String
    @State private var type: String
    @State private var capacity: String
    @State private var driverName: String
    @State private var driverPhone: String
    @State private var isActive: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        token: String,
        scope: FleetDispatchScope,
        actingStaffId: String?,
        agencyName: String,
        vehicle: FleetDispatchVehicle? = nil,
        onSaved: @escaping () async -> Void
    ) {
        self.token = token
        self.scope = scope
        self.actingStaffId = actingStaffId
        self.agencyName = agencyName
        self.vehicle = vehicle
        self.onSaved = onSaved
        _number = State(initialValue: vehicle?.vehicleNumber ?? "")
        _type = State(initialValue: vehicle?.type ?? "")
        _capacity = State(initialValue: vehicle?.capacity.map(String.init) ?? "")
        _driverName = State(initialValue: vehicle?.defaultDriverName ?? "")
        _driverPhone = State(initialValue: vehicle?.defaultDriverPhone ?? "")
        _isActive = State(initialValue: vehicle?.isActive ?? true)
    }

    private var isEditing: Bool { vehicle != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Registration number", text: $number)
                        .textInputAutocapitalization(.characters)
                        .textContentType(.none)
                    TextField("Vehicle type", text: $type)
                    TextField("Capacity", text: $capacity)
                        .keyboardType(.numberPad)
                }

                Section("Default Driver") {
                    TextField("Driver name", text: $driverName)
                        .textContentType(.name)
                    TextField("10-digit mobile number", text: $driverPhone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .onChange(of: driverPhone) { _, value in
                            driverPhone = sanitizedPhone(value)
                        }
                }

                if isEditing {
                    Section {
                        Toggle("Active", isOn: $isActive)
                            .tint(Color(hex: 0x19C90B))
                    }
                }

                Section("Agency") {
                    LabeledContent("Selected", value: agencyName)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Vehicle" : "Create Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") { Task { await submit() } }
                        .disabled(!canSave || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var canSave: Bool {
        !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (driverPhone.isEmpty || isValidMobile(driverPhone))
    }

    @MainActor
    private func submit() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let vehicle {
                // Edit is agency-scope only — Android has no MMS vehicle update.
                try await FleetDispatchAPIService.updateVehicle(
                    token: token,
                    draft: FleetVehicleUpdateDraft(
                        id: vehicle.id,
                        vehicleNumber: number.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank,
                        type: type.nonBlank,
                        capacity: Int(capacity),
                        defaultDriverName: driverName.nonBlank,
                        defaultDriverPhone: driverPhone.nonBlank.map(sanitizedPhone),
                        status: isActive ? "active" : "inactive"
                    )
                )
            } else {
                try await FleetDispatchAPIService.createVehicle(
                    token: token,
                    scope: scope,
                    vehicleNumber: number.trimmingCharacters(in: .whitespacesAndNewlines),
                    type: type.nonBlank,
                    capacity: Int(capacity),
                    defaultDriverName: driverName.nonBlank,
                    defaultDriverPhone: driverPhone.nonBlank.map(sanitizedPhone),
                    actingStaffId: actingStaffId
                )
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FleetVehicleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vehicle: FleetDispatchVehicle
    let agencyName: String
    let token: String
    let scope: FleetDispatchScope
    let actingStaffId: String?
    let onSaved: () async -> Void

    @State private var showEdit = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                FleetSheetTitle(title: "Vehicle Detail", subtitle: "Information about Vehicle")
                // Edit is agency-scope only: Android exposes vehicle update on the
                // travel-desk route only (no MMS in-house vehicle update route).
                if scope == .agency {
                    Button("Edit") { showEdit = true }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .padding(.trailing, 20)
                        .padding(.top, 12)
                }
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    FleetReadOnlyField(title: "Vehicle Number", value: vehicle.vehicleNumber?.nonBlank ?? "—", icon: "car.side")
                    FleetReadOnlyField(title: "Vehicle Type", value: vehicle.type?.nonBlank ?? "—", icon: "car.side")
                    FleetReadOnlyField(title: "Capacity", value: vehicle.capacity.map(String.init) ?? "—", icon: "rectangle.3.group")
                    FleetReadOnlyField(title: "Name", value: vehicle.defaultDriverName?.nonBlank ?? "—", icon: "person.crop.square")
                    FleetReadOnlyField(title: "Phone Number", value: vehicle.defaultDriverPhone?.nonBlank ?? "—", icon: "phone")
                    FleetReadOnlyField(title: "Agency", value: agencyName, icon: "building.2")
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            FleetPrimaryButton(title: "Close", isLoading: false, enabled: true) { dismiss() }
        }
        .sheet(isPresented: $showEdit) {
            FleetVehicleFormSheet(
                token: token,
                scope: scope,
                actingStaffId: actingStaffId,
                agencyName: agencyName,
                vehicle: vehicle
            ) {
                await onSaved()
                dismiss()
            }
            .appFormActivity()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.light)
        }
    }
}

private struct FleetDriverFormSheet: View {
    @Environment(\.dismiss) private var dismiss

    let token: String
    let scope: FleetDispatchScope
    let actingStaffId: String?
    let driver: FleetDispatchDriver?
    let onSaved: () async -> Void

    @State private var name: String
    @State private var phone: String
    @State private var address: String
    // Lowercase MMS contract value ("old" | "new"), matching Android's
    // CreateDriverBottomSheet which sends category.lowercase() (default "new").
    @State private var category: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        token: String,
        scope: FleetDispatchScope,
        actingStaffId: String?,
        driver: FleetDispatchDriver?,
        onSaved: @escaping () async -> Void
    ) {
        self.token = token
        self.scope = scope
        self.actingStaffId = actingStaffId
        self.driver = driver
        self.onSaved = onSaved
        _name = State(initialValue: driver?.name ?? "")
        _phone = State(initialValue: driver?.phone ?? "")
        _address = State(initialValue: driver?.address ?? "")
        let seededCategory = driver?.category?.lowercased()
        _category = State(initialValue: seededCategory == "old" ? "old" : "new")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Driver") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("10-digit mobile number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .onChange(of: phone) { _, value in
                            phone = sanitizedPhone(value)
                        }
                    TextField("Address", text: $address, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                        .lineLimit(2...4)
                    Picker("Category", selection: $category) {
                        Text("New").tag("new")
                        Text("Old").tag("old")
                    }
                }

                if let driver {
                    Section {
                        Button(driver.isActive ? "Deactivate Driver" : "Activate Driver", role: driver.isActive ? .destructive : nil) {
                            Task { await toggleStatus(driver) }
                        }
                        .disabled(isSaving)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(driver == nil ? "Create Driver" : "Edit Driver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(driver == nil ? "Create" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isValidMobile(phone)
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let driver {
                try await FleetDispatchAPIService.updateDriver(
                    token: token,
                    scope: scope,
                    id: driver.id,
                    name: name.nonBlank,
                    phone: sanitizedPhone(phone),
                    address: address.nonBlank,
                    category: category,
                    actingStaffId: actingStaffId
                )
            } else {
                try await FleetDispatchAPIService.createDriver(
                    token: token,
                    scope: scope,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: sanitizedPhone(phone),
                    address: address.nonBlank,
                    category: category,
                    actingStaffId: actingStaffId
                )
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleStatus(_ driver: FleetDispatchDriver) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await FleetDispatchAPIService.setDriverStatus(
                token: token,
                scope: scope,
                id: driver.id,
                status: driver.isActive ? "inactive" : "active",
                actingStaffId: actingStaffId
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FleetRateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var perKm: String
    @Binding var package: String
    @State private var draftPerKm: String
    @State private var draftPackage: String
    @State private var validationMessage: String?

    init(perKm: Binding<String>, package: Binding<String>) {
        _perKm = perKm
        _package = package
        _draftPerKm = State(initialValue: perKm.wrappedValue)
        _draftPackage = State(initialValue: package.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rates") {
                    LabeledContent("Per km amount (₹)") {
                        TextField("0.00", text: $draftPerKm)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Package amount (₹)") {
                        TextField("0.00", text: $draftPackage)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Manage Rates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    private func save() {
        guard Double(draftPerKm) != nil, Double(draftPackage) != nil else {
            validationMessage = "Enter valid amounts for both rates."
            return
        }
        perKm = draftPerKm
        package = draftPackage
        dismiss()
    }
}

private struct FleetSheetTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

private struct FleetPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FleetPrimaryButtonContent(title: title, isLoading: isLoading)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
        .opacity(enabled ? 1 : 0.45)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.appScreenBackground)
    }
}

private struct FleetPrimaryButtonContent: View {
    let title: String
    let isLoading: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(isLoading ? 0 : 1)
            if isLoading { ProgressView().tint(.white) }
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Color(hex: 0x19C90B), in: Capsule())
    }
}

private struct FleetFormError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: 0xB42318))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(hex: 0xFEF3F2), in: RoundedRectangle(cornerRadius: 8))
    }
}

private func sanitizedPhone(_ value: String) -> String {
    String(value.filter(\.isNumber).prefix(10))
}

private func isValidMobile(_ value: String) -> Bool {
    let digits = sanitizedPhone(value)
    guard digits.count == 10, let first = digits.first else { return false }
    return "6789".contains(first)
}
