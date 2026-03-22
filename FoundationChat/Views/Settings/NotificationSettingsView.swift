import SwiftUI

struct NotificationSettingsView: View {
    let targetType: String  // "dm" or "channel"
    let targetId: String
    let targetName: String

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: NotificationLevel = .all
    @State private var isMuted = false
    @State private var isLoading = true
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(NotificationLevel.allCases, id: \.self) { level in
                        Button {
                            selectedLevel = level
                        } label: {
                            HStack {
                                Image(systemName: level.systemImage)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.displayName)
                                        .foregroundStyle(.primary)
                                    Text(descriptionFor(level))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedLevel == level {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Notifications for \(targetName)")
                }

                Section {
                    Toggle("Mute", isOn: $isMuted)
                } footer: {
                    Text("Muted conversations won't send push notifications.")
                }
            }
            .navigationTitle("Notifications")
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
                    .disabled(isSaving)
                }
            }
            .task {
                await loadPreference()
            }
        }
    }

    private func descriptionFor(_ level: NotificationLevel) -> String {
        switch level {
        case .all: return "Notify for all messages"
        case .mentions: return "Only when you're mentioned"
        case .none: return "No notifications"
        }
    }

    private func loadPreference() async {
        isLoading = true
        do {
            if let pref = try await authStore.fetchNotificationPreference(targetType: targetType, targetId: targetId) {
                selectedLevel = pref.notificationLevel
                isMuted = pref.muteUntil != nil
            }
        } catch {}
        isLoading = false
    }

    private func save() async {
        isSaving = true
        do {
            let muteUntil: Double? = isMuted ? Double(Date.distantFuture.timeIntervalSince1970 * 1000) : nil
            try await authStore.upsertNotificationPreference(
                targetType: targetType,
                targetId: targetId,
                level: selectedLevel,
                muteUntil: muteUntil
            )
            dismiss()
        } catch {}
        isSaving = false
    }
}
