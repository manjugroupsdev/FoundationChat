import SwiftUI

struct AttendanceFilter: Equatable {
    var fromDate: Date
    var toDate: Date
    var statuses: Set<String>

    static let availableStatuses: [String] = ["present", "approved", "half-day", "absent"]

    static func currentMonth(reference: Date = Date()) -> AttendanceFilter {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: reference)
        let start = cal.date(from: comps) ?? reference
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? reference
        return AttendanceFilter(fromDate: start, toDate: end, statuses: [])
    }

    var isAllStatuses: Bool { statuses.isEmpty }

    func matches(status: String?) -> Bool {
        guard !statuses.isEmpty else { return true }
        guard let raw = status?.lowercased() else { return false }
        if statuses.contains(raw) { return true }
        if raw == "auto-approved" && statuses.contains("approved") { return true }
        return false
    }

    var apiRange: (from: String, to: String) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return (df.string(from: fromDate), df.string(from: toDate))
    }

    var rangeLabel: String {
        let cal = Calendar.current
        let display = DateFormatter()
        display.dateFormat = "d MMM yyyy"
        if cal.isDate(fromDate, equalTo: toDate, toGranularity: .month) {
            let firstDay = cal.component(.day, from: fromDate)
            let lastDay = cal.component(.day, from: toDate)
            let lastOfMonth = cal.range(of: .day, in: .month, for: fromDate)?.count ?? lastDay
            if firstDay == 1 && lastDay == lastOfMonth {
                let monthFmt = DateFormatter()
                monthFmt.dateFormat = "MMMM yyyy"
                return monthFmt.string(from: fromDate)
            }
        }
        return "\(display.string(from: fromDate)) – \(display.string(from: toDate))"
    }
}

struct AttendanceFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: AttendanceFilter
    @State private var draft: AttendanceFilter
    @State private var showDateRangePicker = false

    init(filter: Binding<AttendanceFilter>) {
        self._filter = filter
        self._draft = State(initialValue: filter.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 8) {
                presetButton("This month") { applyThisMonth() }
                presetButton("Last month") { applyLastMonth() }
                presetButton("Last 7days") { applyLast7Days() }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 18)

            Button {
                showDateRangePicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                    Text(draft.rangeLabel.isEmpty ? "Select date range" : draft.rangeLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            HStack(spacing: 12) {
                filterOutlineButton("Cancel") { dismiss() }

                filterFilledButton("Select") {
                    if draft.fromDate > draft.toDate {
                        let tmp = draft.fromDate
                        draft.fromDate = draft.toDate
                        draft.toDate = tmp
                    }
                    filter = draft
                    dismiss()
                }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(Color.white)
        .appCompactSheetCTAContainer()
        .sheet(isPresented: $showDateRangePicker) {
            AttendanceDateRangePickerSheet(
                fromDate: draft.fromDate,
                toDate: draft.toDate,
                onCancel: { showDateRangePicker = false },
                onSelect: { from, to in
                    draft.fromDate = min(from, to)
                    draft.toDate = min(max(from, to), Date())
                    showDateRangePicker = false
                }
            )
            .appLibraryNativeSheet([.height(360)])
        }
    }

    private var header: some View {
        ZStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 2) {
                Text("Filter")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Text("Pick your date to view your attendance")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x475467))
            }
        }
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.white, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color(hex: 0xD8E8FA), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func applyThisMonth() {
        draft = AttendanceFilter.currentMonth().with(statuses: draft.statuses)
    }

    private func applyLastMonth() {
        let cal = Calendar.current
        let now = Date()
        guard let lastMonth = cal.date(byAdding: .month, value: -1, to: now) else { return }
        let comps = cal.dateComponents([.year, .month], from: lastMonth)
        guard let start = cal.date(from: comps),
              let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) else { return }
        draft.fromDate = start
        draft.toDate = end
    }

    private func applyLast7Days() {
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        guard let from = cal.date(byAdding: .day, value: -6, to: now) else { return }
        draft.fromDate = from
        draft.toDate = now
    }
}

private struct AttendanceDateRangePickerSheet: View {
    @State private var fromDate: Date
    @State private var toDate: Date
    let onCancel: () -> Void
    let onSelect: (Date, Date) -> Void

    init(fromDate: Date, toDate: Date, onCancel: @escaping () -> Void, onSelect: @escaping (Date, Date) -> Void) {
        _fromDate = State(initialValue: fromDate)
        _toDate = State(initialValue: toDate)
        self.onCancel = onCancel
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Date Range")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
            Text("Pick a date range")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x475467))
                .padding(.top, -10)

            VStack(spacing: 12) {
                DatePicker("From", selection: $fromDate, in: ...min(toDate, Date()), displayedComponents: .date)
                DatePicker("To", selection: $toDate, in: fromDate...Date(), displayedComponents: .date)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(14)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            filterFilledButton("Submit Date") {
                onSelect(fromDate, toDate)
            }

            filterOutlineButton("Close Message", action: onCancel)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .background(Color.white)
        .appCompactSheetCTAContainer()
    }
}

private func filterFilledButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                LinearGradient(colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
    }
    .buttonStyle(.plain)
}

private func filterOutlineButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(hex: 0x1BCA0B))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color(hex: 0xD7F7D1), in: Capsule())
    }
    .buttonStyle(.plain)
}

private extension AttendanceFilter {
    func with(statuses: Set<String>) -> AttendanceFilter {
        var copy = self
        copy.statuses = statuses
        return copy
    }
}

#Preview {
    @Previewable @State var filter = AttendanceFilter.currentMonth()
    return AttendanceFilterSheet(filter: $filter)
}
