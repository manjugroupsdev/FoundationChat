import SwiftUI

struct ApplyLeaveView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var leaveType = "casual"
    @State private var duration = "full-day"
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSubmitConfirmation = false

    var onApplied: (() -> Void)?

    private let leaveTypes = [
        ("casual", "Casual Leave"),
        ("sick", "Sick Leave"),
        ("earned", "Earned Leave"),
        ("unpaid", "Unpaid Leave"),
        ("compensatory", "Compensatory Off"),
    ]

    private let durations = [
        ("full-day", "Full Day"),
        ("first-half", "First Half"),
        ("second-half", "Second Half"),
    ]

    private var selectedLeaveTypeLabel: String {
        leaveTypes.first { $0.0 == leaveType }?.1 ?? "Leave"
    }

    private var selectedDurationLabel: String {
        durations.first { $0.0 == duration }?.1 ?? "Full Day"
    }

    private var requestedDays: Double {
        let rawDays = Calendar.current.dateComponents([.day], from: fromDate, to: toDate).day.map { Double($0 + 1) } ?? 1
        return duration == "full-day" ? rawDays : 0.5
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0xF5F6FA)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fill Leave Information")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x101828))
                            Text("Information about leave details")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: 0x98A2B3))
                        }

                        leavePickerField(
                            title: "Leave Category",
                            value: selectedLeaveTypeLabel,
                            icon: "calendar",
                            options: leaveTypes.map(\.1)
                        ) { label in
                            if let match = leaveTypes.first(where: { $0.1 == label }) {
                                leaveType = match.0
                            }
                        }

                        leavePickerField(
                            title: "Leave Duration",
                            value: selectedDurationLabel,
                            icon: "calendar",
                            options: durations.map(\.1)
                        ) { label in
                            if let match = durations.first(where: { $0.1 == label }) {
                                duration = match.0
                                normalizeDatesForDuration()
                            }
                        }

                        leaveDateField(title: "From Date", date: $fromDate)
                            .onChange(of: fromDate) { _, _ in normalizeDatesForDuration() }

                        if duration == "full-day" {
                            leaveDateField(title: "To Date", date: $toDate, range: fromDate...)
                        }

                        Text(daysLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0x667085))

                        leaveTextEditor(
                            title: "Leave Description",
                            placeholder: "Enter Leave Description",
                            text: $reason
                        )
                    }
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 8)
                    .padding(.top, 10)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 90)
            }

            Button {
                normalizeDatesForDuration()
                showSubmitConfirmation = true
            } label: {
                Text(isSubmitting ? "Submitting..." : "Submit Now")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(hex: 0x1BCA0B))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
        }
        .navigationTitle("Apply Leave")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showSubmitConfirmation) {
            SubmitLeaveConfirmSheet(
                summary: "\(selectedLeaveTypeLabel) · \(selectedDurationLabel) · \(daysLabel)",
                isSubmitting: isSubmitting,
                onSubmit: { submit() }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.hidden)
        }
    }

    private var daysLabel: String {
        if requestedDays == 0.5 { return "0.5 day" }
        let days = Int(requestedDays)
        return "\(days) day\(days > 1 ? "s" : "")"
    }

    private func submit() {
        guard let token = authStore.currentSession?.token else { return }
        normalizeDatesForDuration()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                _ = try await HRConvexAPIService.applyLeave(
                    token: token,
                    leaveType: leaveType,
                    fromDate: df.string(from: fromDate),
                    toDate: df.string(from: toDate),
                    reason: reason.trimmingCharacters(in: .whitespaces),
                    duration: duration
                )
                onApplied?()
                dismiss()
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func normalizeDatesForDuration() {
        if duration != "full-day" {
            toDate = fromDate
        }
    }

    private func leavePickerField(
        title: String,
        value: String,
        icon: String,
        options: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x667085))
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { onSelect(option) }
                }
            } label: {
                leaveFieldShell(icon: icon) {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x344054))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func leaveDateField(title: String, date: Binding<Date>, range: PartialRangeFrom<Date>? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x667085))
            leaveFieldShell(icon: "calendar") {
                if let range {
                    DatePicker("", selection: date, in: range, displayedComponents: .date)
                        .labelsHidden()
                } else {
                    DatePicker("", selection: date, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func leaveTextEditor(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x667085))
            TextField(placeholder, text: text, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(4...6)
                .padding(10)
                .frame(minHeight: 90, alignment: .topLeading)
                .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func leaveFieldShell<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .frame(width: 16)
            content()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SubmitLeaveConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: String
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .fill(Color(hex: 0xEAF8E8))
                    .frame(width: 68, height: 68)
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1BCA0B))
            }

            Text("Submit Leave")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            Text("Double-check your leave details to ensure everything is correct. Do you want to proceed?")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x475467))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Text(summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button(isSubmitting ? "Submitting..." : "Submit") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(hex: 0x1BCA0B))
                .frame(maxWidth: .infinity)
                .disabled(isSubmitting)
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
        .background(.white)
    }
}
