import SwiftData
import SwiftUI

struct AuthRootView: View {
  @Environment(AuthStore.self) private var authStore

  var body: some View {
    Group {
      switch authStore.status {
      case .loading:
        if authStore.currentSession == nil {
          ZStack(alignment: .top) {
            LoginView()
              .allowsHitTesting(false)

            ProgressView("Checking session...")
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
              .background(.ultraThinMaterial, in: Capsule())
              .padding(.top, 24)
          }
        } else {
          ProgressView("Restoring session...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      case .signedOut:
        LoginView()
      case .signedIn:
        MainTabView()
      }
    }
    .task {
      await authStore.restoreSessionIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .didRegisterForRemoteNotificationsToken)) {
      notification in
      guard let apnsToken = notification.object as? String else { return }
      Task {
        await authStore.handleAPNSToken(apnsToken)
      }
    }
  }
}

#Preview {
  AuthRootView()
    .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
    .environment(AuthStore())
}
