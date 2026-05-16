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

  private enum CodingKeys: String, CodingKey {
    case _id
    case id
    case stackUserId
    case staffId
    case name
    case displayName
    case profilePhoto
    case imageUrl
  }

  init(_id: String, name: String? = nil, profilePhoto: String? = nil) {
    self._id = _id
    self.name = name
    self.profilePhoto = profilePhoto
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _id = try container.decodeIfPresent(String.self, forKey: ._id)
      ?? container.decodeIfPresent(String.self, forKey: .id)
      ?? container.decodeIfPresent(String.self, forKey: .stackUserId)
      ?? container.decodeIfPresent(String.self, forKey: .staffId)
      ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name)
      ?? container.decodeIfPresent(String.self, forKey: .displayName)
    profilePhoto = try container.decodeIfPresent(String.self, forKey: .profilePhoto)
      ?? container.decodeIfPresent(String.self, forKey: .imageUrl)
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
  let otherParticipantRaw: ConvexConversationParticipant?
  let participantStackUserIdsRaw: [String]?
  let otherParticipantLastReadAt: Double?

  // Compat
  var id: String { _id }
  var unreadCountValue: Int { unreadCount ?? 0 }

  var participantStackUserIds: [String] {
    let participantIDs = participants?.map(\.stackUserId).filter { !$0.isEmpty } ?? []
    return participantStackUserIdsRaw ?? participantIDs
  }

  var otherParticipant: ConvexConversationParticipant? {
    otherParticipantRaw ?? participants?.first
  }

  var otherParticipantLastReadDate: Date? {
    guard let otherParticipantLastReadAt, otherParticipantLastReadAt > 0 else { return nil }
    let seconds = otherParticipantLastReadAt > 10_000_000_000 ? otherParticipantLastReadAt / 1000 : otherParticipantLastReadAt
    return Date(timeIntervalSince1970: seconds)
  }

  var createdAt: Double { lastMessageAt ?? 0 }
  var updatedAt: Double { lastMessageAt ?? 0 }

  private enum CodingKeys: String, CodingKey {
    case _id
    case id
    case conversationId
    case type
    case displayName
    case lastMessageAt
    case latestActivityAt
    case updatedAt
    case createdAt
    case lastMessagePreview
    case lastMessageSenderId
    case lastReadTime
    case participants
    case participantStackUserIds
    case otherParticipant
    case otherParticipantLastReadAt
    case lastMessage
    case unreadCount
    case muted
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _id = try container.decodeIfPresent(String.self, forKey: ._id)
      ?? container.decodeIfPresent(String.self, forKey: .id)
      ?? container.decodeIfPresent(String.self, forKey: .conversationId)
      ?? UUID().uuidString
    type = try container.decodeIfPresent(String.self, forKey: .type)
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    lastMessageAt = try container.decodeIfPresent(Double.self, forKey: .lastMessageAt)
      ?? container.decodeIfPresent(Double.self, forKey: .latestActivityAt)
      ?? container.decodeIfPresent(Double.self, forKey: .updatedAt)
      ?? container.decodeIfPresent(Double.self, forKey: .createdAt)
    lastMessagePreview = try container.decodeIfPresent(String.self, forKey: .lastMessagePreview)
    lastMessageSenderId = try container.decodeIfPresent(String.self, forKey: .lastMessageSenderId)
    lastReadTime = try container.decodeIfPresent(Double.self, forKey: .lastReadTime)
    participants = try container.decodeIfPresent([ConvexConversationParticipant].self, forKey: .participants)
    participantStackUserIdsRaw = try container.decodeIfPresent([String].self, forKey: .participantStackUserIds)
    otherParticipantRaw = try container.decodeIfPresent(ConvexConversationParticipant.self, forKey: .otherParticipant)
    otherParticipantLastReadAt = try container.decodeIfPresent(Double.self, forKey: .otherParticipantLastReadAt)
    lastMessage = try container.decodeIfPresent(ConvexConversationLastMessage.self, forKey: .lastMessage)
    unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount)
    muted = try container.decodeIfPresent(Bool.self, forKey: .muted)
  }
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
  let thumbnail: String?
  let url: String?

  var id: String { _id ?? messageId ?? storageId ?? fileName ?? UUID().uuidString }

  private enum CodingKeys: String, CodingKey {
    case _id
    case id
    case messageId
    case fileName
    case attachmentFileName
    case fileType
    case attachmentType
    case attachmentMimeType
    case fileSize
    case attachmentFileSize
    case storageId
    case attachmentStorageId
    case thumbnail
    case attachmentThumbnail
    case url
    case attachmentUrl
  }

  init(
    _id: String? = nil,
    messageId: String? = nil,
    fileName: String? = nil,
    fileType: String? = nil,
    fileSize: Int? = nil,
    storageId: String? = nil,
    thumbnail: String? = nil,
    url: String? = nil
  ) {
    self._id = _id
    self.messageId = messageId
    self.fileName = fileName
    self.fileType = fileType
    self.fileSize = fileSize
    self.storageId = storageId
    self.thumbnail = thumbnail
    self.url = url
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _id = try container.decodeIfPresent(String.self, forKey: ._id)
      ?? container.decodeIfPresent(String.self, forKey: .id)
    messageId = try container.decodeIfPresent(String.self, forKey: .messageId)
    fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
      ?? container.decodeIfPresent(String.self, forKey: .attachmentFileName)
    fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
      ?? container.decodeIfPresent(String.self, forKey: .attachmentMimeType)
      ?? container.decodeIfPresent(String.self, forKey: .attachmentType)
    fileSize = try container.decodeIfPresent(Int.self, forKey: .fileSize)
      ?? container.decodeIfPresent(Int.self, forKey: .attachmentFileSize)
    storageId = try container.decodeIfPresent(String.self, forKey: .storageId)
      ?? container.decodeIfPresent(String.self, forKey: .attachmentStorageId)
    thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
      ?? container.decodeIfPresent(String.self, forKey: .attachmentThumbnail)
    url = try container.decodeIfPresent(String.self, forKey: .url)
      ?? container.decodeIfPresent(String.self, forKey: .attachmentUrl)
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
  var attachmentThumbnail: String? { attachments?.first?.thumbnail }
  var attachmentUrl: String? { attachments?.first?.url }

  var timestamp: Date {
    let raw = _creationTime ?? 0
    return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
  }

  private enum CodingKeys: String, CodingKey {
    case _id
    case id
    case messageId
    case channelId
    case conversationId
    case senderId
    case senderStackUserId
    case senderName
    case body
    case content
    case isEdited
    case isDeleted
    case replyCount
    case lastReplyAt
    case parentMessageId
    case replyToId
    case _creationTime
    case createdAt
    case sentAt
    case attachments
    case attachmentType
    case attachmentStorageId
    case attachmentFileName
    case attachmentMimeType
    case attachmentThumbnail
    case attachmentUrl
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
      ?? container.decodeIfPresent(String.self, forKey: .id)
      ?? container.decodeIfPresent(String.self, forKey: .messageId)
      ?? UUID().uuidString
    channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
    conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
    senderId = try container.decodeIfPresent(String.self, forKey: .senderId)
      ?? container.decodeIfPresent(String.self, forKey: .senderStackUserId)
    senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
    body = try container.decodeIfPresent(String.self, forKey: .body)
      ?? container.decodeIfPresent(String.self, forKey: .content)
    isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited)
    isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted)
    replyCount = try container.decodeIfPresent(Int.self, forKey: .replyCount)
    lastReplyAt = try container.decodeIfPresent(Double.self, forKey: .lastReplyAt)
    parentMessageId = try container.decodeIfPresent(String.self, forKey: .parentMessageId)
      ?? container.decodeIfPresent(String.self, forKey: .replyToId)
    _creationTime = try container.decodeIfPresent(Double.self, forKey: ._creationTime)
      ?? container.decodeIfPresent(Double.self, forKey: .createdAt)
      ?? container.decodeIfPresent(Double.self, forKey: .sentAt)
    let decodedAttachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments)
    if let decodedAttachments, !decodedAttachments.isEmpty {
      attachments = decodedAttachments
    } else {
      let legacyAttachmentType = try container.decodeIfPresent(String.self, forKey: .attachmentType)
      let legacyStorageId = try container.decodeIfPresent(String.self, forKey: .attachmentStorageId)
      let legacyFileName = try container.decodeIfPresent(String.self, forKey: .attachmentFileName)
      let legacyMimeType = try container.decodeIfPresent(String.self, forKey: .attachmentMimeType)
      let legacyThumbnail = try container.decodeIfPresent(String.self, forKey: .attachmentThumbnail)
      let legacyURL = try container.decodeIfPresent(String.self, forKey: .attachmentUrl)
      if legacyAttachmentType != nil || legacyStorageId != nil || legacyFileName != nil || legacyURL != nil {
        attachments = [
          MessageAttachment(
            messageId: _id,
            fileName: legacyFileName,
            fileType: legacyMimeType ?? legacyAttachmentType,
            storageId: legacyStorageId,
            thumbnail: legacyThumbnail,
            url: legacyURL
          )
        ]
      } else {
        attachments = decodedAttachments
      }
    }
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
