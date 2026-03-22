import Foundation

struct DirectoryUser: Decodable, Identifiable, Equatable, Hashable {
  let id: String
  let stackUserId: String
  let email: String?
  let name: String?
  let imageUrl: String?

  var displayName: String {
    let candidate = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
      ? name
      : email
    return candidate ?? stackUserId
  }
}

struct StartDirectConversationResult: Decodable {
  let conversationId: String
  let pairKey: String
  let participantStackUserIds: [String]
  let created: Bool
}

enum ConvexChatRole: String, Codable, Sendable {
  case user
  case assistant
  case system

  static func from(_ role: Role) -> ConvexChatRole {
    switch role {
    case .user:
      return .user
    case .assistant:
      return .assistant
    case .system:
      return .system
    }
  }

  var appRole: Role {
    switch self {
    case .user:
      return .user
    case .assistant:
      return .assistant
    case .system:
      return .system
    }
  }
}

struct ConvexChatMessage: Decodable, Identifiable, Equatable, Sendable {
  let id: String
  let conversationId: String
  let senderStackUserId: String
  let role: ConvexChatRole
  let content: String
  let attachmentType: String?
  let attachmentStorageId: String?
  let attachmentFileName: String?
  let attachmentMimeType: String?
  let attachmentTitle: String?
  let attachmentDescription: String?
  let attachmentThumbnail: String?
  let attachmentUrl: String?
  let replyToId: String?
  let editedAt: Double?
  let isDeleted: Bool?
  let createdAt: Double
  let updatedAt: Double

  var timestamp: Date {
    Date(timeIntervalSince1970: createdAt / 1000)
  }
}

struct ConvexUploadUrlResponse: Decodable, Sendable {
  let uploadUrl: String
}

struct ConvexConversationParticipant: Decodable, Equatable, Sendable {
  let stackUserId: String
  let email: String?
  let name: String?
  let imageUrl: String?

  var displayName: String {
    let candidate = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
      ? name
      : email
    return candidate ?? stackUserId
  }
}

struct ConvexConversationSummary: Decodable, Identifiable, Equatable, Sendable {
  let id: String
  let type: String
  let participantStackUserIds: [String]
  let otherParticipant: ConvexConversationParticipant?
  let lastMessage: ConvexChatMessage?
  let unreadCount: Int?
  let otherParticipantLastReadAt: Double?
  let createdAt: Double
  let updatedAt: Double

  var unreadCountValue: Int {
    unreadCount ?? 0
  }

  var otherParticipantLastReadDate: Date? {
    guard let otherParticipantLastReadAt else { return nil }
    return Date(timeIntervalSince1970: otherParticipantLastReadAt / 1000)
  }
}

struct MarkConversationSeenResult: Decodable, Sendable {
  let conversationId: String
  let stackUserId: String
  let lastReadAt: Double
}

struct SharedFileItem: Decodable, Identifiable, Equatable, Sendable {
  let id: String
  let conversationId: String?
  let senderStackUserId: String
  let storageId: String?
  let attachmentType: String
  let fileName: String
  let mimeType: String?
  let title: String?
  let description: String?
  let thumbnail: String?
  let url: String?
  let createdAt: Double
  let updatedAt: Double

  var createdDate: Date {
    Date(timeIntervalSince1970: createdAt / 1000)
  }
}

struct SavePrivateFileResult: Decodable, Sendable {
  let fileId: String
}

struct SharePrivateFileResult: Decodable, Sendable {
  let shared: Bool
  let conversationId: String
  let messageId: String
}

struct ChannelSummary: Decodable, Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let description: String?
  let memberCount: Int
  let lastMessageContent: String?
  let lastMessageAt: Double
  let createdByStackUserId: String
  let myRole: String
  let canManage: Bool
  let createdAt: Double
  let updatedAt: Double

  var lastMessageDate: Date {
    Date(timeIntervalSince1970: lastMessageAt / 1000)
  }
}

struct ChannelMember: Decodable, Identifiable, Equatable, Sendable {
  let channelId: String
  let stackUserId: String
  let role: String
  let invitedByStackUserId: String?
  let user: DirectoryUser
  let createdAt: Double
  let updatedAt: Double

  var id: String {
    "\(channelId)|\(stackUserId)"
  }
}

struct CreateChannelResult: Decodable, Sendable {
  let channelId: String
  let name: String
  let description: String?
  let createdAt: Double
}

struct InviteChannelMemberResult: Decodable, Sendable {
  let channelId: String
  let memberStackUserId: String
  let invited: Bool
}

struct ChannelChatMessage: Decodable, Identifiable, Equatable, Sendable {
  let id: String
  let channelId: String
  let senderStackUserId: String
  let senderName: String
  let content: String
  let replyToId: String?
  let editedAt: Double?
  let isDeleted: Bool?
  let createdAt: Double
  let updatedAt: Double

  var createdDate: Date {
    Date(timeIntervalSince1970: createdAt / 1000)
  }
}
