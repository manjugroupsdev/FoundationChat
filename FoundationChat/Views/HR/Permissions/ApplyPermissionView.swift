import SwiftUI

struct ApplyPermissionView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date?
    @State private var selectedFromTime: Date?
    @State private var selectedToTime: Date?
    @State private var draftDate = Date()
    @State private var draftFromTime = Date()
    @State private var draftToTime = Date().addingTimeInterval(3600)
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showDatePicker = false
    @State private var showDurationPicker = false

    var onApplied: (() -> Void)?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Fill Permission Summary")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))

                    Text("Information about Permission details")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .padding(.top, 2)

                    pickerField(
                        title: "Permission Date",
                        value: selectedDate.map(dateLabel) ?? "Select Date",
                        placeholder: selectedDate == nil,
                        icon: "calendar",
                        topPadding: 22
                    ) {
                        draftDate = selectedDate ?? Date()
                        showDatePicker = true
                    }

                    pickerField(
                        title: "Permission Duration",
                        value: durationValue,
                        placeholder: selectedFromTime == nil || selectedToTime == nil,
                        icon: "clock",
                        topPadding: 16
                    ) {
                        draftFromTime = selectedFromTime ?? Date()
                        draftToTime = selectedToTime ?? Date().addingTimeInterval(3600)
                        showDurationPicker = true
                    }

                    permissionDescriptionField
                        .padding(.top, 16)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 96)
            }

            Button {
                submit()
            } label: {
                ZStack {
                    Text("Submit Now")
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(isSubmitting ? 0 : 1)
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(submitEnabled ? enabledButtonFill : disabledButtonFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!submitEnabled || isSubmitting)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .background(Color.white.opacity(0.98).ignoresSafeArea(edges: .bottom))

        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDatePicker) {
            PermissionDatePickerSheet(selection: $draftDate) {
                selectedDate = draftDate
            }
            .presentationDetents([.height(470)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDurationPicker) {
            PermissionDurationPickerSheet(
                fromTime: $draftFromTime,
                toTime: $draftToTime
            ) {
                selectedFromTime = draftFromTime
                selectedToTime = draftToTime
            }
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.visible)
        }
    }

    private var permissionDescriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permission Description")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: 0x344054))

            TextField("Enter Permission Description", text: $reason, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(4...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
                }
        }
    }

    private func pickerField(
        title: String,
        value: String,
        placeholder: Bool,
        icon: String,
        topPadding: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: 0x344054))

            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))
                        .frame(width: 22)
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(placeholder ? Color(hex: 0x9CA3AF) : Color(hex: 0x101828))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, topPadding)
    }

    private var submitEnabled: Bool {
        selectedDate != nil && selectedFromTime != nil && selectedToTime != nil && isValidTimeRange
    }

    private var isValidTimeRange: Bool {
        guard let selectedFromTime, let selectedToTime else { return false }
        return minutesBetween(from: selectedFromTime, to: selectedToTime) > 0
    }

    private var durationValue: String {
        guard let selectedFromTime, let selectedToTime else { return "Select Duration" }
        return "\(timeLabel(selectedFromTime)) - \(timeLabel(selectedToTime))"
    }

    private func submit() {
        guard let token = authStore.currentSession?.token,
              let selectedDate,
              let selectedFromTime,
              let selectedToTime
        else { return }
        guard isValidTimeRange else {
            errorMessage = "To time must be after from time."
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                _ = try await HRConvexAPIService.applyPermission(
                    token: token,
                    date: apiDateLabel(selectedDate),
                    fromTime: apiTimeLabel(selectedFromTime),
                    toTime: apiTimeLabel(selectedToTime),
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                onApplied?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func minutesBetween(from: Date, to: Date) -> Int {
        let calendar = Calendar.current
        let fromComponents = calendar.dateComponents([.hour, .minute], from: from)
        let toComponents = calendar.dateComponents([.hour, .minute], from: to)
        let fromMinutes = (fromComponents.hour ?? 0) * 60 + (fromComponents.minute ?? 0)
        let toMinutes = (toComponents.hour ?? 0) * 60 + (toComponents.minute ?? 0)
        return toMinutes - fromMinutes
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func apiDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func apiTimeLabel(_ date: Date) -> String {
        timeLabel(date)
    }

    private var enabledButtonFill: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var disabledButtonFill: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xE5E7EB), Color(hex: 0xD1D5DB)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

}

private struct PermissionDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Date

    let onSelect: () -> Void

    var body: some View {
        NavigationStack {
            DatePicker(
                "Permission Date",
                selection: $selection,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Permission Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSelect()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PermissionDurationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fromTime: Date
    @Binding var toTime: Date

    let onSelect: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                timePickerRow(title: "From Time", selection: $fromTime)
                timePickerRow(title: "To Time", selection: $toTime)

                Text(durationSummary)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(isValidDuration ? .secondary : Color(hex: 0xB42318))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("Permission Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSelect()
                        dismiss()
                    }
                    .disabled(!isValidDuration)
                }
            }
        }
    }

    private func timePickerRow(title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    private var isValidDuration: Bool {
        durationMinutes > 0
    }

    private var durationSummary: String {
        guard durationMinutes > 0 else { return "To time must be after from time." }
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        if hours == 0 { return "Total \(minutes) min" }
        if minutes == 0 { return "Total \(hours)h" }
        return "Total \(hours)h \(minutes)m"
    }

    private var durationMinutes: Int {
        let calendar = Calendar.current
        let fromComponents = calendar.dateComponents([.hour, .minute], from: fromTime)
        let toComponents = calendar.dateComponents([.hour, .minute], from: toTime)
        let fromMinutes = (fromComponents.hour ?? 0) * 60 + (fromComponents.minute ?? 0)
        let toMinutes = (toComponents.hour ?? 0) * 60 + (toComponents.minute ?? 0)
        return toMinutes - fromMinutes
    }
}
