import SwiftUI

struct StatusPickerView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: PresenceStatus = .online
    @State private var customText = ""
    @State private var customEmoji = ""
    @State private var isSaving = false

    private let quickStatuses = [
        ("📍", "In the office"),
        ("🏠", "Working from home"),
        ("🏖️", "On vacation"),
        ("🤒", "Out sick"),
        ("📅", "In a meeting"),
        ("🎧", "Focusing"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    ForEach(PresenceStatus.allCases) { (status: PresenceStatus) in
                        Button {
                            selectedStatus = status
                        } label: {
                            HStack {
                                PresenceIndicatorView(status: status, size: 10)
                                Text(status.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedStatus == status {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                Section("Custom Status") {
                    HStack {
                        TextField("Emoji", text: $customEmoji)
                            .frame(width: 40)
                        TextField("What's your status?", text: $customText)
                    }
                }

                Section("Quick Set") {
                    ForEach(quickStatuses, id: \.1) { emoji, text in
                        Button {
                            customEmoji = emoji
                            customText = text
                        } label: {
                            HStack {
                                Text(emoji)
                                Text(text)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                if !customText.isEmpty || !customEmoji.isEmpty {
                    Section {
                        Button("Clear Custom Status", role: .destructive) {
                            customText = ""
                            customEmoji = ""
                        }
                    }
                }
            }
            .navigationTitle("Set Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveStatus() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
        }
    }

    private func saveStatus() async {
        isSaving = true
        do {
            try await authStore.setPresenceStatus(
                status: selectedStatus,
                customStatusText: customText.isEmpty ? nil : customText,
                customStatusEmoji: customEmoji.isEmpty ? nil : customEmoji
            )
            dismiss()
        } catch {}
        isSaving = false
    }
}
