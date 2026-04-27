import SwiftUI

struct NotificationsListView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if notifications.isEmpty && !isLoading {
                    ContentUnavailableView("No Notifications", systemImage: "bell.slash", description: Text("You're all caught up!"))
                }

                ForEach(notifications) { notification in
                    notificationRow(notification)
                        .onTapGesture {
                            markRead(notification)
                        }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Read All") {
                        markAllRead()
                    }
                    .disabled(notifications.allSatisfy { !$0.isUnread })
                }
            }
            .refreshable { loadData() }
            .overlay {
                if isLoading && notifications.isEmpty { ProgressView() }
            }
            .task { loadData() }
        }
    }

    private func notificationRow(_ notification: AppNotification) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notification.icon)
                .font(.title3)
                .foregroundStyle(colorFromString(notification.iconColor))
                .frame(width: 36, height: 36)
                .background(colorFromString(notification.iconColor).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title ?? "Notification")
                    .font(.subheadline.weight(notification.isUnread ? .semibold : .regular))
                if let message = notification.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let date = notification.createdDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if notification.isUnread {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
        .opacity(notification.isUnread ? 1 : 0.7)
    }

    private func colorFromString(_ name: String) -> Color {
        switch name {
        case "green": return .green
        case "red": return .red
        case "blue": return .blue
        case "orange": return .orange
        default: return .secondary
        }
    }

    private func loadData() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                notifications = try await authStore.fetchNotifications()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func markRead(_ notification: AppNotification) {
        guard notification.isUnread else { return }
        Task {
            try? await authStore.markNotificationRead(id: notification._id)
            loadData()
        }
    }

    private func markAllRead() {
        Task {
            try? await authStore.markAllNotificationsRead()
            loadData()
        }
    }
}
