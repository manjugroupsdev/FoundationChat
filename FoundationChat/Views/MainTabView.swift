import SwiftUI

enum AppTab: Hashable {
    case home
    case hr
    case chats
    case apps
    /// Legacy values retained so navigation routes that originally targeted
    /// these tabs still compile. Channel deep-links land on the unified Chat
    /// tab; updates and files have been consolidated into Home / Chat / Apps.
    case channels
    case updates
    case files
}

struct MainTabView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var selectedTab: AppTab = .home
    @State private var openConversationIDFromPush: String?
    @State private var openChannelIDFromPush: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            HRDashboardView()
                .tabItem {
                    Label {
                        Text("Attendance")
                    } icon: {
                        Image("AttendanceTabIcon")
                    }
                }
                .tag(AppTab.hr)

            ConversationsListView(
                selectedTab: $selectedTab,
                openConversationID: openConversationIDFromPush
            ) {
                openConversationIDFromPush = nil
            }
            .tabItem {
                Label("Chat", systemImage: "message.fill")
            }
            .tag(AppTab.chats)

            AppLibraryView()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.2x2.fill")
                }
                .tag(AppTab.apps)
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
            selectedTab = .chats
            openChannelIDFromPush = channelID
        case .leaveRequest, .leaveApproved, .leaveRejected,
             .permissionRequest, .permissionApproved, .permissionRejected:
            selectedTab = .hr
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
