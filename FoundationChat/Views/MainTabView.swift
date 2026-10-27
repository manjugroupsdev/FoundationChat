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

private struct ApprovalQueuePresentation: Identifiable {
    let id = UUID()
}

private struct CabRequestsPresentation: Identifiable {
    let id = UUID()
    let tab: CabRequestsView.Tab?
}

struct MainTabView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var selectedTab: AppTab = .home
    @State private var openConversationIDFromPush: String?
    @State private var openChannelIDFromPush: String?
    @State private var openHRRouteFromPush: HRDashboardRoute?
    @State private var approvalQueuePresentation: ApprovalQueuePresentation?
    @State private var cabRequestsPresentation: CabRequestsPresentation?
    @State private var hasPlayedHomeEntryAnimation = false

    init() {
        Self.configureTabBarColors()
    }

    private static func configureTabBarColors() {
        let active = UIColor(red: 0.106, green: 0.792, blue: 0.043, alpha: 1)
        let inactive = UIColor(red: 0.6, green: 0.615, blue: 0.635, alpha: 1)
        let tabBar = UITabBar.appearance()
        if #available(iOS 26.0, *) {
            // iOS 26 owns the floating tab bar's glass backdrop. Installing a
            // custom UITabBarAppearance can expand that backdrop into an opaque
            // layer after a scroll transition and cover the page content.
            tabBar.tintColor = active
            tabBar.unselectedItemTintColor = inactive
            return
        }

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.62)
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
            Tab("Home", image: "AndroidNavHomeIcon", value: .home) {
                HomeView(hasPlayedEntryAnimation: $hasPlayedHomeEntryAnimation)
            }

            Tab("Attendance", image: "AndroidNavAttendanceIcon", value: .hr) {
                HRDashboardView(isActive: selectedTab == .hr, openRoute: openHRRouteFromPush) {
                    openHRRouteFromPush = nil
                }
            }

            Tab("Chat", image: "AndroidNavChatIcon", value: .chats) {
                ConversationsListView(
                    selectedTab: $selectedTab,
                    openConversationID: openConversationIDFromPush,
                    openChannelID: openChannelIDFromPush
                ) {
                    openConversationIDFromPush = nil
                } onOpenChannelHandled: {
                    openChannelIDFromPush = nil
                }
            }

            Tab("Apps", image: "AndroidNavAppsIcon", value: .apps) {
                AppLibraryView()
            }
        }
        .onAppear {
            Self.configureTabBarColors()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNavigationRoute)) { notification in
            guard let route = notification.object as? PushNavigationRoute else { return }
            applyPushRoute(route)
            _ = PushNavigationCoordinator.shared.consumePendingRoute()
        }
        .task {
            if let pending = await MainActor.run(body: {
                PushNavigationCoordinator.shared.consumePendingRoute()
            }) {
                applyPushRoute(pending)
            }
        }
        .sheet(item: $approvalQueuePresentation) { presentation in
            NavigationStack {
                CpApprovalQueueView()
                    .id(presentation.id)
                    .navigationTitle("Approvals")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { approvalQueuePresentation = nil }
                        }
                    }
            }
        }
        .sheet(item: $cabRequestsPresentation) { presentation in
            NavigationStack {
                CabRequestsView(initialTab: presentation.tab)
                    .id(presentation.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { cabRequestsPresentation = nil }
                        }
                    }
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
        case .cpApproval:
            selectedTab = .apps
            approvalQueuePresentation = ApprovalQueuePresentation()
        case .cabRequests:
            // A new request goes to the approver's Approvals tab; the rest to
            // the requester's My Requests (Android parity).
            selectedTab = .apps
            cabRequestsPresentation = CabRequestsPresentation(
                tab: route.workflowTargetMode?.lowercased() == "approvals" ? .approvals : .mine
            )
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
