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

struct TypingUser: Decodable, Identifiable, Equatable, Sendable {
    let stackUserId: String
    let name: String?

    var id: String { stackUserId }
    var displayName: String { name ?? stackUserId }
}

struct TypingResult: Decodable, Sendable {
    let set: Bool?
    let cleared: Bool?
}

struct EditMessageResult: Decodable, Sendable {
    let edited: Bool
}

struct DeleteMessageResult: Decodable, Sendable {
    let deleted: Bool
}
