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
        Form {
            Section("Date") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section("Time") {
                DatePicker("From", selection: $fromTime, displayedComponents: .hourAndMinute)
                DatePicker("To", selection: $toTime, displayedComponents: .hourAndMinute)
            }

            Section("Reason") {
                TextField("Reason for permission", text: $reason, axis: .vertical)
                    .lineLimit(2...4)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Apply Permission")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Submit") { submit() }
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
    }

    private func submit() {
        guard let token = authStore.currentSession?.token else { return }

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
}
