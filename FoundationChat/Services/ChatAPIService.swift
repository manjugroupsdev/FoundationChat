import Foundation

/// HTTP client for all chat-related endpoints (channels, conversations, messages, typing).
enum ChatAPIService {
  private static let baseURL = AppConfig.chatBaseURL

  private struct EmptySuccessResponse: Decodable, Sendable {
    let success: Bool?
    let error: String?
  }

  private struct BooleanFlagResponse: Decodable, Sendable {
    let success: Bool?
    let saved: Bool?
    let added: Bool?
    let removed: Bool?
    let deleted: Bool?
    let edited: Bool?
    let error: String?
  }

  private struct StorageUploadResponse: Decodable, Sendable {
    let success: Bool
    let storageId: String?
    let error: String?
  }

  // MARK: - Staff Directory

  struct StaffMember: Decodable, Sendable {
    let _id: String?
    let employeeId: String?
    let name: String?
    let phone: String?
    let email: String?
    let role: String?
    let designation: String?
    let department: String?
    let status: String?
    let profilePhoto: String?

    private enum CodingKeys: String, CodingKey {
      case _id
      case id
      case staffId
      case employeeId
      case name
      case displayName
      case phone
      case email
      case role
      case designation
      case department
      case status
      case profilePhoto
      case profilePhotoUrl
      case photo
      case photoUrl
      case avatar
      case avatarUrl
      case imageUrl
      case profileImage
      case profileImageUrl
      case profilePicture
      case profilePictureUrl
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      _id = try container.decodeFirstPresentString(forKeys: [._id, .id, .staffId])
      employeeId = try container.decodeIfPresent(String.self, forKey: .employeeId)
      name = try container.decodeFirstPresentString(forKeys: [.name, .displayName])
      phone = try container.decodeIfPresent(String.self, forKey: .phone)
      email = try container.decodeIfPresent(String.self, forKey: .email)
      role = try container.decodeIfPresent(String.self, forKey: .role)
      designation = try container.decodeIfPresent(String.self, forKey: .designation)
      department = try container.decodeIfPresent(String.self, forKey: .department)
      status = try container.decodeIfPresent(String.self, forKey: .status)
      profilePhoto = try container.decodeFirstPresentString(forKeys: [
        .profilePhoto,
        .profilePhotoUrl,
        .photo,
        .photoUrl,
        .avatar,
        .avatarUrl,
        .imageUrl,
        .profileImage,
        .profileImageUrl,
        .profilePicture,
        .profilePictureUrl
      ])
    }
  }

  private struct StaffListResponse: Decodable, Sendable {
    let success: Bool?
    let staff: [StaffMember]?
    let total: Int?
  }

  /// Fetch active staff directory (requires auth).
  static func listActiveStaff(token: String) async throws -> [StaffMember] {
    let data = try await get(path: "/api/hr/staff/active", token: token)
    let wrapper = try await decode(StaffListResponse.self, from: data)
    return wrapper.staff ?? []
  }

  // MARK: - Channels

  static func listMyChannels(token: String) async throws -> [ChannelSummary] {
    let data = try await get(path: "/api/chat/channels", token: token)
    let wrapper = try await decode(ChannelsListResponse.self, from: data)
    return wrapper.channels ?? []
  }

  static func listPublicChannels(token: String) async throws -> [ChannelSummary] {
    let data = try await get(path: "/api/chat/channels/public", token: token)
    let wrapper = try await decode(ChannelsListResponse.self, from: data)
    return wrapper.channels ?? []
  }

  static func searchChannels(token: String, query: String) async throws -> [ChannelSummary] {
    let data = try await get(
      path: path("/api/chat/channels/search", [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "limit", value: "50"),
      ]),
      token: token
    )
    let wrapper = try await decode(ChannelsListResponse.self, from: data)
    return wrapper.channels ?? []
  }

  static func getChannel(token: String, channelId: String) async throws -> ChannelSummary {
    let data = try await get(path: path("/api/chat/channels/get", [URLQueryItem(name: "channelId", value: channelId)]), token: token)
    let wrapper = try await decode(ChannelDetailResponse.self, from: data)
    guard let channel = wrapper.channel else { throw ChatAPIError.notFound("Channel not found") }
    return channel
  }

  static func getChannelMembers(token: String, channelId: String) async throws -> [ChannelMember] {
    let data = try await get(path: path("/api/chat/channels/members", [URLQueryItem(name: "channelId", value: channelId)]), token: token)
    let wrapper = try await decode(ChannelMembersResponse.self, from: data)
    return wrapper.members ?? []
  }

  static func createChannel(
    token: String, name: String, description: String? = nil,
    type: String = "private", projectId: String? = nil, memberIds: [String]? = nil
  ) async throws -> String {
    var body: [String: Any] = ["name": name, "type": type]
    if let description { body["description"] = description }
    if let projectId { body["projectId"] = projectId }
    if let memberIds { body["memberIds"] = memberIds }
    let data = try await post(path: "/api/chat/channels/create", token: token, jsonBody: body)
    let wrapper = try await decode(CreateChannelResponse.self, from: data)
    guard let id = wrapper.channelId else { throw ChatAPIError.unexpected("Missing channelId") }
    return id
  }

  static func joinChannel(token: String, channelId: String) async throws {
    let body: [String: Any] = ["channelId": channelId]
    _ = try await post(path: "/api/chat/channels/join", token: token, jsonBody: body)
  }

  static func leaveChannel(token: String, channelId: String) async throws {
    let body: [String: Any] = ["channelId": channelId]
    _ = try await post(path: "/api/chat/channels/leave", token: token, jsonBody: body)
  }

  static func addChannelMember(token: String, channelId: String, memberStackUserId: String) async throws {
    let body: [String: Any] = [
      "channelId": channelId,
      "staffId": memberStackUserId,
    ]
    _ = try await post(path: "/api/chat/channels/add-member", token: token, jsonBody: body)
  }

  static func removeChannelMember(token: String, channelId: String, memberStackUserId: String) async throws {
    let body: [String: Any] = [
      "channelId": channelId,
      "staffId": memberStackUserId,
    ]
    _ = try await post(path: "/api/chat/channels/remove-member", token: token, jsonBody: body)
  }

  static func setChannelMute(token: String, channelId: String, muted: Bool) async throws {
    let body: [String: Any] = ["channelId": channelId, "muted": muted]
    _ = try await post(path: "/api/chat/channels/set-mute", token: token, jsonBody: body)
  }

  static func setChannelRole(token: String, channelId: String, memberStackUserId: String, role: String) async throws {
    let body: [String: Any] = [
      "channelId": channelId,
      "targetStaffId": memberStackUserId,
      "role": role,
    ]
    _ = try await post(path: "/api/chat/channels/set-role", token: token, jsonBody: body)
  }

  static func updateChannel(
    token: String,
    channelId: String,
    name: String? = nil,
    description: String? = nil,
    type: String? = nil,
    avatarStorageId: String? = nil
  ) async throws {
    var body: [String: Any] = ["channelId": channelId]
    if let name { body["name"] = name }
    if let description { body["description"] = description }
    if let type { body["type"] = type }
    if let avatarStorageId { body["avatarStorageId"] = avatarStorageId }
    _ = try await post(path: "/api/chat/channels/update", token: token, jsonBody: body)
  }

  static func archiveChannel(token: String, channelId: String) async throws {
    let body: [String: Any] = ["channelId": channelId]
    _ = try await post(path: "/api/chat/channels/archive", token: token, jsonBody: body)
  }

  static func deleteChannel(token: String, channelId: String) async throws {
    let body: [String: Any] = ["channelId": channelId]
    _ = try await post(path: "/api/chat/channels/delete", token: token, jsonBody: body)
  }

  // MARK: - Conversations

  static func listConversations(token: String) async throws -> [ConvexConversationSummary] {
    let data = try await get(path: "/api/chat/conversations", token: token)
    let wrapper = try await decode(ConversationsListResponse.self, from: data)
    return wrapper.conversations ?? []
  }

  static func getConversation(token: String, conversationId: String) async throws -> ConvexConversationSummary {
    let data = try await get(path: path("/api/chat/conversations/get", [URLQueryItem(name: "conversationId", value: conversationId)]), token: token)
    let wrapper = try await decode(ConversationDetailResponse.self, from: data)
    guard let conv = wrapper.conversation else { throw ChatAPIError.notFound("Conversation not found") }
    return conv
  }

  static func startOrFindDM(token: String, otherStaffId: String) async throws -> String {
    let body: [String: Any] = ["otherStaffId": otherStaffId]
    let data = try await post(path: "/api/chat/conversations/dm", token: token, jsonBody: body)
    let wrapper = try await decode(StartDMResponse.self, from: data)
    guard let id = wrapper.conversationId else { throw ChatAPIError.unexpected("Missing conversationId") }
    return id
  }

  static func createGroupDM(token: String, memberIds: [String], name: String? = nil) async throws -> String {
    var body: [String: Any] = ["memberIds": memberIds]
    if let name { body["name"] = name }
    let data = try await post(path: "/api/chat/conversations/group-dm", token: token, jsonBody: body)
    let wrapper = try await decode(StartDMResponse.self, from: data)
    guard let id = wrapper.conversationId else { throw ChatAPIError.unexpected("Missing conversationId") }
    return id
  }

  static func addConversationMember(token: String, conversationId: String, memberStackUserId: String) async throws {
    let body: [String: Any] = [
      "conversationId": conversationId,
      "staffId": memberStackUserId,
    ]
    _ = try await post(path: "/api/chat/conversations/add-member", token: token, jsonBody: body)
  }

  static func removeConversationMember(token: String, conversationId: String, memberStackUserId: String) async throws {
    let body: [String: Any] = [
      "conversationId": conversationId,
      "staffId": memberStackUserId,
    ]
    _ = try await post(path: "/api/chat/conversations/remove-member", token: token, jsonBody: body)
  }

  static func updateGroupConversation(
    token: String,
    conversationId: String,
    name: String,
    description: String
  ) async throws {
    let body: [String: Any] = [
      "conversationId": conversationId,
      "name": name,
      "description": description,
    ]
    _ = try await post(path: "/api/chat/conversations/update", token: token, jsonBody: body)
  }

  static func setConversationRole(
    token: String,
    conversationId: String,
    memberStackUserId: String,
    role: String
  ) async throws {
    let body: [String: Any] = [
      "conversationId": conversationId,
      "targetStaffId": memberStackUserId,
      "role": role,
    ]
    _ = try await post(path: "/api/chat/conversations/set-role", token: token, jsonBody: body)
  }

  static func hideConversation(token: String, conversationId: String) async throws {
    let body: [String: Any] = ["conversationId": conversationId]
    _ = try await post(path: "/api/chat/conversations/hide", token: token, jsonBody: body)
  }

  static func setConversationMute(token: String, conversationId: String, muted: Bool) async throws {
    let body: [String: Any] = ["conversationId": conversationId, "muted": muted]
    _ = try await post(path: "/api/chat/conversations/set-mute", token: token, jsonBody: body)
  }

  // MARK: - Messages

  static func listChannelMessages(token: String, channelId: String, numItems: Int = 25, cursor: String? = nil) async throws -> PaginatedMessages {
    var items = [
      URLQueryItem(name: "channelId", value: channelId),
      URLQueryItem(name: "numItems", value: String(numItems)),
    ]
    if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
    let data = try await get(path: path("/api/chat/messages/channel", items), token: token)
    return try await decode(PaginatedMessages.self, from: data)
  }

  static func listConversationMessages(token: String, conversationId: String, numItems: Int = 25, cursor: String? = nil) async throws -> PaginatedMessages {
    var items = [
      URLQueryItem(name: "conversationId", value: conversationId),
      URLQueryItem(name: "numItems", value: String(numItems)),
    ]
    if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
    let data = try await get(path: path("/api/chat/messages/conversation", items), token: token)
    return try await decode(PaginatedMessages.self, from: data)
  }

  static func listReplies(token: String, parentMessageId: String) async throws -> [ConvexChatMessage] {
    let data = try await get(path: path("/api/chat/messages/replies", [URLQueryItem(name: "parentMessageId", value: parentMessageId)]), token: token)
    let wrapper = try await decode(RepliesResponse.self, from: data)
    return wrapper.replies ?? []
  }

  static func getMessage(token: String, messageId: String) async throws -> ConvexChatMessage {
    let data = try await get(path: path("/api/chat/messages/get", [URLQueryItem(name: "messageId", value: messageId)]), token: token)
    let wrapper = try await decode(MessageDetailResponse.self, from: data)
    guard let msg = wrapper.message else { throw ChatAPIError.notFound("Message not found") }
    return msg
  }

  static func getUnreadSummary(token: String) async throws -> UnreadSummary {
    let data = try await get(path: "/api/chat/messages/unread-summary", token: token)
    let wrapper = try await decode(UnreadSummaryResponse.self, from: data)
    return wrapper.summary
      ?? UnreadSummary(
        channels: wrapper.channels ?? wrapper.unreadChannels ?? 0,
        dms: wrapper.dms ?? wrapper.unreadConversations ?? 0,
        mentions: wrapper.mentions ?? 0,
        total: wrapper.total ?? wrapper.totalUnreadMessages ?? 0
      )
  }

  static func sendMessage(
    token: String,
    channelId: String? = nil,
    conversationId: String? = nil,
    body: String,
    parentMessageId: String? = nil,
    mentionedStaffIds: [String]? = nil,
    channelMentionType: String? = nil,
    attachments: [[String: Any]]? = nil
  ) async throws -> String {
    guard (channelId == nil) != (conversationId == nil) else {
      throw ChatAPIError.unexpected("Send message requires exactly one channelId or conversationId")
    }
    var json: [String: Any] = ["body": body]
    if let channelId { json["channelId"] = channelId }
    if let conversationId { json["conversationId"] = conversationId }
    if let parentMessageId { json["parentMessageId"] = parentMessageId }
    if let mentionedStaffIds { json["mentionedStaffIds"] = mentionedStaffIds }
    if let channelMentionType { json["channelMentionType"] = channelMentionType }
    if let attachments, !attachments.isEmpty { json["attachments"] = attachments }
    let data = try await post(path: "/api/chat/messages/send", token: token, jsonBody: json)
    let wrapper = try await decode(SendMessageResponse.self, from: data)
    guard let id = wrapper.messageId else { throw ChatAPIError.unexpected("Missing messageId") }
    return id
  }

  /// Upload chat media through the authenticated endpoint used by Android.
  static func uploadAttachment(
    token: String,
    data fileData: Data,
    mimeType: String
  ) async throws -> String {
    guard !fileData.isEmpty else {
      throw ChatAPIError.unexpected("The selected attachment is empty")
    }
    guard let url = URL(string: "\(baseURL)/api/storage/upload") else {
      throw ChatAPIError.badURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 90
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 90
    configuration.timeoutIntervalForResource = 180
    let session = URLSession(configuration: configuration)
    let (responseData, response) = try await session.upload(for: request, from: fileData)
    try checkHTTPError(data: responseData, response: response, request: request)

    let wrapper = try await decode(StorageUploadResponse.self, from: responseData)
    guard wrapper.success, let storageId = wrapper.storageId, !storageId.isEmpty else {
      throw ChatAPIError.unexpected(
        wrapper.error ?? "The attachment upload did not return a storage ID"
      )
    }
    return storageId
  }

  static func editMessage(token: String, messageId: String, body: String) async throws {
    let json: [String: Any] = ["messageId": messageId, "body": body]
    _ = try await post(path: "/api/chat/messages/edit", token: token, jsonBody: json)
  }

  static func deleteMessage(token: String, messageId: String) async throws {
    let json: [String: Any] = ["messageId": messageId]
    _ = try await post(path: "/api/chat/messages/delete", token: token, jsonBody: json)
  }

  static func markChannelRead(token: String, channelId: String) async throws {
    let json: [String: Any] = ["channelId": channelId]
    _ = try await post(path: "/api/chat/messages/mark-channel-read", token: token, jsonBody: json)
  }

  static func markConversationRead(token: String, conversationId: String) async throws {
    let json: [String: Any] = ["conversationId": conversationId]
    _ = try await post(path: "/api/chat/messages/mark-conversation-read", token: token, jsonBody: json)
  }

  // MARK: - Search & Attachments

  static func searchMessages(
    token: String,
    query: String,
    conversationId: String? = nil,
    channelId: String? = nil,
    limit: Int = 50
  ) async throws -> [ConvexChatMessage] {
    var components = URLComponents()
    components.path = "/api/chat/messages/search"
    var items: [URLQueryItem] = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    if let conversationId { items.append(URLQueryItem(name: "conversationId", value: conversationId)) }
    if let channelId { items.append(URLQueryItem(name: "channelId", value: channelId)) }
    components.queryItems = items
    let path = (components.path) + "?" + (components.percentEncodedQuery ?? "")
    let data = try await get(path: path, token: token)
    let wrapper = try await decode(SearchMessagesResponse.self, from: data)
    return wrapper.messages ?? wrapper.results ?? []
  }

  static func listAttachments(
    token: String,
    conversationId: String? = nil,
    channelId: String? = nil,
    limit: Int = 100
  ) async throws -> [ConvexChatMessage] {
    var components = URLComponents()
    components.path = "/api/chat/messages/attachments"
    var items: [URLQueryItem] = [
      URLQueryItem(name: "limit", value: String(limit))
    ]
    if let conversationId { items.append(URLQueryItem(name: "conversationId", value: conversationId)) }
    if let channelId { items.append(URLQueryItem(name: "channelId", value: channelId)) }
    components.queryItems = items
    let path = (components.path) + "?" + (components.percentEncodedQuery ?? "")
    let data = try await get(path: path, token: token)
    let wrapper = try await decode(AttachmentsResponse.self, from: data)
    return wrapper.messages ?? wrapper.attachments ?? []
  }

  // MARK: - Typing

  static func setTyping(token: String, channelId: String? = nil, conversationId: String? = nil) async throws {
    var json: [String: Any] = [:]
    if let channelId { json["channelId"] = channelId }
    if let conversationId { json["conversationId"] = conversationId }
    _ = try await post(path: "/api/chat/typing", token: token, jsonBody: json)
  }

  static func getTyping(token: String, channelId: String? = nil, conversationId: String? = nil) async throws -> [TypingUser] {
    var items: [URLQueryItem] = []
    if let channelId { items.append(URLQueryItem(name: "channelId", value: channelId)) }
    if let conversationId { items.append(URLQueryItem(name: "conversationId", value: conversationId)) }
    let data = try await get(path: path("/api/chat/typing", items), token: token)
    let wrapper = try await decode(TypingResponse.self, from: data)
    return wrapper.typing ?? []
  }

  // MARK: - Reactions

  static func getReactions(token: String, messageId: String, messageSource: String) async throws -> [MessageReactionInfo] {
    let data = try await get(path: path("/api/chat/reactions", [URLQueryItem(name: "messageId", value: messageId)]), token: token)
    let wrapper = try await decode(ReactionsResponse.self, from: data)
    return wrapper.reactions ?? []
  }

  static func addReaction(token: String, messageId: String, messageSource: String, emoji: String) async throws -> MessageReactionResult {
    let body: [String: Any] = ["messageId": messageId, "messageSource": messageSource, "emoji": emoji]
    let data = try await post(path: "/api/chat/reactions/add", token: token, jsonBody: body)
    let wrapper = try await decode(ReactionMutationResponse.self, from: data)
    return MessageReactionResult(added: wrapper.added ?? wrapper.success ?? true, removed: false)
  }

  static func removeReaction(token: String, messageId: String, messageSource: String, emoji: String) async throws -> MessageReactionResult {
    let body: [String: Any] = ["messageId": messageId, "messageSource": messageSource, "emoji": emoji]
    let data = try await post(path: "/api/chat/reactions/remove", token: token, jsonBody: body)
    let wrapper = try await decode(ReactionMutationResponse.self, from: data)
    return MessageReactionResult(added: false, removed: wrapper.removed ?? wrapper.success ?? true)
  }

  static func toggleReaction(token: String, messageId: String, messageSource: String, emoji: String) async throws -> MessageReactionResult {
    let body: [String: Any] = ["messageId": messageId, "messageSource": messageSource, "emoji": emoji]
    let data = try await post(path: "/api/chat/reactions/toggle", token: token, jsonBody: body)
    let wrapper = try await decode(ReactionMutationResponse.self, from: data)
    return MessageReactionResult(
      added: wrapper.added ?? (wrapper.state == "added" ? true : nil),
      removed: wrapper.removed ?? (wrapper.state == "removed" ? true : nil)
    )
  }

  static func getBulkReactions(token: String, messageIds: [String]) async throws -> [String: [MessageReactionInfo]] {
    let body: [String: Any] = ["messageIds": messageIds]
    let data = try await post(path: "/api/chat/reactions/bulk", token: token, jsonBody: body)
    let wrapper = try await decode(BulkReactionsResponse.self, from: data)
    return wrapper.reactions ?? [:]
  }

  // MARK: - Presence

  static func getPresence(token: String, stackUserIds: [String]) async throws -> [UserPresenceInfo] {
    var components = URLComponents()
    components.path = "/api/chat/presence"
    if !stackUserIds.isEmpty {
      components.queryItems = [
        URLQueryItem(name: "staffIds", value: stackUserIds.joined(separator: ",")),
      ]
    }
    let path = components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
    let data = try await get(path: path, token: token)
    let wrapper = try await decode(PresenceResponse.self, from: data)
    return wrapper.presence ?? wrapper.users ?? []
  }

  static func getOnlinePresence(token: String) async throws -> [UserPresenceInfo] {
    let data = try await get(path: path("/api/chat/presence/online", [URLQueryItem(name: "limit", value: "100")]), token: token)
    let wrapper = try await decode(PresenceResponse.self, from: data)
    return wrapper.presence ?? wrapper.users ?? []
  }

  static func sendPresenceHeartbeat(
    token: String,
    status: PresenceStatus? = nil,
    customStatusText: String? = nil,
    customStatusEmoji: String? = nil
  ) async throws -> PresenceHeartbeatResponse {
    var body: [String: Any] = [:]
    if let status { body["status"] = status.rawValue }
    let data = try await post(path: "/api/chat/presence/heartbeat", token: token, jsonBody: body)
    return try await decode(PresenceHeartbeatResponse.self, from: data)
  }

  // MARK: - Push Notifications

  static func registerPushToken(
    token: String,
    deviceToken: String,
    platform: String = "ios",
    provider: String? = nil,
    bundleId: String? = nil
  ) async throws -> String {
    let resolvedBundleId = bundleId ?? Bundle.main.bundleIdentifier ?? "com.manju.chat"
    let resolvedProvider = provider ?? (platform == "ios_voip" ? "apns_voip" : "apns")
    let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? "M-Chat"
    let device = LoginDeviceInfo.capture()
    var body: [String: Any] = [
      "token": deviceToken,
      "platform": platform,
      "provider": resolvedProvider,
      "bundleId": resolvedBundleId,
      "appId": resolvedBundleId,
      "appName": appName,
      "deviceId": device?.deviceId ?? "",
    ]
    if let model = device?.model { body["deviceModel"] = model }
    let data = try await post(path: "/api/push/register", token: token, jsonBody: body)
    let wrapper = try await decode(RegisterPushResponse.self, from: data)
    guard wrapper.success else { throw ChatAPIError.unexpected(wrapper.error ?? "Push registration failed") }
    return wrapper.deviceTokenId ?? ""
  }

  static func unregisterPushToken(token: String, deviceToken: String) async throws {
    let body: [String: Any] = ["token": deviceToken]
    _ = try await post(path: "/api/push/unregister", token: token, jsonBody: body)
  }

  // MARK: - Message Polling

  static func pollMessages(token: String, conversationId: String? = nil, channelId: String? = nil, after: Double = 0) async throws -> [ConvexChatMessage] {
    var items = [URLQueryItem(name: "after", value: String(after))]
    if let conversationId { items.append(URLQueryItem(name: "conversationId", value: conversationId)) }
    if let channelId { items.append(URLQueryItem(name: "channelId", value: channelId)) }
    let data = try await get(path: path("/api/chat/messages/poll", items), token: token)
    let wrapper = try await decode(PollMessagesResponse.self, from: data)
    return wrapper.messages ?? []
  }

  // MARK: - Notifications

  static func getNotifications(token: String) async throws -> [AppNotification] {
    let data = try await get(path: "/api/notifications", token: token)
    let wrapper = try await decode(NotificationsListResponse.self, from: data)
    return wrapper.notifications ?? []
  }

  static func getUnreadNotificationCount(token: String) async throws -> Int {
    let data = try await get(path: "/api/notifications/unread-count", token: token)
    let wrapper = try await decode(UnreadCountResponse.self, from: data)
    return wrapper.unreadCount ?? 0
  }

  static func markNotificationRead(token: String, id: String) async throws {
    let body: [String: Any] = ["id": id]
    _ = try await post(path: "/api/notifications/mark-read", token: token, jsonBody: body)
  }

  static func markAllNotificationsRead(token: String) async throws {
    _ = try await post(path: "/api/notifications/mark-all-read", token: token, jsonBody: [:])
  }

  // MARK: - Internal response wrappers

  private struct ChannelsListResponse: Decodable, Sendable {
    let success: Bool; let channels: [ChannelSummary]?; let error: String?
  }
  private struct ChannelDetailResponse: Decodable, Sendable {
    let success: Bool; let channel: ChannelSummary?; let error: String?
  }
  private struct ChannelMembersResponse: Decodable, Sendable {
    let success: Bool; let members: [ChannelMember]?; let error: String?
  }
  private struct CreateChannelResponse: Decodable, Sendable {
    let success: Bool; let channelId: String?; let error: String?
  }
  private struct ConversationsListResponse: Decodable, Sendable {
    let success: Bool; let conversations: [ConvexConversationSummary]?; let error: String?
  }
  private struct ConversationDetailResponse: Decodable, Sendable {
    let success: Bool; let conversation: ConvexConversationSummary?; let error: String?
  }
  private struct StartDMResponse: Decodable, Sendable {
    let success: Bool; let conversationId: String?; let error: String?
  }
  private struct RepliesResponse: Decodable, Sendable {
    let success: Bool; let replies: [ConvexChatMessage]?; let error: String?
  }
  private struct MessageDetailResponse: Decodable, Sendable {
    let success: Bool; let message: ConvexChatMessage?; let error: String?
  }
  private struct SendMessageResponse: Decodable, Sendable {
    let success: Bool; let messageId: String?; let error: String?
  }
  private struct UnreadSummaryResponse: Decodable, Sendable {
    let success: Bool?
    let summary: UnreadSummary?
    let channels: Int?
    let dms: Int?
    let mentions: Int?
    let total: Int?
    let totalUnreadMessages: Int?
    let unreadChannels: Int?
    let unreadConversations: Int?
    let error: String?
  }
  private struct TypingResponse: Decodable, Sendable {
    let success: Bool; let typing: [TypingUser]?; let error: String?
  }
  private struct ReactionsResponse: Decodable, Sendable {
    let success: Bool?
    let reactions: [MessageReactionInfo]?
    let error: String?
  }
  private struct ReactionMutationResponse: Decodable, Sendable {
    let success: Bool?
    let added: Bool?
    let removed: Bool?
    let state: String?
    let error: String?
  }
  private struct BulkReactionsResponse: Decodable, Sendable {
    let success: Bool?
    let reactions: [String: [MessageReactionInfo]]?
    let error: String?
  }
  private struct PresenceResponse: Decodable, Sendable {
    let success: Bool?
    let presence: [UserPresenceInfo]?
    let users: [UserPresenceInfo]?
    let error: String?
  }
  struct PresenceHeartbeatResponse: Decodable, Sendable {
    let success: Bool?
    let status: String?
    let cleared: Bool?
    let error: String?
  }
  private struct SearchMessagesResponse: Decodable, Sendable {
    let success: Bool?; let messages: [ConvexChatMessage]?; let results: [ConvexChatMessage]?; let total: Int?; let error: String?
  }
  private struct AttachmentsResponse: Decodable, Sendable {
    let success: Bool?; let messages: [ConvexChatMessage]?; let attachments: [ConvexChatMessage]?; let total: Int?; let error: String?
  }

  private struct RegisterPushResponse: Decodable, Sendable {
    let success: Bool; let deviceTokenId: String?; let error: String?
  }
  private struct PollMessagesResponse: Decodable, Sendable {
    let success: Bool; let count: Int?; let messages: [ConvexChatMessage]?; let error: String?
  }
  private struct NotificationsListResponse: Decodable, Sendable {
    let success: Bool; let total: Int?; let notifications: [AppNotification]?; let error: String?
  }
  private struct UnreadCountResponse: Decodable, Sendable {
    let success: Bool; let unreadCount: Int?; let error: String?
  }

  struct PaginatedMessages: Decodable, Sendable {
    let success: Bool
    let page: [ConvexChatMessage]?
    let isDone: Bool?
    let continueCursor: String?
    let error: String?
  }

  struct UnreadSummary: Decodable, Sendable {
    let channels: Int
    let dms: Int
    let mentions: Int
    let total: Int

    var totalUnreadMessages: Int { total }
    var unreadChannels: Int { channels }
    var unreadConversations: Int { dms }
  }

  // MARK: - HTTP helpers

  private static func path(_ path: String, _ queryItems: [URLQueryItem]) -> String {
    guard !queryItems.isEmpty else { return path }
    var components = URLComponents()
    components.path = path
    components.queryItems = queryItems
    return components.path + "?" + (components.percentEncodedQuery ?? "")
  }

  private static func get(path: String, token: String) async throws -> Data {
    guard let url = URL(string: "\(baseURL)\(path)") else { throw ChatAPIError.badURL }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    try checkHTTPError(data: data, response: response, request: request)
    return data
  }

  private static func post(path: String, token: String, jsonBody: [String: Any]) async throws -> Data {
    guard let url = URL(string: "\(baseURL)\(path)") else { throw ChatAPIError.badURL }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
    let (data, response) = try await URLSession.shared.data(for: request)
    try checkHTTPError(data: data, response: response, request: request)
    return data
  }

  private static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
    try await BackgroundJSONDecoder.decode(type, from: data)
  }

  private static func checkHTTPError(data: Data, response: URLResponse, request: URLRequest) throws {
    guard let http = response as? HTTPURLResponse else { return }
    if http.statusCode == 401 {
      SessionInvalidationBus.emit(for: request)
      // Try to extract error message
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let error = json["error"] as? String {
        throw ChatAPIError.unauthorized(error)
      }
      throw ChatAPIError.unauthorized("Unauthorized")
    }
    if http.statusCode >= 400 {
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let error = json["error"] as? String {
        throw ChatAPIError.server(error, statusCode: http.statusCode)
      }
      throw ChatAPIError.server("Request failed", statusCode: http.statusCode)
    }
  }

}

private extension KeyedDecodingContainer {
  func decodeFirstPresentString(forKeys keys: [Key]) throws -> String? {
    for key in keys {
      if let value = try decodeIfPresent(String.self, forKey: key),
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return value
      }
    }
    return nil
  }
}

enum ChatAPIError: LocalizedError {
  case badURL
  case unauthorized(String)
  case notFound(String)
  case server(String, statusCode: Int)
  case unexpected(String)

  var errorDescription: String? {
    switch self {
    case .badURL: return "Invalid URL"
    case .unauthorized(let msg): return msg
    case .notFound(let msg): return msg
    case .server(let msg, _): return msg
    case .unexpected(let msg): return msg
    }
  }
}
