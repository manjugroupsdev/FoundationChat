import SwiftUI

struct ConvexAttendanceListView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var records: [ConvexAttendanceRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filter: AttendanceFilter = .currentMonth()
    @State private var showFilter = false
    @State private var selectedRecord: ConvexAttendanceRecord?
    @State private var editRecord: ConvexAttendanceRecord?
    @State private var submittedRequestDates: Set<String> = []

    private var filteredRecords: [ConvexAttendanceRecord] {
        records.filter { filter.matches(status: $0.approvedAttendance ?? $0.status) }
    }

    private var presentDays: Int {
        let today = Self.dateKeyFormatter.string(from: Date())
        return records.filter { record in
            if record.date == today { return false }
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
        String(format: "%02d:%02d Hrs", totalMinutes / 60, totalMinutes % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterStatusBar
            summaryStats
            content
        }
        .background(Color(hex: 0xF6F7FB).ignoresSafeArea())
        .navigationTitle("My Attendance")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("My Attendance")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text(filter.rangeLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showFilter) {
            AttendanceFilterSheet(filter: $filter)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedRecord) { record in
            PunchLogSheet(record: record)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editRecord) { record in
            AttendanceRequestSheet(record: record) {
                if let date = record.date { submittedRequestDates.insert(date) }
                await loadDataAsync()
            }
            .presentationDetents([.height(560), .large])
            .presentationBackground(Color.clear)
        }
        .task(id: filter.apiRange.from + "_" + filter.apiRange.to) {
            await loadDataAsync()
        }
    }

    @ViewBuilder
    private var filterStatusBar: some View {
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
            .padding(.top, 4)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
    }

    private var summaryStats: some View {
        HStack(spacing: 12) {
            statCard(value: "\(presentDays)", label: "Present", icon: "calendar", tint: Color(hex: 0x16A34A))
            statCard(value: totalHoursLabel, label: "Total Hours", icon: "clock", tint: Color(hex: 0x16A34A))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    private func statCard(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
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
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color(hex: 0xB42318))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(hex: 0xFEF3F2), in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(filteredRecords) { record in
                        AttendanceHistoryCard(
                            record: record,
                            requestSubmitted: record.date.map { submittedRequestDates.contains($0) } == true,
                            canEdit: record.canSubmitAttendanceRequest && !(record.date.map { submittedRequestDates.contains($0) } == true)
                        ) {
                            editRecord = record
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedRecord = record
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

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

private struct AttendanceHistoryCard: View {
    let record: ConvexAttendanceRecord
    let requestSubmitted: Bool
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x7A5AF8))

                Text(displayDate)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))

                Spacer()

                if let badge = statusBadge {
                    Text(badge.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(badge.color.opacity(0.12), in: Capsule())
                }

                if requestSubmitted {
                    Label("Remark submitted", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x067647))
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(Color(hex: 0xECFDF3), in: Capsule())
                } else if canEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .frame(width: 24, height: 24)
                            .background(Color(hex: 0xF5F8FF), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Hours")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x475467))
                    Text(totalHoursHMS)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: 0x344054))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Clock in & Out")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x475467))
                    Text(clockRange)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x344054))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))

            if let lateFine = lateFineBanner {
                fineBanner(icon: "clock.fill", title: "Late by \(lateFine.minutes)mins", amount: lateFine.amount, tint: Color(hex: 0xD92D20), background: Color(hex: 0xFEF3F2))
            }

            ForEach(record.otherFines?.filter { ($0.amount ?? 0) > 0 } ?? []) { fine in
                fineBanner(icon: "exclamationmark.circle.fill", title: fine.typeName?.nilIfBlank ?? "Other Fine", amount: fine.amount ?? 0, tint: Color(hex: 0x0B61CA), background: Color(hex: 0xEFF8FF))
            }

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
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
    }

    private func fineBanner(icon: String, title: String, amount: Double, tint: Color, background: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("Fine : \(AppModuleFormatters.rupees(amount))")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
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

    private var statusBadge: (title: String, color: Color)? {
        guard !Self.isToday(record.date) else { return nil }
        let raw = (record.approvedAttendance ?? record.status)?.lowercased()
        switch raw {
        case "present", "approved", "auto-approved":
            return ("Present", Color(hex: 0x169B2F))
        case "half-day":
            return ("Half Day", Color(hex: 0xB54708))
        case "absent", "rejected":
            return ("Absent", Color(hex: 0xB42318))
        case "weekoff":
            return ("Weekoff", Color(hex: 0x475467))
        case "holiday":
            return ("Holiday", Color(hex: 0x0B61CA))
        default:
            let mins = record.totalMinutes ?? record.cumulativeMinutes ?? 0
            return mins > 0 ? ("Pending", Color(hex: 0xB54708)) : nil
        }
    }

    private var lateFineBanner: (minutes: Int, amount: Double)? {
        let minutes = record.lateMinutes ?? 0
        let amount = record.lateFineDeduction ?? record.fineAmount ?? 0
        guard minutes > 0, amount > 0 else { return nil }
        return (minutes, amount)
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

    private static func isToday(_ raw: String?) -> Bool {
        guard let raw, let date = ymd.date(from: raw) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}

private struct AttendanceRequestSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let record: ConvexAttendanceRecord
    let onSubmitted: () async -> Void

    @State private var requestType = "remark"
    @State private var remarks = ""
    @State private var usePunchIn = false
    @State private var usePunchOut = false
    @State private var correctedPunchIn = Date()
    @State private var correctedPunchOut = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xD0D5DD))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)

            Text("Remarks My Attendance")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Text("Want to Remark Todays Attendance")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .padding(.top, 2)
                .padding(.bottom, 12)

            sectionLabel("Request Type")
            Menu {
                Button("Remark") { requestType = "remark" }
                Button("Time Correction") {
                    requestType = "correction"
                }
            } label: {
                fieldShell {
                    Text(requestType == "correction" ? "Time Correction" : "Remark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if requestType == "correction" {
                sectionLabel("In Time")
                    .padding(.top, 10)
                timePickerField(title: "Select In Time", selection: $correctedPunchIn, isSelected: usePunchIn) {
                    usePunchIn = true
                }
                    .padding(.top, 4)

                sectionLabel("Out Time")
                    .padding(.top, 10)
                timePickerField(title: "Select Out Time", selection: $correctedPunchOut, isSelected: usePunchOut) {
                    usePunchOut = true
                }
                    .padding(.top, 4)
            }

            sectionLabel("Remarks (Optional)")
                .padding(.top, 10)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
                if remarks.isEmpty {
                    Text("Enter Remarks")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                }
                TextEditor(text: $remarks)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90, maxHeight: 104)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .padding(.top, 4)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xB42318))
                    .padding(.top, 10)
            }

            Button {
                submit()
            } label: {
                Text(isSubmitting ? "Submitting..." : "Submit Now")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(androidGreenGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .opacity(isSubmitting ? 0.72 : 1)
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28, style: .continuous))
        .onAppear {
            let existingIn = initialDateIfPresent(from: record.firstPunchIn ?? record.sessions?.first?.punchInTime)
            let existingOut = initialDateIfPresent(from: record.lastPunchOut ?? record.sessions?.last?.punchOutTime)
            correctedPunchIn = existingIn ?? Date()
            correctedPunchOut = existingOut ?? Date()
            usePunchIn = existingIn != nil
            usePunchOut = existingOut != nil
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: 0x475467))
    }

    private func fieldShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .frame(height: 52)
        .padding(.horizontal, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
    }

    private func timePickerField(
        title: String,
        selection: Binding<Date>,
        isSelected: Bool,
        onSelectionChanged: @escaping () -> Void
    ) -> some View {
        fieldShell {
            Image(systemName: "clock")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: 0x475467))
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .onChange(of: selection.wrappedValue) { _, _ in
                    onSelectionChanged()
                }
            if !isSelected {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x667085))
        }
    }

    private var displayDate: String {
        guard let raw = record.date, let date = Self.ymd.date(from: raw) else {
            return record.date ?? "--"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private func submit() {
        guard let token = authStore.currentSession?.token else { return }
        guard let attendanceId = record._id?.nilIfBlank ?? record.attendanceId?.nilIfBlank,
              let date = record.date?.nilIfBlank
        else {
            errorMessage = "This day can't be edited."
            return
        }

        let trimmed = remarks.trimmingCharacters(in: .whitespacesAndNewlines)
        if requestType == "correction", !usePunchIn, !usePunchOut {
            errorMessage = "Select a corrected in or out time."
            return
        }
        if requestType == "correction", usePunchOut {
            let comparisonInTime = usePunchIn
                ? correctedPunchIn
                : initialDateIfPresent(from: record.firstPunchIn ?? record.sessions?.first?.punchInTime)
            if let comparisonInTime,
               !Self.isOutTimeLaterThanInTime(inTime: comparisonInTime, outTime: correctedPunchOut) {
                errorMessage = "Out time must be later than in time."
                return
            }
        }

        isSubmitting = true
        errorMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                _ = try await HRConvexAPIService.submitAttendanceRequest(
                    token: token,
                    attendanceId: attendanceId,
                    date: date,
                    type: requestType,
                    remark: requestType == "remark" ? trimmed.nilIfBlank ?? "Remark requested from mobile app" : nil,
                    correctedPunchIn: requestType == "correction" && usePunchIn ? Self.isoString(date: date, time: correctedPunchIn) : nil,
                    correctedPunchOut: requestType == "correction" && usePunchOut ? Self.isoString(date: date, time: correctedPunchOut) : nil,
                    correctionReason: requestType == "correction" ? trimmed.nilIfBlank ?? "Time correction requested from mobile app" : nil
                )
                await onSubmitted()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func initialDate(from raw: String?) -> Date {
        initialDateIfPresent(from: raw) ?? Date()
    }

    private func initialDateIfPresent(from raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func isoString(date: String, time: Date) -> String {
        let calendar = Calendar.current
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        let base = ymd.date(from: date) ?? Date()
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        components.hour = timeParts.hour
        components.minute = timeParts.minute
        components.second = 0
        let localDate = calendar.date(from: components) ?? time
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: localDate)
    }

    private static func isOutTimeLaterThanInTime(inTime: Date, outTime: Date) -> Bool {
        let calendar = Calendar.current
        let inParts = calendar.dateComponents([.hour, .minute], from: inTime)
        let outParts = calendar.dateComponents([.hour, .minute], from: outTime)
        let inMinutes = (inParts.hour ?? 0) * 60 + (inParts.minute ?? 0)
        let outMinutes = (outParts.hour ?? 0) * 60 + (outParts.minute ?? 0)
        return outMinutes > inMinutes
    }

    private static let ymd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var androidGreenGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x1BCA0B), Color(hex: 0x3D9D02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ConvexAttendanceRecord {
    var canSubmitAttendanceRequest: Bool {
        _id?.isEmpty == false && date?.isEmpty == false
    }
}
