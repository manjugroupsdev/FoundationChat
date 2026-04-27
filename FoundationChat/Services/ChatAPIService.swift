import Foundation

/// HTTP client for all chat-related endpoints (channels, conversations, messages, typing).
enum ChatAPIService {
  private static let baseURL = AppConfig.baseURL

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
  }

  private struct StaffListResponse: Decodable {
    let success: Bool?
    let staff: [StaffMember]?
    let total: Int?
  }

  /// Fetch active staff directory (requires auth).
  static func listActiveStaff(token: String) async throws -> [StaffMember] {
    let data = try await get(path: "/api/hr/staff/active", token: token)
    let wrapper = try decode(StaffListResponse.self, from: data)
    return wrapper.staff ?? []
  }

  // MARK: - Channels

  static func listMyChannels(token: String) async throws -> [ChannelSummary] {
    let data = try await get(path: "/api/chat/channels", token: token)
    let wrapper = try decode(ChannelsListResponse.self, from: data)
    return wrapper.channels ?? []
  }

  static func listPublicChannels(token: String) async throws -> [ChannelSummary] {
    let data = try await get(path: "/api/chat/channels/public", token: token)
    let wrapper = try decode(ChannelsListResponse.self, from: data)
    return wrapper.channels ?? []
  }

  static func getChannel(token: String, channelId: String) async throws -> ChannelSummary {
    let data = try await get(path: "/api/chat/channels/get?channelId=\(channelId)", token: token)
    let wrapper = try decode(ChannelDetailResponse.self, from: data)
    guard let channel = wrapper.channel else { throw ChatAPIError.notFound("Channel not found") }
    return channel
  }

  static func getChannelMembers(token: String, channelId: String) async throws -> [ChannelMember] {
    let data = try await get(path: "/api/chat/channels/members?channelId=\(channelId)", token: token)
    let wrapper = try decode(ChannelMembersResponse.self, from: data)
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
    let wrapper = try decode(CreateChannelResponse.self, from: data)
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

  static func updateChannel(token: String, channelId: String, name: String? = nil, description: String? = nil, type: String? = nil) async throws {
    var body: [String: Any] = ["channelId": channelId]
    if let name { body["name"] = name }
    if let description { body["description"] = description }
    if let type { body["type"] = type }
    _ = try await post(path: "/api/chat/channels/update", token: token, jsonBody: body)
  }

  static func archiveChannel(token: String, channelId: String) async throws {
    let body: [String: Any] = ["channelId": channelId]
    _ = try await post(path: "/api/chat/channels/archive", token: token, jsonBody: body)
  }

  // MARK: - Conversations

  static func listConversations(token: String) async throws -> [ConvexConversationSummary] {
    let data = try await get(path: "/api/chat/conversations", token: token)
    let wrapper = try decode(ConversationsListResponse.self, from: data)
    return wrapper.conversations ?? []
  }

  static func getConversation(token: String, conversationId: String) async throws -> ConvexConversationSummary {
    let data = try await get(path: "/api/chat/conversations/get?conversationId=\(conversationId)", token: token)
    let wrapper = try decode(ConversationDetailResponse.self, from: data)
    guard let conv = wrapper.conversation else { throw ChatAPIError.notFound("Conversation not found") }
    return conv
  }

  static func startOrFindDM(token: String, otherStaffId: String) async throws -> String {
    let body: [String: Any] = ["otherStaffId": otherStaffId]
    let data = try await post(path: "/api/chat/conversations/dm", token: token, jsonBody: body)
    let wrapper = try decode(StartDMResponse.self, from: data)
    guard let id = wrapper.conversationId else { throw ChatAPIError.unexpected("Missing conversationId") }
    return id
  }

  static func createGroupDM(token: String, memberIds: [String], name: String? = nil) async throws -> String {
    var body: [String: Any] = ["memberIds": memberIds]
    if let name { body["name"] = name }
    let data = try await post(path: "/api/chat/conversations/group-dm", token: token, jsonBody: body)
    let wrapper = try decode(StartDMResponse.self, from: data)
    guard let id = wrapper.conversationId else { throw ChatAPIError.unexpected("Missing conversationId") }
    return id
  }

  // MARK: - Messages

  static func listChannelMessages(token: String, channelId: String, numItems: Int = 25, cursor: String? = nil) async throws -> PaginatedMessages {
    var path = "/api/chat/messages/channel?channelId=\(channelId)&numItems=\(numItems)"
    if let cursor { path += "&cursor=\(cursor)" }
    let data = try await get(path: path, token: token)
    return try decode(PaginatedMessages.self, from: data)
  }

  static func listConversationMessages(token: String, conversationId: String, numItems: Int = 25, cursor: String? = nil) async throws -> PaginatedMessages {
    var path = "/api/chat/messages/conversation?conversationId=\(conversationId)&numItems=\(numItems)"
    if let cursor { path += "&cursor=\(cursor)" }
    let data = try await get(path: path, token: token)
    return try decode(PaginatedMessages.self, from: data)
  }

  static func listReplies(token: String, parentMessageId: String) async throws -> [ConvexChatMessage] {
    let data = try await get(path: "/api/chat/messages/replies?parentMessageId=\(parentMessageId)", token: token)
    let wrapper = try decode(RepliesResponse.self, from: data)
    return wrapper.replies ?? []
  }

  static func getMessage(token: String, messageId: String) async throws -> ConvexChatMessage {
    let data = try await get(path: "/api/chat/messages/get?messageId=\(messageId)", token: token)
    let wrapper = try decode(MessageDetailResponse.self, from: data)
    guard let msg = wrapper.message else { throw ChatAPIError.notFound("Message not found") }
    return msg
  }

  static func sendMessage(
    token: String,
    channelId: String? = nil,
    conversationId: String? = nil,
    body: String,
    parentMessageId: String? = nil,
    mentionedStaffIds: [String]? = nil
  ) async throws -> String {
    var json: [String: Any] = ["body": body]
    if let channelId { json["channelId"] = channelId }
    if let conversationId { json["conversationId"] = conversationId }
    if let parentMessageId { json["parentMessageId"] = parentMessageId }
    if let mentionedStaffIds { json["mentionedStaffIds"] = mentionedStaffIds }
    let data = try await post(path: "/api/chat/messages/send", token: token, jsonBody: json)
    let wrapper = try decode(SendMessageResponse.self, from: data)
    guard let id = wrapper.messageId else { throw ChatAPIError.unexpected("Missing messageId") }
    return id
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
    let wrapper = try decode(SearchMessagesResponse.self, from: data)
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
    let wrapper = try decode(AttachmentsResponse.self, from: data)
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
    var path = "/api/chat/typing?"
    if let channelId { path += "channelId=\(channelId)" }
    if let conversationId { path += "conversationId=\(conversationId)" }
    let data = try await get(path: path, token: token)
    let wrapper = try decode(TypingResponse.self, from: data)
    return wrapper.typing ?? []
  }

  // MARK: - Push Notifications

  static func registerPushToken(token: String, deviceToken: String, platform: String = "ios", bundleId: String = "com.manju.chat") async throws -> String {
    let body: [String: Any] = ["token": deviceToken, "platform": platform, "bundleId": bundleId]
    let data = try await post(path: "/api/push/register", token: token, jsonBody: body)
    let wrapper = try decode(RegisterPushResponse.self, from: data)
    guard wrapper.success else { throw ChatAPIError.unexpected(wrapper.error ?? "Push registration failed") }
    return wrapper.deviceTokenId ?? ""
  }

  static func unregisterPushToken(token: String, deviceToken: String) async throws {
    let body: [String: Any] = ["token": deviceToken]
    _ = try await post(path: "/api/push/unregister", token: token, jsonBody: body)
  }

  // MARK: - Message Polling

  static func pollMessages(token: String, conversationId: String? = nil, channelId: String? = nil, after: Double = 0) async throws -> [ConvexChatMessage] {
    var path = "/api/chat/messages/poll?"
    if let conversationId { path += "conversationId=\(conversationId)&" }
    if let channelId { path += "channelId=\(channelId)&" }
    path += "after=\(after)"
    let data = try await get(path: path, token: token)
    let wrapper = try decode(PollMessagesResponse.self, from: data)
    return wrapper.messages ?? []
  }

  // MARK: - Notifications

  static func getNotifications(token: String) async throws -> [AppNotification] {
    let data = try await get(path: "/api/notifications", token: token)
    let wrapper = try decode(NotificationsListResponse.self, from: data)
    return wrapper.notifications ?? []
  }

  static func getUnreadNotificationCount(token: String) async throws -> Int {
    let data = try await get(path: "/api/notifications/unread-count", token: token)
    let wrapper = try decode(UnreadCountResponse.self, from: data)
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

  private struct ChannelsListResponse: Decodable {
    let success: Bool; let channels: [ChannelSummary]?; let error: String?
  }
  private struct ChannelDetailResponse: Decodable {
    let success: Bool; let channel: ChannelSummary?; let error: String?
  }
  private struct ChannelMembersResponse: Decodable {
    let success: Bool; let members: [ChannelMember]?; let error: String?
  }
  private struct CreateChannelResponse: Decodable {
    let success: Bool; let channelId: String?; let error: String?
  }
  private struct ConversationsListResponse: Decodable {
    let success: Bool; let conversations: [ConvexConversationSummary]?; let error: String?
  }
  private struct ConversationDetailResponse: Decodable {
    let success: Bool; let conversation: ConvexConversationSummary?; let error: String?
  }
  private struct StartDMResponse: Decodable {
    let success: Bool; let conversationId: String?; let error: String?
  }
  private struct RepliesResponse: Decodable {
    let success: Bool; let replies: [ConvexChatMessage]?; let error: String?
  }
  private struct MessageDetailResponse: Decodable {
    let success: Bool; let message: ConvexChatMessage?; let error: String?
  }
  private struct SendMessageResponse: Decodable {
    let success: Bool; let messageId: String?; let error: String?
  }
  private struct TypingResponse: Decodable {
    let success: Bool; let typing: [TypingUser]?; let error: String?
  }
  private struct SearchMessagesResponse: Decodable {
    let success: Bool?; let messages: [ConvexChatMessage]?; let results: [ConvexChatMessage]?; let total: Int?; let error: String?
  }
  private struct AttachmentsResponse: Decodable {
    let success: Bool?; let messages: [ConvexChatMessage]?; let attachments: [ConvexChatMessage]?; let total: Int?; let error: String?
  }

  private struct RegisterPushResponse: Decodable {
    let success: Bool; let deviceTokenId: String?; let error: String?
  }
  private struct PollMessagesResponse: Decodable {
    let success: Bool; let count: Int?; let messages: [ConvexChatMessage]?; let error: String?
  }
  private struct NotificationsListResponse: Decodable {
    let success: Bool; let total: Int?; let notifications: [AppNotification]?; let error: String?
  }
  private struct UnreadCountResponse: Decodable {
    let success: Bool; let unreadCount: Int?; let error: String?
  }

  struct PaginatedMessages: Decodable, Sendable {
    let success: Bool
    let page: [ConvexChatMessage]?
    let isDone: Bool?
    let continueCursor: String?
    let error: String?
  }

  // MARK: - HTTP helpers

  private static func get(path: String, token: String) async throws -> Data {
    guard let url = URL(string: "\(baseURL)\(path)") else { throw ChatAPIError.badURL }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    try checkHTTPError(data: data, response: response)
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
    try checkHTTPError(data: data, response: response)
    return data
  }

  private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    try JSONDecoder().decode(T.self, from: data)
  }

  private static func checkHTTPError(data: Data, response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { return }
    if http.statusCode == 401 {
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
