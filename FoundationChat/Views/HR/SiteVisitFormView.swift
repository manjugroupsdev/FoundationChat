import SwiftUI

struct SiteVisitFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var statusText = ""
    @State private var statusId = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    let siteVisitId: Int
    let onSaved: () async -> Void

    private let api = HRAPIService.shared

    private var isValid: Bool {
        !statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Update Status") {
                    TextField("Status", text: $statusText)
                    Picker("Status Type", selection: $statusId) {
                        Text("Planned").tag(1)
                        Text("Confirmed").tag(2)
                        Text("Completed").tag(3)
                        Text("Cancelled").tag(4)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Update Site Visit")
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

        do {
            _ = try await api.updateSiteVisitStatus(
                siteVisitId: siteVisitId,
                statusId: statusId,
                statusText: statusText.trimmingCharacters(in: .whitespacesAndNewlines),
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
