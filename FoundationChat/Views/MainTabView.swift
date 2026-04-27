import SwiftUI

enum AppTab: Hashable {
    case chats
    case files
    case channels
    case updates
    case apps
    case hr
}

struct MainTabView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var selectedTab: AppTab = .chats
    @State private var openConversationIDFromPush: String?
    @State private var openChannelIDFromPush: String?
    @State private var unreadNotificationCount: Int = 0
    @State private var badgePollingTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $selectedTab) {
            ConversationsListView(
                selectedTab: $selectedTab,
                openConversationID: openConversationIDFromPush
            ) {
                openConversationIDFromPush = nil
            }
            .tabItem {
                Label("Chats", systemImage: "message.fill")
            }
            .tag(AppTab.chats)

            FilesTabView()
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }
                .tag(AppTab.files)

            ChannelsTabView(openChannelID: openChannelIDFromPush) {
                openChannelIDFromPush = nil
            }
            .tabItem {
                Label("Channels", systemImage: "person.3.fill")
            }
            .tag(AppTab.channels)

            NotificationsListView()
                .tabItem {
                    Label("Notifications", systemImage: "bell.fill")
                }
                .tag(AppTab.updates)
                .badge(unreadNotificationCount)

            AppLibraryView()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.2x2.fill")
                }
                .tag(AppTab.apps)

            HRDashboardView()
                .tabItem {
                    Label("HR", systemImage: "briefcase.fill")
                }
                .tag(AppTab.hr)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNavigationRoute)) { notification in
            guard let route = notification.object as? PushNavigationRoute else { return }
            applyPushRoute(route)
        }
        .task {
            if let pending = await MainActor.run(body: {
                PushNavigationCoordinator.shared.consumePendingRoute()
            }) {
                applyPushRoute(pending)
            }
            startBadgePolling()
        }
        .onDisappear {
            badgePollingTask?.cancel()
        }
    }

    private func applyPushRoute(_ route: PushNavigationRoute) {
        switch route.type {
        case .directMessage:
            guard let conversationID = route.conversationId else { return }
            selectedTab = .chats
            openConversationIDFromPush = conversationID
        case .channelMessage:
            guard let channelID = route.channelId else { return }
            selectedTab = .channels
            openChannelIDFromPush = channelID
        case .leaveRequest, .leaveApproved, .leaveRejected,
             .permissionRequest, .permissionApproved, .permissionRejected:
            selectedTab = .hr
        }
    }

    private func startBadgePolling() {
        badgePollingTask?.cancel()
        badgePollingTask = Task {
            while !Task.isCancelled {
                do {
                    let count = try await authStore.fetchUnreadNotificationCount()
                    unreadNotificationCount = count
                } catch {
                    // Ignore badge polling errors
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
