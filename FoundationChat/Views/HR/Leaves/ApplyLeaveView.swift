import SwiftUI

struct ApplyLeaveView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var leaveType = "casual"
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var onApplied: (() -> Void)?

    private let leaveTypes = [
        ("casual", "Casual Leave"),
        ("sick", "Sick Leave"),
        ("earned", "Earned Leave"),
        ("unpaid", "Unpaid Leave"),
        ("compensatory", "Compensatory Off"),
    ]

    var body: some View {
        Form {
            Section("Leave Type") {
                Picker("Type", selection: $leaveType) {
                    ForEach(leaveTypes, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Duration") {
                DatePicker("From", selection: $fromDate, displayedComponents: .date)
                DatePicker("To", selection: $toDate, in: fromDate..., displayedComponents: .date)

                let days = Calendar.current.dateComponents([.day], from: fromDate, to: toDate).day.map { $0 + 1 } ?? 1
                Text("\(days) day\(days > 1 ? "s" : "")")
                    .foregroundStyle(.secondary)
            }

            Section("Reason") {
                TextField("Why do you need leave?", text: $reason, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Apply Leave")
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
