import SwiftUI

struct PermissionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var fromTime = Date()
    @State private var toTime = Date()
    @State private var reason = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onSaved: () async -> Void

    private let api = HRAPIService.shared

    private var duration: TimeInterval {
        max(0, toTime.timeIntervalSince(fromTime))
    }

    private var durationText: String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        return String(format: "%02d:%02d", hours, minutes)
    }

    private var isValid: Bool {
        duration > 0 && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date & Time") {
                    DatePicker("Permission Date", selection: $selectedDate, displayedComponents: .date)
                    DatePicker("From Time", selection: $fromTime, displayedComponents: .hourAndMinute)
                    DatePicker("To Time", selection: $toTime, displayedComponents: .hourAndMinute)
                    if duration > 0 {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(durationText)
                                .foregroundStyle(.green)
                                .fontWeight(.semibold)
                        }
                    }
                }

                Section("Details") {
                    TextField("Reason", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Spacer()
                        Text("\(reason.count)/50")
                            .font(.caption2)
                            .foregroundStyle(reason.count > 50 ? .red : .secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New Permission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!isValid || isSaving || reason.count > 50)
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
        let durationMins = Int(duration / 60)

        do {
            // TODO: Get actual employeeId and userId from auth context
            _ = try await api.savePermission(
                employeeId: 1040,
                permissionDate: df.string(from: selectedDate),
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                expectedDurationInMins: durationMins,
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
