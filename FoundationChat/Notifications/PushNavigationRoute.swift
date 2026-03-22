import Foundation

enum PushNavigationType: String {
  case directMessage = "direct_message"
  case channelMessage = "channel_message"
}

struct PushNavigationRoute {
  let type: PushNavigationType
  let conversationId: String?
  let channelId: String?

  init?(_ userInfo: [AnyHashable: Any]) {
    guard let rawType = PushNavigationRoute.stringValue(userInfo["type"]),
      let parsedType = PushNavigationType(rawValue: rawType)
    else {
      return nil
    }

    type = parsedType
    conversationId = PushNavigationRoute.stringValue(userInfo["conversationId"])
    channelId = PushNavigationRoute.stringValue(userInfo["channelId"])
  }

  private static func stringValue(_ value: Any?) -> String? {
    guard let value else { return nil }
    if let string = value as? String {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let nsString = value as? NSString {
      let string = String(nsString)
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    return nil
  }
}

@MainActor
final class PushNavigationCoordinator {
  static let shared = PushNavigationCoordinator()

  private var pendingRoute: PushNavigationRoute?

  private init() {}

  func enqueue(_ route: PushNavigationRoute) {
    pendingRoute = route
    NotificationCenter.default.post(name: .didReceivePushNavigationRoute, object: route)
  }

  func consumePendingRoute() -> PushNavigationRoute? {
    let route = pendingRoute
    pendingRoute = nil
    return route
  }
}
