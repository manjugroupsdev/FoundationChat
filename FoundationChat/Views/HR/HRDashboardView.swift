import Combine
import SwiftUI

enum HRDashboardRoute: Hashable {
    case leaves
    case permissions
}

struct HRDashboardView: View {
    @Environment(AuthStore.self) private var authStore

    let openRoute: HRDashboardRoute?
    var onOpenRouteHandled: () -> Void

    @State private var path = NavigationPath()
    @State private var todayAttendance: ConvexTodayAttendance?
    @State private var historyRecords: [ConvexAttendanceRecord] = []
    @State private var isLoading = false
    @State private var nowTick = Date()
    @State private var showPunchIn = false
    @State private var showPunchOut = false
    @State private var showClockOutConfirm = false
    @State private var errorMessage: String?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(openRoute: HRDashboardRoute? = nil, onOpenRouteHandled: @escaping () -> Void = {}) {
        self.openRoute = openRoute
        self.onOpenRouteHandled = onOpenRouteHandled
    }

    private var hasPunchedIn: Bool {
        todayAttendance?.hasPunchedIn == true || firstPunchIn(for: todayHistoryRecord) != nil
    }

    private var isOpen: Bool {
        if todayAttendance?.isOpen == true {
            return true
        }
        return firstPunchIn(for: todayHistoryRecord) != nil && lastPunchOut(for: todayHistoryRecord) == nil
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

                VStack(spacing: 0) {
                    fixedAttendanceHeader
                        .zIndex(1)

                    HRDashboardLoadingStrip(isLoading: isLoading)

                    ScrollView {
                        VStack(spacing: 14) {
                            dashboardErrorBanner
                            attendanceHistoryCards
                        }
                        .padding(.bottom, 120)
                    }
                    .refreshable {
                        await reloadAll()
                    }
                }

                attendanceTopFill
                    .zIndex(2)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HRDashboardRoute.self) { route in
                switch route {
                case .leaves:
                    LeavesListView()
                case .permissions:
                    ConvexPermissionListView()
                }
            }
            .task { await reloadAll() }
            .task(id: openRoute) {
                guard let openRoute else { return }
                path = NavigationPath()
                path.append(openRoute)
                onOpenRouteHandled()
            }
            .onReceive(timer) { nowTick = $0 }
            .sheet(isPresented: $showPunchIn) {
                PunchFlowView(mode: .punchIn) { Task { await reloadAll() } }
            }
            .sheet(isPresented: $showPunchOut) {
                PunchFlowView(mode: .punchOut) { Task { await reloadAll() } }
            }
            .sheet(isPresented: $showClockOutConfirm) {
                ClockOutConfirmSheet {
                    showClockOutConfirm = false
                    showPunchOut = true
                } onCancel: {
                    showClockOutConfirm = false
                }
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.hidden)
            }
        }
    }

    private var fixedAttendanceHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                headerBackground
                androidHeader
            }

            workingHourCard
                .padding(.top, -89)
        }
    }

    private var attendanceTopFill: some View {
        Color(hex: 0x0B61CA)
            .frame(height: 74)
            .frame(maxWidth: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
    }

    private var headerBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.043, green: 0.38, blue: 0.792), Color(red: 0.008, green: 0.286, blue: 0.616)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 250)
        .clipShape(
            .rect(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0
            )
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
        .frame(height: 233, alignment: .top)
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

    @ViewBuilder
    private var actionButtons: some View {
        if hasPunchedIn {
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
        } else {
            Button {
                showPunchIn = true
            } label: {
                Text("Clock In Now")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(androidGreen)
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
                    Text(formatAndroidTimeRange(in: firstPunchIn(for: record), out: lastPunchOut(for: record)))
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
        if hasPunchedIn { return "Tap Clock Out again to update — final time locks at midnight" }
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

    private var todayHistoryRecord: ConvexAttendanceRecord? {
        historyRecords.first { $0.date == todayDateKey }
    }

    private var firstPunchInDate: Date? {
        if let raw = firstPunchIn(for: todayHistoryRecord), let date = parseAttendanceDate(raw) { return date }
        return parseAttendanceDate(todayAttendance?.punchInTime)
    }

    private var lastPunchOutDate: Date? {
        if let raw = lastPunchOut(for: todayHistoryRecord), let date = parseAttendanceDate(raw) { return date }
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

    private func lastPunchOut(for record: ConvexAttendanceRecord?) -> String? {
        record?.lastPunchOut ?? record?.sessions?.last?.punchOutTime
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
            group.addTask { await self.loadMonthHistory() }
        }
    }

    @MainActor
    private func loadToday() async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            todayAttendance = try await HRConvexAPIService.getTodayAttendance(token: token)
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMonthHistory() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }

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
            historyRecords = records.sorted { ($0.date ?? "") > ($1.date ?? "") }
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as NSError).code == NSURLErrorCancelled
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

#Preview {
    HRDashboardView()
        .environment(AuthStore())
}
