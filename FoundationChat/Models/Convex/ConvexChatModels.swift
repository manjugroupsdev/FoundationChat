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
  let senderId: String?
  let senderName: String?
  let _creationTime: Double?
}

struct ConvexConversationSummary: Decodable, Identifiable, Equatable, Sendable {
  let _id: String
  let type: String?
  let displayName: String?
  let lastMessageAt: Double?
  let lastMessagePreview: String?
  let lastMessageSenderId: String?
  let lastReadTime: Double?
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
  let _id: String?
  let messageId: String?
  let fileName: String?
  let fileType: String?
  let fileSize: Int?
  let storageId: String?
  let url: String?

  var id: String { _id ?? messageId ?? storageId ?? fileName ?? UUID().uuidString }

  init(
    _id: String? = nil,
    messageId: String? = nil,
    fileName: String? = nil,
    fileType: String? = nil,
    fileSize: Int? = nil,
    storageId: String? = nil,
    url: String? = nil
  ) {
    self._id = _id
    self.messageId = messageId
    self.fileName = fileName
    self.fileType = fileType
    self.fileSize = fileSize
    self.storageId = storageId
    self.url = url
  }
}

struct MessageMention: Decodable, Identifiable, Equatable, Sendable {
  let mentionType: String?
  let mentionedStaffId: String?

  var id: String { "\(mentionType ?? "staff"):\(mentionedStaffId ?? "")" }
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
  let reactions: [MessageReactionInfo]?
  let mentions: [MessageMention]?

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
  var attachmentStorageId: String? { attachments?.first?.storageId }
  var attachmentFileName: String? { attachments?.first?.fileName }
  var attachmentMimeType: String? { attachments?.first?.fileType }
  var attachmentTitle: String? { nil }
  var attachmentDescription: String? { nil }
  var attachmentThumbnail: String? { nil }
  var attachmentUrl: String? { attachments?.first?.url }

  var timestamp: Date {
    let raw = _creationTime ?? 0
    return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
  }

  private enum CodingKeys: String, CodingKey {
    case _id
    case messageId
    case channelId
    case conversationId
    case senderId
    case senderName
    case body
    case isEdited
    case isDeleted
    case replyCount
    case lastReplyAt
    case parentMessageId
    case _creationTime
    case sentAt
    case attachments
    case reactions
    case mentions
  }

  init(
    _id: String,
    channelId: String? = nil,
    conversationId: String? = nil,
    senderId: String? = nil,
    senderName: String? = nil,
    body: String? = nil,
    isEdited: Bool? = nil,
    isDeleted: Bool? = nil,
    replyCount: Int? = nil,
    lastReplyAt: Double? = nil,
    parentMessageId: String? = nil,
    _creationTime: Double? = nil,
    attachments: [MessageAttachment]? = nil,
    reactions: [MessageReactionInfo]? = nil,
    mentions: [MessageMention]? = nil
  ) {
    self._id = _id
    self.channelId = channelId
    self.conversationId = conversationId
    self.senderId = senderId
    self.senderName = senderName
    self.body = body
    self.isEdited = isEdited
    self.isDeleted = isDeleted
    self.replyCount = replyCount
    self.lastReplyAt = lastReplyAt
    self.parentMessageId = parentMessageId
    self._creationTime = _creationTime
    self.attachments = attachments
    self.reactions = reactions
    self.mentions = mentions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _id = try container.decodeIfPresent(String.self, forKey: ._id)
      ?? container.decodeIfPresent(String.self, forKey: .messageId)
      ?? UUID().uuidString
    channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
    conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
    senderId = try container.decodeIfPresent(String.self, forKey: .senderId)
    senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
    body = try container.decodeIfPresent(String.self, forKey: .body)
    isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited)
    isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted)
    replyCount = try container.decodeIfPresent(Int.self, forKey: .replyCount)
    lastReplyAt = try container.decodeIfPresent(Double.self, forKey: .lastReplyAt)
    parentMessageId = try container.decodeIfPresent(String.self, forKey: .parentMessageId)
    _creationTime = try container.decodeIfPresent(Double.self, forKey: ._creationTime)
      ?? container.decodeIfPresent(Double.self, forKey: .sentAt)
    attachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments)
    reactions = try container.decodeIfPresent([MessageReactionInfo].self, forKey: .reactions)
    mentions = try container.decodeIfPresent([MessageMention].self, forKey: .mentions)
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
  let lastMessagePreview: String?
  let lastMessageAtRaw: Double?
  let lastMessageSenderId: String?
  let mentionCount: Int?
  let joined: Bool?

  // Compat
  var id: String { _id }
  var lastMessageContent: String? { lastMessagePreview }
  var lastMessageAt: Double { lastMessageAtRaw ?? 0 }
  var createdByStackUserId: String { createdBy ?? "" }
  var myRole: String { role ?? "member" }
  var canManage: Bool { role == "admin" || role == "owner" }
  var unreadCountValue: Int { unreadCount ?? 0 }
  var createdAt: Double { 0 }
  var updatedAt: Double { 0 }
  var lastMessageDate: Date { Date(timeIntervalSince1970: lastMessageAt / 1000) }

  private enum CodingKeys: String, CodingKey {
    case _id
    case name
    case slug
    case description
    case type
    case createdBy
    case isArchived
    case memberCount
    case role
    case muted
    case unreadCount
    case lastMessagePreview
    case lastMessageAtRaw = "lastMessageAt"
    case lastMessageSenderId
    case mentionCount
    case joined
  }

  init(
    _id: String,
    name: String,
    slug: String? = nil,
    description: String? = nil,
    type: String? = nil,
    createdBy: String? = nil,
    isArchived: Bool? = nil,
    memberCount: Int? = nil,
    role: String? = nil,
    muted: Bool? = nil,
    unreadCount: Int? = nil,
    lastMessagePreview: String? = nil,
    lastMessageAtRaw: Double? = nil,
    lastMessageSenderId: String? = nil,
    mentionCount: Int? = nil,
    joined: Bool? = nil
  ) {
    self._id = _id
    self.name = name
    self.slug = slug
    self.description = description
    self.type = type
    self.createdBy = createdBy
    self.isArchived = isArchived
    self.memberCount = memberCount
    self.role = role
    self.muted = muted
    self.unreadCount = unreadCount
    self.lastMessagePreview = lastMessagePreview
    self.lastMessageAtRaw = lastMessageAtRaw
    self.lastMessageSenderId = lastMessageSenderId
    self.mentionCount = mentionCount
    self.joined = joined
  }
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
  let attachments: [MessageAttachment]?
  let reactions: [MessageReactionInfo]?
  let mentions: [MessageMention]?

  // Compat
  var id: String { _id }
  var senderStackUserId: String { senderId ?? "" }
  var content: String { body ?? "" }
  var replyToId: String? { parentMessageId }
  var editedAt: Double? { isEdited == true ? _creationTime : nil }
  var createdAt: Double { _creationTime ?? 0 }
  var updatedAt: Double { _creationTime ?? 0 }
  var createdDate: Date { Date(timeIntervalSince1970: (_creationTime ?? 0) / 1000) }

  var attachmentType: String? { attachments?.first?.fileType }
  var attachmentFileName: String? { attachments?.first?.fileName }
  var attachmentMimeType: String? { attachments?.first?.fileType }
  var attachmentUrl: String? { attachments?.first?.url }

  init(
    _id: String,
    channelId: String? = nil,
    senderId: String? = nil,
    senderName: String? = nil,
    body: String? = nil,
    isEdited: Bool? = nil,
    isDeleted: Bool? = nil,
    replyCount: Int? = nil,
    lastReplyAt: Double? = nil,
    parentMessageId: String? = nil,
    _creationTime: Double? = nil,
    attachments: [MessageAttachment]? = nil,
    reactions: [MessageReactionInfo]? = nil,
    mentions: [MessageMention]? = nil
  ) {
    self._id = _id
    self.channelId = channelId
    self.senderId = senderId
    self.senderName = senderName
    self.body = body
    self.isEdited = isEdited
    self.isDeleted = isDeleted
    self.replyCount = replyCount
    self.lastReplyAt = lastReplyAt
    self.parentMessageId = parentMessageId
    self._creationTime = _creationTime
    self.attachments = attachments
    self.reactions = reactions
    self.mentions = mentions
  }

  init(_ message: ConvexChatMessage) {
    self.init(
      _id: message.id,
      channelId: message.channelId,
      senderId: message.senderId,
      senderName: message.senderName,
      body: message.body,
      isEdited: message.isEdited,
      isDeleted: message.isDeleted,
      replyCount: message.replyCount,
      lastReplyAt: message.lastReplyAt,
      parentMessageId: message.parentMessageId,
      _creationTime: message._creationTime,
      attachments: message.attachments,
      reactions: message.reactions,
      mentions: message.mentions
    )
  }
}
