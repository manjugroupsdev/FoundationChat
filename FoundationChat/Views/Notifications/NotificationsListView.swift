import SwiftUI

struct NotificationsListView: View {
    @Environment(AuthStore.self) private var authStore
    var onClose: (() -> Void)? = nil

    @State private var notifications: [AppNotification] = []
    @State private var selectedFilter: NotificationListFilter = .all
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredNotifications: [AppNotification] {
        notifications.filter { selectedFilter.includes($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterTabs

                List {
                    if let errorMessage {
                        Section {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if filteredNotifications.isEmpty && !isLoading {
                        ContentUnavailableView(
                            selectedFilter.emptyTitle,
                            systemImage: selectedFilter.emptyIcon,
                            description: Text(selectedFilter.emptyMessage)
                        )
                    }

                    ForEach(filteredNotifications) { notification in
                        Button {
                            open(notification)
                        } label: {
                            notificationRow(notification)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                markRead(notification)
                            } label: {
                                Label("Read", systemImage: "checkmark")
                            }
                            .tint(.blue)
                            .disabled(!notification.isUnread)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { loadData() }
                .overlay {
                    if isLoading && notifications.isEmpty { ProgressView() }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("Back")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Read All") {
                        markAllRead()
                    }
                    .disabled(notifications.allSatisfy { !$0.isUnread })
                }
            }
            .task { loadData() }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var filterTabs: some View {
        Picker("Notification filter", selection: $selectedFilter) {
            ForEach(NotificationListFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
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
                errorMessage = nil
                notifications = try await authStore.fetchNotifications()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func open(_ notification: AppNotification) {
        Task {
            if notification.isUnread {
                try? await authStore.markNotificationRead(id: notification._id)
            }
            if let route = PushNavigationRoute(notification) {
                await MainActor.run {
                    PushNavigationCoordinator.shared.enqueue(route)
                }
            }
            loadData()
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

private enum NotificationListFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case read

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .read: return "Read"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "No Notifications"
        case .unread: return "No Unread Notifications"
        case .read: return "No Read Notifications"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "You're all caught up!"
        case .unread: return "Everything has been read."
        case .read: return "Read notifications will appear here."
        }
    }

    var emptyIcon: String {
        switch self {
        case .all: return "bell.slash"
        case .unread: return "checkmark.circle"
        case .read: return "tray"
        }
    }

    func includes(_ notification: AppNotification) -> Bool {
        switch self {
        case .all:
            return true
        case .unread:
            return notification.isUnread
        case .read:
            return !notification.isUnread
        }
    }
}
