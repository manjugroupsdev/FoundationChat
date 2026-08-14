import Combine
import CoreLocation
import SwiftUI
import UIKit

/// Home tab cloned from Android `HomeFragment`, adapted to SwiftUI.
///
/// Scope note: this view owns the Home surface only.
struct HomeView: View {
    @Environment(AuthStore.self) private var authStore
    @Binding private var hasPlayedEntryAnimation: Bool
    @State private var formActivityStore = AppFormActivityStore.shared

    @State private var todayVisits: [GeoTrackTodayVisit] = []
    @State private var assignedPlaces: [GeoTrackAssignedPlace] = []
    @State private var todayAttendance: ConvexTodayAttendance?
    @State private var monthAttendanceRecords: [ConvexAttendanceRecord] = []
    @State private var dailyTasks: [DailyTask] = []
    @State private var taskNudgeTasks: [DailyTask] = []
    @State private var managementDashboard: ConvexMobileDashboard?
    @State private var managementDashboardError: String?
    @State private var isManagementDashboardLoading = false
    @State private var selectedManagementDashboardTab: HomeDashboardTab = .hr
    @State private var selectedDashboardDate: Date?
    @State private var dashboardPickerDate = Date()
    // Lenient day-gate: source-agnostic "clocked in / open session for today"
    // (any non-blank firstPunchIn, biometric included; survives a mid-day break).
    // Drives the attendance status + live ticker.
    @State private var hasOpenSession = false
    // Strict "an attendance session is open RIGHT NOW". Gates STARTING a new trip
    // so a clocked-out staffer must clock in first. Nil-on-error is absorbed in
    // loadAttendanceGate (a transient error never flips this false).
    @State private var hasOpenSessionNow = false
    @State private var unreadCount = 0
    @State private var isLoading = true
    @State private var isVisitsLoading = false
    @State private var loadError: String?
    @State private var visitToOpen: GeoTrackTodayVisit?
    @State private var backendDriverMode = false
    @State private var showPunchIn = false
    @State private var showPunchOut = false
    @State private var showClockOutConfirm = false
    @State private var selectedTripFilter: HomeTripFilter = .all
    @State private var appeared = false
    @State private var headerEntryStarted = false
    @State private var headerFloating = false
    @State private var showQRPanel = false
    @State private var showQRScanner = false
    @State private var showPendingTasksSheet = false
    @State private var showTaskManager = false
    @State private var selectedTaskDestination: HomeTaskDestination?
    @State private var webTaskLink: HomeWebTaskLink?
    @State private var showNotifications = false
    @State private var showProfile = false
    @State private var showDashboardDatePicker = false
    @State private var showScrollToTop = false
    @State private var homeScrollOffset: CGFloat = 0
    @AppStorage("home.pendingTasksSheet.lastPresentedAt") private var pendingTaskSheetLastPresentedAt = 0.0

    private let geoAPI = GeoTrackAPIService.shared
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let pendingTaskSheetInterval: TimeInterval = 15 * 60

    init(hasPlayedEntryAnimation: Binding<Bool> = .constant(false)) {
        _hasPlayedEntryAnimation = hasPlayedEntryAnimation
        let isSettled = hasPlayedEntryAnimation.wrappedValue
        _appeared = State(initialValue: isSettled)
        _headerEntryStarted = State(initialValue: isSettled)
        _headerFloating = State(initialValue: isSettled)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                HomePalette.pageBackground.ignoresSafeArea()

                headerTopFill

                blueHeader
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .zIndex(1)

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        Color.clear
                            .frame(height: 0)
                            .id(HomeScrollTarget.top)

                        Color.clear
                            .frame(height: homeHeaderHeight)

                        contentArea
                            .padding(.bottom, 28)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await reload() }
                    .ignoresSafeArea(edges: .top)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                    } action: { _, scrollY in
                        homeScrollOffset = -scrollY
                        let shouldShow = scrollY > 520
                        guard shouldShow != showScrollToTop else { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            showScrollToTop = shouldShow
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showScrollToTop {
                            Button {
                                withAnimation(.snappy(duration: 0.35)) {
                                    scrollProxy.scrollTo(HomeScrollTarget.top, anchor: .top)
                                }
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 46, height: 46)
                                    .background(.blue.gradient, in: Circle())
                                    .shadow(color: Color(hex: 0x0B61CA).opacity(0.28), radius: 14, x: 0, y: 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Scroll to top")
                            .padding(.trailing, 18)
                            .padding(.bottom, 18)
                            .transition(.scale(scale: 0.82).combined(with: .opacity))
                        }
                    }
                    .offset(y: headerEntryStarted ? 0 : -150)
                    .animation(.easeOut(duration: 0.72), value: headerEntryStarted)
                }
                .zIndex(2)

                if showsBottomTaskPeek {
                    GeometryReader { geometry in
                        let isCollapsed = isBottomTaskPeekCollapsed
                        let peekWidth: CGFloat = isCollapsed ? 52 : 264
                        let peekHeight: CGFloat = isCollapsed ? 52 : 40
                        let firstTabCenterX = geometry.size.width / 8

                        bottomPendingTaskStrip
                            .frame(width: peekWidth, height: peekHeight)
                            .position(
                                x: isCollapsed ? firstTabCenterX : geometry.size.width / 2,
                                y: geometry.size.height - 82 - (peekHeight / 2)
                            )
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(
                        .interactiveSpring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.16),
                        value: isBottomTaskPeekCollapsed
                    )
                    .zIndex(9)
                }

                if !isHomeChromeCollapsed {
                    homeHeaderActions
                        .padding(.top, 8)
                        .padding(.trailing, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .opacity(headerEntryStarted ? 1 : 0)
                        .offset(x: headerEntryStarted ? 0 : 30)
                        .allowsHitTesting(headerEntryStarted && !showQRPanel)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(13)
                }

                edgeQRHandle
                    .zIndex(12)

                if showQRPanel {
                    edgeQRPanel
                        .zIndex(18)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(
                (showQRPanel || showNotifications || showProfile) ? .hidden : .visible,
                for: .tabBar
            )
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
                    cpVisitCategory: visit.visitCategory,
                    cpType: visit.cpVisit?.cpType,
                    requiresOpenAttendance: true,
                    onTripChanged: {
                        Task { await reload() }
                    }
                )
            }
            .navigationDestination(isPresented: $showTaskManager) {
                TasksListView()
            }
            .navigationDestination(item: $selectedTaskDestination) { destination in
                destination.view
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationsListView()
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
                    .toolbar(.hidden, for: .tabBar)
            }
            .sheet(isPresented: $showPunchIn) {
                PunchFlowView(mode: .punchIn) {
                    Task { await reload() }
                }
            }
            .sheet(isPresented: $showPunchOut) {
                PunchFlowView(mode: .punchOut) {
                    Task { await reload() }
                }
            }
            .sheet(isPresented: $showClockOutConfirm) {
                ClockOutConfirmSheet {
                    showClockOutConfirm = false
                    showPunchOut = true
                } onCancel: {
                    showClockOutConfirm = false
                }
                .presentationDetents([.height(430)])
                .presentationBackground(Color.clear)
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showPendingTasksSheet) {
                NavigationStack {
                    PendingTasksSheet(
                        tasks: pendingTaskNudgeTasks,
                        totalPending: pendingTaskNudgeTasks.count,
                        onOpenTask: openPendingTask
                    )
                }
                .presentationDetents([.height(680), .large])
                .presentationCornerRadius(30)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $webTaskLink) { item in
                HomeWebTaskLinkSheet(item: item)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showDashboardDatePicker) {
                NavigationStack {
                    dashboardDatePickerSheet
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showQRScanner) {
                NavigationStack {
                    FrontDeskQRScannerView(showsCloseButton: true)
                }
            }
            .task {
                await reload()
                appeared = true
                if hasPlayedEntryAnimation {
                    headerEntryStarted = true
                    headerFloating = true
                } else {
                    playHomeHeaderAnimation()
                    hasPlayedEntryAnimation = true
                }
            }
            .onAppear {
                guard appeared else { return }
                headerEntryStarted = true
                headerFloating = true
                Task { await reload() }
            }
            .onDisappear {
                headerFloating = false
            }
            .onChange(of: canViewManagementDashboard) { oldValue, newValue in
                guard oldValue != newValue, appeared else { return }
                Task { await reload() }
            }
            .onChange(of: formActivityStore.isFormActive) { _, isFormActive in
                if isFormActive {
                    showPendingTasksSheet = false
                } else {
                    presentPendingTasksSheetIfDue()
                }
            }
            .onReceive(timer) { _ in
                presentPendingTasksSheetIfDue()
                guard todayAttendance?.isOpen == true || hasOpenSession else { return }
                Task { await loadAttendanceSummary() }
            }
        }
    }

    // MARK: - Header

    private var headerTopFill: some View {
        HomePalette.headerBlue
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private var homeHeaderHeight: CGFloat { 222 }

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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 98)
                    .opacity(headerEntryStarted ? 1 : 0)
                    .offset(x: headerEntryStarted ? 0 : -30)
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38).delay(0.12), value: headerEntryStarted)

                Text("Track your tasks, visits and\nattendance in one place.")
                    .font(.system(size: 10.8, weight: .medium))
                    .foregroundStyle(Color(red: 0.93, green: 0.92, blue: 1.0))
                    .lineSpacing(2)
                    .padding(.top, 4)
                    .opacity(headerEntryStarted ? 1 : 0)
                    .offset(x: headerEntryStarted ? 0 : -30)
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38).delay(0.20), value: headerEntryStarted)

                NavigationLink {
                    ConvexAttendanceListView()
                } label: {
                    HStack(spacing: 4) {
                        Text("View My Summary")
                            .font(.system(size: 9.6, weight: .semibold))

                        Image(systemName: "chevron.right.3")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(HomePalette.headerBlue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.white.opacity(0.96), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .opacity(headerEntryStarted ? 1 : 0)
                .offset(x: headerEntryStarted ? 0 : -30)
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38).delay(0.30), value: headerEntryStarted)

                Spacer(minLength: 0)
            }
            .frame(width: 208, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)

            bannerIllustration
                .padding(.top, 104)
                .padding(.trailing, 20)

        }
        .frame(height: 222)
        .clipped()
    }

    private var homeHeaderActions: some View {
        HStack(spacing: 6) {
            Button {
                showNotifications = true
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
            .accessibilityLabel("Notifications")

            Button {
                showProfile = true
            } label: {
                ProfileAvatarView(label: authStore.currentUserLabel)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(4)
        .background(Color.white.opacity(0.18), in: Capsule())
    }

    private var bannerIllustration: some View {
        ZStack {
            bannerImage(
                name: "HomeBannerGlitter",
                size: CGSize(width: 96, height: 48),
                alignment: .top,
                entryDelay: 0.16,
                floatOffset: 4,
                floatDelay: 1.0
            )

            bannerImage(
                name: "HomeBannerMobile",
                size: CGSize(width: 76, height: 99),
                alignment: .center,
                entryDelay: 0.20,
                floatOffset: -6,
                floatDelay: 0.75
            )

            bannerImage(
                name: "HomeBannerProgress",
                size: CGSize(width: 52, height: 33),
                alignment: .bottomLeading,
                entryDelay: 0.28,
                floatOffset: 5,
                floatDelay: 0.50
            )
            .padding(.bottom, 24)

            bannerImage(
                name: "HomeBannerSuitcase",
                size: CGSize(width: 50, height: 52),
                alignment: .bottomTrailing,
                entryDelay: 0.36,
                floatOffset: -5,
                floatDelay: 1.50
            )
            .padding(.bottom, 16)
        }
        .frame(width: 122, height: 114)
        .accessibilityHidden(true)
    }

    private func bannerImage(
        name: String,
        size: CGSize,
        alignment: Alignment,
        entryDelay: Double,
        floatOffset: CGFloat,
        floatDelay: Double
    ) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .opacity(headerEntryStarted ? 1 : 0)
            .scaleEffect(headerEntryStarted ? 1 : 0.92)
            .offset(
                x: headerEntryStarted ? 0 : 32,
                y: headerEntryStarted ? (headerFloating ? floatOffset : 0) : 12
            )
            .animation(.easeOut(duration: 0.42).delay(entryDelay), value: headerEntryStarted)
            .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(floatDelay), value: headerFloating)
    }

    private func playHomeHeaderAnimation() {
        headerFloating = false
        headerEntryStarted = false
        DispatchQueue.main.async {
            headerEntryStarted = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.84) {
            headerFloating = true
        }
    }

    private var edgeQRHandle: some View {
        HStack {
            Spacer()

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    showQRPanel = true
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 80)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 14,
                            bottomLeadingRadius: 14,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                        .fill(Color(hex: 0x0B61CA).opacity(0.96))
                        .shadow(color: .black.opacity(0.18), radius: 10, x: -4, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        guard value.translation.width < -18 else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            showQRPanel = true
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.top, 92)
    }

    private var edgeQRPanel: some View {
        ZStack {
            Color(hex: 0x0F172A)
                .opacity(0.90)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        showQRPanel = false
                    }
                }

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    showQRPanel = false
                }
                showQRScanner = true
            } label: {
                VStack(spacing: 14) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Scan QR Code")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Tap to open Front Desk Scanner")
                        .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if canViewManagementDashboard {
                managementDashboardSection
                    .padding(.top, 18)
            } else {
                tripSection
                    .padding(.top, 18)
            }
        }
        .padding(.horizontal, canViewManagementDashboard ? 16 : 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            HomePalette.pageBackground,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
    }

    private var homeOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Today's Overview")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HomePalette.textPrimary)

                Spacer()

                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HomePalette.headerBlue)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color(hex: 0xEAF1FF), in: Capsule())
            }

            todayAttendanceCard
            monthlyStatsCard
        }
    }

    private var tripSection: some View {
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

                if !allTripVisits.isEmpty {
                    Text("\(allTripVisits.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HomePalette.badgePurple)
                        .frame(width: 20, height: 20)
                        .background(Color(red: 0.95, green: 0.93, blue: 1.0), in: Circle())
                }

                Spacer()
            }

            if isDriverMode && !allTripVisits.isEmpty {
                tripFilterRow
            }

            // Only show the full white skeleton on a TRUE cold load (no data yet).
            // On refresh / return-to-Home, keep the existing trips visible instead
            // of flashing the skeleton over them (the "white layer" that covered the
            // view on every reload). Mirrors the dashboard's `managementDashboard == nil` gate.
            if isLoading && visibleVisits.isEmpty {
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
                            etaText: etaText(for: visit)
                        ) {
                            handleTripTap(visit)
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
    }

    private var managementDashboardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(selectedDashboardDate == nil ? "Today's Overview" : "Overview")
                    .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

                Spacer()

                Button {
                    dashboardPickerDate = selectedDashboardDate ?? Date()
                    showDashboardDatePicker = true
                } label: {
                    Label(dashboardDateLabel, systemImage: "calendar")
                        .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(.white, in: Capsule())
                        .overlay(Capsule().stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose the dashboard date")
            }
            .padding(.bottom, 2)

            managementDashboardTabs

            if isManagementDashboardLoading && managementDashboard == nil {
                managementDashboardSkeleton
            } else if let managementDashboard {
                managementDashboardGrid(for: managementDashboard)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                ContentUnavailableView(
                    "Dashboard Unavailable",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text(managementDashboardError ?? "Pull to refresh and try again.")
                )
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let managementDashboardError, managementDashboard != nil {
                Label(managementDashboardError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xB42318))
                    .padding(.horizontal, 4)
            }
        }
    }

    private var managementDashboardTabs: some View {
        HStack(spacing: 0) {
            dashboardTabButton(.marketing)
            dashboardTabButton(.hr)
        }
        .padding(3)
        .frame(height: 36)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dashboardTabButton(_ tab: HomeDashboardTab) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                selectedManagementDashboardTab = tab
            }
        } label: {
            Text(tab.title)
                .font(.system(size: 18, weight: selectedManagementDashboardTab == tab ? .bold : .medium))
                .foregroundStyle(selectedManagementDashboardTab == tab ? .white : Color(hex: 0x475467))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    selectedManagementDashboardTab == tab ? HomePalette.headerBlue : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func managementDashboardGrid(for dashboard: ConvexMobileDashboard) -> some View {
        let metrics = dashboardMetrics(for: dashboard)
        if selectedManagementDashboardTab == .hr {
            let largeMetrics = Array(metrics.prefix(4))
            let compactMetrics = Array(metrics.dropFirst(4))
            VStack(spacing: 12) {
                LazyVGrid(columns: dashboardGridColumns, spacing: 12) {
                    ForEach(largeMetrics) { metric in
                        dashboardMetricCard(metric)
                    }
                }

                LazyVGrid(columns: dashboardCompactGridColumns, spacing: 10) {
                    ForEach(compactMetrics) { metric in
                        dashboardMetricCard(metric)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: dashboardGridColumns, spacing: 12) {
                    ForEach(metrics) { metric in
                        dashboardMetricCard(metric)
                    }
                }

                marketingFunnelCard(for: dashboard)
                marketingConversionSection(for: dashboard)
            }
        }
    }

    @ViewBuilder
    private func dashboardMetricCard(_ metric: ManagementDashboardMetric) -> some View {
        if let destination = metric.destination {
            NavigationLink {
                dashboardDestination(destination)
            } label: {
                ManagementDashboardMetricCard(metric: metric)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(metric.title) details")
        } else {
            ManagementDashboardMetricCard(metric: metric)
        }
    }

    private var managementDashboardSkeleton: some View {
        LazyVGrid(columns: dashboardGridColumns, spacing: 12) {
            ForEach(0..<6, id: \.self) { index in
                VStack(alignment: .leading, spacing: 12) {
                    Circle()
                        .fill(HomePalette.skeleton)
                        .frame(width: 34, height: 34)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(HomePalette.skeleton)
                        .frame(width: index.isMultiple(of: 2) ? 64 : 82, height: 22)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(HomePalette.skeleton)
                        .frame(width: index.isMultiple(of: 2) ? 92 : 74, height: 10)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
                .background(Color.appSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .redacted(reason: .placeholder)
            }
        }
    }

    private var dashboardDatePickerSheet: some View {
        VStack(spacing: 16) {
            DatePicker(
                "Dashboard date",
                selection: $dashboardPickerDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Button {
                    selectedDashboardDate = nil
                    dashboardPickerDate = Date()
                    showDashboardDatePicker = false
                    Task { await loadManagementDashboard(force: true) }
                } label: {
                    Text("Today")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HomePalette.headerBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(hex: 0xEAF1FF), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    selectedDashboardDate = isDashboardDateToday(dashboardPickerDate) ? nil : dashboardPickerDate
                    showDashboardDatePicker = false
                    Task { await loadManagementDashboard(force: true) }
                } label: {
                    Text("Apply")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(HomePalette.headerBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .navigationTitle("Dashboard Date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDashboardDatePicker = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                }
                .accessibilityLabel("Close")
            }
        }
    }

    private var showsBottomTaskPeek: Bool {
        !pendingTaskNudgeTasks.isEmpty && !showPendingTasksSheet && !showQRPanel
    }

    private var isHomeChromeCollapsed: Bool {
        homeScrollOffset < -10
    }

    private var isBottomTaskPeekCollapsed: Bool {
        isHomeChromeCollapsed
    }

    private var bottomTaskPeekText: String {
        if dueSoonTaskCount > 0 {
            return "\(pendingTaskNudgeTasks.count) pending · \(dueSoonTaskCount) due"
        }
        return "\(pendingTaskNudgeTasks.count) pending"
    }

    private var bottomPendingTaskStrip: some View {
        let isCollapsed = isBottomTaskPeekCollapsed

        return Button {
            presentPendingTasksSheet(force: true)
        } label: {
            ZStack {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .frame(width: 48, height: 48)

                    Text("\(pendingTaskNudgeTasks.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color(hex: 0xE53935), in: Circle())
                        .overlay {
                            Circle().stroke(.white, lineWidth: 1.5)
                        }
                        .offset(x: 3, y: -3)
                }
                .opacity(isCollapsed ? 1 : 0)
                .scaleEffect(isCollapsed ? 1 : 0.72)

                HStack(spacing: 10) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .heavy))

                    Text(bottomTaskPeekText)
                        .font(.system(size: 16, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .monospacedDigit()
                }
                .foregroundStyle(Color(hex: 0xA61B18))
                .frame(maxWidth: .infinity)
                .opacity(isCollapsed ? 0 : 1)
                .scaleEffect(isCollapsed ? 0.92 : 1)
            }
            .frame(height: isCollapsed ? 52 : 40)
            .background {
                LinearGradient(
                    colors: isCollapsed
                        ? [Color.white.opacity(0.98), Color.white.opacity(0.92)]
                        : [Color(hex: 0xFFF7F7).opacity(0.98), Color(hex: 0xFCE7E7).opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: isCollapsed ? 26 : 18,
                        bottomLeadingRadius: isCollapsed ? 26 : 0,
                        bottomTrailingRadius: isCollapsed ? 26 : 0,
                        topTrailingRadius: isCollapsed ? 26 : 18,
                        style: .continuous
                    )
                )
            }
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: isCollapsed ? 26 : 18,
                    bottomLeadingRadius: isCollapsed ? 26 : 0,
                    bottomTrailingRadius: isCollapsed ? 26 : 0,
                    topTrailingRadius: isCollapsed ? 26 : 18,
                    style: .continuous
                )
                .stroke(Color(hex: 0xF0A8A8).opacity(0.8), lineWidth: 1.2)
            }
            .shadow(color: Color(hex: 0xB42318).opacity(isCollapsed ? 0.08 : 0.16), radius: isCollapsed ? 6 : 12, x: 0, y: isCollapsed ? 3 : 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bottomTaskPeekText)
    }

    private var tripFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeTripFilter.allCases) { filter in
                    Button {
                        selectedTripFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 12, weight: selectedTripFilter == filter ? .semibold : .medium))
                            .foregroundStyle(selectedTripFilter == filter ? .white : Color(hex: 0x475467))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTripFilter == filter ? HomePalette.headerBlue : Color.white, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color(hex: 0xE5E7EB), lineWidth: selectedTripFilter == filter ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var todayAttendanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today Attendance", systemImage: "clock.badge.checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HomePalette.textPrimary)

                Spacer()

                Text(attendanceStatusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(attendanceStatusColor)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(attendanceStatusColor.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 8) {
                dashboardMetric(title: "In", value: formatAttendanceTime(todayPunchInRaw) ?? "--")
                dashboardMetric(title: "Out", value: formatAttendanceTime(todayPunchOutRaw) ?? (hasOpenSession ? "Active" : "--"))
                dashboardMetric(title: "Hours", value: todayHoursText)
            }

            homeAttendanceActions
        }
        .padding(14)
        .background(dashboardCardBackground)
    }

    @ViewBuilder
    private var homeAttendanceActions: some View {
        if todayPunchInRaw != nil {
            Button {
                showClockOutConfirm = true
            } label: {
                Label("Clock Out", systemImage: "arrow.up.forward.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color(red: 0.09, green: 0.61, blue: 0.18), in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                showPunchIn = true
            } label: {
                Label("Clock In", systemImage: "clock.badge.checkmark.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(HomePalette.headerBlue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var monthlyStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Monthly Stats", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HomePalette.textPrimary)

                Spacer()

                Text(monthLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HomePalette.textSecondary)
            }

            HStack(spacing: 8) {
                dashboardMetric(title: "Days", value: "\(workedDays)")
                dashboardMetric(title: "Total", value: monthHoursText)
                dashboardMetric(title: "Present", value: "\(presentDays)")
            }
        }
        .padding(14)
        .background(dashboardCardBackground)
    }

    private func dashboardMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HomePalette.textSecondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(HomePalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 58)
        .padding(.horizontal, 10)
        .background(Color(red: 0.976, green: 0.98, blue: 0.986), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var dashboardCardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white)
            .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
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

    private var dashboardGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var dashboardCompactGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    @ViewBuilder
    private func dashboardDestination(_ destination: HomeDashboardDestination) -> some View {
        switch destination {
        case .attendance:
            ConvexAttendanceListView()
        case .leaves:
            LeavesListView()
        case .permissions:
            ConvexPermissionListView()
        case .calls:
            DialerView()
        case .leads:
            MyLeadsView()
        case .cpVisits:
            CpVisitsView()
        case .siteVisits:
            SiteVisitsListView()
        case .bookings:
            BookingsListView()
        case .collections:
            CollectionsView()
        }
    }

    /// Mirrors Android `HomeFragment.bindTrend`: a truthful "vs last week" pill
    /// computed from the same-weekday-one-week-earlier baseline, or an empty
    /// string (hidden by the card) when there is no honest delta to show.
    /// Replaces the previously hardcoded fake percentages.
    private func dashboardTrendPill(current: Int, previous: Int?) -> String {
        guard let previous else { return "" }
        if previous == 0 && current == 0 { return "" }
        if previous == 0 { return "↗ new vs last week" }
        let delta = Double(current - previous) * 100.0 / Double(previous)
        let arrow = delta > 0 ? "↗" : (delta < 0 ? "↘" : "→")
        return "\(arrow) \(Int(abs(delta).rounded()))% vs last week"
    }

    private func dashboardMetrics(for dashboard: ConvexMobileDashboard) -> [ManagementDashboardMetric] {
        let blue = Color(hex: 0x0B61CA)
        let green = Color(hex: 0x059669)
        let red = Color(hex: 0xDC2626)
        let orange = Color(hex: 0xEA580C)
        let gray = Color(hex: 0x64748B)
        let blueBg = blue.opacity(0.075)
        let greenBg = green.opacity(0.075)
        let redBg = red.opacity(0.07)
        let orangeBg = orange.opacity(0.07)
        let grayBg = gray.opacity(0.07)
        let bluePill = blue.opacity(0.12)
        let greenPill = green.opacity(0.12)
        let redPill = red.opacity(0.11)
        let orangePill = orange.opacity(0.11)
        let grayPill = gray.opacity(0.11)
        let presentPercent = dashboard.totalStaff > 0
            ? Int((Double(dashboard.present) / Double(dashboard.totalStaff) * 100).rounded())
            : 0

        switch selectedManagementDashboardTab {
        case .hr:
            return [
                .init(
                    title: "Total Active Staff",
                    value: "\(dashboard.totalStaff)",
                    pill: "All Departments",
                    systemImage: "person",
                    tint: blue,
                    background: blueBg,
                    pillBackground: bluePill,
                    pillTextColor: Color(hex: 0x1D4ED8),
                    imageName: "HomeOverview3DStaff",
                    imageSize: CGSize(width: 60, height: 46),
                    size: .large,
                    destination: .attendance
                ),
                .init(
                    title: "Present",
                    value: "\(dashboard.present)",
                    pill: dashboard.totalStaff > 0 ? "\(presentPercent)% of Total" : nil,
                    systemImage: "calendar",
                    tint: green,
                    background: greenBg,
                    pillBackground: greenPill,
                    pillTextColor: Color(hex: 0x047857),
                    imageName: "HomeOverview3DPresent",
                    imageSize: CGSize(width: 62, height: 62),
                    size: .large,
                    destination: .attendance
                ),
                .init(
                    title: "Absent",
                    value: "\(dashboard.absent)",
                    pill: "↘ High Today",
                    systemImage: "person",
                    tint: red,
                    background: redBg,
                    pillBackground: redPill,
                    pillTextColor: Color(hex: 0xB42318),
                    imageName: "HomeOverview3DAbsent",
                    imageSize: CGSize(width: 66, height: 60),
                    size: .large,
                    destination: .attendance
                ),
                .init(
                    title: "Leave",
                    value: "\(dashboard.leaveCount)",
                    pill: "✓ Approved",
                    systemImage: "calendar",
                    tint: orange,
                    background: orangeBg,
                    pillBackground: orangePill,
                    pillTextColor: Color(hex: 0xB54708),
                    imageName: "HomeOverview3DLeave",
                    imageSize: CGSize(width: 66, height: 60),
                    size: .large,
                    destination: .leaves
                ),
                .init(
                    title: "Week Off",
                    value: "\(dashboard.weekOff ?? 0)",
                    pill: "No Data",
                    systemImage: "calendar",
                    tint: gray,
                    background: grayBg,
                    pillBackground: grayPill,
                    pillTextColor: Color(hex: 0x475467),
                    imageName: "HomeOverview3DWeekOff",
                    imageSize: CGSize(width: 42, height: 50),
                    size: .compact,
                    destination: .attendance
                ),
                .init(
                    title: "Permission",
                    value: "\(dashboard.permissionCount ?? 0)",
                    pill: "No Requests",
                    systemImage: "clipboard",
                    tint: blue,
                    background: blueBg,
                    pillBackground: bluePill,
                    pillTextColor: Color(hex: 0x1D4ED8),
                    imageName: "HomeOverview3DPermission",
                    imageSize: CGSize(width: 38, height: 46),
                    size: .compact,
                    destination: .permissions
                ),
                .init(
                    title: "WFH Approved",
                    value: "\(dashboard.wfhApproved ?? 0)",
                    pill: "No Data",
                    systemImage: "house",
                    tint: green,
                    background: greenBg,
                    pillBackground: grayPill,
                    pillTextColor: Color(hex: 0x475467),
                    imageName: "HomeOverview3DWfh",
                    imageSize: CGSize(width: 50, height: 56),
                    size: .compact,
                    destination: .attendance
                )
            ]

        case .marketing:
            return [
                .init(
                    title: "Total Calls",
                    value: "\(dashboard.totalCalls)",
                    pill: dashboardTrend(current: dashboard.totalCalls, previous: dashboard.prevTotalCalls),
                    systemImage: "phone",
                    tint: blue,
                    background: blueBg,
                    pillBackground: bluePill,
                    pillTextColor: Color(hex: 0x1D4ED8),
                    imageName: "HomeMarketing3DCalls",
                    imageSize: CGSize(width: 66, height: 66),
                    size: .large,
                    destination: .calls
                ),
                .init(
                    title: "Incoming",
                    value: "\(dashboard.incomingCalls)",
                    pill: dashboardTrend(current: dashboard.incomingCalls, previous: dashboard.prevIncomingCalls),
                    systemImage: "phone.fill",
                    tint: green,
                    background: greenBg,
                    pillBackground: greenPill,
                    pillTextColor: Color(hex: 0x047857),
                    imageName: "HomeMarketing3DIncoming",
                    imageSize: CGSize(width: 66, height: 66),
                    size: .large,
                    destination: .calls
                ),
                .init(
                    title: "Outgoing",
                    value: "\(dashboard.outboundCalls)",
                    pill: dashboardTrend(current: dashboard.outboundCalls, previous: dashboard.prevOutboundCalls),
                    systemImage: "phone",
                    tint: blue,
                    background: blueBg,
                    pillBackground: bluePill,
                    pillTextColor: Color(hex: 0x1D4ED8),
                    imageName: "HomeMarketing3DOutgoing",
                    imageSize: CGSize(width: 66, height: 66),
                    size: .large,
                    destination: .calls
                ),
                .init(
                    title: "Hot",
                    value: "\(dashboard.hotLeadCount)",
                    pill: "🔥 High Priority",
                    systemImage: "rectangle.fill",
                    tint: red,
                    background: redBg,
                    pillBackground: redPill,
                    pillTextColor: Color(hex: 0xB42318),
                    imageName: "HomeMarketing3DHot",
                    imageSize: CGSize(width: 60, height: 66),
                    size: .large,
                    destination: .leads
                ),
                .init(
                    title: "Warm",
                    value: "\(dashboard.warmLeadCount)",
                    pill: "Trending",
                    systemImage: "mappin",
                    tint: orange,
                    background: orangeBg,
                    pillBackground: orangePill,
                    pillTextColor: Color(hex: 0xB54708),
                    imageName: "HomeMarketing3DWarm",
                    imageSize: CGSize(width: 66, height: 66),
                    size: .compact,
                    destination: .leads
                ),
                .init(
                    title: "Cold",
                    value: "\(dashboard.coldLeadCount)",
                    pill: "Needs Attention",
                    systemImage: "person.fill",
                    tint: gray,
                    background: grayBg,
                    pillBackground: grayPill,
                    pillTextColor: Color(hex: 0x475467),
                    imageName: "HomeMarketing3DCold",
                    imageSize: CGSize(width: 72, height: 66),
                    size: .compact,
                    destination: .leads
                ),
                .init(
                    title: "SV Fixed",
                    value: "\(dashboard.svVisitsFixed)",
                    pill: "Verified",
                    systemImage: "clipboard",
                    tint: blue,
                    background: blueBg,
                    pillBackground: bluePill,
                    pillTextColor: Color(hex: 0x1D4ED8),
                    imageName: "HomeMarketing3DSv",
                    imageSize: CGSize(width: 72, height: 66),
                    size: .compact,
                    destination: .siteVisits
                ),
                .init(
                    title: "CP / Bookings",
                    value: "\(dashboard.cpVisitsFixed)",
                    pill: "Confirmed",
                    systemImage: "house",
                    tint: green,
                    background: greenBg,
                    pillBackground: grayPill,
                    pillTextColor: Color(hex: 0x475467),
                    imageName: "HomeMarketing3DCp",
                    imageSize: CGSize(width: 66, height: 66),
                    size: .compact,
                    destination: .cpVisits
                )
            ]
        }
    }

    private func dashboardTrend(current: Int, previous: Int?) -> String? {
        guard let previous, previous != 0 || current != 0 else { return nil }
        guard previous != 0 else { return "↗ new vs last week" }
        let delta = Double(current - previous) * 100 / Double(previous)
        let arrow = delta > 0 ? "↗" : delta < 0 ? "↘" : "→"
        return "\(arrow) \(Int(abs(delta).rounded()))% vs last week"
    }

    private func marketingFunnelCard(for dashboard: ConvexMobileDashboard) -> some View {
        let stages = marketingFunnelStages(for: dashboard)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TODAY'S FUNNEL")
                    .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                Spacer()
                Text(dashboardDateLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 3) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                        Text(stage.value)
                            .font(.system(size: index < 4 ? 12 : 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: max(38, 132 - CGFloat(index * 18)), height: 28)
                            .background(
                                LinearGradient(
                                    colors: [stage.color.opacity(0.82), stage.color],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .shadow(color: stage.color.opacity(0.18), radius: 3, y: 2)
                    }
                }
                .frame(width: 136)

                VStack(spacing: 0) {
                    ForEach(stages) { stage in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(stage.color)
                                .frame(width: 7, height: 7)
                            Text(stage.title)
                                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 3)
                            Text(stage.percentage)
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
                        }
                        .frame(height: 31)
                    }
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xE5E7EB), lineWidth: 1))
        .shadow(color: Color(hex: 0x101828).opacity(0.06), radius: 10, y: 4)
    }

    private func marketingConversionSection(for dashboard: ConvexMobileDashboard) -> some View {
        let interested = dashboard.hotLeadCount + dashboard.warmLeadCount
        let booking = dashboard.bookingCount
        let metrics = [
            MarketingConversionMetric(
                title: "Interest Rate",
                value: conversionPercent(interested, from: dashboard.totalCalls),
                systemImage: "person.crop.circle.badge.checkmark",
                tint: Color(hex: 0x3B82F6)
            ),
            MarketingConversionMetric(
                title: "Warm to Hot",
                value: conversionPercent(dashboard.hotLeadCount, from: dashboard.warmLeadCount),
                systemImage: "flame.fill",
                tint: Color(hex: 0xEF4444)
            ),
            MarketingConversionMetric(
                title: "Hot to Site Visit",
                value: conversionPercent(dashboard.svVisitsFixed, from: dashboard.hotLeadCount),
                systemImage: "mappin.and.ellipse",
                tint: Color(hex: 0xF59E0B)
            ),
            MarketingConversionMetric(
                title: "Site Visit to Booking",
                value: booking.map { conversionPercent($0, from: dashboard.svVisitsFixed) } ?? "—",
                systemImage: "house.fill",
                tint: Color(hex: 0x10B981)
            )
        ]

        return VStack(alignment: .leading, spacing: 9) {
            Text("KEY CONVERSION KPIs")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(metrics) { metric in
                        MarketingConversionCard(metric: metric)
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func marketingFunnelStages(for dashboard: ConvexMobileDashboard) -> [MarketingFunnelStage] {
        let interested = dashboard.hotLeadCount + dashboard.warmLeadCount
        let booking = dashboard.bookingCount
        return [
            .init(title: "Total Calls", value: "\(dashboard.totalCalls)", percentage: "100%", color: Color(hex: 0x3B82F6)),
            .init(title: "Interested", value: "\(interested)", percentage: conversionPercent(interested, from: dashboard.totalCalls), color: Color(hex: 0x06B6D4)),
            .init(title: "Warm Leads", value: "\(dashboard.warmLeadCount)", percentage: conversionPercent(dashboard.warmLeadCount, from: dashboard.totalCalls), color: Color(hex: 0xF59E0B)),
            .init(title: "Hot Leads", value: "\(dashboard.hotLeadCount)", percentage: conversionPercent(dashboard.hotLeadCount, from: dashboard.totalCalls), color: Color(hex: 0xEF4444)),
            .init(title: "Site Visits", value: "\(dashboard.svVisitsFixed)", percentage: conversionPercent(dashboard.svVisitsFixed, from: dashboard.totalCalls), color: Color(hex: 0x8B5CF6)),
            .init(title: "Bookings", value: booking.map(String.init) ?? "—", percentage: booking.map { conversionPercent($0, from: dashboard.totalCalls) } ?? "—", color: Color(hex: 0x10B981))
        ]
    }

    private func conversionPercent(_ value: Int, from total: Int) -> String {
        guard total > 0 else { return "0%" }
        return (Double(value) * 100 / Double(total))
            .formatted(.number.precision(.fractionLength(1))) + "%"
    }

    // MARK: - Data Mapping

    private var allTripVisits: [GeoTrackTodayVisit] {
        todayVisits.filter { !["cancelled", "canceled"].contains($0.status.lowercased()) }
    }

    private var visibleVisits: [GeoTrackTodayVisit] {
        guard isDriverMode else { return allTripVisits }
        return allTripVisits.filter { selectedTripFilter.matches($0, state: tripState(for: $0)) }
    }

    private var isDriverMode: Bool {
        authStore.currentSession?.user.isFleetDriverMode == true || backendDriverMode
    }

    private var canViewManagementDashboard: Bool {
        authStore.currentSession?.user.canViewManagementDashboard == true
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
        // Starting a NEW trip requires a live open session (strict gate). An
        // already-started trip above is unaffected, so it keeps working through a
        // mid-day break; only a fresh start is blocked until the staffer clocks in.
        if !hasOpenSessionNow {
            return .clockInFirst
        }
        return .ready
    }

    private func handleTripTap(_ visit: GeoTrackTodayVisit) {
        if tripState(for: visit) == .clockInFirst {
            showPunchIn = true
            return
        }
        visitToOpen = visit
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
        // Cache-first: paint the last-known attendance + dashboard snapshots
        // synchronously BEFORE the loading flags/network round-trip, so the
        // clocked-in status, times and VP tiles appear instantly on open.
        paintCachedHomeState()
        let usesManagementDashboard = canViewManagementDashboard
        isLoading = true
        isVisitsLoading = !usesManagementDashboard
        defer {
            isLoading = false
            isVisitsLoading = false
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.flushPendingPunches() }
            group.addTask { await self.loadAttendanceGate() }
            group.addTask { await self.loadAttendanceSummary() }
            group.addTask { await self.loadDailyTasks() }
            group.addTask { await self.loadUnread() }
            if usesManagementDashboard {
                group.addTask { await self.loadManagementDashboard() }
            } else {
                group.addTask { await self.loadTodayVisits() }
                group.addTask { await self.loadAssignedPlaces() }
            }
        }
    }

    // MARK: - Cache-first (Android LocalCache parity)

    /// Signed-in staff id used to namespace cache keys so one user never reads
    /// another's snapshot. Falls back to the auth `_id`, then a constant.
    private var cacheStaffId: String {
        let raw = authStore.currentSession?.user.staffId ?? authStore.currentSession?.user._id
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed : nil) ?? "anon"
    }

    private func attendanceCacheKey() -> String {
        "home.attendance.\(cacheStaffId).\(todayDateKey)"
    }

    private func dashboardCacheKey(date: String?) -> String {
        "home.dashboard.\(cacheStaffId).\(date ?? "today")"
    }

    /// Synchronously repaint attendance + dashboard from the last-known cache
    /// when in-memory state is still empty (first open / cold launch). Guarded so
    /// it never clobbers fresher network data on a later reload.
    @MainActor
    private func paintCachedHomeState() {
        if todayAttendance == nil && monthAttendanceRecords.isEmpty,
           let snapshot = LocalCache.get(attendanceCacheKey(), as: HomeAttendanceSnapshot.self) {
            todayAttendance = snapshot.today
            monthAttendanceRecords = snapshot.month
        }
        if canViewManagementDashboard, managementDashboard == nil,
           let cached = LocalCache.get(dashboardCacheKey(date: dashboardDateQuery), as: ConvexMobileDashboard.self) {
            managementDashboard = cached
        }
    }

    @MainActor
    private func loadManagementDashboard(force: Bool = false) async {
        guard let token = authStore.currentSession?.token else {
            managementDashboard = nil
            managementDashboardError = nil
            return
        }
        guard force || !isManagementDashboardLoading else { return }

        let requestedDate = dashboardDateQuery
        isManagementDashboardLoading = true
        defer { isManagementDashboardLoading = false }

        do {
            let dashboard = try await DashboardConvexAPIService.getMobileDashboard(
                token: token,
                date: requestedDate
            )
            guard requestedDate == dashboardDateQuery else { return }
            managementDashboard = dashboard
            managementDashboardError = nil
            // Cache-first: getMobileDashboard already throws unless success==true,
            // so a returned dashboard is always worth caching (Android parity).
            LocalCache.put(dashboardCacheKey(date: requestedDate), dashboard)
        } catch {
            guard requestedDate == dashboardDateQuery else { return }
            if isCancellationError(error) { return }
            let fallbackDate = requestedDate ?? dashboardDateKey(for: Date())
            async let cpResult = try? MarketingConvexAPIService.getMyMarketingCpVisits(
                    token: token,
                    fromDate: fallbackDate,
                    toDate: fallbackDate
                )
            async let svResult = try? HRConvexAPIService.getMySiteVisits(
                    token: token,
                    fromDate: fallbackDate,
                    toDate: fallbackDate
                )
            let (cp, sv) = await (cpResult, svResult)
            guard requestedDate == dashboardDateQuery else { return }
            if cp != nil || sv != nil {
                managementDashboard = .visitFallback(
                    date: fallbackDate,
                    cpVisitsFixed: cp?.count ?? 0,
                    svVisitsFixed: sv?.count ?? 0
                )
                managementDashboardError = "Some company-wide statistics are temporarily unavailable."
            } else {
                managementDashboardError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadTodayVisits() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let sessionDriverMode = authStore.currentSession?.user.isFleetDriverMode == true

        async let legacyResult = loadLegacyTodayVisits(date: today)
        async let cpResult = sessionDriverMode ? .success([]) : loadMarketingCPVisitsForHome()
        async let driverResult = loadFleetDriverTripsForHome()

        let legacyVisitsResult = await legacyResult
        let cpVisitsResult = await cpResult
        let driverTripsResult = await driverResult

        switch legacyVisitsResult {
        case .success(let legacyVisits):
            let cpVisits = (try? cpVisitsResult.get()) ?? []
            let driverTrips: [FleetDriverTrip]
            switch driverTripsResult {
            case .success(let trips):
                backendDriverMode = true
                driverTrips = trips
            case .failure:
                backendDriverMode = false
                driverTrips = []
            }
            todayVisits = mergeTodayVisits(
                legacyVisits: legacyVisits,
                cpVisits: sessionDriverMode || backendDriverMode ? [] : cpVisits,
                driverTrips: sessionDriverMode || backendDriverMode ? driverTrips : []
            )
            loadError = nil
        case .failure(let error) where error is CancellationError:
            loadError = nil
        case .failure(let error):
            if isCancellationError(error) {
                loadError = nil
                return
            }
            todayVisits = []
            loadError = error.localizedDescription
        }
    }

    private func loadLegacyTodayVisits(date: String) async -> Result<[GeoTrackTodayVisit], Error> {
        do {
            let visits = try await geoAPI.todayVisits(date: date)
                .filter { $0.status.lowercased() != "cancelled" }
            return .success(visits)
        } catch {
            return .failure(error)
        }
    }

    private func loadMarketingCPVisitsForHome() async -> Result<[GeoTrackCPVisitDetail], Error> {
        do {
            return .success(try await geoAPI.marketingCPVisits())
        } catch {
            return .failure(error)
        }
    }

    private func loadFleetDriverTripsForHome() async -> Result<[FleetDriverTrip], Error> {
        guard let token = authStore.currentSession?.token else { return .success([]) }
        do {
            return .success(try await FleetConvexAPIService.listDriverTrips(token: token))
        } catch {
            return .failure(error)
        }
    }

    private func mergeTodayVisits(
        legacyVisits: [GeoTrackTodayVisit],
        cpVisits: [GeoTrackCPVisitDetail],
        driverTrips: [FleetDriverTrip]
    ) -> [GeoTrackTodayVisit] {
        let legacyCPIds = Set(legacyVisits.compactMap { $0.clientPlaceVisitId?.nilIfBlank })
        let cpExtras = cpVisits.compactMap { detail -> GeoTrackTodayVisit? in
            guard let id = detail.id?.nilIfBlank, !legacyCPIds.contains(id) else { return nil }
            let status = detail.status?.lowercased() ?? ""
            guard status != "cancelled", status != "completed" else { return nil }
            return detail.toTodayVisitOrNil()
        }
        let existingIds = Set((legacyVisits + cpExtras).map(\.id))
        let driverExtras = driverTrips
            .compactMap { $0.toTodayVisitOrNil() }
            .filter { !existingIds.contains($0.id) }
        let completedStatuses = Set(["completed", "complete", "done", "closed"])
        return (legacyVisits + cpExtras + driverExtras).sorted { lhs, rhs in
            let lhsCompleted = completedStatuses.contains(lhs.status.lowercased())
            let rhsCompleted = completedStatuses.contains(rhs.status.lowercased())
            if lhsCompleted != rhsCompleted { return !lhsCompleted }
            let lhsCreation = lhs.creationTime ?? 0
            let rhsCreation = rhs.creationTime ?? 0
            if lhsCreation != rhsCreation { return lhsCreation > rhsCreation }
            let lhsStart = lhs.scheduledStartTime ?? ""
            let rhsStart = rhs.scheduledStartTime ?? ""
            if lhsStart != rhsStart { return lhsStart > rhsStart }
            return lhs.id < rhs.id
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return (error as NSError).code == NSURLErrorCancelled
    }

    @MainActor
    private func loadAssignedPlaces() async {
        assignedPlaces = (try? await geoAPI.assignedPlaces()) ?? []
    }

    @MainActor
    private func loadAttendanceGate() async {
        guard let token = authStore.currentSession?.token else {
            hasOpenSession = false
            hasOpenSessionNow = false
            return
        }
        // Lenient day-gate (source-agnostic; drives status + ticker).
        hasOpenSession = await AttendanceTrackingGate.hasOpenSessionForToday(token: token)
        // Strict open-session-now gate (gates starting a new trip). nil = couldn't
        // determine (both endpoints errored) — keep the last known value so a
        // transient outage never spuriously forces "Clock in first".
        if let openNow = await AttendanceTrackingGate.hasOpenSessionNow(token: token) {
            hasOpenSessionNow = openNow
        }
    }

    @MainActor
    private func flushPendingPunches() async {
        guard let token = authStore.currentSession?.token else { return }
        // Replay any punches queued while offline, oldest-first, with their original
        // tap time. Runs whenever Home loads (mirrors Android loadHomeData → PunchSyncWorker).
        await PendingPunchSyncCoordinator.shared.flush(token: token)
    }

    @MainActor
    private func loadAttendanceSummary() async {
        guard let token = authStore.currentSession?.token else {
            todayAttendance = nil
            monthAttendanceRecords = []
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        do {
            async let today = HRConvexAPIService.getTodayAttendance(token: token)
            async let month = HRConvexAPIService.getMyAttendance(
                token: token,
                fromDate: formatter.string(from: monthStart),
                toDate: formatter.string(from: now)
            )
            let freshToday = try await today
            let freshMonth = try await month
            todayAttendance = freshToday
            monthAttendanceRecords = freshMonth
            // Cache-first: persist the fresh snapshot so the next Home open paints
            // the clocked-in status + times INSTANTLY (mirrors Android LocalCache).
            LocalCache.put(
                attendanceCacheKey(),
                HomeAttendanceSnapshot(today: freshToday, month: freshMonth)
            )
        } catch {
            // Offline-keep: never wipe the (cached or in-memory) snapshot on a
            // network failure. Only fall to empty when we have nothing to show.
            if todayAttendance == nil && monthAttendanceRecords.isEmpty {
                todayAttendance = nil
                monthAttendanceRecords = []
            }
        }
    }

    @MainActor
    private func loadUnread() async {
        unreadCount = (try? await authStore.fetchUnreadNotificationCount()) ?? 0
    }

    @MainActor
    private func loadDailyTasks() async {
        guard let token = authStore.currentSession?.token else {
            dailyTasks = []
            taskNudgeTasks = []
            return
        }
        async let taskManagerRequest = TasksConvexAPIService.getTaskManagerTasks(
            token: token,
            today: todayDateKey
        )
        async let reminderRequest = TasksConvexAPIService.getPendingTaskReminders(
            token: token,
            today: todayDateKey,
            limit: 10
        )

        do {
            let payload = try await taskManagerRequest
            let sortedTasks = payload.tasks.sorted { ($0.creationTime ?? 0) > ($1.creationTime ?? 0) }
            dailyTasks = sortedTasks
        } catch {
            dailyTasks = []
        }

        do {
            taskNudgeTasks = try await reminderRequest
            presentPendingTasksSheetIfDue()
        } catch {
            // Never fall back to the broad Task Manager list. For admins that
            // scope contains organisation-wide tasks and would recreate the
            // incorrect reminder dialogue this endpoint is designed to avoid.
            taskNudgeTasks = []
        }
    }

    @MainActor
    private func presentPendingTasksSheetIfDue() {
        presentPendingTasksSheet(force: false)
    }

    @MainActor
    private func presentPendingTasksSheet(force: Bool) {
        guard !formActivityStore.isFormActive,
              !pendingTaskNudgeTasks.isEmpty,
              !showPendingTasksSheet,
              !showQRPanel else { return }

        let now = Date().timeIntervalSince1970
        let hasShownRecently = pendingTaskSheetLastPresentedAt > 0
            && now - pendingTaskSheetLastPresentedAt < pendingTaskSheetInterval
        guard force || !hasShownRecently else { return }

        pendingTaskSheetLastPresentedAt = now
        showPendingTasksSheet = true
    }

    @MainActor
    private func openPendingTask(_ task: DailyTask?) {
        pendingTaskSheetLastPresentedAt = Date().timeIntervalSince1970
        showPendingTasksSheet = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let task else {
                showTaskManager = true
                return
            }
            if let destination = HomeTaskDestination(task: task) {
                selectedTaskDestination = destination
            } else {
                webTaskLink = HomeWebTaskLink(task: task)
            }
        }
    }

    // MARK: - Formatting

    private var dashboardDateLabel: String {
        guard let selectedDashboardDate else { return "Today" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return formatter.string(from: selectedDashboardDate)
    }

    private var dashboardDateQuery: String? {
        guard let selectedDashboardDate, !isDashboardDateToday(selectedDashboardDate) else { return nil }
        return dashboardDateKey(for: selectedDashboardDate)
    }

    private func dashboardDateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return formatter.string(from: date)
    }

    private func isDashboardDateToday(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        return calendar.isDate(date, inSameDayAs: Date())
    }

    private func formatDashboardCurrency(_ value: Double) -> String {
        if value >= 100_00_000 {
            return String(format: "INR %.1fCr", value / 100_00_000)
        }
        if value >= 100_000 {
            return String(format: "INR %.1fL", value / 100_000)
        }
        if value >= 1_000 {
            return String(format: "INR %.1fK", value / 1_000)
        }
        return String(format: "INR %.0f", value)
    }

    private func formatVisitTimeOrDate(_ visit: GeoTrackTodayVisit) -> String {
        let start = visit.scheduledStartTime.flatMap(formatTimeValue)
        let end = visit.scheduledEndTime.flatMap(formatTimeValue)
        if let start, let end { return "\(start) - \(end)" }
        if let start { return start }
        if let end { return end }
        return "-"
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
        guard !trimmed.isEmpty, !looksLikeDateOnly(trimmed) else { return nil }

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

        let patterns = ["HH:mm:ss", "HH:mm", "h:mm a", "hh:mm a"]
        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            if let date = formatter.date(from: trimmed) {
                return visitTimeFormatter.string(from: date)
            }
        }

        return nil
    }

    private func looksLikeDateOnly(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":") { return false }
        if trimmed.range(of: #"^\d{4}-\d{1,2}-\d{1,2}$"#, options: .regularExpression) != nil { return true }
        return trimmed.range(of: #"^\d{1,2}/\d{1,2}/\d{2,4}$"#, options: .regularExpression) != nil
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

    private var pendingTaskNudgeTasks: [DailyTask] {
        taskNudgeTasks
    }

    private var dueSoonTaskCount: Int {
        pendingTaskNudgeTasks.filter { task in
            guard let deadline = task.deadline?.nilIfBlank else { return false }
            return deadline <= todayDateKey
        }.count
    }

    private var todayPunchInRaw: String? {
        todayRecord?.firstPunchIn ?? todayRecord?.sessions?.first?.punchInTime ?? todayAttendance?.firstPunchIn ?? todayAttendance?.punchInTime
    }

    private var todayPunchOutRaw: String? {
        todayRecord?.lastPunchOut ?? todayRecord?.sessions?.last?.punchOutTime ?? todayAttendance?.lastPunchOut ?? todayAttendance?.punchOutTime
    }

    private var todayRecord: ConvexAttendanceRecord? {
        monthAttendanceRecords.first { $0.date == todayDateKey }
    }

    private var todayDateKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var attendanceStatusLabel: String {
        if hasOpenSession || todayAttendance?.isOpen == true { return "Clocked In" }
        if todayPunchInRaw != nil { return "Completed" }
        return "Not Started"
    }

    private var attendanceStatusColor: Color {
        if hasOpenSession || todayAttendance?.isOpen == true { return Color(red: 0.09, green: 0.61, blue: 0.18) }
        if todayPunchInRaw != nil { return HomePalette.headerBlue }
        return HomePalette.textSecondary
    }

    private var todayHoursText: String {
        if hasOpenSession || todayAttendance?.isOpen == true,
           let punchIn = parseAttendanceDate(todayPunchInRaw) {
            return formatShortHours(minutes: max(0, Int(Date().timeIntervalSince(punchIn) / 60)))
        }
        let minutes = todayRecord?.totalMinutes
            ?? todayRecord?.cumulativeMinutes
            ?? todayAttendance?.cumulativeMinutes
            ?? todayAttendance?.totalMinutes
            ?? 0
        return minutes > 0 ? formatShortHours(minutes: minutes) : "--"
    }

    private var workedDays: Int {
        monthAttendanceRecords.filter {
            ($0.totalMinutes ?? $0.cumulativeMinutes ?? 0) > 0 || $0.firstPunchIn != nil || $0.sessions?.isEmpty == false
        }.count
    }

    private var presentDays: Int {
        monthAttendanceRecords.filter { record in
            let status = (record.approvedAttendance ?? record.status ?? "").lowercased()
            return status == "present"
                || status == "approved"
                || status == "auto-approved"
                || status == "p"
                || (record.attendanceValue ?? 0) > 0
        }.count
    }

    private var monthHoursText: String {
        let minutes = monthAttendanceRecords.reduce(0) { $0 + ($1.totalMinutes ?? $1.cumulativeMinutes ?? 0) }
        return minutes > 0 ? formatShortHours(minutes: minutes) : "--"
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: Date())
    }

    private func formatShortHours(minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        return String(format: "%dh %02dm", hours, remaining)
    }

    private func formatAttendanceTime(_ raw: String?) -> String? {
        guard let raw, let date = parseAttendanceDate(raw) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func parseAttendanceDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        return nil
    }

}

/// Codable snapshot of the Home attendance-status read path, cached so the
/// clocked-in status + punch times paint instantly on the next Home open.
/// Both fields are `Codable` model structs (see ConvexHRModels).
private struct HomeAttendanceSnapshot: Codable {
    let today: ConvexTodayAttendance?
    let month: [ConvexAttendanceRecord]
}

private enum HomeDashboardTab: String, CaseIterable, Identifiable {
    case hr
    case marketing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hr: return "HR"
        case .marketing: return "Marketing"
        }
    }
}

private enum HomeDashboardDestination {
    case attendance
    case leaves
    case permissions
    case calls
    case leads
    case cpVisits
    case siteVisits
    case bookings
    case collections
}

private enum ManagementDashboardMetricSize {
    case large
    case compact

    var height: CGFloat {
        switch self {
        case .large: return 138
        case .compact: return 120
        }
    }
}

private struct ManagementDashboardMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let pill: String?
    let systemImage: String
    let tint: Color
    let background: Color
    let pillBackground: Color
    let pillTextColor: Color
    let imageName: String
    let imageSize: CGSize
    let size: ManagementDashboardMetricSize
    var destination: HomeDashboardDestination?
}

private struct ManagementDashboardMetricCard: View {
    let metric: ManagementDashboardMetric

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: metric.size == .large ? 14 : 12, weight: .semibold))
                        .foregroundStyle(metric.tint)
                        .frame(width: metric.size == .large ? 30 : 26, height: metric.size == .large ? 30 : 26)
                        .background(metric.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Spacer(minLength: 8)

                    Color.clear
                        .frame(width: 18, height: 18)
                }

                Spacer(minLength: metric.size == .large ? 14 : 9)

                Text(metric.title)
                    .font(.system(size: metric.size == .large ? 14 : 11, weight: .bold))
                .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, metric.size == .compact ? 8 : 0)

                Text(metric.value)
                    .font(.system(size: metric.size == .large ? 26 : 21, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.top, metric.size == .large ? 3 : 1)

                if let pill = metric.pill {
                    Text(pill)
                        .font(.system(size: 8.2, weight: .bold))
                        .foregroundStyle(metric.pillTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                        .padding(.horizontal, metric.size == .large ? 5 : 4)
                        .padding(.vertical, 2.5)
                        .background(metric.pillBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(.top, metric.size == .large ? 5 : 3)
                }
            }
            .padding(metric.size == .large ? 11 : 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Image(metric.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: metric.imageSize.width, height: metric.imageSize.height)
                .padding(.trailing, metric.size == .large ? 3 : 4)
                .padding(.bottom, metric.size == .large ? 3 : 5)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: metric.size.height)
        .background(metric.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appSeparator, lineWidth: 1)
        }
        .shadow(color: Color(hex: 0x101828).opacity(0.03), radius: 1, x: 0, y: 1)
    }
}

private struct MarketingFunnelStage: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let percentage: String
    let color: Color
}

private struct MarketingConversionMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
}

private struct MarketingConversionCard: View {
    let metric: MarketingConversionMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(metric.tint)
                    .frame(width: 38, height: 38)
                    .background(metric.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

                Text(metric.title)
                    .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Text(metric.value)
                .font(.system(size: 23, weight: .bold).monospacedDigit())
                .foregroundStyle(metric.tint)

            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("Live conversion")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(hex: 0x059669))
        }
        .padding(13)
        .frame(width: 154, height: 142, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xE5E7EB), lineWidth: 1))
        .shadow(color: Color(hex: 0x101828).opacity(0.05), radius: 8, y: 3)
    }
}

private struct HomeTripCard: View {
    let title: String
    let time: String
    let distance: String
    let state: HomeTripState
    let etaText: String
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
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHint(state == .clockInFirst ? "Opens clock in" : "Opens trip details")
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

private struct PendingTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int? = 0

    let tasks: [DailyTask]
    let totalPending: Int
    let onOpenTask: (DailyTask?) -> Void

    private var previewTasks: [DailyTask] {
        Array(tasks.prefix(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Task Pending")
                        .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

                    Text("You have \(totalPending) pending task\(totalPending == 1 ? "" : "s")")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(hex: 0xF04438))
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: 0xF04438))
                        .frame(width: 50, height: 50)
                        .background(Color(hex: 0xFEF3F2), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 28)

            if previewTasks.isEmpty {
                ContentUnavailableView(
                    "No Pending Tasks",
                    systemImage: "checkmark.circle.fill",
                    description: Text("You're all caught up.")
                )
                .foregroundStyle(.secondary)
                .frame(height: 430)
            } else {
                GeometryReader { geometry in
                    let cardWidth = min(490, max(252, geometry.size.width - 100))
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(Array(previewTasks.enumerated()), id: \.offset) { index, task in
                                PendingTaskPreviewCard(task: task, index: index)
                                    .frame(width: cardWidth, height: 430)
                                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .onTapGesture {
                                        openTask(task)
                                    }
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, max(50, (geometry.size.width - cardWidth) / 2))
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $selectedIndex)
                }
                .frame(height: 430)
            }

            VStack(spacing: 16) {
                if !previewTasks.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(previewTasks.enumerated()), id: \.element.id) { index, task in
                            Circle()
                                .fill((selectedIndex ?? 0) == index ? Color(hex: 0x2D68FE) : Color(hex: 0xBBD2FF))
                                .frame(width: 8, height: 8)
                                .animation(.snappy(duration: 0.18), value: selectedIndex)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 14, weight: .medium))
                        Text("Swipe to view all tasks")
                            .font(.system(size: 14, weight: .medium))
                    }
                .foregroundStyle(.tertiary)
                }

                Button {
                    openTask(selectedTask)
                } label: {
                    Label(previewTasks.isEmpty ? "Open Tasks" : "Complete Task", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: 0xF04438), Color(hex: 0xC9221C)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.appSurface.opacity(0.0), Color.appFieldBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .background(Color.appSurface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedTask: DailyTask? {
        guard !previewTasks.isEmpty else { return nil }
        return previewTasks[min(max(selectedIndex ?? 0, 0), previewTasks.count - 1)]
    }

    private func openTask(_ task: DailyTask?) {
        dismiss()
        onOpenTask(task)
    }
}

private enum HomeTaskDestination: String, Identifiable {
    case attendance
    case cpVisits
    case siteVisits
    case landInspection
    case issues
    case leaves
    case permissions
    case fines
    case loanDesk
    case loans
    case bookings

    var id: String { rawValue }

    init?(task: DailyTask) {
        let source = (task.sourceReferenceType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch source {
        case "staff_attendance": self = .attendance
        case "client_place_visit", "clientplacevisit": self = .cpVisits
        case "site_visit", "sitevisit": self = .siteVisits
        case "land_inspection", "landinspection", "landproperty": self = .landInspection
        case "issue": self = .issues
        case "leave": self = .leaves
        case "permission": self = .permissions
        case "fine", "fines": self = .fines
        case "loan": self = .loans
        default:
            if source.hasPrefix("fine_") { self = .fines }
            else if source.hasPrefix("loan_") { self = .loanDesk }
            else if source.hasPrefix("loan") { self = .loans }
            else if source.contains("booking") { self = .bookings }
            else { return nil }
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .attendance: ConvexAttendanceListView()
        case .cpVisits: CpVisitsView()
        case .siteVisits: SiteVisitsListView()
        case .landInspection: LandInspectionView()
        case .issues: IssuesView()
        case .leaves: LeavesListView()
        case .permissions: ConvexPermissionListView()
        case .fines: FinesDeductionsView()
        case .loanDesk: LoanDeskView()
        case .loans: LoansView()
        case .bookings: BookingsListView()
        }
    }
}

private struct HomeWebTaskLink: Identifiable {
    let id: String
    let title: String
    let url: URL

    init(task: DailyTask) {
        id = task.id
        title = task.displayTitle
        let raw = task.actionUrl?.nonBlank ?? "https://mg.theairix.com"
        if let absolute = URL(string: raw), absolute.scheme != nil {
            url = absolute
        } else {
            let path = raw.hasPrefix("/") ? raw : "/\(raw)"
            url = URL(string: "https://mg.theairix.com\(path)")!
        }
    }
}

private struct HomeWebTaskLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: HomeWebTaskLink

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("This task is completed in the web app.", systemImage: "safari")
                    .font(.headline)
                Text(item.url.absoluteString)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Open in Web", systemImage: "arrow.up.right.square") {
                    openURL(item.url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                Spacer()
            }
            .padding(20)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct PendingTaskPreviewCard: View {
    let task: DailyTask
    let index: Int

    private var theme: PendingTaskTheme {
        PendingTaskTheme.themes[index % PendingTaskTheme.themes.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(theme.main)
                    .frame(width: 32, height: 32)
                    .background(Color.appElevatedSurface, in: Circle())
                    .overlay {
                        Circle().stroke(theme.main, lineWidth: 1.5)
                    }

                Spacer()

                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.main)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(theme.tint, in: Capsule())
            }

            Image(theme.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .padding(.top, 4)

            Text(task.displayTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.top, 6)

            HStack(spacing: 8) {
                Text("For")
                    .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

                Text(moduleLabel)
                    .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(Color(hex: 0xE7ECFF), in: Capsule())
            }
            .padding(.top, 10)

            Divider()
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Created by")
                    .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                HStack(spacing: 9) {
                    Text(creatorInitials)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.main)
                        .frame(width: 28, height: 28)
                        .background(theme.tint, in: Circle())
                        .overlay {
                            Circle().stroke(theme.main, lineWidth: 1.5)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(creatorName)
                            .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let creatorRole {
                            Text(creatorRole)
                                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.top, 10)

            Divider()
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 8) {
                Text("Created on")
                    .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                HStack(spacing: 9) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xF97316))

                    Text(createdOnText)
                        .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.main.opacity(index == (0) ? 1 : 0.18), lineWidth: index == 0 ? 2.5 : 1.2)
        }
    }

    private var statusLabel: String {
        switch task.status?.lowercased() {
        case "in-progress", "in_progress": return "In Progress"
        case "completed": return "Completed"
        case "cancelled": return "Cancelled"
        default: return "Pending"
        }
    }

    private var moduleLabel: String {
        task.module?.nilIfBlank ?? task.taskCategory?.nilIfBlank ?? task.label?.nilIfBlank ?? "General"
    }

    private var creatorName: String {
        let assignedBy = task.assignedByName?.nilIfBlank
        let assignedTo = task.assignedToName?.nilIfBlank
        if let assignedBy, assignedBy == assignedTo {
            return "Auto assigned"
        }
        return assignedBy ?? "Auto assigned"
    }

    private var creatorRole: String? {
        task.assignedByRole?.nilIfBlank
            ?? task.assignedByDesignation?.nilIfBlank
            ?? task.creatorRole?.nilIfBlank
            ?? task.creatorDesignation?.nilIfBlank
    }

    private var creatorInitials: String {
        let pieces = creatorName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let initials = String(pieces).uppercased()
        return initials.isEmpty ? "U" : initials
    }

    private var createdOnText: String {
        guard let creationTime = task.creationTime else { return "Unknown" }
        let seconds = creationTime > 10_000_000_000 ? creationTime / 1000 : creationTime
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }
}

private struct PendingTaskTheme {
    let main: Color
    let tint: Color
    let symbol: String
    let imageName: String

    static let themes = [
        PendingTaskTheme(main: Color(hex: 0x2D68FE), tint: Color(hex: 0xE0E7FF), symbol: "checklist", imageName: "HomeTask3DBlue"),
        PendingTaskTheme(main: Color(hex: 0xF97316), tint: Color(hex: 0xFFEDD5), symbol: "calendar.badge.clock", imageName: "HomeTask3DOrange"),
        PendingTaskTheme(main: Color(hex: 0x8B5CF6), tint: Color(hex: 0xEDE9FE), symbol: "sparkles", imageName: "HomeTask3DPurple")
    ]
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
        case .complete: return "Completed"
        case .clockInFirst: return "Clock in"
        }
    }

    var actionLabel: String {
        switch self {
        case .ready: return "Start Trip"
        case .enroute: return "Enroute"
        case .reaching: return "Complete Trip"
        case .complete: return "Completed"
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
        case .complete: return Color(red: 0.09, green: 0.61, blue: 0.18)
        case .clockInFirst: return HomePalette.textSecondary
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
        case .complete: return Color(hex: 0x1F7A3F)
        case .clockInFirst: return HomePalette.textSecondary
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

private enum HomeTripFilter: String, CaseIterable, Identifiable {
    case all
    case upcoming
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        }
    }

    func matches(_ visit: GeoTrackTodayVisit, state: HomeTripState) -> Bool {
        switch self {
        case .all:
            return true
        case .upcoming:
            return state != .complete
        case .completed:
            return state == .complete || ["completed", "complete", "done", "closed"].contains(visit.status.lowercased())
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

private extension GeoTrackCPVisitDetail {
    func toTodayVisitOrNil() -> GeoTrackTodayVisit? {
        guard let cpId = id?.nilIfBlank,
              let scheduled = scheduledDate?.nilIfBlank
        else { return nil }

        let effectiveStatus = fieldVisit?.status?.nilIfBlank
            ?? status?.nilIfBlank
            ?? "scheduled"
        let category = isSVCumCP ? "sv_cum_cp" : "direct_cp"
        let canonicalClient = client?.clientName?.nilIfBlank
        let typedContact = lead?.contactName?.nilIfBlank
        let placeLabel = clientPlace?.name?.nilIfBlank
        let displayName = canonicalClient
            ?? typedContact
            ?? placeLabel
            ?? "CP visit"

        return GeoTrackTodayVisit(
            id: cpId,
            clientPlaceId: clientPlaceId?.nilIfBlank ?? cpId,
            scheduledDate: scheduled,
            status: effectiveStatus,
            mobileStatus: nil,
            reachingRadiusMeters: nil,
            placeName: displayName,
            placeAddress: clientPlace?.address?.nilIfBlank ?? clientPlace?.formattedAddress?.nilIfBlank,
            placeType: nil,
            placeLat: clientPlace?.lat,
            placeLng: clientPlace?.lng,
            tripType: "client_place",
            clientPlaceVisitId: cpId,
            leadName: canonicalClient ?? typedContact,
            leadPhone: lead?.mobileNumber?.nilIfBlank ?? client?.mobileNumber?.nilIfBlank,
            cpVisit: GeoTrackCPVisitState(
                clientMet: clientMet,
                clientMetAt: clientMetAt,
                clientNoShowReason: clientNoShowReason,
                outcome: outcome,
                postponeReasons: postponeReasons,
                cpType: cpType
            ),
            scheduledStartTime: scheduledTime?.nilIfBlank,
            scheduledEndTime: nil,
            visitCategory: category,
            travelMode: nil,
            vehiclePreference: vehiclePreference,
            vehicleAssigned: nil,
            creationTime: createdAt
        )
    }

    private var isSVCumCP: Bool {
        let proposedHasFields = proposedSiteVisit?.hasMeaningfulFields == true
        let leadFlaggedSVFixed = lead?.followUpStatus?
            .lowercased()
            .contains("sv_fixed") == true
            || lead?.followUpStatus?
            .lowercased()
            .contains("sv-fixed") == true
        let hasSVFixParty = (expectedAttendeeCount ?? 0) > 0
            || attendees?.isEmpty == false
            || foodPreferences?.nilIfBlank != nil
            || vehiclePreference?.nilIfBlank != nil
        return proposedHasFields || leadFlaggedSVFixed || hasSVFixParty
    }
}

private extension FleetDriverTrip {
    func toTodayVisitOrNil() -> GeoTrackTodayVisit? {
        guard let scheduled = scheduledDate?.nilIfBlank else { return nil }
        let normalizedPhase = phase?.lowercased().replacingOccurrences(of: "-", with: "_")
        let status: String
        switch normalizedPhase {
        case "completed":
            status = "completed"
        case "on_site":
            status = "on_site"
        case "in_progress", "started", "arrived":
            status = "in-progress"
        default:
            status = "scheduled"
        }

        let title = project?.name?.nilIfBlank
            ?? vehicle?.vehicleNumber?.nilIfBlank
            ?? "Driver trip"

        return GeoTrackTodayVisit(
            id: id,
            clientPlaceId: project?.id?.nilIfBlank ?? id,
            scheduledDate: scheduled,
            status: status,
            mobileStatus: status,
            reachingRadiusMeters: nil,
            placeName: title,
            placeAddress: pickupAddress?.nilIfBlank,
            placeType: "project",
            placeLat: nil,
            placeLng: nil,
            tripType: "site_visit",
            clientPlaceVisitId: nil,
            leadName: nil,
            leadPhone: nil,
            cpVisit: nil,
            scheduledStartTime: scheduledTime?.nilIfBlank ?? pickupTime?.nilIfBlank,
            scheduledEndTime: nil,
            visitCategory: "site_visit",
            travelMode: "cab",
            vehiclePreference: vehicle?.vehicleNumber?.nilIfBlank,
            vehicleAssigned: true,
            creationTime: nil
        )
    }
}

private extension GeoTrackProposedSiteVisit {
    var hasMeaningfulFields: Bool {
        projectId?.nilIfBlank != nil
            || scheduledDate?.nilIfBlank != nil
            || scheduledTime?.nilIfBlank != nil
            || inchargeStaffId?.nilIfBlank != nil
            || hodStaffId?.nilIfBlank != nil
            || bdoStaffId?.nilIfBlank != nil
            || avpStaffId?.nilIfBlank != nil
            || gmStaffId?.nilIfBlank != nil
            || seniorManagerStaffId?.nilIfBlank != nil
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

private enum HomeScrollTarget {
    static let top = "home-top"
}

#Preview {
    HomeView()
        .environment(AuthStore())
}
