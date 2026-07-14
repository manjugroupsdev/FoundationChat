import SwiftUI
import UIKit

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
    @State private var openHRRouteFromPush: HRDashboardRoute?
    @State private var hasPlayedHomeEntryAnimation = false

    init() {
        Self.configureTabBarColors()
    }

    private static func configureTabBarColors() {
        let active = UIColor(red: 0.106, green: 0.792, blue: 0.043, alpha: 1)
        let inactive = UIColor(red: 0.6, green: 0.615, blue: 0.635, alpha: 1)
        let tabBar = UITabBar.appearance()
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        appearance.backgroundColor = UIColor.white.withAlphaComponent(0.62)
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
            HomeView(hasPlayedEntryAnimation: $hasPlayedHomeEntryAnimation)
                .tabItem {
                    Label {
                        Text("Home")
                    } icon: {
                        Image("AndroidNavHomeIcon")
                    }
                }
                .tag(AppTab.home)

            HRDashboardView(openRoute: openHRRouteFromPush) {
                openHRRouteFromPush = nil
            }
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
                openConversationID: openConversationIDFromPush,
                openChannelID: openChannelIDFromPush
            ) {
                openConversationIDFromPush = nil
            } onOpenChannelHandled: {
                openChannelIDFromPush = nil
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
        .tabBarMinimizeOnScrollIfAvailable()
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
        case .leaveRequest, .leaveApproved, .leaveRejected:
            selectedTab = .hr
            openHRRouteFromPush = route.workflowTargetMode?.lowercased() == "approval" ? .leaveApprovals : .leaves
        case .permissionRequest, .permissionApproved, .permissionRejected:
            selectedTab = .hr
            openHRRouteFromPush = route.workflowTargetMode?.lowercased() == "approval" ? .permissionApprovals : .permissions
        }
    }
}

private extension View {
    @ViewBuilder
    func tabBarMinimizeOnScrollIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
