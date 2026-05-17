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

    init() {
        Self.configureTabBarColors()
    }

    private static func configureTabBarColors() {
        let active = UIColor(red: 0.106, green: 0.792, blue: 0.043, alpha: 1)
        let inactive = UIColor(red: 0.6, green: 0.615, blue: 0.635, alpha: 1)
        let tabBar = UITabBar.appearance()
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        [appearance.stackedLayoutAppearance,
         appearance.inlineLayoutAppearance,
         appearance.compactInlineLayoutAppearance].forEach { itemAppearance in
            itemAppearance.normal.iconColor = inactive
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: inactive]
            itemAppearance.selected.iconColor = active
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: active]
        }
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = active
        tabBar.unselectedItemTintColor = inactive
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label {
                        Text("Home")
                    } icon: {
                        Image("AndroidNavHomeIcon")
                    }
                }
                .tag(AppTab.home)

            HRDashboardView()
                .tabItem {
                    Label {
                        Text("Attendance")
                    } icon: {
                        Image("AndroidNavAttendanceIcon")
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
                Label {
                    Text("Chat")
                } icon: {
                    Image("AndroidNavChatIcon")
                }
            }
            .tag(AppTab.chats)

            AppLibraryView()
                .tabItem {
                    Label {
                        Text("Apps")
                    } icon: {
                        Image("AndroidNavAppsIcon")
                    }
                }
                .tag(AppTab.apps)
        }
        .onAppear {
            Self.configureTabBarColors()
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
