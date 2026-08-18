import Combine
import CoreLocation
import SwiftUI

enum HRDashboardRoute: Hashable {
    case leaves
    case leaveApprovals
    case permissions
    case permissionApprovals
}

struct HRDashboardView: View {
    @Environment(AuthStore.self) private var authStore

    let isActive: Bool
    let openRoute: HRDashboardRoute?
    var onOpenRouteHandled: () -> Void

    @State private var path = NavigationPath()
    @State private var todayAttendance: ConvexTodayAttendance?
    @State private var todayDaySessions: ConvexDaySessionsResponse?
    @State private var todayShift: HRConvexAPIService.TodayShiftResponse?
    @State private var historyRecords: [ConvexAttendanceRecord] = []
    @State private var isLoading = false
    @State private var nowTick = Date()
    @State private var showPunchIn = false
    @State private var showPunchOut = false
    @State private var showClockOutConfirm = false
    @State private var errorMessage: String?
    @State private var homeFence: ConvexHomeFence?
    @State private var showHomeFenceWarning = false
    @State private var isCheckingHomeFence = false
    @State private var showOnDutySheet = false
    @State private var isOnDutyBusy = false
    @AppStorage("attendance.onDuty.active") private var isOnDuty = false
    @AppStorage("attendance.onDuty.tripId") private var onDutyTripId = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let externalPunchRefreshTimer = Timer.publish(every: 45, on: .main, in: .common).autoconnect()
    private let attendancePanelTopOffset: CGFloat = 116

    init(
        isActive: Bool = true,
        openRoute: HRDashboardRoute? = nil,
        onOpenRouteHandled: @escaping () -> Void = {}
    ) {
        self.isActive = isActive
        self.openRoute = openRoute
        self.onOpenRouteHandled = onOpenRouteHandled
    }

    private var hasPunchedIn: Bool {
        AttendanceTrackingGate.isClockedInForToday(
            firstPunchIn: todayFirstPunchIn,
            hasOpenSession: todayAttendance?.hasOpenSession == true
                || todayDaySessions?.hasOpenSession == true
        )
    }

    private var isOpen: Bool {
        hasPunchedIn && !AttendanceTrackingGate.isClockedOutOnMobile(
            daySessions: todayDaySessions?.sessions,
            attendanceSessions: todayAttendance?.sessions
        )
    }

    private var isClockedOut: Bool {
        hasPunchedIn && !isOpen
    }

    private var availableShortcuts: [HRDashboardShortcut] {
        HRDashboardShortcut.allCases.filter { shortcut in
            shortcut.permissionGroups.contains { group in
                group.isEmpty || group.contains { authStore.hasPermission($0) }
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Color(red: 0.945, green: 0.953, blue: 0.973)
                    .ignoresSafeArea()

                fixedAttendanceHeader
                    .zIndex(0)

                ScrollView {
                    VStack(spacing: 14) {
                        workingHourCard
                        HRDashboardLoadingStrip(isLoading: isLoading)
                        dashboardErrorBanner
                        attendanceHistoryCards
                    }
                    .padding(.top, attendancePanelTopOffset)
                    .padding(.bottom, 120)
                    .background(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: attendancePanelTopOffset)
                            Color.white
                                .clipShape(.rect(topLeadingRadius: 30, topTrailingRadius: 30))
                                .frame(height: 176)
                            Color(red: 0.945, green: 0.953, blue: 0.973)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await reloadAll()
                }
                .zIndex(1)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HRDashboardRoute.self) { route in
                Group {
                    switch route {
                    case .leaves:
                        LeavesListView()
                    case .leaveApprovals:
                        LeaveApprovalsView()
                    case .permissions:
                        ConvexPermissionListView()
                    case .permissionApprovals:
                        PermissionApprovalsView()
                    }
                }
                .toolbar(.hidden, for: .tabBar)
            }
            .task(id: isActive) {
                guard isActive else { return }
                await reloadAll()
            }
            .task(id: openRoute) {
                guard let openRoute else { return }
                path = NavigationPath()
                path.append(openRoute)
                onOpenRouteHandled()
            }
            .onReceive(timer) { date in
                guard isActive else { return }
                nowTick = date
            }
            .onReceive(externalPunchRefreshTimer) { _ in
                guard isActive else { return }
                Task { await refreshAttendanceForExternalPunches() }
            }
            .sheet(isPresented: $showPunchIn) {
                PunchFlowView(mode: .punchIn) { Task { await reloadAll() } }
            }
            .sheet(isPresented: $showPunchOut) {
                PunchFlowView(mode: .punchOut) {
                    isOnDuty = false
                    onDutyTripId = ""
                    Task { await reloadAll() }
                }
            }
            .sheet(isPresented: $showOnDutySheet) {
                NavigationStack {
                    OnDutyStartSheet { request in
                        await startOnDuty(request)
                    }
                }
                .appFormActivity()
                .appLibraryNativeSheet([.fraction(0.72), .large])
                .presentationBackground(Color(hex: 0xF8FAFC))
            }
            .sheet(isPresented: $showClockOutConfirm) {
                ClockOutConfirmSheet(
                    todayMinutes: max(0, Int(todayTotalSeconds / 60)),
                    overtimeMinutes: max(0, Int(todayTotalSeconds / 60) - 480)
                ) {
                    showClockOutConfirm = false
                    showPunchOut = true
                } onCancel: {
                    showClockOutConfirm = false
                }
                .appLibraryNativeSheet([.height(430)])
            }
            .alert("You are at Home!", isPresented: $showHomeFenceWarning) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text("Please move outside your configured home radius before clocking in.")
            }
        }
    }

    private var fixedAttendanceHeader: some View {
        ZStack(alignment: .top) {
            headerBackground
            androidHeader
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private var headerBackground: some View {
        attendanceHeaderGradient
        .frame(height: 220)
    }

    private var attendanceHeaderGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var androidHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(heroTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(heroSubtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.851, green: 0.839, blue: 0.996))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image("AttendanceHeaderIllustration")
                .resizable()
                .scaledToFit()
                .frame(width: 91, height: 76)
                .padding(.top, -18)
        }
        .padding(.horizontal, 28)
        .padding(.top, 71)
        .frame(height: 205, alignment: .top)
        .animation(.snappy(duration: 0.25), value: isOpen)
        .animation(.snappy(duration: 0.25), value: hasPunchedIn)
    }

    private var workingHourCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Working Hour")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.063, green: 0.094, blue: 0.157))
                Text(androidPayPeriodLabel)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.404))
            }

            HStack(spacing: 8) {
                statTile(title: "Today", value: todayDisplayForCard)
                statTile(title: "This Pay Period", value: payPeriodHHMM)
            }
            .padding(.top, 8)

            shiftScheduleRow
                .padding(.top, 10)

            actionButtons
                .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white
                .clipShape(
                    .rect(
                        topLeadingRadius: 30,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 30
                    )
                )
        )
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.404))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.system(size: 22, weight: .regular, design: .default).monospacedDigit())
                .foregroundStyle(Color(red: 0.086, green: 0.106, blue: 0.137))
                .lineLimit(1)
                .minimumScaleFactor(0.52)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 72, alignment: .center)
        .padding(.horizontal, 12)
        .background(Color(red: 0.976, green: 0.976, blue: 0.976), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(red: 0.922, green: 0.925, blue: 0.933), lineWidth: 1)
        )
    }

    private var shiftScheduleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 34, height: 34)
                .background(Color(hex: 0xEAF3FF), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Shift")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                Text(todayShiftLabel)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 8)
            if let name = todayShift?.shift?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 42)
        .padding(.horizontal, 10)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: 0xE4E7EC), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isOpen {
            HStack(spacing: 10) {
                Button {
                    if isOnDuty {
                        Task { await completeOnDuty() }
                    } else {
                        showOnDutySheet = true
                    }
                } label: {
                    Text(isOnDuty ? "Complete On Duty" : "On Duty")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(isOnDuty ? Color(hex: 0x0B61CA) : androidGreen)
                .disabled(isOnDutyBusy)

                Button {
                    showClockOutConfirm = true
                } label: {
                    Text("Clock Out")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(androidGreen)
                .sensoryFeedback(.impact, trigger: showPunchOut)
            }
        } else if isClockedOut {
            Text("Clocked Out")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0xA4E999), Color(hex: 0x9BDB8C)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .accessibilityLabel("Clocked out")
        } else {
            Button {
                Task { await openClockInRespectingHomeFence() }
            } label: {
                Text(isCheckingHomeFence ? "Checking..." : "Clock In Now")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(androidGreen)
            .disabled(isCheckingHomeFence)
            .sensoryFeedback(.impact, trigger: showPunchIn)
        }
    }

    private var attendanceHistoryCards: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Attendance History")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.063, green: 0.094, blue: 0.157))
                Spacer()
                NavigationLink {
                    ConvexAttendanceListView()
                } label: {
                    Text("View All")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                }
            }
            .padding(.horizontal, 16)

            if historyRecords.isEmpty && !isLoading {
                VStack {
                    ContentUnavailableView(
                        "No Records",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Your attendance entries will appear here.")
                    )
                    .padding(.vertical, 24)
                }
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
            } else {
                ForEach(historyRecords) { record in
                    androidHistoryCard(for: record)
                }
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var dashboardErrorBanner: some View {
        if let errorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: 0xB42318))
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x7A271A))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    self.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0x7A271A))
            }
            .padding(12)
            .background(Color(hex: 0xFEF3F2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xFECDCA), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var hrShortcutsSection: some View {
        let shortcuts = availableShortcuts
        if !shortcuts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("HR Shortcuts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.063, green: 0.094, blue: 0.157))
                    .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(shortcuts) { shortcut in
                        NavigationLink {
                            shortcut.destination.view
                        } label: {
                            HRShortcutCard(shortcut: shortcut)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, errorMessage == nil ? 12 : 0)
        }
    }

    private func androidHistoryCard(for record: ConvexAttendanceRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.412, green: 0.22, blue: 0.937))
                Text(formatAndroidHistoryDate(record.date))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.063, green: 0.094, blue: 0.157))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total Hours")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.404))
                    Text(historyTotalHMS(for: record))
                        .font(.system(size: 16, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color(red: 0.204, green: 0.251, blue: 0.329))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Clock in & Out")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.404))
                    Text(formatAndroidTimeRange(in: firstPunchIn(for: record), out: resolvedPunchOut(for: record)))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(red: 0.204, green: 0.251, blue: 0.329))
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color(red: 0.976, green: 0.976, blue: 0.976), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.922, green: 0.925, blue: 0.933), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var heroTitle: String {
        if isOpen { return "You're Clocked In" }
        if hasPunchedIn { return "Clocked Out" }
        return "Let's Clock-In!"
    }

    private var heroSubtitle: String {
        if isOpen { return "Have a productive day ahead" }
        if isClockedOut { return "Attendance completed for today" }
        return "Don't miss your clock in schedule"
    }

    private var heroSymbol: String {
        if isOpen { return "clock.badge.checkmark.fill" }
        if hasPunchedIn { return "checkmark.seal.fill" }
        return "calendar.badge.clock"
    }

    private var heroGradient: LinearGradient {
        if isOpen {
            return LinearGradient(colors: [Color(red: 0.13, green: 0.63, blue: 0.25), Color(red: 0.08, green: 0.48, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if hasPunchedIn {
            return LinearGradient(colors: [Color(red: 0.45, green: 0.33, blue: 0.95), Color(red: 0.06, green: 0.42, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Color(red: 0.02, green: 0.38, blue: 0.78), Color(red: 0.03, green: 0.46, blue: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroShadowColor: Color {
        isOpen ? .green : .blue
    }

    private var actionColor: Color {
        isOpen ? .red : Color(red: 0.12, green: 0.74, blue: 0.02)
    }

    private var androidGreen: Color {
        Color(red: 0.106, green: 0.765, blue: 0.008)
    }

    private var todayDateKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var todayShiftLabel: String {
        guard todayShift?.isWeekoff != true else { return "Week off" }
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard let day = todayShift?.shift?.schedule?.day(for: weekday), day.isWorkDay != false else {
            return "--:-- - --:--"
        }
        return "\(formatShiftTime(day.startTime)) - \(formatShiftTime(day.endTime))"
    }

    private func formatShiftTime(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "--:--" }
        let pieces = raw.uppercased().split(whereSeparator: \Character.isWhitespace)
        let clock = pieces.first?.split(separator: ":") ?? []
        guard clock.count >= 2, var hour = Int(clock[0]), let minute = Int(clock[1]),
              (0...59).contains(minute) else { return raw }
        if pieces.count > 1 {
            if pieces[1] == "PM", hour < 12 { hour += 12 }
            if pieces[1] == "AM", hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour) else { return raw }
        return String(format: "%02d:%02d", hour, minute)
    }

    private var todayHistoryRecord: ConvexAttendanceRecord? {
        historyRecords.first { $0.date == todayDateKey }
    }

    private var todayFirstPunchIn: String? {
        nonBlank(todayDaySessions?.firstPunchIn)
            ?? nonBlank(todayAttendance?.firstPunchIn)
            ?? nonBlank(todayAttendance?.punchInTime)
            ?? todayDaySessions?.sessions?.compactMap { nonBlank($0.punchInTime) }.first
            ?? todayAttendance?.sessions?.compactMap { nonBlank($0.punchInTime) }.first
            ?? nonBlank(firstPunchIn(for: todayHistoryRecord))
    }

    private var firstPunchInDate: Date? {
        parseAttendanceDate(todayFirstPunchIn)
    }

    private var lastPunchOutDate: Date? {
        if let raw = resolvedPunchOut(for: todayHistoryRecord), let date = parseAttendanceDate(raw) { return date }
        return parseAttendanceDate(todayAttendance?.punchOutTime)
    }

    private var todayTotalSeconds: TimeInterval {
        if isOpen, let firstIn = firstPunchInDate {
            return max(0, nowTick.timeIntervalSince(firstIn))
        }
        let mins = todayHistoryRecord?.totalMinutes
            ?? todayAttendance?.cumulativeMinutes
            ?? todayAttendance?.totalMinutes
            ?? 0
        return TimeInterval(mins * 60)
    }

    private var todayDisplayForCard: String {
        formatHrs(seconds: Int(todayTotalSeconds))
    }

    private var todayHistoryDisplay: String {
        formatHM(seconds: Int(todayTotalSeconds))
    }

    private var payPeriodMinutes: Int {
        historyRecords.reduce(0) { $0 + ($1.totalMinutes ?? $1.cumulativeMinutes ?? 0) }
    }

    private var payPeriodHHMM: String {
        formatHrs(seconds: payPeriodMinutes * 60)
    }

    private var payPeriodLabel: String {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        let first = calendar.date(from: comps) ?? now
        let last = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first) ?? now
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return "Paid Period \(f.string(from: first)) - \(f.string(from: last))"
    }

    private var androidPayPeriodLabel: String {
        payPeriodLabel.replacingOccurrences(of: "Paid Period", with: "Period")
    }

    private func historyTotal(for record: ConvexAttendanceRecord) -> String {
        if Calendar.current.isDateInToday(parseDateOnly(record.date) ?? .distantPast), isOpen {
            return todayHistoryDisplay
        }
        let mins = record.totalMinutes ?? record.cumulativeMinutes ?? 0
        if mins <= 0 { return "--" }
        return formatHM(seconds: mins * 60)
    }

    private func historyTotalHMS(for record: ConvexAttendanceRecord) -> String {
        let mins = record.totalMinutes ?? record.cumulativeMinutes ?? 0
        let seconds = mins * 60
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d hrs", h, m, s)
    }

    private func firstPunchIn(for record: ConvexAttendanceRecord?) -> String? {
        record?.firstPunchIn ?? record?.sessions?.first?.punchInTime
    }

    private func resolvedPunchOut(for record: ConvexAttendanceRecord?) -> String? {
        guard let record else { return nil }
        if record.date == todayDateKey, isOpen { return nil }
        guard record.hasOpenSession != true else { return nil }
        let firstIn = firstPunchIn(for: record)
        let candidate = record.lastPunchOut ?? record.sessions?.last?.punchOutTime
        guard let candidate, candidate != firstIn else { return nil }
        return candidate
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func formatHM(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return String(format: "%dh %02dm", h, m)
    }

    private func formatHrs(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return String(format: "%02d:%02d Hrs", h, m)
    }

    private func formatHistoryDate(_ raw: String?) -> String {
        guard let raw else { return "--" }
        if let date = parseDateOnly(raw) {
            if Calendar.current.isDateInToday(date) { return "Today" }
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            let outFormatter = DateFormatter()
            outFormatter.dateFormat = "EEEE, d MMM"
            return outFormatter.string(from: date)
        }
        return raw
    }

    private func formatAndroidHistoryDate(_ raw: String?) -> String {
        guard let raw else { return "--" }
        if let date = parseDateOnly(raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMMM yyyy"
            return formatter.string(from: date)
        }
        return raw
    }

    private func parseDateOnly(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd"
        return inFormatter.date(from: raw)
    }

    private func formatTimeRange(in punchIn: String?, out punchOut: String?) -> String {
        let i = formatClockTime(punchIn) ?? "--"
        let o = formatClockTime(punchOut) ?? (isOpen ? "in progress" : "--")
        return "\(i) -> \(o)"
    }

    private func formatAndroidTimeRange(in punchIn: String?, out punchOut: String?) -> String {
        let i = formatClockTimeLowercase(punchIn) ?? "--"
        let o = formatClockTimeLowercase(punchOut) ?? (isOpen ? "in progress" : "--")
        return "\(i) - \(o)"
    }

    @MainActor
    private func openClockInRespectingHomeFence() async {
        isCheckingHomeFence = true
        defer { isCheckingHomeFence = false }

        if homeFence == nil {
            await loadHomeFence()
        }

        guard let fence = homeFence,
              fence.enabled,
              let lat = fence.lat,
              let lng = fence.lng
        else {
            showPunchIn = true
            return
        }

        do {
            let location = try await OneShotLocationReader.requestLocation()
            let distance = Self.haversineMeters(
                from: location.coordinate,
                to: CLLocationCoordinate2D(latitude: lat, longitude: lng)
            )
            if distance <= Double(fence.radiusMeters) {
                showHomeFenceWarning = true
            } else {
                showPunchIn = true
            }
        } catch {
            // Match Android's fail-open behavior when the policy cannot be
            // enforced locally; the server still remains the final guard.
            showPunchIn = true
        }
    }

    @MainActor
    private func loadHomeFence() async {
        guard let token = authStore.currentSession?.token else { return }
        homeFence = try? await HRConvexAPIService.getHomeFence(token: token)
    }

    @MainActor
    private func startOnDuty(_ request: OnDutyStartRequest) async {
        guard let token = authStore.currentSession?.token else { return }
        isOnDutyBusy = true
        defer { isOnDutyBusy = false }
        do {
            let location = try? await OneShotLocationReader.requestLocation()
            let tripId = try await HRConvexAPIService.startOnDutyTrip(
                token: token,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude,
                address: nil,
                category: request.category,
                targetId: request.targetId,
                targetName: request.targetName,
                targetAddress: request.targetAddress,
                vehicleOwnership: request.vehicleOwnership,
                vehicleType: request.vehicleType
            )
            onDutyTripId = tripId
            isOnDuty = true
            showOnDutySheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func completeOnDuty() async {
        guard let token = authStore.currentSession?.token else { return }
        isOnDutyBusy = true
        defer { isOnDutyBusy = false }
        do {
            let location = try? await OneShotLocationReader.requestLocation()
            try await HRConvexAPIService.completeOnDutyTrip(
                token: token,
                tripId: onDutyTripId.nilIfBlank,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude
            )
            onDutyTripId = ""
            isOnDuty = false
        } catch {
            // Android clears local state even if the network call fails so the
            // user does not get stuck on a stale On Duty pill.
            onDutyTripId = ""
            isOnDuty = false
            errorMessage = error.localizedDescription
        }
    }

    private func formatClockTime(_ raw: String?) -> String? {
        guard let raw, let date = parseAttendanceDate(raw) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func formatClockTimeLowercase(_ raw: String?) -> String? {
        guard let raw, let date = parseAttendanceDate(raw) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f.string(from: date).lowercased()
    }

    private func parseAttendanceDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let manual = DateFormatter()
        manual.locale = Locale(identifier: "en_US_POSIX")
        manual.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        if let date = manual.date(from: raw) { return date }
        manual.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
        if let date = manual.date(from: raw) { return date }
        return nil
    }

    @MainActor
    private func reloadAll() async {
        await authStore.refreshIAMPermissions()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadToday() }
            group.addTask { await self.loadTodayShift() }
            group.addTask { await self.loadMonthHistory() }
            group.addTask { await self.loadHomeFence() }
        }
    }

    @MainActor
    private func loadTodayShift() async {
        guard let session = authStore.currentSession else { return }
        let staffId = session.user.staffId ?? session.user._id
        todayShift = try? await HRConvexAPIService.getTodayShift(
            token: session.token,
            staffId: staffId,
            date: todayDateKey
        )
    }

    @MainActor
    private func refreshAttendanceForExternalPunches() async {
        guard authStore.currentSession?.token != nil else { return }
        let wasOpen = isOpen
        let wasClockedOut = isClockedOut
        await loadToday()

        if wasOpen != isOpen || wasClockedOut != isClockedOut || isOpen {
            await loadMonthHistory(showLoader: false)
        }
    }

    @MainActor
    private func loadToday() async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            async let attendanceRequest = HRConvexAPIService.getTodayAttendance(token: token)
            async let sessionsRequest = try? HRConvexAPIService.getDaySessions(
                token: token,
                date: todayDateKey
            )

            todayDaySessions = await sessionsRequest
            todayAttendance = try await attendanceRequest
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMonthHistory(showLoader: Bool = true) async {
        guard let token = authStore.currentSession?.token else { return }
        if showLoader { isLoading = true }
        defer { if showLoader { isLoading = false } }

        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        let firstOfMonth = calendar.date(from: comps) ?? now
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        do {
            let records = try await HRConvexAPIService.getMyAttendance(
                token: token,
                fromDate: formatter.string(from: firstOfMonth),
                toDate: formatter.string(from: now)
            )
            historyRecords = fillMonthGaps(records, from: firstOfMonth, to: now)
                .sorted { ($0.date ?? "") > ($1.date ?? "") }
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func fillMonthGaps(_ records: [ConvexAttendanceRecord], from start: Date, to end: Date) -> [ConvexAttendanceRecord] {
        let calendar = Calendar.current
        let keyed = Dictionary(uniqueKeysWithValues: records.compactMap { record -> (String, ConvexAttendanceRecord)? in
            guard let date = record.date else { return nil }
            return (date, record)
        })
        var output: [ConvexAttendanceRecord] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            let key = Self.dateKeyFormatter.string(from: day)
            output.append(keyed[key] ?? ConvexAttendanceRecord.placeholder(date: key))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return output
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as NSError).code == NSURLErrorCancelled
    }

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func haversineMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let radius = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return radius * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}

@MainActor
final class OneShotLocationReader: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    static func requestLocation() async throws -> CLLocation {
        let reader = OneShotLocationReader()
        return try await reader.location()
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private func location() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            default:
                continuation.resume(throwing: CLError(.denied))
                self.continuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                continuation?.resume(throwing: CLError(.denied))
                continuation = nil
            default:
                break
            }
        }
    }
}

private struct HRDashboardShortcut: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let destination: HRDashboardShortcutDestination
    let permissionGroups: [[String]]

    static let allCases: [HRDashboardShortcut] = [
        .init(
            id: "attendance",
            title: "Attendance",
            subtitle: "History",
            icon: "calendar.badge.clock",
            tint: Color(hex: 0x0B61CA),
            destination: .attendance,
            permissionGroups: [["attendance.view", "attendance.viewAll"]]
        ),
        .init(
            id: "attendanceReview",
            title: "Review",
            subtitle: "Attendance",
            icon: "checklist.checked",
            tint: Color(hex: 0x079455),
            destination: .attendanceReview,
            permissionGroups: [["attendance.approve", "attendance.viewAll"]]
        ),
        .init(
            id: "leave",
            title: "Leave",
            subtitle: "Requests",
            icon: "calendar.badge.plus",
            tint: Color(hex: 0x6941C6),
            destination: .leave,
            permissionGroups: [["leaves.view", "leaves.viewAll", "leaves.approve"]]
        ),
        .init(
            id: "leaveReview",
            title: "Leave Review",
            subtitle: "Approvals",
            icon: "checklist.checked",
            tint: Color(hex: 0x067647),
            destination: .leaveReview,
            permissionGroups: [["leaves.approve", "leaves.viewAll"]]
        ),
        .init(
            id: "permissions",
            title: "Permissions",
            subtitle: "Time off",
            icon: "clock.badge.questionmark",
            tint: Color(hex: 0xDC6803),
            destination: .permissions,
            permissionGroups: [["permissions.view", "permissions.viewAll", "permissions.approve"]]
        ),
        .init(
            id: "permissionReview",
            title: "Permission Review",
            subtitle: "Approvals",
            icon: "checklist.checked",
            tint: Color(hex: 0xB54708),
            destination: .permissionReview,
            permissionGroups: [["permissions.approve", "permissions.viewAll"]]
        ),
        .init(
            id: "loans",
            title: "Loans",
            subtitle: "HR finance",
            icon: "indianrupeesign.circle",
            tint: Color(hex: 0x039855),
            destination: .loans,
            permissionGroups: [["loans.view", "loans.manage", "loans.approve"]]
        ),
        .init(
            id: "staff",
            title: "Staff",
            subtitle: "Directory",
            icon: "person.2.fill",
            tint: Color(hex: 0x1570EF),
            destination: .staff,
            permissionGroups: [["staff.view"]]
        ),
        .init(
            id: "geotrack",
            title: "GeoTrack Live",
            subtitle: "Tracking",
            icon: "location.viewfinder",
            tint: Color(hex: 0xC11574),
            destination: .geoTrackLive,
            permissionGroups: [["attendance.liveTracking"]]
        )
    ]
}

private enum HRDashboardShortcutDestination {
    case attendance
    case attendanceReview
    case leave
    case leaveReview
    case permissions
    case permissionReview
    case loans
    case staff
    case geoTrackLive

    @ViewBuilder
    var view: some View {
        Group {
            switch self {
            case .attendance:
                ConvexAttendanceListView()
            case .attendanceReview:
                AttendanceReviewView()
            case .leave:
                LeavesListView()
            case .leaveReview:
                LeaveApprovalsView()
            case .permissions:
                ConvexPermissionListView()
            case .permissionReview:
                PermissionApprovalsView()
            case .loans:
                LoansView()
            case .staff:
                StaffListView()
            case .geoTrackLive:
                GeoTrackLiveStatusView()
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct HRShortcutCard: View {
    let shortcut: HRDashboardShortcut

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: shortcut.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(shortcut.tint)
                .frame(width: 38, height: 38)
                .background(shortcut.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(shortcut.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.063, green: 0.094, blue: 0.157))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(shortcut.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.404))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 64)
        .background(Color(red: 0.976, green: 0.976, blue: 0.976), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.922, green: 0.925, blue: 0.933), lineWidth: 1)
        )
    }
}

private struct HRDashboardLoadingStrip: View {
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(red: 0.945, green: 0.953, blue: 0.973))

            if isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color(hex: 0x0B61CA))
                    .transition(.opacity)
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.18), value: isLoading)
    }
}

private struct OnDutyStartRequest {
    let category: String
    let targetId: String?
    let targetName: String
    let targetAddress: String?
    let vehicleOwnership: String
    let vehicleType: String
}

private struct OnDutyStartSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let onSubmit: (OnDutyStartRequest) async -> Void

    @State private var step: OnDutyStep = .category
    @State private var selectedCategory: OnDutyCategory?
    @State private var searchText = ""
    @State private var remarks = ""
    @State private var selectedTarget: OnDutyTarget?
    @State private var selectedVehicleOwnership: String?
    @State private var selectedVehicleType: String?
    @State private var projects: [ProjectSummary] = []
    @State private var vendors: [OnDutyVendor] = []
    @State private var isLoadingMasters = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var title: String {
        switch step {
        case .category:
            return "On Duty Details"
        case .target:
            switch selectedCategory {
            case .projects: return "Select Project"
            case .vendors: return "Select Vendor"
            case .others: return "Enter Remarks"
            case nil: return "On Duty Details"
            }
        case .vehicle:
            return "Select Vehicle"
        }
    }

    private var subtitle: String {
        switch step {
        case .category:
            return "Select a category to start on duty flow"
        case .target:
            switch selectedCategory {
            case .projects: return "Select a Project Which ever you want"
            case .vendors: return "Select a Vendor Which ever you want"
            case .others: return "Provide remarks for on-duty"
            case nil: return "Select a category to start on duty flow"
            }
        case .vehicle:
            return "Which Vehicle You are going to use"
        }
    }

    private var currentTargets: [OnDutyTarget] {
        switch selectedCategory {
        case .projects:
            return projects.map { OnDutyTarget(id: $0.id, name: $0.displayName, address: $0.location) }
        case .vendors:
            return vendors.map { OnDutyTarget(id: $0.id, name: $0.name, address: $0.address) }
        default:
            return []
        }
    }

    private var filteredTargets: [OnDutyTarget] {
        let clean = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return currentTargets }
        return currentTargets.filter { $0.name.localizedCaseInsensitiveContains(clean) }
    }

    private var canGoNext: Bool {
        switch selectedCategory {
        case .projects, .vendors:
            return selectedTarget != nil
        case .others:
            return remarks.nilIfBlank != nil
        case nil:
            return false
        }
    }

    private var canSubmit: Bool {
        selectedVehicleOwnership != nil && selectedVehicleType != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 10) {
                    switch step {
                    case .category:
                        categoryStep
                    case .target:
                        targetStep
                    case .vehicle:
                        vehicleStep
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 92)
            }

            bottomButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color(hex: 0xF8FAFC))
        }
        .background(Color(hex: 0xF8FAFC).ignoresSafeArea())
        .appCompactSheetCTAContainer()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    navigateBackOrDismiss()
                } label: {
                    if step == .category {
                        Text("Cancel")
                    } else {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
        .task { await loadMasterData() }
        .interactiveDismissDisabled(isSubmitting)
        .alert("On Duty", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func navigateBackOrDismiss() {
        switch step {
        case .category:
            dismiss()
        case .target:
            withAnimation(.easeOut(duration: 0.18)) {
                selectedCategory = nil
                selectedTarget = nil
                searchText = ""
                remarks = ""
                step = .category
            }
        case .vehicle:
            withAnimation(.easeOut(duration: 0.18)) {
                selectedVehicleOwnership = nil
                selectedVehicleType = nil
                step = .target
            }
        }
    }

    private var categoryStep: some View {
        VStack(spacing: 10) {
            ForEach(OnDutyCategory.allCases) { category in
                OnDutyCategoryCard(category: category) {
                    selectedCategory = category
                    selectedTarget = nil
                    searchText = ""
                    remarks = ""
                    withAnimation(.easeOut(duration: 0.18)) {
                        step = .target
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var targetStep: some View {
        if selectedCategory == .others {
            TextField("Enter remarks details...", text: $remarks, axis: .vertical)
                .lineLimit(4...6)
                .padding(12)
                .frame(minHeight: 80, alignment: .topLeading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        } else {
            VStack(spacing: 12) {
                NativeInlineSearchBar(
                    text: $searchText,
                    placeholder: selectedCategory == .vendors ? "Search Vendors" : "Search Projects"
                )
                .frame(height: 48)

                if isLoadingMasters && currentTargets.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if filteredTargets.isEmpty {
                    ContentUnavailableView(
                        selectedCategory == .vendors ? "No Vendors" : "No Projects",
                        systemImage: selectedCategory == .vendors ? "building.2" : "building",
                        description: Text("Pull to refresh attendance if the list looks outdated.")
                    )
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 12) {
                        ForEach(filteredTargets) { target in
                            OnDutyTargetRow(target: target, isSelected: selectedTarget?.id == target.id) {
                                selectedTarget = target
                            }
                        }
                    }
                }
            }
        }
    }

    private var vehicleStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            vehicleGroup(title: "Own Vehicle", ownership: "Own Vehicle")
                .padding(.bottom, 10)
            vehicleGroup(title: "Office Vehicle", ownership: "Office Vehicle")
        }
    }

    private func vehicleGroup(title: String, ownership: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x344054))
            HStack(spacing: 12) {
                vehicleCard(ownership: ownership, type: "2 Wheeler", title: "Two Wheeler", systemImage: "bicycle")
                vehicleCard(ownership: ownership, type: "4 Wheeler", title: "Four Wheeler", systemImage: "car.fill")
            }
        }
    }

    private func vehicleCard(ownership: String, type: String, title: String, systemImage: String) -> some View {
        let isSelected = selectedVehicleOwnership == ownership && selectedVehicleType == type
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedVehicleOwnership = ownership
                selectedVehicleType = type
            }
        } label: {
            ZStack {
                if isSelected {
                    Image(systemName: systemImage)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white.opacity(0.24))
                        .offset(x: -44)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Color(hex: 0x101828))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isSelected ? Color(hex: 0x0B61CA) : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0xE4E7EC), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var bottomButton: some View {
        Button {
            switch step {
            case .category:
                break
            case .target:
                withAnimation(.easeOut(duration: 0.18)) {
                    selectedVehicleOwnership = nil
                    selectedVehicleType = nil
                    step = .vehicle
                }
            case .vehicle:
                submit()
            }
        } label: {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                }
                Text(step == .vehicle ? "Start Now" : "Next")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint((step == .vehicle ? canSubmit : canGoNext) ? Color(hex: 0x0B61CA) : Color(hex: 0xD0D5DD))
        .disabled(isSubmitting || (step == .vehicle ? !canSubmit : !canGoNext))
        .opacity(step == .category ? 0 : 1)
        .allowsHitTesting(step != .category)
    }

    private func loadMasterData() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoadingMasters = true
        defer { isLoadingMasters = false }
        async let loadedProjects = ProjectConvexAPIService.getMyProjects(token: token)
        async let loadedVendors = HRConvexAPIService.getVendors(token: token)
        do {
            projects = try await loadedProjects
            vendors = try await loadedVendors
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        guard let selectedVehicleOwnership, let selectedVehicleType else { return }

        let request: OnDutyStartRequest
        switch selectedCategory {
        case .projects, .vendors:
            guard let selectedCategory, let selectedTarget else { return }
            request = OnDutyStartRequest(
                category: selectedCategory.apiValue,
                targetId: selectedTarget.id,
                targetName: selectedTarget.name,
                targetAddress: selectedTarget.address,
                vehicleOwnership: selectedVehicleOwnership,
                vehicleType: selectedVehicleType
            )
        case .others:
            guard let targetName = remarks.nilIfBlank else { return }
            request = OnDutyStartRequest(
                category: OnDutyCategory.others.apiValue,
                targetId: nil,
                targetName: targetName,
                targetAddress: nil,
                vehicleOwnership: selectedVehicleOwnership,
                vehicleType: selectedVehicleType
            )
        case nil:
            return
        }

        isSubmitting = true
        Task {
            await onSubmit(request)
            await MainActor.run {
                isSubmitting = false
            }
        }
    }

    private enum OnDutyStep {
        case category
        case target
        case vehicle
    }

    private enum OnDutyCategory: String, CaseIterable, Identifiable {
        case projects
        case vendors
        case others

        var id: String { rawValue }
        var apiValue: String {
            switch self {
            case .projects: return "Projects"
            case .vendors: return "Vendors"
            case .others: return "Others"
            }
        }
        var title: String {
            switch self {
            case .projects: return "Projects"
            case .vendors: return "Vendors"
            case .others: return "Others (Remarks)"
            }
        }
        var subtitle: String {
            switch self {
            case .projects: return "Duty on developer/construction projects"
            case .vendors: return "Duty on third-party vendor sites"
            case .others: return "Duty for general meetings or custom tasks"
            }
        }
        var icon: String {
            switch self {
            case .projects: return "building.2"
            case .vendors: return "building"
            case .others: return "square.and.pencil"
            }
        }
    }

    private struct OnDutyTarget: Identifiable, Hashable {
        let id: String
        let name: String
        let address: String?
    }

    private struct OnDutyCategoryCard: View {
        let category: OnDutyCategory
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: category.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x101828))
                        Text(category.subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color(hex: 0x667085))
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private struct OnDutyTargetRow: View {
        let target: OnDutyTarget
        let isSelected: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text(target.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0x98A2B3))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(minHeight: 56)
                .background(isSelected ? Color(hex: 0xEAF3FF) : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0xE4E7EC), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    HRDashboardView()
        .environment(AuthStore())
}
