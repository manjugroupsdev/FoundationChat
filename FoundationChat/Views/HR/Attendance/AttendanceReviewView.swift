import SwiftUI

struct AttendanceReviewView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var records: [ConvexAttendanceRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filter = AttendanceReviewFilter()
    @State private var showFilter = false
    @State private var selectedRecord: ConvexAttendanceRecord?
    @State private var rejectingRecord: ConvexAttendanceRecord?
    @State private var rejectReason = ""
    @State private var actionInFlightId: String?

    private var filteredRecords: [ConvexAttendanceRecord] {
        records.filter { filter.matches($0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                reviewHeader
                VStack(spacing: 12) {
                    summaryHeader
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
                        VStack(spacing: 10) {
                            ForEach(filteredRecords) { record in
                                reviewCard(for: record)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 12)
                .padding(.top, -32)
                .padding(.bottom, 24)
            }
        }
        .background(Color(hex: 0xF4F6FB).ignoresSafeArea())
        .navigationTitle("Attendance Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter attendance reviews")
            }
        }
        .sheet(isPresented: $showFilter) {
            AttendanceReviewFilterSheet(filter: $filter)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedRecord) { record in
            PunchLogSheet(record: record)
                .presentationDetents([.medium, .large])
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

    private var reviewHeader: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x0353B8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Attendance Approvals")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(.white)
                Text("In Review")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 22)
            .padding(.top, 46)
        }
        .frame(height: 148)
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.staffName ?? "Unknown Staff")
                        .font(.headline)
                    Text(record.date ?? "--")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(record.totalHoursFormatted)
                        .font(.subheadline.weight(.semibold))
                    if let status = reviewStatus(for: record) {
                        Text(status.capitalized)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(attendanceStatusColor(status).opacity(0.15), in: Capsule())
                            .foregroundStyle(attendanceStatusColor(status))
                    }
                }
            }

            HStack(spacing: 12) {
                Label(record.punchInFormatted, systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(.green)
                Label(record.punchOutFormatted, systemImage: "arrow.left.circle.fill")
                    .foregroundStyle(.orange)
                if let count = record.sessionCount {
                    Label("\(count)", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            Button {
                selectedRecord = record
            } label: {
                Label("Review Punch Log", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 12) {
                Menu {
                    Button("Present") { approveAttendance(record, as: "present") }
                    Button("Half Day") { approveAttendance(record, as: "half-day") }
                    Button("Absent") { approveAttendance(record, as: "absent") }
                    Button("Weekoff") { approveAttendance(record, as: "weekoff") }
                    Button("Holiday") { approveAttendance(record, as: "holiday") }
                } label: {
                    Label(actionInFlightId == record.reviewId ? "Working..." : "Approve", systemImage: "checkmark")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(actionInFlightId != nil)

                Button {
                    rejectingRecord = record
                    rejectReason = ""
                } label: {
                    Label("Reject", systemImage: "xmark")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(actionInFlightId != nil)
            }
        }
        .padding(14)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
    }

    @MainActor
    private func loadReviews() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            records = try await HRConvexAPIService.getPendingAttendanceApprovals(token: token)
                .sorted { ($0.date ?? "") > ($1.date ?? "") }
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                return
            }
            errorMessage = error.localizedDescription
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
