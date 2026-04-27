import SwiftUI

struct ConvexAttendanceListView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var records: [ConvexAttendanceRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filter: AttendanceFilter = .currentMonth()
    @State private var showFilter = false

    private var filteredRecords: [ConvexAttendanceRecord] {
        records.filter { filter.matches(status: $0.approvedAttendance ?? $0.status) }
    }

    private var presentDays: Int {
        records.filter { record in
            let status = record.approvedAttendance ?? record.status
            return status == "present" || status == "approved" || status == "auto-approved"
        }.count
    }

    private var totalMinutes: Int {
        records.reduce(0) { $0 + ($1.totalMinutes ?? $1.cumulativeMinutes ?? 0) }
    }

    private var totalHoursLabel: String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return String(format: "%dh %02dm", h, m)
    }

    var body: some View {
        List {
            Section {
                summaryHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if filteredRecords.isEmpty && !isLoading {
                emptyState
                    .listRowBackground(Color.clear)
            }

            ForEach(filteredRecords) { record in
                attendanceRow(record)
            }
        }
        .navigationTitle("Attendance")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: filter.statuses.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter attendance")
            }
        }
        .sheet(isPresented: $showFilter) {
            AttendanceFilterSheet(filter: $filter)
                .presentationDetents([.medium, .large])
        }
        .refreshable { await loadDataAsync() }
        .overlay {
            if isLoading && records.isEmpty { ProgressView() }
        }
        .task(id: filter.apiRange.from + "_" + filter.apiRange.to) {
            await loadDataAsync()
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filter.rangeLabel)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                summaryTile(value: "\(presentDays)", label: "Days Present", tint: .green)
                summaryTile(value: totalHoursLabel, label: "Total Hours", tint: .blue)
            }

            if !filter.statuses.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(.tint)
                    Text("Status: \(filter.statuses.map { $0.capitalized }.sorted().joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        filter.statuses.removeAll()
                    }
                    .font(.footnote)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.background)
    }

    private func summaryTile(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Records", systemImage: "clock")
        } description: {
            if filter.statuses.isEmpty {
                Text("No attendance records for this date range.")
            } else {
                Text("No records match the selected filters.")
            }
        } actions: {
            if !filter.statuses.isEmpty {
                Button("Clear Filters") {
                    filter.statuses.removeAll()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func attendanceRow(_ record: ConvexAttendanceRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.date ?? "--")
                    .font(.headline)
                HStack(spacing: 12) {
                    Label(record.punchInFormatted, systemImage: "arrow.right.circle.fill")
                        .foregroundStyle(.green)
                    Label(record.punchOutFormatted, systemImage: "arrow.left.circle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(record.totalHoursFormatted)
                    .font(.subheadline.weight(.semibold))
                if let status = record.approvedAttendance ?? record.status {
                    Text(status.capitalized)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(attendanceStatusColor(status).opacity(0.15), in: Capsule())
                        .foregroundStyle(attendanceStatusColor(status))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func attendanceStatusColor(_ status: String) -> Color {
        switch status {
        case "present", "approved", "auto-approved": return .green
        case "half-day": return .orange
        case "absent": return .red
        default: return .secondary
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
