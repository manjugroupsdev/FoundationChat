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

    init(filter: Binding<AttendanceFilter>) {
        self._filter = filter
        self._draft = State(initialValue: filter.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 8) {
                            presetButton("This month") { applyThisMonth() }
                            presetButton("Last month") { applyLastMonth() }
                            presetButton("Last 7days") { applyLast7Days() }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Date Range")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x475467))
                            HStack(spacing: 10) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(Color(hex: 0x0B61CA))
                                Text(draft.rangeLabel)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color(hex: 0x101828))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10))

                            DatePicker("From", selection: $draft.fromDate, in: ...draft.toDate, displayedComponents: .date)
                            DatePicker("To", selection: $draft.toDate, in: draft.fromDate...Date(), displayedComponents: .date)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x475467))
                            statusToggle("All", isOn: draft.isAllStatuses) {
                                draft.statuses.removeAll()
                            }
                            ForEach(AttendanceFilter.availableStatuses, id: \.self) { status in
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
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                }

                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Color(hex: 0x1BCA0B))
                        .frame(maxWidth: .infinity)

                    Button("Select") {
                        if draft.fromDate > draft.toDate {
                            let tmp = draft.fromDate
                            draft.fromDate = draft.toDate
                            draft.toDate = tmp
                        }
                        filter = draft
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color(hex: 0x1BCA0B))
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(.white)
        }
    }

    private var header: some View {
        ZStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Color(hex: 0x0B61CA))
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
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10))
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
