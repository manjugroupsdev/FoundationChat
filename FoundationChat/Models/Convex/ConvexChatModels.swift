import Foundation

// MARK: - Directory / Staff

struct DirectoryUser: Decodable, Identifiable, Equatable, Hashable {
  /// Maps from API `_id`
  let _id: String
  let name: String?
  let email: String?
  let profilePhoto: String?

  // Compat
  var id: String { _id }
  var stackUserId: String { _id }
  var imageUrl: String? { profilePhoto }

  var displayName: String {
    let candidate = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? name : email
    return candidate ?? _id
  }
}

// MARK: - Conversations

struct ConvexConversationParticipant: Decodable, Equatable, Sendable {
  let _id: String
  let name: String?
  let profilePhoto: String?

  var stackUserId: String { _id }
  var email: String? { nil }
  var imageUrl: String? { profilePhoto }

  var displayName: String {
    let candidate = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? name : nil
    return candidate ?? _id
  }
}

struct ConvexConversationLastMessage: Decodable, Equatable, Sendable {
  let _id: String
  let body: String?
  let senderName: String?
  let _creationTime: Double?
}

struct ConvexConversationSummary: Decodable, Identifiable, Equatable, Sendable {
  let _id: String
  let type: String?
  let displayName: String?
  let lastMessageAt: Double?
  let participants: [ConvexConversationParticipant]?
  let lastMessage: ConvexConversationLastMessage?
  let unreadCount: Int?
  let muted: Bool?

  // Compat
  var id: String { _id }
  var unreadCountValue: Int { unreadCount ?? 0 }

  var participantStackUserIds: [String] {
    participants?.map(\.stackUserId) ?? []
  }

  var otherParticipant: ConvexConversationParticipant? {
    participants?.first
  }

  var otherParticipantLastReadDate: Date? { nil }

  var createdAt: Double { lastMessageAt ?? 0 }
  var updatedAt: Double { lastMessageAt ?? 0 }
}

// MARK: - Start DM result

struct StartDirectConversationResult: Decodable, Sendable {
  let conversationId: String
  // Compat fields
  var pairKey: String { conversationId }
  var participantStackUserIds: [String] { [] }
  var created: Bool { true }
}

// MARK: - Messages

struct MessageAttachment: Decodable, Identifiable, Equatable, Sendable {
  let _id: String
  let fileName: String?
  let fileType: String?
  let fileSize: Int?
  let url: String?

  var id: String { _id }
}

enum ConvexChatRole: String, Codable, Sendable {
  case user
  case assistant
  case system

  static func from(_ role: Role) -> ConvexChatRole {
    switch role {
    case .user: return .user
    case .assistant: return .assistant
    case .system: return .system
    }
  }

  var appRole: Role {
    switch self {
    case .user: return .user
    case .assistant: return .assistant
    case .system: return .system
    }
  }
}

struct ConvexChatMessage: Decodable, Identifiable, Equatable, Sendable {
  let _id: String
  let channelId: String?
  let conversationId: String?
  let senderId: String?
  let senderName: String?
  let body: String?
  let isEdited: Bool?
  let isDeleted: Bool?
  let replyCount: Int?
  let lastReplyAt: Double?
  let parentMessageId: String?
  let _creationTime: Double?
  let attachments: [MessageAttachment]?

  // Compat
  var id: String { _id }
  var senderStackUserId: String { senderId ?? "" }
  var role: ConvexChatRole { .user }
  var content: String { body ?? "" }
  var createdAt: Double { _creationTime ?? 0 }
  var updatedAt: Double { _creationTime ?? 0 }
  var replyToId: String? { parentMessageId }
  var editedAt: Double? { isEdited == true ? _creationTime : nil }

  // Attachment compat — flatten first attachment or nil
  var attachmentType: String? { attachments?.first?.fileType }
  var attachmentStorageId: String? { nil }
  var attachmentFileName: String? { attachments?.first?.fileName }
  var attachmentMimeType: String? { attachments?.first?.fileType }
  var attachmentTitle: String? { nil }
  var attachmentDescription: String? { nil }
  var attachmentThumbnail: String? { nil }
  var attachmentUrl: String? { attachments?.first?.url }

  var timestamp: Date {
    Date(timeIntervalSince1970: (_creationTime ?? 0) / 1000)
  }
}

struct ConvexUploadUrlResponse: Decodable, Sendable {
  let uploadUrl: String
}

struct MarkConversationSeenResult: Decodable, Sendable {
  let conversationId: String?
  let stackUserId: String?
  let lastReadAt: Double?
}

struct SharedFileItem: Decodable, Identifiable, Equatable, Sendable {
  let _id: String?
  let conversationId: String?
  let senderStackUserId: String?
  let storageId: String?
  let attachmentType: String
  let fileName: String
  let mimeType: String?
  let title: String?
  let description: String?
  let thumbnail: String?
  let url: String?
  let createdAt: Double?
  let updatedAt: Double?

  var id: String { _id ?? UUID().uuidString }
  var createdDate: Date { Date(timeIntervalSince1970: (createdAt ?? 0) / 1000) }
}

struct SavePrivateFileResult: Decodable, Sendable {
  let fileId: String
}

struct SharePrivateFileResult: Decodable, Sendable {
  let shared: Bool
  let conversationId: String
  let messageId: String
}

// MARK: - Channels

struct ChannelSummary: Decodable, Identifiable, Equatable, Sendable {
  let _id: String
  let name: String
  let slug: String?
  let description: String?
  let type: String?
  let createdBy: String?
  let isArchived: Bool?
  let memberCount: Int?
  let role: String?
  let muted: Bool?
  let unreadCount: Int?

  // Compat
  var id: String { _id }
  var lastMessageContent: String? { nil }
  var lastMessageAt: Double { 0 }
  var createdByStackUserId: String { createdBy ?? "" }
  var myRole: String { role ?? "member" }
  var canManage: Bool { role == "admin" || role == "owner" }
  var createdAt: Double { 0 }
  var updatedAt: Double { 0 }
  var lastMessageDate: Date { Date(timeIntervalSince1970: lastMessageAt / 1000) }
}

struct ChannelMember: Decodable, Identifiable, Equatable, Sendable {
  let _id: String
  let channelId: String?
  let staffId: String?
  let role: String?
  let muted: Bool?
  let staffName: String?
  let staffRole: String?
  let staffDesignation: String?

  var id: String { _id }
  var stackUserId: String { staffId ?? _id }
  var invitedByStackUserId: String? { nil }

  var user: DirectoryUser {
    DirectoryUser(_id: staffId ?? _id, name: staffName, email: nil, profilePhoto: nil)
  }
}

struct CreateChannelResult: Decodable, Sendable {
  let channelId: String
  var name: String? { nil }
  var description: String? { nil }
  var createdAt: Double { 0 }
}

struct InviteChannelMemberResult: Decodable, Sendable {
  let channelId: String?
  let memberStackUserId: String?
  let invited: Bool?

  init(channelId: String? = nil, memberStackUserId: String? = nil, invited: Bool? = nil) {
    self.channelId = channelId
    self.memberStackUserId = memberStackUserId
    self.invited = invited
  }
}

struct ChannelChatMessage: Decodable, Identifiable, Equatable, Sendable {
  let _id: String
  let channelId: String?
  let senderId: String?
  let senderName: String?
  let body: String?
  let isEdited: Bool?
  let isDeleted: Bool?
  let replyCount: Int?
  let lastReplyAt: Double?
  let parentMessageId: String?
  let _creationTime: Double?

  // Compat
  var id: String { _id }
  var senderStackUserId: String { senderId ?? "" }
  var content: String { body ?? "" }
  var replyToId: String? { parentMessageId }
  var editedAt: Double? { isEdited == true ? _creationTime : nil }
  var createdAt: Double { _creationTime ?? 0 }
  var updatedAt: Double { _creationTime ?? 0 }
  var createdDate: Date { Date(timeIntervalSince1970: (_creationTime ?? 0) / 1000) }
}
