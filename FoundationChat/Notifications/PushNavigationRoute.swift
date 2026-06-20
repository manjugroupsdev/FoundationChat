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
    let workflowTargetMode: String?

    init?(_ userInfo: [AnyHashable: Any]) {
        if let targetTab = PushNavigationRoute.firstStringValue(userInfo, keys: ["workflow_target_tab", "targetTab"]) {
            let targetScreen = PushNavigationRoute.firstStringValue(userInfo, keys: ["workflow_target_screen", "targetScreen"])
            let normalizedTab = targetTab.lowercased()
            let normalizedScreen = targetScreen?.lowercased()

            switch normalizedTab {
            case "chat":
                let workflowChannelId = PushNavigationRoute.firstStringValue(userInfo, keys: ["workflow_channel_id", "channelId", "channel_id"])
                let workflowConversationId = PushNavigationRoute.firstStringValue(userInfo, keys: ["workflow_conversation_id", "conversationId", "conversation_id"])
                if normalizedScreen == "chat_channel" || workflowChannelId != nil {
                    type = .channelMessage
                    conversationId = nil
                    channelId = workflowChannelId
                } else if normalizedScreen == "chat_conversation" || workflowConversationId != nil {
                    type = .directMessage
                    conversationId = workflowConversationId
                    channelId = nil
                } else {
                    return nil
                }
            case "hr":
                switch normalizedScreen {
                case "leaves":
                    type = .leaveRequest
                case "permissions":
                    type = .permissionRequest
                default:
                    return nil
                }
                conversationId = nil
                channelId = nil
            default:
                return nil
            }

            messageId = PushNavigationRoute.firstStringValue(userInfo, keys: ["workflow_message_id", "messageId", "message_id"])
            referenceId = PushNavigationRoute.firstStringValue(userInfo, keys: ["workflow_entity_id", "referenceId", "reference_id"])
            workflowTargetMode = PushNavigationRoute.firstStringValue(userInfo, keys: ["workflow_target_mode", "targetMode", "target_mode"])
            return
        }

        guard let rawType = PushNavigationRoute.stringValue(userInfo["type"]),
              let parsedType = PushNavigationType(fromRaw: rawType)
        else {
            return nil
        }

        type = parsedType
        conversationId = PushNavigationRoute.firstStringValue(userInfo, keys: ["conversationId", "conversation_id"])
        channelId = PushNavigationRoute.firstStringValue(userInfo, keys: ["channelId", "channel_id"])
        messageId = PushNavigationRoute.firstStringValue(userInfo, keys: ["messageId", "message_id"])
        referenceId = PushNavigationRoute.firstStringValue(userInfo, keys: ["referenceId", "reference_id"])
        workflowTargetMode = nil
    }

    init?(_ notification: AppNotification) {
        guard let rawType = notification.type,
              let parsedType = PushNavigationType(fromRaw: rawType)
        else {
            return nil
        }

        let reference = notification.referenceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceType = notification.referenceType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        type = parsedType
        messageId = nil
        referenceId = reference?.isEmpty == true ? nil : reference
        workflowTargetMode = nil

        switch parsedType {
        case .directMessage:
            conversationId = referenceType == "channel" ? nil : referenceId
            channelId = nil
        case .channelMessage:
            conversationId = nil
            channelId = referenceType == "conversation" ? nil : referenceId
        case .leaveRequest, .leaveApproved, .leaveRejected,
             .permissionRequest, .permissionApproved, .permissionRejected:
            conversationId = nil
            channelId = nil
        }
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

    private static func firstStringValue(_ userInfo: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(userInfo[key]) {
                return value
            }
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
