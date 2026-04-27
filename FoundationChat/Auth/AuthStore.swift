import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

// MARK: - QA debug auth bypass (KOS-25)
//
// Debug builds support a QA stub-auth gate enabled via the launch arg
// `-FCQAStubAuth 1` (read as `UserDefaults.standard.bool(forKey: "FCQAStubAuth")`).
// When set, `restoreSessionIfNeeded()` short-circuits to a deterministic
// `qa-stub-user` `OtpSession` so simulator smoke runs land in the
// authenticated tab tree without hitting
// `https://convex-http.aivida.in/api/auth/{send,verify}-otp`.
//
// Constraints:
// - Wrapped in `#if DEBUG`; not compiled into Release archives.
// - Opt-in only; never default-on.
// - Stub session is NOT persisted to `KeychainTokenStore` (prevents the
//   fake token bleeding into a subsequent real run).
// - Any code path that calls `requireToken()` (message send, push register,
//   notifications, HR endpoints) will hit the API with the literal
//   `"FCQA_STUB_TOKEN"` and the server will reject it. That is expected:
//   this gate is for UI tile/flow shell smoke, not authenticated network
//   exercise. Disable the launch arg for real-auth runs.
//
// Enable from QA: `xcrun simctl launch booted <bundle-id> -FCQAStubAuth 1`.

/// Lightweight identity view that existing views read via `authStore.viewer`.
struct ConvexViewerIdentity: Sendable, Equatable {
  let subject: String
  let name: String?
  let email: String?
  let phone: String?
  let photo: String?
}

@MainActor
@Observable
final class AuthStore {

  // MARK: - Public state

  enum Status {
    case loading
    case signedOut
    case signedIn
  }

  private(set) var status: Status = .loading
  private(set) var currentSession: OtpSession?
  private(set) var viewer: ConvexViewerIdentity?
  private(set) var errorMessage: String?
  private(set) var isAuthenticating = false
  private(set) var isRequestingOTP = false
  private(set) var lastKnownAPNSToken: String?
  private(set) var registeredAPNSToken: String?

  var currentUserLabel: String? {
    viewer?.name ?? viewer?.email ?? currentSession?.user.phone
  }

  var isAdmin: Bool {
    currentSession?.user.isAdmin == true
  }

  // MARK: - Private

  private let tokenStore = KeychainTokenStore()
  private var didAttemptRestore = false

  private var token: String? { currentSession?.token }

  private func requireToken() throws -> String {
    guard let t = token else { throw AuthStoreError.sessionNotAvailable }
    return t
  }

  // MARK: - Auth flow

  func restoreSessionIfNeeded() async {
    guard !didAttemptRestore else { return }
    didAttemptRestore = true
    status = .loading
    errorMessage = nil

    #if DEBUG
    if let stub = Self.qaStubSessionIfRequested() {
      applySession(stub)
      status = .signedIn
      return
    }
    #endif

    do {
      guard let stored = try tokenStore.load() else {
        status = .signedOut
        return
      }
      applySession(stored)
      status = .signedIn

      let freshUser = try await AuthAPIService.validateSession(token: stored.token)
      let refreshed = OtpSession(token: stored.token, user: freshUser)
      applySession(refreshed)
      try tokenStore.save(refreshed)
    } catch {
      try? tokenStore.clear()
      currentSession = nil
      viewer = nil
      status = .signedOut
    }
  }

  @discardableResult
  func requestOTP(phoneNumber: String) async throws -> String {
    let phone = Self.extractDigits(phoneNumber)
    guard phone.count == 10 else { throw AuthStoreError.invalidPhoneNumber }

    isRequestingOTP = true
    errorMessage = nil
    defer { isRequestingOTP = false }

    do {
      try await AuthAPIService.sendOTP(phone: phone)
      return phone
    } catch {
      errorMessage = error.localizedDescription
      throw error
    }
  }

  func verifyOTP(phoneNumber: String, code: String) async {
    let phone = Self.extractDigits(phoneNumber)
    let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !phone.isEmpty else { errorMessage = AuthStoreError.invalidPhoneNumber.localizedDescription; return }
    guard !trimmedCode.isEmpty else { errorMessage = AuthStoreError.invalidOTP.localizedDescription; return }

    isAuthenticating = true
    errorMessage = nil
    defer { isAuthenticating = false }

    do {
      let session = try await AuthAPIService.verifyOTP(phone: phone, otp: trimmedCode)
      applySession(session)
      try tokenStore.save(session)
      status = .signedIn
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func logout() async {
    // Unregister push token before logging out
    if let t = token, let deviceToken = lastKnownAPNSToken {
      try? await ChatAPIService.unregisterPushToken(token: t, deviceToken: deviceToken)
    }
    if let t = token { try? await AuthAPIService.logout(token: t) }
    try? tokenStore.clear()
    currentSession = nil
    viewer = nil
    errorMessage = nil
    isAuthenticating = false
    isRequestingOTP = false
    lastKnownAPNSToken = nil
    registeredAPNSToken = nil
    status = .signedOut
  }

  func handleAPNSToken(_ apnsToken: String) async {
    let normalized = apnsToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return }
    lastKnownAPNSToken = normalized

    // Register with backend if signed in
    guard let t = token, registeredAPNSToken != normalized else { return }
    do {
      _ = try await ChatAPIService.registerPushToken(token: t, deviceToken: normalized)
      registeredAPNSToken = normalized
    } catch {
      print("[push] failed to register device token: \(error.localizedDescription)")
    }
  }

  func requestNotificationPermissions() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
      if granted {
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
      if let error {
        print("[push] permission error: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Profile

  /// Persist profile edits to convex, then refresh the local session snapshot
  /// so `viewer`/`currentSession` reflect the new values immediately.
  @discardableResult
  func updateProfile(
    name: String?,
    email: String?,
    phone: String?,
    photoStorageId: String?
  ) async throws -> AuthUser {
    let t = try requireToken()
    let serverUser = try await HRConvexAPIService.updateMyProfile(
      token: t, name: name, email: email, phone: phone, photoStorageId: photoStorageId
    )

    let existing = currentSession?.user
    let merged = AuthUser(
      _id: serverUser?._id ?? existing?._id ?? "",
      employeeId: serverUser?.employeeId ?? existing?.employeeId,
      name: serverUser?.name ?? name ?? existing?.name,
      phone: serverUser?.phone ?? phone ?? existing?.phone,
      email: serverUser?.email ?? email ?? existing?.email,
      role: serverUser?.role ?? existing?.role,
      roleLevel: serverUser?.roleLevel ?? existing?.roleLevel,
      isAdmin: serverUser?.isAdmin ?? existing?.isAdmin,
      designation: serverUser?.designation ?? existing?.designation,
      department: serverUser?.department ?? existing?.department,
      status: serverUser?.status ?? existing?.status,
      photo: serverUser?.photo ?? photoStorageId ?? existing?.photo
    )

    let refreshed = OtpSession(token: t, user: merged)
    applySession(refreshed)
    try? tokenStore.save(refreshed)
    return merged
  }

  /// Resolve a Convex storage id (e.g. profile photo) to a download URL.
  func resolveStorageURL(storageId: String) async throws -> URL? {
    let t = try requireToken()
    let urlString = try await HRConvexAPIService.getFileURL(token: t, storageId: storageId)
    return URL(string: urlString)
  }

  // MARK: - Notifications

  func fetchNotifications() async throws -> [AppNotification] {
    let t = try requireToken()
    return try await ChatAPIService.getNotifications(token: t)
  }

  func fetchUnreadNotificationCount() async throws -> Int {
    let t = try requireToken()
    return try await ChatAPIService.getUnreadNotificationCount(token: t)
  }

  func markNotificationRead(id: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.markNotificationRead(token: t, id: id)
  }

  func markAllNotificationsRead() async throws {
    let t = try requireToken()
    try await ChatAPIService.markAllNotificationsRead(token: t)
  }

  // MARK: - Message Polling

  func pollMessages(conversationId: String? = nil, channelId: String? = nil, after: Double = 0) async throws -> [ConvexChatMessage] {
    let t = try requireToken()
    return try await ChatAPIService.pollMessages(token: t, conversationId: conversationId, channelId: channelId, after: after)
  }

  // MARK: - Channels

  func fetchChannels(search: String = "") async throws -> [ChannelSummary] {
    let t = try requireToken()
    // Merge "my channels" + public channels (de-duped) so users see everything available.
    async let myChannels = ChatAPIService.listMyChannels(token: t)
    async let publicChannels = ChatAPIService.listPublicChannels(token: t)

    var seen = Set<String>()
    var merged: [ChannelSummary] = []

    for ch in try await myChannels {
      if seen.insert(ch.id).inserted { merged.append(ch) }
    }
    for ch in try await publicChannels {
      if seen.insert(ch.id).inserted { merged.append(ch) }
    }

    if !search.isEmpty {
      let lowered = search.lowercased()
      merged = merged.filter { $0.name.lowercased().contains(lowered) }
    }

    return merged
  }

  func fetchPublicChannels() async throws -> [ChannelSummary] {
    let t = try requireToken()
    return try await ChatAPIService.listPublicChannels(token: t)
  }

  func fetchChannelMembers(channelID: String) async throws -> [ChannelMember] {
    let t = try requireToken()
    return try await ChatAPIService.getChannelMembers(token: t, channelId: channelID)
  }

  @discardableResult
  func sendChannelMessage(channelID: String, content: String) async throws -> ChannelChatMessage {
    let t = try requireToken()
    let messageId = try await ChatAPIService.sendMessage(token: t, channelId: channelID, body: content)
    // Return a lightweight local echo
    return ChannelChatMessage(
      _id: messageId, channelId: channelID, senderId: viewer?.subject,
      senderName: viewer?.name, body: content, isEdited: false, isDeleted: false,
      replyCount: 0, lastReplyAt: nil, parentMessageId: nil,
      _creationTime: Date().timeIntervalSince1970 * 1000
    )
  }

  @discardableResult
  func createChannel(name: String, description: String?) async throws -> CreateChannelResult {
    let t = try requireToken()
    let channelId = try await ChatAPIService.createChannel(token: t, name: name, description: description)
    return CreateChannelResult(channelId: channelId)
  }

  @discardableResult
  func inviteMember(channelID: String, memberStackUserID: String) async throws -> InviteChannelMemberResult {
    // Join channel on behalf — use join endpoint
    let t = try requireToken()
    try await ChatAPIService.joinChannel(token: t, channelId: channelID)
    return InviteChannelMemberResult(channelId: channelID, memberStackUserId: memberStackUserID, invited: true)
  }

  func updateChannelDescription(channelId: String, description: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.updateChannel(token: t, channelId: channelId, description: description)
  }

  func subscribeChannelMessages(channelID: String) throws -> AnyPublisher<[ChannelChatMessage]?, Never> {
    // Polling-based: fetch once and wrap as publisher
    let t = try requireToken()
    return Future<[ChannelChatMessage]?, Never> { promise in
      Task {
        let result = try? await ChatAPIService.listChannelMessages(token: t, channelId: channelID)
        // Map ConvexChatMessage → ChannelChatMessage
        let mapped: [ChannelChatMessage]? = result?.page?.map { msg in
          ChannelChatMessage(
            _id: msg._id, channelId: msg.channelId, senderId: msg.senderId,
            senderName: msg.senderName, body: msg.body, isEdited: msg.isEdited,
            isDeleted: msg.isDeleted, replyCount: msg.replyCount,
            lastReplyAt: msg.lastReplyAt, parentMessageId: msg.parentMessageId,
            _creationTime: msg._creationTime
          )
        }
        promise(.success(mapped))
      }
    }.eraseToAnyPublisher()
  }

  func pinChannelMessage(channelId: String, messageId: String) async throws {
    // Not in current API — no-op
  }

  func unpinChannelMessage(channelId: String, messageId: String) async throws {
    // Not in current API — no-op
  }

  // MARK: - Conversations

  func fetchDirectoryUsers(search: String) async throws -> [DirectoryUser] {
    let t = try requireToken()
    let myId = viewer?.subject
    let staffList = try await ChatAPIService.listActiveStaff(token: t)

    var users = staffList.compactMap { staff -> DirectoryUser? in
      let staffId = staff._id ?? staff.phone ?? staff.employeeId ?? ""
      // Exclude the current user
      if staffId == myId { return nil }
      return DirectoryUser(
        _id: staffId,
        name: staff.name,
        email: staff.designation,
        profilePhoto: staff.profilePhoto
      )
    }

    // Filter by search
    if !search.isEmpty {
      let lowered = search.lowercased()
      users = users.filter {
        ($0.name?.lowercased().contains(lowered) ?? false)
          || ($0.email?.lowercased().contains(lowered) ?? false)
          || $0._id.lowercased().contains(lowered)
      }
    }

    return users
  }

  func startDirectConversation(withStackUserID otherStackUserID: String) async throws -> StartDirectConversationResult {
    let t = try requireToken()
    let convId = try await ChatAPIService.startOrFindDM(token: t, otherStaffId: otherStackUserID)
    return StartDirectConversationResult(conversationId: convId)
  }

  func fetchConversations() async throws -> [ConvexConversationSummary] {
    let t = try requireToken()
    return try await ChatAPIService.listConversations(token: t)
  }

  func subscribeConversations() throws -> AnyPublisher<[ConvexConversationSummary]?, Never> {
    let t = try requireToken()
    return Future<[ConvexConversationSummary]?, Never> { promise in
      Task {
        let result = try? await ChatAPIService.listConversations(token: t)
        promise(.success(result))
      }
    }.eraseToAnyPublisher()
  }

  func fetchMessages(conversationID: String) async throws -> [ConvexChatMessage] {
    let t = try requireToken()
    let result = try await ChatAPIService.listConversationMessages(token: t, conversationId: conversationID)
    return result.page ?? []
  }

  func subscribeMessages(conversationID: String) throws -> AnyPublisher<[ConvexChatMessage]?, Never> {
    let t = try requireToken()
    return Future<[ConvexChatMessage]?, Never> { promise in
      Task {
        let result = try? await ChatAPIService.listConversationMessages(token: t, conversationId: conversationID)
        promise(.success(result?.page))
      }
    }.eraseToAnyPublisher()
  }

  func deleteConversation(conversationID: String) async throws {
    // Not in current API
  }

  func markConversationSeen(conversationID: String, readAt: Date = Date()) async throws {
    let t = try requireToken()
    try await ChatAPIService.markConversationRead(token: t, conversationId: conversationID)
  }

  func searchMessages(
    query: String,
    conversationID: String? = nil,
    channelID: String? = nil,
    limit: Int = 50
  ) async throws -> [ConvexChatMessage] {
    let t = try requireToken()
    return try await ChatAPIService.searchMessages(
      token: t, query: query, conversationId: conversationID, channelId: channelID, limit: limit
    )
  }

  func fetchConversationAttachments(
    conversationID: String? = nil,
    channelID: String? = nil,
    limit: Int = 100
  ) async throws -> [ConvexChatMessage] {
    let t = try requireToken()
    return try await ChatAPIService.listAttachments(
      token: t, conversationId: conversationID, channelId: channelID, limit: limit
    )
  }

  func fetchConversation(conversationID: String) async throws -> ConvexConversationSummary {
    let t = try requireToken()
    return try await ChatAPIService.getConversation(token: t, conversationId: conversationID)
  }

  func fetchChannel(channelID: String) async throws -> ChannelSummary {
    let t = try requireToken()
    return try await ChatAPIService.getChannel(token: t, channelId: channelID)
  }

  func leaveChannel(channelID: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.leaveChannel(token: t, channelId: channelID)
  }

  func toggleConversationMute(conversationID: String, muted: Bool) async throws {
    // Backend mute endpoint not wired in current API; surface via notification preferences if needed.
    _ = try await upsertNotificationPreference(
      targetType: "conversation",
      targetId: conversationID,
      level: muted ? .none : .all
    )
  }

  func toggleChannelMute(channelID: String, muted: Bool) async throws {
    _ = try await upsertNotificationPreference(
      targetType: "channel",
      targetId: channelID,
      level: muted ? .none : .all
    )
  }

  func sendMessage(
    conversationID: String,
    role: Role,
    content: String,
    attachmentType: String? = nil,
    attachmentStorageId: String? = nil,
    attachmentFileName: String? = nil,
    attachmentMimeType: String? = nil,
    attachmentTitle: String? = nil,
    attachmentDescription: String? = nil,
    attachmentThumbnail: String? = nil
  ) async throws -> ConvexChatMessage {
    let t = try requireToken()
    let messageId = try await ChatAPIService.sendMessage(token: t, conversationId: conversationID, body: content)
    return ConvexChatMessage(
      _id: messageId, channelId: nil, conversationId: conversationID,
      senderId: viewer?.subject, senderName: viewer?.name, body: content,
      isEdited: false, isDeleted: false, replyCount: 0, lastReplyAt: nil,
      parentMessageId: nil, _creationTime: Date().timeIntervalSince1970 * 1000,
      attachments: nil
    )
  }

  func generateAttachmentUploadURL() async throws -> URL {
    throw AuthStoreError.notImplemented
  }

  func uploadAttachmentData(_ data: Data, uploadURL: URL, mimeType: String) async throws -> String {
    throw AuthStoreError.notImplemented
  }

  // MARK: - Files

  func fetchSharedFiles(search: String = "", typeFilter: String = "all") async throws -> [SharedFileItem] { [] }

  func savePrivateFile(
    storageId: String, attachmentType: String, fileName: String, mimeType: String,
    title: String? = nil, description: String? = nil, thumbnail: String? = nil
  ) async throws -> SavePrivateFileResult {
    throw AuthStoreError.notImplemented
  }

  func sharePrivateFileToConversation(fileID: String, conversationID: String) async throws -> SharePrivateFileResult {
    throw AuthStoreError.notImplemented
  }

  // MARK: - Message Edit & Delete

  @discardableResult
  func editMessage(messageId: String, newContent: String) async throws -> EditMessageResult {
    let t = try requireToken()
    try await ChatAPIService.editMessage(token: t, messageId: messageId, body: newContent)
    return EditMessageResult()
  }

  @discardableResult
  func deleteMessage(messageId: String) async throws -> DeleteMessageResult {
    let t = try requireToken()
    try await ChatAPIService.deleteMessage(token: t, messageId: messageId)
    return DeleteMessageResult()
  }

  @discardableResult
  func editChannelMessage(messageId: String, newContent: String) async throws -> EditMessageResult {
    let t = try requireToken()
    try await ChatAPIService.editMessage(token: t, messageId: messageId, body: newContent)
    return EditMessageResult()
  }

  @discardableResult
  func deleteChannelMessage(messageId: String) async throws -> DeleteMessageResult {
    let t = try requireToken()
    try await ChatAPIService.deleteMessage(token: t, messageId: messageId)
    return DeleteMessageResult()
  }

  // MARK: - Typing

  func setTypingIndicator(conversationId: String? = nil, channelId: String? = nil) async throws {
    let t = try requireToken()
    try await ChatAPIService.setTyping(token: t, channelId: channelId, conversationId: conversationId)
  }

  func clearTypingIndicator(conversationId: String? = nil, channelId: String? = nil) async throws {
    // Typing auto-expires after 5s server-side — no explicit clear endpoint.
  }

  func subscribeTypingUsers(conversationId: String? = nil, channelId: String? = nil) throws -> AnyPublisher<[TypingUser]?, Never> {
    let t = try requireToken()
    return Future<[TypingUser]?, Never> { promise in
      Task {
        let result = try? await ChatAPIService.getTyping(token: t, channelId: channelId, conversationId: conversationId)
        promise(.success(result))
      }
    }.eraseToAnyPublisher()
  }

  // MARK: - Mark read helpers

  func markChannelRead(channelID: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.markChannelRead(token: t, channelId: channelID)
  }

  // MARK: - Location (not in current API)

  @discardableResult
  func recordLocation(latitude: Double, longitude: Double, altitude: Double? = nil,
                      horizontalAccuracy: Double? = nil, speed: Double? = nil,
                      heading: Double? = nil, recordedAt: Double) async throws -> RecordLocationResult {
    throw AuthStoreError.notImplemented
  }

  @discardableResult
  func recordLocationBatch(points: String) async throws -> RecordBatchResult {
    throw AuthStoreError.notImplemented
  }

  func fetchLocationHistory(targetStackUserId: String, startDate: Double, endDate: Double) async throws -> [LocationPoint] { [] }
  func fetchTrackedUsers() async throws -> [TrackedUser] { [] }

  @discardableResult
  func deleteLocationHistory(targetStackUserId: String, startDate: Double, endDate: Double) async throws -> DeleteLocationsResult {
    throw AuthStoreError.notImplemented
  }

  // MARK: - Posts (not in current API)

  func fetchPosts(category: String? = nil) async throws -> [ConvexPost] { [] }
  func subscribePosts(category: String? = nil) throws -> AnyPublisher<[ConvexPost]?, Never> { Just(nil).eraseToAnyPublisher() }
  func fetchPostById(postId: String) async throws -> ConvexPost { throw AuthStoreError.notImplemented }

  @discardableResult
  func createPost(title: String?, body: String, imageStorageIds: [String]? = nil,
                  linkUrl: String? = nil, linkTitle: String? = nil, linkThumbnail: String? = nil,
                  isPinned: Bool = false, isAnnouncement: Bool = false,
                  category: String? = nil, scheduledAt: Double? = nil) async throws -> CreatePostResult {
    throw AuthStoreError.notImplemented
  }

  @discardableResult func deletePost(postId: String) async throws -> DeletePostResult { throw AuthStoreError.notImplemented }
  @discardableResult func addPostReaction(postId: String, emoji: String) async throws -> PostReactionResult { throw AuthStoreError.notImplemented }
  @discardableResult func addPostComment(postId: String, content: String, imageStorageId: String? = nil) async throws -> AddCommentResult { throw AuthStoreError.notImplemented }
  @discardableResult func deletePostComment(commentId: String) async throws -> DeleteCommentResult { throw AuthStoreError.notImplemented }
  func fetchPostComments(postId: String) async throws -> [PostComment] { [] }
  func subscribePostComments(postId: String) throws -> AnyPublisher<[PostComment]?, Never> { Just(nil).eraseToAnyPublisher() }
  @discardableResult func markPostRead(postId: String) async throws -> MarkPostReadResult { throw AuthStoreError.notImplemented }
  func fetchUnreadPostCount() async throws -> Int { 0 }

  // MARK: - Presence (not in current API)

  @discardableResult func sendPresenceHeartbeat() async throws -> HeartbeatResult { throw AuthStoreError.notImplemented }
  @discardableResult func setPresenceStatus(status: PresenceStatus, customStatusText: String? = nil, customStatusEmoji: String? = nil) async throws -> SetStatusResult { throw AuthStoreError.notImplemented }
  func fetchPresence(for stackUserIds: [String]) async throws -> [UserPresenceInfo] { [] }
  @discardableResult func clearPresenceStatus() async throws -> ClearStatusResult { throw AuthStoreError.notImplemented }

  // MARK: - Reactions (not in current API)

  @discardableResult func addMessageReaction(messageId: String, messageSource: String, emoji: String) async throws -> MessageReactionResult { throw AuthStoreError.notImplemented }
  func fetchMessageReactions(messageId: String, messageSource: String) async throws -> [MessageReactionInfo] { [] }

  // MARK: - Notification preferences (not in current API)

  func fetchNotificationPreference(targetType: String, targetId: String) async throws -> NotificationPreference? { nil }
  @discardableResult func upsertNotificationPreference(targetType: String, targetId: String, level: NotificationLevel, muteUntil: Double? = nil) async throws -> UpsertNotificationPrefResult { throw AuthStoreError.notImplemented }

  // MARK: - Storage folders (not in current API)

  func fetchStorageFolders(parentFolderId: String? = nil) async throws -> [StorageFolder] { [] }
  @discardableResult func createStorageFolder(name: String, parentFolderId: String? = nil) async throws -> CreateFolderResult { throw AuthStoreError.notImplemented }
  @discardableResult func deleteStorageFolder(folderId: String) async throws -> DeleteFolderResult { throw AuthStoreError.notImplemented }
  @discardableResult func moveFileToFolder(fileId: String, folderId: String?) async throws -> MoveFileResult { throw AuthStoreError.notImplemented }

  // MARK: - Helpers

  private func applySession(_ session: OtpSession) {
    currentSession = session
    let user = session.user
    viewer = ConvexViewerIdentity(
      subject: user._id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      photo: user.photo
    )
  }

  private static func extractDigits(_ input: String) -> String {
    let digits = input.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
    if digits.count > 10 { return String(digits.suffix(10)) }
    return digits
  }

  #if DEBUG
  /// Deterministic stub session for QA simulator smoke. See file header (KOS-25).
  /// Returns `nil` unless launched with `-FCQAStubAuth 1`.
  private static func qaStubSessionIfRequested() -> OtpSession? {
    guard UserDefaults.standard.bool(forKey: "FCQAStubAuth") else { return nil }
    let user = AuthUser(
      _id: "qa-stub-user",
      employeeId: "QA-STUB",
      name: "QA Stub",
      phone: "9999999999",
      email: "qa-stub@example.local",
      role: "staff",
      roleLevel: 0,
      isAdmin: false,
      designation: "QA Automation",
      department: "QA",
      status: "active",
      photo: nil
    )
    return OtpSession(token: "FCQA_STUB_TOKEN", user: user)
  }
  #endif
}

// MARK: - Errors

enum AuthStoreError: LocalizedError {
  case sessionNotAvailable
  case invalidPhoneNumber
  case invalidOTP
  case notImplemented

  var errorDescription: String? {
    switch self {
    case .sessionNotAvailable: return "Session is not available. Please sign in again."
    case .invalidPhoneNumber: return "Enter a valid 10-digit phone number."
    case .invalidOTP: return "Enter the OTP you received."
    case .notImplemented: return "This feature is not yet connected."
    }
  }
}
