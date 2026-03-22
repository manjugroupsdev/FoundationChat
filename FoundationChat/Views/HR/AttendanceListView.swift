import SwiftUI

struct AttendanceListView: View {
    @State private var records: [APIMobileAttendance] = []
    @State private var selectedMonth = Date()
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let api = HRAPIService.shared

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .listRowSeparator(.hidden)
            } else if records.isEmpty {
                ContentUnavailableView(
                    "No Attendance Records",
                    systemImage: "clock",
                    description: Text("Your attendance will appear here.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(records) { record in
                    MobileAttendanceRow(record: record)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("My Attendance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                MonthPicker(selectedMonth: $selectedMonth)
            }
        }
        .task { await loadAttendance() }
        .onChange(of: selectedMonth) { Task { await loadAttendance() } }
        .refreshable { await loadAttendance() }
    }

    private func loadAttendance() async {
        isLoading = true
        errorMessage = nil
        do {
            let calendar = Calendar.current
            let comps = calendar.dateComponents([.year, .month], from: selectedMonth)
            let startOfMonth = calendar.date(from: comps)!
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"

            records = try await api.fetchMobileAttendance(
                limit: 100,
                fromDate: df.string(from: startOfMonth),
                toDate: df.string(from: endOfMonth)
            )
            // Sort newest first
            records.sort { ($0.inDateAndTime ?? .distantPast) > ($1.inDateAndTime ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct MobileAttendanceRow: View {
    let record: APIMobileAttendance

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                if let inTime = record.inDateAndTime {
                    Text(inTime, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                        .font(.subheadline.weight(.medium))
                }

                HStack(spacing: 4) {
                    if let inTime = record.inDateAndTime {
                        Text(inTime, format: .dateTime.hour().minute())
                            .font(.caption)
                    }
                    if let outTime = record.outDateAndTime {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(outTime, format: .dateTime.hour().minute())
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)

                if let name = record.empUserName, !name.isEmpty {
                    Text(name)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.teal)
                }
            }

            Spacer()

            if record.isOpen {
                Text("Open")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
            } else if let formatted = record.totalHoursFormatted {
                let hours = record.totalHours ?? 0
                Text(formatted)
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hoursColor(hours), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 4)
    }

    private func hoursColor(_ hours: Double) -> Color {
        if hours >= 8 { return .green }
        if hours >= 4 { return .orange }
        return .red
    }
}

struct MonthPicker: View {
    @Binding var selectedMonth: Date

    var body: some View {
        Menu {
            ForEach(0..<6) { offset in
                let month = Calendar.current.date(byAdding: .month, value: -offset, to: Date())!
                Button {
                    selectedMonth = month
                } label: {
                    Text(month, format: .dateTime.month(.wide).year())
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedMonth, format: .dateTime.month(.abbreviated))
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
    }
}
