import Combine
import CoreLocation
import SwiftUI

/// Home tab cloned from Android `HomeFragment`, adapted to SwiftUI.
///
/// Scope note: this view owns the Home surface only.
struct HomeView: View {
    @Environment(AuthStore.self) private var authStore
    @Binding private var hasPlayedEntryAnimation: Bool

    @State private var todayVisits: [GeoTrackTodayVisit] = []
    @State private var assignedPlaces: [GeoTrackAssignedPlace] = []
    @State private var todayAttendance: ConvexTodayAttendance?
    @State private var monthAttendanceRecords: [ConvexAttendanceRecord] = []
    @State private var hasOpenSession = false
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
    @State private var showScrollToTop = false

    private let geoAPI = GeoTrackAPIService.shared
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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

                VStack(spacing: 0) {
                    blueHeader
                        .zIndex(1)

                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            Color.clear
                                .frame(height: 0)
                                .id(HomeScrollTarget.top)

                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: HomeScrollOffsetPreferenceKey.self,
                                        value: geometry.frame(in: .named(HomeScrollTarget.space)).minY
                                    )
                            }
                            .frame(height: 0)

                            contentArea
                                .padding(.bottom, 28)
                        }
                        .coordinateSpace(name: HomeScrollTarget.space)
                        .scrollIndicators(.hidden)
                        .refreshable { await reload() }
                        .onPreferenceChange(HomeScrollOffsetPreferenceKey.self) { offset in
                            let shouldShow = offset < -520
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
            .fullScreenCover(isPresented: $showQRScanner) {
                NavigationStack {
                    FrontDeskQRScannerView()
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
            .onReceive(timer) { _ in
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 60)
                    .opacity(headerEntryStarted ? 1 : 0)
                    .offset(x: headerEntryStarted ? 0 : -30)
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38).delay(0.12), value: headerEntryStarted)

                Text("Track your tasks, visits and\nattendance in one place.")
                    .font(.system(size: 11.5, weight: .medium))
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
                            .font(.system(size: 10, weight: .semibold))

                        Image(systemName: "chevron.right.3")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(HomePalette.headerBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.96), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .opacity(headerEntryStarted ? 1 : 0)
                .offset(x: headerEntryStarted ? 0 : -30)
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38).delay(0.30), value: headerEntryStarted)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)

            homeHeaderActions
                .padding(.top, 16)
                .padding(.trailing, 12)
                .opacity(headerEntryStarted ? 1 : 0)
                .offset(y: headerEntryStarted ? 0 : -16)
                .animation(.easeOut(duration: 0.36), value: headerEntryStarted)

            bannerIllustration
                .padding(.top, 60)
                .padding(.trailing, 16)
        }
        .frame(height: 222)
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

    private var bannerIllustration: some View {
        ZStack {
            bannerImage(
                name: "HomeBannerGlitter",
                size: CGSize(width: 120, height: 60),
                alignment: .top,
                entryDelay: 0.16,
                floatOffset: 4,
                floatDelay: 1.0
            )

            bannerImage(
                name: "HomeBannerMobile",
                size: CGSize(width: 96, height: 125),
                alignment: .center,
                entryDelay: 0.20,
                floatOffset: -6,
                floatDelay: 0.75
            )

            bannerImage(
                name: "HomeBannerProgress",
                size: CGSize(width: 66, height: 42),
                alignment: .bottomLeading,
                entryDelay: 0.28,
                floatOffset: 5,
                floatDelay: 0.50
            )
            .padding(.bottom, 24)

            bannerImage(
                name: "HomeBannerSuitcase",
                size: CGSize(width: 66, height: 68),
                alignment: .bottomTrailing,
                entryDelay: 0.36,
                floatOffset: -5,
                floatDelay: 1.50
            )
            .padding(.bottom, 16)
        }
        .frame(width: 150, height: 160)
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
                        .foregroundStyle(Color(hex: 0x94A3B8))
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
            .padding(.top, 20)

            if isDriverMode && !allTripVisits.isEmpty {
                tripFilterRow
            }

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
        return state != .clockInFirst
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
            group.addTask { await self.loadAttendanceSummary() }
            group.addTask { await self.loadUnread() }
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
            return
        }
        hasOpenSession = await AttendanceTrackingGate.hasOpenSessionForToday(token: token)
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
            todayAttendance = try await today
            monthAttendanceRecords = try await month
        } catch {
            todayAttendance = nil
            monthAttendanceRecords = []
        }
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

    private var userSubtitle: String {
        let user = authStore.currentSession?.user
        return [user?.designation?.nilIfBlank, user?.department?.nilIfBlank, user?.role?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfBlank ?? "Ready for today's work"
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

private struct HomeTripCard: View {
    let title: String
    let time: String
    let distance: String
    let state: HomeTripState
    let etaText: String
    let canOpen: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard canOpen else { return }
            action()
        } label: {
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
    static let space = "home-scroll-space"
}

private struct HomeScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    HomeView()
        .environment(AuthStore())
}
