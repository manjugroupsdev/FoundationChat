import Combine
import SwiftUI

/// HR tab. Page structure mirrors Android `HrDashboardFragment`:
/// 1) Today status + total elapsed (= now − first punch-in) + primary clock action
/// 2) Pay-period total
/// 3) Attendance history list (latest first)
///
/// Visual language is intentionally minimal and Settings-like to feel native.
struct HRDashboardView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var todayAttendance: ConvexTodayAttendance?
    @State private var historyRecords: [ConvexAttendanceRecord] = []
    @State private var isLoading: Bool = false
    @State private var nowTick = Date()
    @State private var showPunchIn = false
    @State private var showPunchOut = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var hasPunchedIn: Bool { todayAttendance?.hasPunchedIn == true }
    private var isOpen: Bool { todayAttendance?.isOpen == true }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    todayRow
                    if isOpen || !hasPunchedIn {
                        actionButtonRow
                    }
                } header: {
                    Text("Today")
                }

                Section {
                    HStack {
                        Text("Total worked")
                        Spacer()
                        Text(payPeriodHHMM)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("This Pay Period")
                }

                Section {
                    if historyRecords.isEmpty && !isLoading {
                        ContentUnavailableView(
                            "No Records",
                            systemImage: "clock.badge.questionmark",
                            description: Text("Your attendance entries will appear here.")
                        )
                    } else {
                        ForEach(historyRecords) { record in
                            historyRow(for: record)
                        }
                    }
                } header: {
                    Text("Attendance")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("HR")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await reloadAll() }
            .task { await reloadAll() }
            .onReceive(timer) { date in nowTick = date }
            .sheet(isPresented: $showPunchIn) {
                PunchFlowView(mode: .punchIn) { Task { await reloadAll() } }
            }
            .sheet(isPresented: $showPunchOut) {
                PunchFlowView(mode: .punchOut) { Task { await reloadAll() } }
            }
        }
    }

    // MARK: - Today row

    private var todayRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isOpen ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: isOpen ? "play.circle.fill" : (hasPunchedIn ? "checkmark.circle.fill" : "clock"))
                    .font(.title3)
                    .foregroundStyle(isOpen ? .green : (hasPunchedIn ? .blue : .secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(statusLine)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let sub = statusSubtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(todayLiveDisplay)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 6)
    }

    private var statusLine: String {
        if isOpen { return "Working" }
        if hasPunchedIn { return "Day Complete" }
        return "Not Clocked In"
    }

    private var statusSubtitle: String? {
        if isOpen, let punchIn = firstPunchInDate ?? parseAttendanceDate(todayAttendance?.punchInTime) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return "Since \(f.string(from: punchIn))"
        }
        if hasPunchedIn,
           let inDate = firstPunchInDate ?? parseAttendanceDate(todayAttendance?.punchInTime),
           let outDate = parseAttendanceDate(todayAttendance?.punchOutTime) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return "\(f.string(from: inDate)) → \(f.string(from: outDate))"
        }
        return nil
    }

    // MARK: - Action button row

    @ViewBuilder
    private var actionButtonRow: some View {
        if !hasPunchedIn {
            Button {
                showPunchIn = true
            } label: {
                Label {
                    Text("Clock In Now")
                } icon: {
                    Image(systemName: "play.fill")
                        .symbolRenderingMode(.monochrome)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
        } else if isOpen {
            HStack(spacing: 10) {
                Button {
                    // Mirrors Android: button shown but break flow not implemented.
                } label: {
                    Label("Take a Break", systemImage: "pause.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.orange)
                .disabled(true)

                Button {
                    showPunchOut = true
                } label: {
                    Label {
                        Text("Clock Out")
                    } icon: {
                        Image(systemName: "stop.fill")
                            .symbolRenderingMode(.monochrome)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
        }
    }

    // MARK: - Today total: now − first punch-in

    /// Today's date string in "yyyy-MM-dd". Used to find today's record in the
    /// history list, which contains `firstPunchIn` for the day (the today
    /// snapshot endpoint only exposes the latest open session's punch-in time).
    private var todayDateKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var todayHistoryRecord: ConvexAttendanceRecord? {
        historyRecords.first { $0.date == todayDateKey }
    }

    private var firstPunchInDate: Date? {
        if let raw = todayHistoryRecord?.firstPunchIn,
           let date = parseAttendanceDate(raw) { return date }
        return parseAttendanceDate(todayAttendance?.punchInTime)
    }

    private var todayTotalSeconds: TimeInterval {
        // Live total = now − first punch-in (Android parity).
        if isOpen, let firstIn = firstPunchInDate {
            return max(0, nowTick.timeIntervalSince(firstIn))
        }
        // Closed for the day — show whatever the server aggregated.
        let mins = todayHistoryRecord?.totalMinutes
            ?? todayAttendance?.cumulativeMinutes
            ?? todayAttendance?.totalMinutes
            ?? 0
        return TimeInterval(mins * 60)
    }

    private var todayLiveDisplay: String {
        formatHM(seconds: Int(todayTotalSeconds))
    }

    private var payPeriodHHMM: String {
        let mins = historyRecords.reduce(0) { $0 + ($1.totalMinutes ?? $1.cumulativeMinutes ?? 0) }
        return formatHM(seconds: mins * 60)
    }

    private func formatHM(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return String(format: "%dh %02dm", h, m)
    }

    // MARK: - History row

    private func historyRow(for record: ConvexAttendanceRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(formatHistoryDate(record.date))
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(formatTimeRange(in: record.firstPunchIn, out: record.lastPunchOut))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(historyTotal(for: record))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    private func historyTotal(for record: ConvexAttendanceRecord) -> String {
        let mins = record.totalMinutes ?? record.cumulativeMinutes ?? 0
        if mins <= 0 { return "—" }
        return formatHM(seconds: mins * 60)
    }

    private func formatHistoryDate(_ raw: String?) -> String {
        guard let raw else { return "—" }
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd"
        if let date = inFormatter.date(from: raw) {
            if Calendar.current.isDateInToday(date) { return "Today" }
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            let outFormatter = DateFormatter()
            outFormatter.dateFormat = "EEEE, d MMM"
            return outFormatter.string(from: date)
        }
        return raw
    }

    private func formatTimeRange(in punchIn: String?, out punchOut: String?) -> String {
        let i = formatClockTime(punchIn) ?? "—"
        let o = formatClockTime(punchOut) ?? "in progress"
        return "\(i) → \(o)"
    }

    private func formatClockTime(_ raw: String?) -> String? {
        guard let raw, let date = parseAttendanceDate(raw) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
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

    // MARK: - Loading

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
            // Silent — keep existing state.
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
        let from = formatter.string(from: firstOfMonth)
        let to = formatter.string(from: now)

        do {
            let records = try await HRConvexAPIService.getMyAttendance(token: token, fromDate: from, toDate: to)
            historyRecords = records.sorted { ($0.date ?? "") > ($1.date ?? "") }
        } catch {
            // Silent — state shown in section.
        }
    }
}

#Preview {
    HRDashboardView()
        .environment(AuthStore())
}
