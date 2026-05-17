import Combine
import SwiftUI

struct HRDashboardView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var todayAttendance: ConvexTodayAttendance?
    @State private var historyRecords: [ConvexAttendanceRecord] = []
    @State private var isLoading = false
    @State private var nowTick = Date()
    @State private var showPunchIn = false
    @State private var showPunchOut = false
    @State private var errorMessage: String?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var hasPunchedIn: Bool {
        todayAttendance?.hasPunchedIn == true || firstPunchIn(for: todayHistoryRecord) != nil
    }

    private var isOpen: Bool {
        if todayAttendance?.isOpen == true {
            return true
        }
        return firstPunchIn(for: todayHistoryRecord) != nil && lastPunchOut(for: todayHistoryRecord) == nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(red: 0.945, green: 0.953, blue: 0.973)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            headerBackground
                            androidHeader
                        }

                        VStack(spacing: 12) {
                            attendanceRefreshIndicator

                            workingHourCard

                            attendanceHistoryCards
                        }
                        .padding(.top, -89)
                        .padding(.bottom, 120)
                    }
                }

                attendanceTopFill
                    .zIndex(2)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await reloadAll() }
            .onReceive(timer) { nowTick = $0 }
            .sheet(isPresented: $showPunchIn) {
                PunchFlowView(mode: .punchIn) { Task { await reloadAll() } }
            }
            .sheet(isPresented: $showPunchOut) {
                PunchFlowView(mode: .punchOut) { Task { await reloadAll() } }
            }
        }
    }

    @ViewBuilder
    private var attendanceRefreshIndicator: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
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
        if isOpen {
            HStack(spacing: 12) {
                Button {
                    showPunchOut = true
                } label: {
                    Text("Take A Break")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.412, green: 0.22, blue: 0.937))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 0.412, green: 0.22, blue: 0.937), lineWidth: 1.4)
                        )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: showPunchOut)

                Button {
                    showPunchOut = true
                } label: {
                    Text("Clock Out")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(androidGreen, in: Capsule())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: showPunchOut)
            }
        } else {
            Button {
                showPunchIn = true
            } label: {
                Text("Clock In Now")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(androidGreen, in: Capsule())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact, trigger: showPunchIn)
        }
    }

    private var attendanceHistoryCards: some View {
        VStack(spacing: 12) {
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
        return "Let's Clock-In!"
    }

    private var heroSubtitle: String {
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
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    HRDashboardView()
        .environment(AuthStore())
}
