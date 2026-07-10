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
                    Capsule()
                        .fill(Color(hex: 0xCBD0D8))
                        .frame(width: 40, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 14)

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

            pickerOverlay
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(showDatePicker || showDurationPicker)
    }

    @ViewBuilder
    private var pickerOverlay: some View {
        if showDatePicker {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    closePickerOverlay()
                }
                .transition(.opacity)
                .zIndex(10)

            pickerSheet(title: "Permission Date", subtitle: "Select Date") {
                DatePicker("Permission Date", selection: $draftDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, 8)
            } onDone: {
                selectedDate = draftDate
            }
            .frame(height: 500)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(11)
        } else if showDurationPicker {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    closePickerOverlay()
                }
                .transition(.opacity)
                .zIndex(10)

            pickerSheet(title: "Fill Permission Summary", subtitle: "Information about Permission details") {
                VStack(spacing: 16) {
                    timePickerRow(title: "From Time", selection: $draftFromTime)
                    timePickerRow(title: "To Time", selection: $draftToTime)
                    Text(draftDurationLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isDraftDurationValid ? Color(hex: 0x667085) : Color(hex: 0xB42318))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
            } onDone: {
                selectedFromTime = draftFromTime
                selectedToTime = draftToTime
            }
            .frame(height: 560)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(11)
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

    private func pickerSheet<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content,
        onDone: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xCBD0D8))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.height > 32 {
                                closePickerOverlay()
                            }
                        }
                )

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.horizontal, 20)
            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .padding(.horizontal, 20)
                .padding(.top, 3)

            content()
                .padding(.top, 16)

            Spacer(minLength: 12)

            Button {
                onDone()
                showDatePicker = false
                showDurationPicker = false
            } label: {
                Text("Select")
                    .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(selectButtonFill(title: title), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(title != "Permission Date" && !isDraftDurationValid)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let mostlyVertical = abs(value.translation.height) > abs(value.translation.width)
                    if mostlyVertical && value.translation.height > 64 {
                        closePickerOverlay()
                    }
                }
        )
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 28, bottomLeading: 0, bottomTrailing: 0, topTrailing: 28),
                style: .continuous
            )
            .fill(Color.white)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func timePickerRow(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: 0x344054))
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .clipped()
                .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .clipped()
    }

    private func closePickerOverlay() {
        withAnimation(.snappy(duration: 0.2)) {
            showDatePicker = false
            showDurationPicker = false
        }
    }

    private var submitEnabled: Bool {
        selectedDate != nil && selectedFromTime != nil && selectedToTime != nil && isValidTimeRange
    }

    private var isValidTimeRange: Bool {
        guard let selectedFromTime, let selectedToTime else { return false }
        return minutesBetween(from: selectedFromTime, to: selectedToTime) > 0
    }

    private var isDraftDurationValid: Bool {
        minutesBetween(from: draftFromTime, to: draftToTime) > 0
    }

    private var durationValue: String {
        guard let selectedFromTime, let selectedToTime else { return "Select Duration" }
        return "\(timeLabel(selectedFromTime)) - \(timeLabel(selectedToTime))"
    }

    private var draftDurationLabel: String {
        let minutes = minutesBetween(from: draftFromTime, to: draftToTime)
        guard minutes > 0 else { return "Invalid time range" }
        return "Total \(durationLabel(minutes: minutes))"
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

    private func durationLabel(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
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

    private func selectButtonFill(title: String) -> LinearGradient {
        title != "Permission Date" && !isDraftDurationValid ? disabledButtonFill : enabledButtonFill
    }
}
