import SwiftUI

struct ApplyLeaveView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var leaveTypes = ["casual", "sick", "earned"]
    @State private var selectedLeaveType = "casual"
    @State private var fromDate: Date?
    @State private var toDate: Date?
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showCategorySheet = false
    @State private var showDurationSheet = false
    @State private var showSubmitConfirmation = false
    @FocusState private var isReasonFocused: Bool

    var onApplied: (() -> Void)?

    private var canSubmit: Bool {
        fromDate != nil && toDate != nil && !isSubmitting
    }

    private var selectedLeaveTypeLabel: String {
        prettyType(selectedLeaveType)
    }

    private var durationLabel: String {
        guard let fromDate, let toDate else { return "Select Duration" }
        if Calendar.current.isDate(fromDate, inSameDayAs: toDate) {
            return Self.labelDateFormatter.string(from: fromDate)
        }
        return "\(Self.labelDateFormatter.string(from: fromDate)) - \(Self.labelDateFormatter.string(from: toDate))"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Capsule()
                        .fill(Color(hex: 0xD0D5DD))
                        .frame(width: 40, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 14)

                    Text("Fill Leave Information")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))

                    Text("Information about leave details")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .padding(.top, 2)

                    fieldLabel("Leave Category")
                        .padding(.top, 16)
                    applyField(icon: "doc.text", value: selectedLeaveTypeLabel, action: { showCategorySheet = true })

                    fieldLabel("Leave Duration")
                        .padding(.top, 16)
                    applyField(icon: "calendar", value: durationLabel, action: { showDurationSheet = true })

                    fieldLabel("Leave Description")
                        .padding(.top, 16)
                    TextField("Enter Leave Description", text: $reason, axis: .vertical)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(4...6)
                        .focused($isReasonFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 90, alignment: .topLeading)
                        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
                        }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                            .padding(.top, 10)
                    }

                    Button {
                        promptSubmitConfirmation()
                    } label: {
                        ZStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Submit Now")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(submitBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .padding(.top, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    if isReasonFocused {
                        dismissKeyboard()
                    }
                }
            )
        }
        .background(Color.white)
        .task { await loadLeaveTypes() }
        .onDisappear {
            dismissKeyboard()
        }
        .sheet(isPresented: $showCategorySheet) {
            LeaveCategorySheet(
                leaveTypes: leaveTypes,
                selectedType: selectedLeaveType,
                onClose: { showCategorySheet = false },
                onSubmit: { type in
                    selectedLeaveType = type
                    showCategorySheet = false
                }
            )
            .presentationDetents([.height(categorySheetHeight)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showDurationSheet) {
            LeaveDurationSheet(
                initialFromDate: fromDate,
                initialToDate: toDate,
                onClose: { showDurationSheet = false },
                onSubmit: { pickedFrom, pickedTo in
                    fromDate = min(pickedFrom, pickedTo)
                    toDate = max(pickedFrom, pickedTo)
                    showDurationSheet = false
                }
            )
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showSubmitConfirmation) {
            SubmitLeaveConfirmSheet(
                isSubmitting: isSubmitting,
                onCancel: { showSubmitConfirmation = false },
                onSubmit: { submit() }
            )
            .presentationDetents([.height(248)])
            .presentationDragIndicator(.hidden)
        }
    }

    private var submitBackground: some ShapeStyle {
        canSubmit
            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)], startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(Color(hex: 0xD0D5DD))
    }

    private var categorySheetHeight: CGFloat {
        CGFloat(168 + max(leaveTypes.count, 1) * 54)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(hex: 0x344054))
            .padding(.bottom, 6)
    }

    private func applyField(icon: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 20)
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(value.hasPrefix("Select") ? Color(hex: 0x9CA3AF) : Color(hex: 0x101828))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func promptSubmitConfirmation() {
        dismissKeyboard()
        guard let fromDate, let toDate else {
            errorMessage = "Select leave duration"
            return
        }
        guard toDate >= fromDate else {
            errorMessage = "To date must be on or after from date"
            return
        }
        errorMessage = nil
        showSubmitConfirmation = true
    }

    private func submit() {
        dismissKeyboard()
        guard let token = authStore.currentSession?.token else { return }
        guard let fromDate, let toDate else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                _ = try await HRConvexAPIService.applyLeave(
                    token: token,
                    leaveType: selectedLeaveType,
                    fromDate: Self.apiDateFormatter.string(from: min(fromDate, toDate)),
                    toDate: Self.apiDateFormatter.string(from: max(fromDate, toDate)),
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                onApplied?()
                dismiss()
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                showSubmitConfirmation = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadLeaveTypes() async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            let policy = try await HRConvexAPIService.getLeavePolicy(token: token)
            var types: [String] = []
            if (policy?.casualPerYear ?? 1) > 0 { types.append("casual") }
            if (policy?.sickPerYear ?? 1) > 0 { types.append("sick") }
            if (policy?.earnedPerYear ?? 1) > 0 { types.append("earned") }
            for type in policy?.types ?? [] where !["casual", "sick", "earned"].contains(type) && !types.contains(type) {
                types.append(type)
            }
            if !types.isEmpty {
                leaveTypes = types
                selectedLeaveType = types.first ?? selectedLeaveType
            }
        } catch {
            // Android keeps defaults when policy fails; mirror that.
        }
    }

    private func dismissKeyboard() {
        isReasonFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func prettyType(_ value: String) -> String {
        let base = value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst().lowercased()
            }
            .joined(separator: " ")
        return base.localizedCaseInsensitiveContains("leave") ? base : "\(base) Leave"
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let labelDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()
}

private struct LeaveCategorySheet: View {
    let leaveTypes: [String]
    let selectedType: String
    let onClose: () -> Void
    let onSubmit: (String) -> Void

    @State private var draftType: String

    init(leaveTypes: [String], selectedType: String, onClose: @escaping () -> Void, onSubmit: @escaping (String) -> Void) {
        self.leaveTypes = leaveTypes
        self.selectedType = selectedType
        self.onClose = onClose
        self.onSubmit = onSubmit
        _draftType = State(initialValue: selectedType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHandle

            Text("Leave Category")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Text("Select Leave category")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .padding(.top, 2)

            VStack(spacing: 8) {
                ForEach(leaveTypes, id: \.self) { type in
                    Button {
                        draftType = type
                    } label: {
                        HStack {
                            Text(prettyType(type))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(hex: 0x101828))
                            Spacer()
                            Image(systemName: draftType == type ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(draftType == type ? Color(hex: 0x1BCA0B) : Color(hex: 0x98A2B3))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(draftType == type ? Color(hex: 0xEAF8E8) : Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(draftType == type ? Color(hex: 0x1BCA0B).opacity(0.35) : Color(hex: 0xEAECF0), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)

            HStack(spacing: 12) {
                outlineButton("Close Message", action: onClose)
                filledButton("Submit") { onSubmit(draftType) }
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .background(Color.white)
    }

    private var sheetHandle: some View {
        Capsule()
            .fill(Color(hex: 0xD0D5DD))
            .frame(width: 40, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)
    }

    private func prettyType(_ value: String) -> String {
        let base = value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return base.localizedCaseInsensitiveContains("leave") ? base : "\(base) Leave"
    }
}

private struct LeaveDurationSheet: View {
    let initialFromDate: Date?
    let initialToDate: Date?
    let onClose: () -> Void
    let onSubmit: (Date, Date) -> Void

    @State private var displayedMonth: Date
    @State private var draftFromDate: Date?
    @State private var draftToDate: Date?

    init(initialFromDate: Date?, initialToDate: Date?, onClose: @escaping () -> Void, onSubmit: @escaping (Date, Date) -> Void) {
        self.initialFromDate = initialFromDate
        self.initialToDate = initialToDate
        self.onClose = onClose
        self.onSubmit = onSubmit
        let baseDate = initialFromDate ?? Date()
        _displayedMonth = State(initialValue: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: baseDate)) ?? baseDate)
        _draftFromDate = State(initialValue: initialFromDate)
        _draftToDate = State(initialValue: initialToDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHandle

            Text("Leave Duration")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Text("Select Leave Duration")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .padding(.top, 2)

            HStack {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(Self.monthFormatter.string(from: displayedMonth))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)

            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 24)
            .background(Color(hex: 0xEEF0F5))
            .padding(.top, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(monthGridDays, id: \.self) { date in
                    dayCell(date)
                }
            }
            .padding(.top, 6)

            filledButton("Submit Date") {
                guard let draftFromDate else { return }
                onSubmit(draftFromDate, draftToDate ?? draftFromDate)
            }
            .padding(.top, 16)
            .disabled(draftFromDate == nil)

            outlineButton("Close Message", action: onClose)
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .background(Color.white)
    }

    private var sheetHandle: some View {
        Capsule()
            .fill(Color(hex: 0xD0D5DD))
            .frame(width: 40, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)
    }

    private var monthGridDays: [Date] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
        let weekdayOffset = calendar.component(.weekday, from: monthStart) - 1
        let firstVisible = calendar.date(byAdding: .day, value: -weekdayOffset, to: monthStart) ?? monthStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstVisible) }
    }

    private func dayCell(_ date: Date) -> some View {
        let calendar = Calendar.current
        let inCurrentMonth = calendar.component(.month, from: date) == calendar.component(.month, from: displayedMonth)
            && calendar.component(.year, from: date) == calendar.component(.year, from: displayedMonth)
        let selectedStart = draftFromDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let selectedEnd = draftToDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let inRange = isInRange(date)

        return Button {
            guard inCurrentMonth else { return }
            select(date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 12, weight: selectedStart || selectedEnd ? .bold : .regular))
                .foregroundStyle(dayTextColor(inCurrentMonth: inCurrentMonth, selected: selectedStart || selectedEnd))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if selectedStart || selectedEnd {
                        Circle().fill(Color(hex: 0x1BCA0B))
                    } else if inRange {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: 0xEAF8E8))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!inCurrentMonth)
    }

    private func dayTextColor(inCurrentMonth: Bool, selected: Bool) -> Color {
        if selected { return .white }
        return inCurrentMonth ? Color(hex: 0x101828) : Color(hex: 0x98A2B3)
    }

    private func isInRange(_ date: Date) -> Bool {
        guard let draftFromDate, let draftToDate else { return false }
        let start = min(draftFromDate, draftToDate)
        let end = max(draftFromDate, draftToDate)
        return date >= Calendar.current.startOfDay(for: start) && date <= Calendar.current.startOfDay(for: end)
    }

    private func select(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        if draftFromDate == nil || draftToDate != nil {
            draftFromDate = normalized
            draftToDate = nil
        } else if let from = draftFromDate, normalized < from {
            draftToDate = from
            draftFromDate = normalized
        } else {
            draftToDate = normalized
        }
    }

    private func changeMonth(_ value: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }

    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}

private struct SubmitLeaveConfirmSheet: View {
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0xEAF8E8))
                    .frame(width: 58, height: 58)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1BCA0B))
            }
            .padding(.top, 20)

            Text("Submit Leave")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.top, 10)

            Text("Double-check your leave details to ensure everything is correct. Do you want to proceed?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            HStack(spacing: 12) {
                outlineButton("Close Message", action: onCancel)
                filledButton(isSubmitting ? "Submitting..." : "Submit") {
                    onSubmit()
                }
                .disabled(isSubmitting)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .background(Color.white)
    }
}

private func filledButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
    }
    .buttonStyle(.plain)
}

private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: 0x1BCA0B))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(hex: 0x1BCA0B), lineWidth: 1)
            }
    }
    .buttonStyle(.plain)
}
