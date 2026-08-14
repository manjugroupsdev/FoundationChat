import SwiftUI

struct AttendanceReviewView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var records: [ConvexAttendanceRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filter = AttendanceReviewFilter()
    @State private var selectedRecord: ConvexAttendanceRecord?
    @State private var approvingRecord: ConvexAttendanceRecord?
    @State private var rejectingRecord: ConvexAttendanceRecord?
    @State private var rejectReason = ""
    @State private var actionInFlightId: String?

    private var filteredRecords: [ConvexAttendanceRecord] {
        records.filter { filter.matches($0) }
    }

    private var reviewCacheKey: String {
        let staff = authStore.currentSession?.user.staffId?.nonBlank
            ?? authStore.currentSession?.user._id.nonBlank
            ?? "anon"
        return "hr.attendance.reviews.pending.\(staff)"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    reviewHeader(topInset: proxy.safeAreaInsets.top)
                    VStack(spacing: 12) {
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }

                        if isLoading && records.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(0..<2, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(hex: 0xF8FAFC))
                                        .frame(height: 112)
                                        .redacted(reason: .placeholder)
                                }
                            }
                        } else if filteredRecords.isEmpty {
                            ContentUnavailableView(
                                "No attendance to review",
                                systemImage: "checkmark.circle",
                                description: Text(records.isEmpty ? "Pending punches from your team will land here." : "No approvals match the selected filters.")
                            )
                            .padding(.vertical, 24)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(filteredRecords) { record in
                                    reviewCard(for: record)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, -32)
                    .padding(.bottom, 24)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Color(hex: 0xF4F6FB).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $selectedRecord) { record in
            PunchLogSheet(record: record)
                .appLibraryNativeSheet([.medium, .large])
        }
        .confirmationDialog("Approve as", isPresented: Binding(
            get: { approvingRecord != nil },
            set: { if !$0 { approvingRecord = nil } }
        ), titleVisibility: .visible) {
            Button("Present") { approveSelectedAttendance(as: "present") }
            Button("Half-day") { approveSelectedAttendance(as: "half-day") }
            Button("Absent") { approveSelectedAttendance(as: "absent") }
            Button("Weekoff") { approveSelectedAttendance(as: "weekoff") }
            Button("Holiday") { approveSelectedAttendance(as: "holiday") }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Reject Attendance", isPresented: Binding(
            get: { rejectingRecord != nil },
            set: { if !$0 { rejectingRecord = nil } }
        )) {
            TextField("Reason", text: $rejectReason)
            Button("Reject", role: .destructive) {
                if let rejectingRecord {
                    rejectAttendance(rejectingRecord)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a reason for rejection")
        }
        .refreshable {
            await loadReviews()
        }
        .overlay {
            if isLoading && records.isEmpty {
                ProgressView()
            }
        }
        .task {
            await loadReviews()
        }
    }

    private func reviewHeader(topInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x0353B8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 0) {
                Text("Attendance Approvals")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("In Review")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 2)
            }
            .padding(.leading, 20)
            .padding(.top, topInset + 54)
        }
        .frame(height: 148 + topInset)
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(filteredRecords.count) Pending")
                        .font(.headline)
                    Text(filter.summaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(records.count)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0xEFF8FF), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func reviewCard(for record: ConvexAttendanceRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(staffInitial(for: record))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0xF2F4F7), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(nonBlank(record.staffName) ?? "Staff")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)

                    Text(staffMeta(for: record))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Text(sourceLabel(for: record.source))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0369A1))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0xE0F2FE), in: Capsule())
            }

            Button {
                selectedRecord = record
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(formattedDate(record.date) ?? record.date ?? "-")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x344054))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .top, spacing: 8) {
                        approvalMetric(title: "Punch In", value: record.punchInFormatted)
                        approvalMetric(title: "Punch Out", value: record.punchOutFormatted)
                        approvalMetric(title: "Duration", value: durationText(for: record))
                    }
                }
                .padding(12)
                .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    approvingRecord = record
                } label: {
                    Text(actionInFlightId == record.reviewId ? "Working..." : "Approve")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: 0x0B61CA), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(actionInFlightId != nil)

                Button {
                    rejectingRecord = record
                    rejectReason = ""
                } label: {
                    Text("Reject")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xDC2626))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: 0xFEE2E2), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(actionInFlightId != nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 4)
    }

    private func approvalMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func loadReviews() async {
        guard let token = authStore.currentSession?.token else { return }
        if records.isEmpty,
           let cached = LocalCache.get(reviewCacheKey, as: [ConvexAttendanceRecord].self) {
            records = cached
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            records = try await HRConvexAPIService.getPendingAttendanceApprovals(token: token)
                .sorted { ($0.date ?? "") > ($1.date ?? "") }
            LocalCache.put(reviewCacheKey, records)
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                return
            }
            if records.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func approveAttendance(_ record: ConvexAttendanceRecord, as approvedAttendance: String) {
        guard let token = authStore.currentSession?.token else { return }
        guard let id = record.reviewId else {
            errorMessage = "Attendance id is missing."
            return
        }

        actionInFlightId = id
        Task {
            defer { actionInFlightId = nil }
            do {
                try await HRConvexAPIService.approveAttendance(
                    token: token,
                    id: id,
                    approvedAttendance: approvedAttendance
                )
                await loadReviews()
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func approveSelectedAttendance(as approvedAttendance: String) {
        guard let approvingRecord else { return }
        self.approvingRecord = nil
        approveAttendance(approvingRecord, as: approvedAttendance)
    }

    private func rejectAttendance(_ record: ConvexAttendanceRecord) {
        guard let token = authStore.currentSession?.token else { return }
        guard let id = record.reviewId else {
            errorMessage = "Attendance id is missing."
            return
        }

        let reason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            errorMessage = "Please enter a rejection reason."
            return
        }

        actionInFlightId = id
        Task {
            defer {
                actionInFlightId = nil
                rejectingRecord = nil
                rejectReason = ""
            }
            do {
                try await HRConvexAPIService.rejectAttendance(token: token, id: id, reason: reason)
                await loadReviews()
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reviewStatus(for record: ConvexAttendanceRecord) -> String? {
        record.approvedAttendance ?? record.status
    }

    private func attendanceStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "present", "approved", "auto-approved": return .green
        case "half-day", "weekoff", "holiday": return .orange
        case "absent", "rejected": return .red
        default: return .secondary
        }
    }

    private func staffInitial(for record: ConvexAttendanceRecord) -> String {
        let name = nonBlank(record.staffName) ?? "?"
        return name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }

    private func staffMeta(for record: ConvexAttendanceRecord) -> String {
        nonBlank(record.staffId) ?? "-"
    }

    private func sourceLabel(for source: String?) -> String {
        switch source?.lowercased() {
        case "mobile":
            return "Mobile"
        case "biometric":
            return "Biometric"
        case "manual":
            return "Manual"
        case "csv-import":
            return "CSV"
        case .some(let value) where !value.isEmpty:
            return value.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        default:
            return "-"
        }
    }

    private func durationText(for record: ConvexAttendanceRecord) -> String {
        let minutes = record.totalMinutes ?? record.cumulativeMinutes
        guard let minutes, minutes > 0 else { return "-" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }

    private func formattedDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: raw) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AttendanceReviewFilter: Equatable {
    var fromDate: Date?
    var toDate: Date?
    var statuses: Set<String> = []
    var searchText = ""

    static let availableStatuses = ["present", "half-day", "absent", "weekoff", "holiday"]

    var isActive: Bool {
        fromDate != nil || toDate != nil || !statuses.isEmpty || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var summaryLabel: String {
        guard isActive else { return "All pending approvals" }
        var parts: [String] = []
        if fromDate != nil || toDate != nil { parts.append("Date range") }
        if !statuses.isEmpty { parts.append(statuses.map(\.capitalized).sorted().joined(separator: ", ")) }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("Search") }
        return parts.joined(separator: " · ")
    }

    func matches(_ record: ConvexAttendanceRecord) -> Bool {
        if !statuses.isEmpty {
            guard let status = (record.approvedAttendance ?? record.status)?.lowercased(),
                  statuses.contains(status) else { return false }
        }

        if fromDate != nil || toDate != nil {
            guard let recordDate = record.reviewDate else { return false }
            if let fromDate, recordDate < Calendar.current.startOfDay(for: fromDate) { return false }
            if let toDate {
                let endOfDay = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: toDate)) ?? toDate
                if recordDate > endOfDay { return false }
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            let haystack = [
                record.staffName,
                record.staffId,
                record.date,
                record.source,
                record.status,
                record.approvedAttendance
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

            return haystack.contains(query)
        }

        return true
    }
}

private struct AttendanceReviewFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: AttendanceReviewFilter
    @State private var draft: AttendanceReviewFilter

    init(filter: Binding<AttendanceReviewFilter>) {
        self._filter = filter
        self._draft = State(initialValue: filter.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    TextField("Staff name or ID", text: $draft.searchText)
                }

                Section("Date Range") {
                    Toggle("Use From Date", isOn: Binding(
                        get: { draft.fromDate != nil },
                        set: { draft.fromDate = $0 ? Date() : nil }
                    ))
                    if draft.fromDate != nil {
                        DatePicker("From", selection: Binding(
                            get: { draft.fromDate ?? Date() },
                            set: { draft.fromDate = $0 }
                        ), displayedComponents: .date)
                    }

                    Toggle("Use To Date", isOn: Binding(
                        get: { draft.toDate != nil },
                        set: { draft.toDate = $0 ? Date() : nil }
                    ))
                    if draft.toDate != nil {
                        DatePicker("To", selection: Binding(
                            get: { draft.toDate ?? Date() },
                            set: { draft.toDate = $0 }
                        ), displayedComponents: .date)
                    }
                }

                Section("Attendance Status") {
                    statusToggle("All", isOn: draft.statuses.isEmpty) {
                        draft.statuses.removeAll()
                    }
                    ForEach(AttendanceReviewFilter.availableStatuses, id: \.self) { status in
                        statusToggle(status.capitalized, isOn: draft.statuses.contains(status)) {
                            if draft.statuses.contains(status) {
                                draft.statuses.remove(status)
                            } else {
                                draft.statuses.insert(status)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Reviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        filter = AttendanceReviewFilter()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        normalizeRange()
                        filter = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func statusToggle(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func normalizeRange() {
        if let fromDate = draft.fromDate, let toDate = draft.toDate, fromDate > toDate {
            draft.fromDate = toDate
            draft.toDate = fromDate
        }
    }
}

private extension ConvexAttendanceRecord {
    var reviewId: String? {
        _id ?? attendanceId
    }

    var reviewDate: Date? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: date)
    }
}
