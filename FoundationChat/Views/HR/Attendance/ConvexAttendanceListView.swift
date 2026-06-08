import SwiftUI

struct ConvexAttendanceListView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var records: [ConvexAttendanceRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filter: AttendanceFilter = .currentMonth()
    @State private var showFilter = false
    @State private var selectedRecord: ConvexAttendanceRecord?
    @State private var attendanceToWithdraw: ConvexAttendanceRecord?
    @State private var withdrawingDate: String?

    private var filteredRecords: [ConvexAttendanceRecord] {
        records.filter { filter.matches(status: $0.approvedAttendance ?? $0.status) }
    }

    private var presentDays: Int {
        records.filter { record in
            let approved = record.approvedAttendance?.lowercased()
            switch approved {
            case "absent", "weekoff", "holiday":
                return false
            case "present", "half-day":
                return true
            default:
                return (record.totalMinutes ?? record.cumulativeMinutes ?? 0) > 0
            }
        }.count
    }

    private var totalMinutes: Int {
        records.reduce(0) { $0 + ($1.totalMinutes ?? $1.cumulativeMinutes ?? 0) }
    }

    private var totalHoursLabel: String {
        "\(totalMinutes / 60)h"
    }

    var body: some View {
        VStack(spacing: 0) {
            androidHeader
            summaryStats
            content
        }
        .background(Color(hex: 0xF6F7FB).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFilter) {
            AttendanceFilterSheet(filter: $filter)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedRecord) { record in
            PunchLogSheet(record: record)
                .presentationDetents([.medium, .large])
        }
        .alert("Withdraw Attendance", isPresented: Binding(
            get: { attendanceToWithdraw != nil },
            set: { if !$0 { attendanceToWithdraw = nil } }
        )) {
            Button("Withdraw", role: .destructive) {
                if let attendanceToWithdraw {
                    withdrawAttendance(attendanceToWithdraw)
                }
                attendanceToWithdraw = nil
            }
            Button("Cancel", role: .cancel) {
                attendanceToWithdraw = nil
            }
        } message: {
            Text("This will withdraw your pending attendance request.")
        }
        .task(id: filter.apiRange.from + "_" + filter.apiRange.to) {
            await loadDataAsync()
        }
    }

    private var androidHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color(hex: 0x101828))
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)

                Text("My Attendance")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)

                Spacer()

                Button {
                    showFilter = true
                } label: {
                    Text("Filter")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(Color(hex: 0x0B61CA), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 48)

            Text(filter.rangeLabel)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: 0x7A5AF8))
                .padding(.leading, 40)

            if !filter.statuses.isEmpty {
                HStack(spacing: 8) {
                    Text("Status: \(filter.statuses.map { $0.capitalized }.sorted().joined(separator: ", "))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                    Button("Clear") {
                        filter.statuses.removeAll()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .buttonStyle(.plain)
                }
                .padding(.leading, 40)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.white)
    }

    private var summaryStats: some View {
        HStack(spacing: 12) {
            statCard(value: "\(presentDays)", label: "Present", tint: Color(hex: 0x16A34A))
            statCard(value: totalHoursLabel, label: "Total Hours", tint: Color(hex: 0x7C3AED))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    private func statCard(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: 0x667085))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(hex: 0xF4F4F5), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && records.isEmpty {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(height: 118)
                        .redacted(reason: .placeholder)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        } else if filteredRecords.isEmpty {
            ContentUnavailableView {
                Label("No Records", systemImage: "clock")
            } description: {
                Text(filter.statuses.isEmpty ? "No attendance records for this date range." : "No records match the selected filters.")
            } actions: {
                if !filter.statuses.isEmpty {
                    Button("Clear Filters") {
                        filter.statuses.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredRecords) { record in
                        VStack(spacing: 8) {
                            Button {
                                selectedRecord = record
                            } label: {
                                AttendanceHistoryCard(record: record)
                            }
                            .buttonStyle(.plain)

                            if record.canWithdrawPendingAttendance {
                                Button {
                                    attendanceToWithdraw = record
                                } label: {
                                    if withdrawingDate == record.date {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Label("Withdraw Pending Attendance", systemImage: "arrow.uturn.backward.circle")
                                            .font(.system(size: 14, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: 0x0B61CA))
                                .controlSize(.large)
                                .disabled(withdrawingDate != nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .refreshable { await loadDataAsync() }
        }
    }

    @MainActor
    private func loadDataAsync() async {
        guard let token = authStore.currentSession?.token else { return }
        let (from, to) = filter.apiRange
        isLoading = true
        defer { isLoading = false }
        do {
            records = try await HRConvexAPIService.getMyAttendance(token: token, fromDate: from, toDate: to)
            errorMessage = nil
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func withdrawAttendance(_ record: ConvexAttendanceRecord) {
        guard let token = authStore.currentSession?.token else { return }
        guard let date = record.date else {
            errorMessage = "Attendance date is missing."
            return
        }
        withdrawingDate = date
        Task {
            defer { withdrawingDate = nil }
            do {
                try await HRConvexAPIService.cancelMyAttendance(token: token, date: date)
                await loadDataAsync()
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AttendanceHistoryCard: View {
    let record: ConvexAttendanceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x7A5AF8))

                Text(displayDate)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))

                Spacer()
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Hours")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x475467))
                    Text(totalHoursHMS)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color(hex: 0x344054))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Clock in & Out")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x475467))
                    Text(clockRange)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0x344054))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))

            if let footer = decisionFooter {
                HStack(spacing: 5) {
                    Image(systemName: footer.isApproved ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(footer.color)
                    Text(footer.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(footer.color)
                        .lineLimit(1)
                    Spacer()
                    Text("By")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text(approverInitial)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                        .frame(width: 22, height: 22)
                        .background(Color(hex: 0xF2F4F7), in: Circle())
                    Text(record.approvedByName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "HR")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
    }

    private var displayDate: String {
        guard let raw = record.date, let date = Self.ymd.date(from: raw) else {
            return record.date ?? ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private var totalHoursHMS: String {
        let mins = record.totalMinutes ?? record.cumulativeMinutes ?? 0
        return String(format: "%02d:%02d:00 hrs", mins / 60, mins % 60)
    }

    private var clockRange: String {
        let firstIn = record.firstPunchIn ?? record.sessions?.first?.punchInTime
        let inLabel = firstIn.flatMap(Self.formatTime) ?? "--"
        let resolvedOut = record.lastPunchOut ?? record.sessions?.last?.punchOutTime
        let outLabel: String
        if let resolvedOut, let formatted = Self.formatTime(resolvedOut) {
            outLabel = formatted
        } else if hasOpenSession {
            outLabel = "---"
        } else if firstIn != nil {
            outLabel = "Not Punched Out"
        } else {
            outLabel = "--"
        }
        return "\(inLabel) · \(outLabel)"
    }

    private var hasOpenSession: Bool {
        record.sessions?.contains { session in
            session.punchInTime != nil && session.punchOutTime == nil
        } == true
    }

    private var decisionFooter: (text: String, color: Color, isApproved: Bool)? {
        let status = record.status?.lowercased() ?? ""
        guard status == "approved" || status == "rejected" else { return nil }
        let isApproved = status == "approved"
        let verb = isApproved ? "Approved" : "Rejected"
        let dateText = record.approvedOn.flatMap(Self.formatDecisionDate)
        let text = dateText.map { "\(verb) at \($0)" } ?? verb
        return (text, isApproved ? Color(hex: 0x169B2F) : Color(hex: 0xB42318), isApproved)
    }

    private var approverInitial: String {
        let name = record.approvedByName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "HR"
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    private static let ymd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func formatTime(_ raw: String) -> String? {
        if let date = parseISO(raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "hh:mm a"
            return formatter.string(from: date)
        }
        return raw.isEmpty ? nil : raw
    }

    private static func formatDecisionDate(_ raw: String) -> String? {
        let date = parseISO(raw) ?? ymd.date(from: raw)
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private static func parseISO(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ConvexAttendanceRecord {
    var canWithdrawPendingAttendance: Bool {
        status?.lowercased() == "pending" && date?.isEmpty == false
    }
}
