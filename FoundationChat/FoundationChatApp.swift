import SwiftData
import SwiftUI

@main
struct FoundationChatApp: App {
  @UIApplicationDelegateAdaptor(PushNotificationAppDelegate.self)
  private var pushNotificationAppDelegate

  @State private var authStore = AuthStore()

  var body: some Scene {
    WindowGroup {
      AuthRootView()
        .modelContainer(for: [Conversation.self, Message.self])
        .environment(authStore)
    }
  }
}
