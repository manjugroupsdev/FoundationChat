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

  var iamPermissions: Set<String> {
    Set(currentSession?.user.iamPermissions ?? [])
  }

  func hasPermission(_ permission: String) -> Bool {
    isAdmin || iamPermissions.contains(permission)
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
      await refreshIAMPermissions()
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
      await refreshIAMPermissions()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func refreshIAMPermissions() async {
    guard let t = token, currentSession?.token != "FCQA_STUB_TOKEN" else { return }
    do {
      let iam = try await AuthAPIService.getMyIAMPermissions(token: t)
      guard let existing = currentSession?.user else { return }
      let updated = AuthUser(
        _id: existing._id,
        staffId: existing.staffId,
        employeeId: existing.employeeId,
        name: existing.name,
        phone: existing.phone,
        email: existing.email,
        role: existing.role,
        roleLevel: existing.roleLevel,
        iamPermissions: iam.permissions,
        isAdmin: iam.isAdmin,
        designation: existing.designation,
        department: existing.department,
        status: existing.status,
        photo: existing.photo
      )
      let refreshed = OtpSession(token: t, user: updated)
      applySession(refreshed)
      try? tokenStore.save(refreshed)
    } catch {
      print("[auth] failed to refresh IAM permissions: \(error.localizedDescription)")
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
    PushTokenCache.lastKnownToken = normalized

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
      staffId: serverUser?.staffId ?? existing?.staffId,
      employeeId: serverUser?.employeeId ?? existing?.employeeId,
      name: serverUser?.name ?? name ?? existing?.name,
      phone: serverUser?.phone ?? phone ?? existing?.phone,
      email: serverUser?.email ?? email ?? existing?.email,
      role: serverUser?.role ?? existing?.role,
      roleLevel: serverUser?.roleLevel ?? existing?.roleLevel,
      iamPermissions: serverUser?.iamPermissions ?? existing?.iamPermissions,
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

  @discardableResult
  func refreshMyStaffProfile() async throws -> AuthUser {
    let t = try requireToken()
    let sessionUser = currentSession?.user
    let fallbackId = sessionUser?._id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let staffId = sessionUser?.staffId ?? (fallbackId?.isEmpty == false ? fallbackId : nil) else {
      throw AuthStoreError.sessionNotAvailable
    }
    let staff = try await HRConvexAPIService.getStaffDetail(token: t, id: staffId)
    let existing = currentSession?.user
    let refreshedUser = AuthUser(
      _id: existing?._id ?? staff._id,
      staffId: staff._id,
      employeeId: staff.employeeId ?? existing?.employeeId,
      name: staff.name ?? existing?.name,
      phone: staff.phone ?? existing?.phone,
      email: staff.email ?? existing?.email,
      role: existing?.role,
      roleLevel: staff.roleLevel ?? existing?.roleLevel,
      iamPermissions: existing?.iamPermissions,
      isAdmin: existing?.isAdmin,
      designation: staff.designation ?? existing?.designation,
      department: staff.department ?? existing?.department,
      status: staff.status ?? existing?.status,
      photo: staff.photo
    )
    let refreshed = OtpSession(token: t, user: refreshedUser)
    applySession(refreshed)
    try? tokenStore.save(refreshed)
    return refreshedUser
  }

  @discardableResult
  func setProfilePhoto(storageId: String) async throws -> AuthUser {
    let t = try requireToken()
    let serverUser = try await HRConvexAPIService.setMyProfilePhoto(token: t, storageId: storageId)
    return try await mergeProfilePhotoUpdate(serverUser: serverUser, fallbackPhoto: storageId)
  }

  @discardableResult
  func deleteProfilePhoto() async throws -> AuthUser {
    let t = try requireToken()
    let serverUser = try await HRConvexAPIService.deleteMyProfilePhoto(token: t)
    return try await mergeProfilePhotoUpdate(serverUser: serverUser, fallbackPhoto: nil, forceClearPhoto: true)
  }

  /// Resolve a Convex storage id (e.g. profile photo) to a download URL.
  func resolveStorageURL(storageId: String) async throws -> URL? {
    let t = try requireToken()
    let urlString = try await HRConvexAPIService.getFileURL(token: t, storageId: storageId)
    return URL(string: urlString)
  }

  private func mergeProfilePhotoUpdate(
    serverUser: AuthUser?,
    fallbackPhoto: String?,
    forceClearPhoto: Bool = false
  ) async throws -> AuthUser {
    let t = try requireToken()
    let existing = currentSession?.user
    let merged = AuthUser(
      _id: serverUser?._id ?? existing?._id ?? "",
      staffId: serverUser?.staffId ?? existing?.staffId,
      employeeId: serverUser?.employeeId ?? existing?.employeeId,
      name: serverUser?.name ?? existing?.name,
      phone: serverUser?.phone ?? existing?.phone,
      email: serverUser?.email ?? existing?.email,
      role: serverUser?.role ?? existing?.role,
      roleLevel: serverUser?.roleLevel ?? existing?.roleLevel,
      iamPermissions: serverUser?.iamPermissions ?? existing?.iamPermissions,
      isAdmin: serverUser?.isAdmin ?? existing?.isAdmin,
      designation: serverUser?.designation ?? existing?.designation,
      department: serverUser?.department ?? existing?.department,
      status: serverUser?.status ?? existing?.status,
      photo: forceClearPhoto ? nil : (serverUser?.photo ?? fallbackPhoto ?? existing?.photo)
    )
    let refreshed = OtpSession(token: t, user: merged)
    applySession(refreshed)
    try? tokenStore.save(refreshed)
    return merged
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
    let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)

    if !trimmed.isEmpty {
      return try await ChatAPIService.searchChannels(token: t, query: trimmed)
    }

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
  func sendChannelMessage(
    channelID: String,
    content: String,
    parentMessageId: String? = nil,
    mentionedStaffIds: [String]? = nil,
    attachments: [[String: Any]]? = nil
  ) async throws -> ChannelChatMessage {
    let t = try requireToken()
    let messageId = try await ChatAPIService.sendMessage(
      token: t,
      channelId: channelID,
      body: content,
      parentMessageId: parentMessageId,
      mentionedStaffIds: mentionedStaffIds,
      attachments: attachments
    )
    let saved = try await ChatAPIService.getMessage(token: t, messageId: messageId)
    return ChannelChatMessage(saved)
  }

  @discardableResult
  func createChannel(name: String, description: String?) async throws -> CreateChannelResult {
    let t = try requireToken()
    let channelId = try await ChatAPIService.createChannel(token: t, name: name, description: description)
    return CreateChannelResult(channelId: channelId)
  }

  @discardableResult
  func createGroupConversation(memberIds: [String], name: String? = nil) async throws -> StartDirectConversationResult {
    let t = try requireToken()
    let conversationId = try await ChatAPIService.createGroupDM(token: t, memberIds: memberIds, name: name)
    return StartDirectConversationResult(conversationId: conversationId)
  }

  @discardableResult
  func inviteMember(channelID: String, memberStackUserID: String) async throws -> InviteChannelMemberResult {
    let t = try requireToken()
    try await ChatAPIService.addChannelMember(
      token: t,
      channelId: channelID,
      memberStackUserId: memberStackUserID
    )
    return InviteChannelMemberResult(channelId: channelID, memberStackUserId: memberStackUserID, invited: true)
  }

  func removeMember(channelID: String, memberStackUserID: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.removeChannelMember(
      token: t,
      channelId: channelID,
      memberStackUserId: memberStackUserID
    )
  }

  func setChannelMemberRole(channelID: String, memberStackUserID: String, role: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.setChannelRole(
      token: t,
      channelId: channelID,
      memberStackUserId: memberStackUserID,
      role: role
    )
  }

  func updateChannelDescription(channelId: String, description: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.updateChannel(token: t, channelId: channelId, description: description)
  }

  func archiveChannel(channelID: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.archiveChannel(token: t, channelId: channelID)
  }

  func subscribeChannelMessages(channelID: String) throws -> AnyPublisher<[ChannelChatMessage]?, Never> {
    // Polling-based: fetch once and wrap as publisher
    let t = try requireToken()
    return Future<[ChannelChatMessage]?, Never> { promise in
      Task {
        let result = try? await ChatAPIService.listChannelMessages(token: t, channelId: channelID)
        let mapped: [ChannelChatMessage]? = result?.page?.map(ChannelChatMessage.init)
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
    try await hideConversation(conversationID: conversationID)
  }

  func addConversationMember(conversationID: String, memberStackUserID: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.addConversationMember(
      token: t,
      conversationId: conversationID,
      memberStackUserId: memberStackUserID
    )
  }

  func removeConversationMember(conversationID: String, memberStackUserID: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.removeConversationMember(
      token: t,
      conversationId: conversationID,
      memberStackUserId: memberStackUserID
    )
  }

  func hideConversation(conversationID: String) async throws {
    let t = try requireToken()
    try await ChatAPIService.hideConversation(token: t, conversationId: conversationID)
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

  func fetchMessage(messageID: String) async throws -> ConvexChatMessage {
    let t = try requireToken()
    return try await ChatAPIService.getMessage(token: t, messageId: messageID)
  }

  func fetchReplies(parentMessageID: String) async throws -> [ConvexChatMessage] {
    let t = try requireToken()
    return try await ChatAPIService.listReplies(token: t, parentMessageId: parentMessageID)
  }

  func fetchUnreadSummary() async throws -> ChatAPIService.UnreadSummary {
    let t = try requireToken()
    return try await ChatAPIService.getUnreadSummary(token: t)
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
    let t = try requireToken()
    try await ChatAPIService.setConversationMute(
      token: t,
      conversationId: conversationID,
      muted: muted
    )
  }

  func toggleChannelMute(channelID: String, muted: Bool) async throws {
    let t = try requireToken()
    try await ChatAPIService.setChannelMute(
      token: t,
      channelId: channelID,
      muted: muted
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
    attachmentFileSize: Int? = nil,
    attachmentTitle: String? = nil,
    attachmentDescription: String? = nil,
    attachmentThumbnail: String? = nil,
    parentMessageId: String? = nil,
    mentionedStaffIds: [String]? = nil,
    attachments: [[String: Any]]? = nil
  ) async throws -> ConvexChatMessage {
    let t = try requireToken()
    let attachmentsPayload: [[String: Any]]?
    if let attachments {
      attachmentsPayload = attachments
    } else if let attachmentStorageId {
      var attachment: [String: Any] = [
        "storageId": attachmentStorageId
      ]
      if let attachmentFileName, !attachmentFileName.isEmpty {
        attachment["fileName"] = attachmentFileName
      }
      if let attachmentMimeType, !attachmentMimeType.isEmpty {
        attachment["fileType"] = attachmentMimeType
      } else if let attachmentType, !attachmentType.isEmpty {
        attachment["fileType"] = attachmentType
      }
      if let attachmentFileSize {
        attachment["fileSize"] = attachmentFileSize
      }
      attachmentsPayload = [attachment]
    } else {
      attachmentsPayload = nil
    }

    let messageId = try await ChatAPIService.sendMessage(
      token: t,
      conversationId: conversationID,
      body: content,
      parentMessageId: parentMessageId,
      mentionedStaffIds: mentionedStaffIds,
      attachments: attachmentsPayload
    )
    return try await ChatAPIService.getMessage(token: t, messageId: messageId)
  }

  func generateAttachmentUploadURL() async throws -> URL {
    let t = try requireToken()
    let urlString = try await HRConvexAPIService.generateUploadURL(token: t)
    guard let url = URL(string: urlString) else {
      throw AuthStoreError.invalidUploadURL
    }
    return url
  }

  func uploadAttachmentData(_ data: Data, uploadURL: URL, mimeType: String) async throws -> String {
    try await HRConvexAPIService.uploadFile(
      uploadURL: uploadURL.absoluteString,
      data: data,
      contentType: mimeType
    )
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

  func fetchTypingUsers(conversationId: String? = nil, channelId: String? = nil) async throws -> [TypingUser] {
    let t = try requireToken()
    return try await ChatAPIService.getTyping(token: t, channelId: channelId, conversationId: conversationId)
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

  // MARK: - Presence

  @discardableResult
  func sendPresenceHeartbeat() async throws -> HeartbeatResult {
    let t = try requireToken()
    let response = try await ChatAPIService.sendPresenceHeartbeat(token: t)
    return HeartbeatResult(status: response.status ?? PresenceStatus.online.rawValue)
  }

  @discardableResult
  func setPresenceStatus(status: PresenceStatus, customStatusText: String? = nil, customStatusEmoji: String? = nil) async throws -> SetStatusResult {
    let t = try requireToken()
    let response = try await ChatAPIService.sendPresenceHeartbeat(
      token: t,
      status: status,
      customStatusText: customStatusText,
      customStatusEmoji: customStatusEmoji
    )
    return SetStatusResult(status: response.status ?? status.rawValue)
  }

  func fetchPresence(for stackUserIds: [String]) async throws -> [UserPresenceInfo] {
    let t = try requireToken()
    return try await ChatAPIService.getPresence(token: t, stackUserIds: stackUserIds)
  }

  func fetchOnlinePresence() async throws -> [UserPresenceInfo] {
    let t = try requireToken()
    return try await ChatAPIService.getOnlinePresence(token: t)
  }

  @discardableResult
  func clearPresenceStatus() async throws -> ClearStatusResult {
    let t = try requireToken()
    let response = try await ChatAPIService.sendPresenceHeartbeat(
      token: t,
      status: .online,
      customStatusText: "",
      customStatusEmoji: ""
    )
    return ClearStatusResult(cleared: response.cleared ?? response.success ?? true)
  }

  // MARK: - Reactions

  @discardableResult
  func addMessageReaction(messageId: String, messageSource: String, emoji: String) async throws -> MessageReactionResult {
    let t = try requireToken()
    return try await ChatAPIService.addReaction(
      token: t,
      messageId: messageId,
      messageSource: messageSource,
      emoji: emoji
    )
  }

  @discardableResult
  func removeMessageReaction(messageId: String, messageSource: String, emoji: String) async throws -> MessageReactionResult {
    let t = try requireToken()
    return try await ChatAPIService.removeReaction(
      token: t,
      messageId: messageId,
      messageSource: messageSource,
      emoji: emoji
    )
  }

  @discardableResult
  func toggleMessageReaction(messageId: String, messageSource: String, emoji: String) async throws -> MessageReactionResult {
    let t = try requireToken()
    return try await ChatAPIService.toggleReaction(
      token: t,
      messageId: messageId,
      messageSource: messageSource,
      emoji: emoji
    )
  }

  func fetchMessageReactions(messageId: String, messageSource: String) async throws -> [MessageReactionInfo] {
    let t = try requireToken()
    return try await ChatAPIService.getReactions(
      token: t,
      messageId: messageId,
      messageSource: messageSource
    )
  }

  func fetchBulkMessageReactions(messageIds: [String]) async throws -> [String: [MessageReactionInfo]] {
    let t = try requireToken()
    return try await ChatAPIService.getBulkReactions(token: t, messageIds: messageIds)
  }

  // MARK: - Notification preferences

  func fetchNotificationPreference(targetType: String, targetId: String) async throws -> NotificationPreference? {
    switch targetType {
    case "channel":
      let channel = try await fetchChannel(channelID: targetId)
      return NotificationPreference(
        targetType: targetType,
        targetId: targetId,
        level: (channel.muted ?? false) ? NotificationLevel.none.rawValue : NotificationLevel.all.rawValue,
        muteUntil: nil,
        updatedAt: Date().timeIntervalSince1970 * 1000
      )
    default:
      let conversation = try await fetchConversation(conversationID: targetId)
      return NotificationPreference(
        targetType: targetType,
        targetId: targetId,
        level: (conversation.muted ?? false) ? NotificationLevel.none.rawValue : NotificationLevel.all.rawValue,
        muteUntil: nil,
        updatedAt: Date().timeIntervalSince1970 * 1000
      )
    }
  }

  @discardableResult
  func upsertNotificationPreference(targetType: String, targetId: String, level: NotificationLevel, muteUntil: Double? = nil) async throws -> UpsertNotificationPrefResult {
    let isMuted = level == .none
    switch targetType {
    case "channel":
      try await toggleChannelMute(channelID: targetId, muted: isMuted)
    default:
      try await toggleConversationMute(conversationID: targetId, muted: isMuted)
    }
    return UpsertNotificationPrefResult(saved: true)
  }

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
    // Wire the geotrack singleton so any view (Home, HR dashboard, trips) can
    // call its endpoints without re-binding the token each time.
    GeoTrackAPIService.shared.tokenProvider = { [weak self] in
      self?.currentSession?.token
    }
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
      staffId: "qa-stub-user",
      employeeId: "QA-STUB",
      name: "QA Stub",
      phone: "9999999999",
      email: "qa-stub@example.local",
      role: "staff",
      roleLevel: 0,
      iamPermissions: [],
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
  case invalidUploadURL
  case notImplemented

  var errorDescription: String? {
    switch self {
    case .sessionNotAvailable: return "Session is not available. Please sign in again."
    case .invalidPhoneNumber: return "Enter a valid 10-digit phone number."
    case .invalidOTP: return "Enter the OTP you received."
    case .invalidUploadURL: return "Attachment upload URL is invalid."
    case .notImplemented: return "This feature is not yet connected."
    }
  }
}
