import SwiftUI

struct CallFollowUpFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var remarks = ""
    @State private var nextFollowUpDate = Date()
    @State private var hasFollowUp = false
    @State private var callStatusId = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    let callLogId: Int
    let onSaved: () async -> Void

    private let api = HRAPIService.shared

    private var isValid: Bool {
        !remarks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Follow Up Details") {
                    TextField("Remarks", text: $remarks, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Next Follow Up") {
                    Toggle("Schedule Follow Up", isOn: $hasFollowUp)
                    if hasFollowUp {
                        DatePicker("Follow Up Date", selection: $nextFollowUpDate, displayedComponents: .date)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Follow Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || isSaving)
                }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        do {
            _ = try await api.saveLeadFollowup(
                callLogId: callLogId,
                nextReviewDate: hasFollowUp ? df.string(from: nextFollowUpDate) : "",
                remarks: remarks.trimmingCharacters(in: .whitespacesAndNewlines),
                callStatusId: callStatusId,
                userId: 1
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
