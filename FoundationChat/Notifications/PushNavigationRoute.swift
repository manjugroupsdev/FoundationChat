import Foundation

enum PushNavigationType: String {
    case directMessage = "chat-dm"
    case channelMessage = "chat-mention"
    case leaveRequest = "leave-request"
    case leaveApproved = "leave-approved"
    case leaveRejected = "leave-rejected"
    case permissionRequest = "permission-request"
    case permissionApproved = "permission-approved"
    case permissionRejected = "permission-rejected"

    // Legacy compatibility
    init?(fromRaw raw: String) {
        switch raw {
        case "direct_message", "chat-dm": self = .directMessage
        case "channel_message", "chat-mention": self = .channelMessage
        case "leave-request": self = .leaveRequest
        case "leave-approved": self = .leaveApproved
        case "leave-rejected": self = .leaveRejected
        case "permission-request": self = .permissionRequest
        case "permission-approved": self = .permissionApproved
        case "permission-rejected": self = .permissionRejected
        default: return nil
        }
    }
}

struct PushNavigationRoute {
    let type: PushNavigationType
    let conversationId: String?
    let channelId: String?
    let messageId: String?
    let referenceId: String?

    init?(_ userInfo: [AnyHashable: Any]) {
        guard let rawType = PushNavigationRoute.stringValue(userInfo["type"]),
              let parsedType = PushNavigationType(fromRaw: rawType)
        else {
            return nil
        }

        type = parsedType
        conversationId = PushNavigationRoute.stringValue(userInfo["conversationId"])
        channelId = PushNavigationRoute.stringValue(userInfo["channelId"])
        messageId = PushNavigationRoute.stringValue(userInfo["messageId"])
        referenceId = PushNavigationRoute.stringValue(userInfo["referenceId"])
    }

    var isChat: Bool {
        type == .directMessage || type == .channelMessage
    }

    var isHR: Bool {
        switch type {
        case .leaveRequest, .leaveApproved, .leaveRejected,
             .permissionRequest, .permissionApproved, .permissionRejected:
            return true
        default:
            return false
        }
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
