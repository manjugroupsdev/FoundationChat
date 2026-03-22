import SwiftUI

enum AppTab: Hashable {
  case chats
  case files
  case channels
  case updates
  case hr
}

struct MainTabView: View {
  @State private var selectedTab: AppTab = .chats
  @State private var openConversationIDFromPush: String?
  @State private var openChannelIDFromPush: String?

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

      UpdatesFeedView()
        .tabItem {
          Label("Updates", systemImage: "newspaper.fill")
        }
        .tag(AppTab.updates)

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
    }
  }
}

#Preview {
  MainTabView()
    .environment(AuthStore())
}
