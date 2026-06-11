import SwiftUI

struct ApplyPermissionView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var fromTime = Date()
    @State private var toTime = Date().addingTimeInterval(3600)
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var onApplied: (() -> Void)?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    permissionDateField(title: "Date", date: $date, components: .date, placeholder: "Select date")
                    permissionDateField(title: "From Time", date: $fromTime, components: .hourAndMinute, placeholder: "Select time")
                    permissionDateField(title: "To Time", date: $toTime, components: .hourAndMinute, placeholder: "Select time")

                    Text(durationLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isValidTimeRange ? Color(hex: 0x667085) : Color(hex: 0xB42318))
                        .padding(.top, -10)

                    permissionTextEditor(title: "Reason", placeholder: "Enter reason for permission", text: $reason)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 96)
            }

            Button {
                submit()
            } label: {
                Text(isSubmitting ? "Submitting..." : "Submit Permission Request")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .background(.ultraThinMaterial)
            .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
        }
        .navigationTitle("Apply for Permission")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func submit() {
        guard let token = authStore.currentSession?.token else { return }
        guard isValidTimeRange else {
            errorMessage = "To time must be after from time."
            return
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"

        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                _ = try await HRConvexAPIService.applyPermission(
                    token: token,
                    date: df.string(from: date),
                    fromTime: tf.string(from: fromTime),
                    toTime: tf.string(from: toTime),
                    reason: reason.trimmingCharacters(in: .whitespaces)
                )
                onApplied?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var isValidTimeRange: Bool {
        permissionMinutes > 0
    }

    private var permissionMinutes: Int {
        let calendar = Calendar.current
        let fromComponents = calendar.dateComponents([.hour, .minute], from: fromTime)
        let toComponents = calendar.dateComponents([.hour, .minute], from: toTime)
        let fromMinutes = (fromComponents.hour ?? 0) * 60 + (fromComponents.minute ?? 0)
        let toMinutes = (toComponents.hour ?? 0) * 60 + (toComponents.minute ?? 0)
        return toMinutes - fromMinutes
    }

    private var durationLabel: String {
        guard permissionMinutes > 0 else { return "Invalid time range" }
        let h = permissionMinutes / 60
        let m = permissionMinutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    private func permissionDateField(
        title: String,
        date: Binding<Date>,
        components: DatePickerComponents,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
            HStack {
                DatePicker(placeholder, selection: date, displayedComponents: components)
                    .labelsHidden()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func permissionTextEditor(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
            TextField(placeholder, text: text, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(5...8)
                .padding(16)
                .frame(minHeight: 120, alignment: .topLeading)
                .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
