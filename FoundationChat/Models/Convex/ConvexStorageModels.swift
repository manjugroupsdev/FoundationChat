import Foundation

struct StorageFolder: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let ownerStackUserId: String
    let name: String
    let parentFolderId: String?
    let fileCount: Int?
    let createdAt: Double
    let updatedAt: Double

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000)
    }
}

struct CreateFolderResult: Decodable, Sendable {
    let folderId: String
}

struct RenameFolderResult: Decodable, Sendable {
    let renamed: Bool
}

struct DeleteFolderResult: Decodable, Sendable {
    let deleted: Bool
}

struct MoveFileResult: Decodable, Sendable {
    let moved: Bool
}

struct MessageReactionInfo: Decodable, Identifiable, Equatable, Sendable {
    let emoji: String
    let count: Int
    let users: [ReactionUser]
    let hasReacted: Bool

    var id: String { emoji }

    private enum CodingKeys: String, CodingKey {
        case emoji
        case count
        case users
        case hasReacted
        case staffIds
        case mine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emoji = try container.decode(String.self, forKey: .emoji)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        users = try container.decodeIfPresent([ReactionUser].self, forKey: .users) ?? []
        hasReacted = try container.decodeIfPresent(Bool.self, forKey: .hasReacted)
            ?? container.decodeIfPresent(Bool.self, forKey: .mine)
            ?? false
    }

    init(emoji: String, count: Int, users: [ReactionUser] = [], hasReacted: Bool = false) {
        self.emoji = emoji
        self.count = count
        self.users = users
        self.hasReacted = hasReacted
    }
}

struct MessageReactionResult: Decodable, Sendable {
    let added: Bool?
    let removed: Bool?
}

struct NotificationPreference: Decodable, Identifiable, Equatable, Sendable {
    let targetType: String
    let targetId: String
    let level: String
    let muteUntil: Double?
    let updatedAt: Double

    var id: String { "\(targetType)|\(targetId)" }

    var notificationLevel: NotificationLevel {
        NotificationLevel(rawValue: level) ?? .all
    }
}

enum NotificationLevel: String, Sendable, CaseIterable {
    case all
    case mentions
    case none

    var displayName: String {
        switch self {
        case .all: return "All Messages"
        case .mentions: return "Mentions Only"
        case .none: return "Nothing"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "bell.fill"
        case .mentions: return "at"
        case .none: return "bell.slash.fill"
        }
    }
}

struct UpsertNotificationPrefResult: Decodable, Sendable {
    let saved: Bool
}

// MARK: - App Notifications

struct AppNotification: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let type: String?
    let title: String?
    let message: String?
    let read: Bool?
    let referenceId: String?
    let referenceType: String?
    let createdAt: String?

    var id: String { _id }

    var isUnread: Bool { read != true }

    var icon: String {
        switch type {
        case "chat-dm": return "message.fill"
        case "chat-mention": return "at"
        case "leave-request": return "calendar.badge.plus"
        case "leave-approved": return "checkmark.circle.fill"
        case "leave-rejected": return "xmark.circle.fill"
        case "permission-request": return "clock.badge.questionmark"
        case "permission-approved": return "checkmark.circle.fill"
        case "permission-rejected": return "xmark.circle.fill"
        default: return "bell.fill"
        }
    }

    var iconColor: String {
        switch type {
        case "leave-approved", "permission-approved": return "green"
        case "leave-rejected", "permission-rejected": return "red"
        case "chat-dm", "chat-mention": return "blue"
        default: return "orange"
        }
    }

    var createdDate: Date? {
        guard let createdAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt)
    }
}

struct TypingUser: Decodable, Identifiable, Equatable, Sendable {
    let staffId: String
    let staffName: String?
    let expiresAt: Double?

    // Compat
    var id: String { staffId }
    var stackUserId: String { staffId }
    var name: String? { staffName }
    var displayName: String { staffName ?? staffId }
}

struct TypingResult: Decodable, Sendable {
    let set: Bool?
    let cleared: Bool?
}

struct EditMessageResult: Decodable, Sendable {
    let edited: Bool?
    init(edited: Bool? = true) { self.edited = edited }
}

struct DeleteMessageResult: Decodable, Sendable {
    let deleted: Bool?
    init(deleted: Bool? = true) { self.deleted = deleted }
}
