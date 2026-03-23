import Combine
import ConvexMobile
import Foundation
import SwiftUI
import UIKit
import UserNotifications

private struct ConvexStorageUploadResult: Decodable {
  let storageId: String
}

private struct ClientOtpChallengeResponse: Decodable {
  let challengeId: String
  let phoneNumber: String
  let expiresAt: Double
  let expiresInSeconds: Int
}

private struct OtpSessionResponse: Decodable {
  let sessionToken: String
  let phoneNumber: String
  let stackUserId: String
  let expiresAt: Double
  let identity: ConvexViewerIdentity
}

private struct LogoutResponse: Decodable {
  let success: Bool
}

private struct PushTokenOperationResponse: Decodable {
  let registered: Bool?
  let reused: Bool?
  let removed: Bool?
}

struct ConvexViewerIdentity: Decodable, Sendable, Equatable {
  let tokenIdentifier: String
  let subject: String
  let issuer: String
  let email: String?
  let name: String?
}

@MainActor
@Observable
final class AuthStore {
  private static let pushLogPrefix = "[push-ios]"
  private static let adminStackUserID = "phone:+916369487527"
  private static let adminPhoneNumber = "+916369487527"
  private static let adminFixedOTP = "123456"

  enum Status {
    case loading
    case signedOut
    case signedIn
  }

  private let tokenStore: KeychainTokenStore
  private let convexClient: ConvexClient
  private let config: AppConfig

  private var didAttemptRestore = false

  private(set) var status: Status = .loading
  private(set) var currentSession: OtpSession?
  private(set) var viewer: ConvexViewerIdentity?
  private(set) var errorMessage: String?
  private(set) var isAuthenticating = false
  private(set) var isRequestingOTP = false
  private(set) var lastKnownAPNSToken: String?
  private(set) var registeredAPNSToken: String?

  var currentUserLabel: String? {
    viewer?.name ?? viewer?.email ?? currentSession?.phoneNumber
  }

  var isAdmin: Bool {
    viewer?.subject == Self.adminStackUserID
  }

  init(
    config: AppConfig? = nil,
    tokenStore: KeychainTokenStore? = nil
  ) {
    let resolvedConfig = config ?? .current
    let resolvedTokenStore = tokenStore ?? KeychainTokenStore()

    self.tokenStore = resolvedTokenStore
    self.config = resolvedConfig
    convexClient = ConvexClient(deploymentUrl: resolvedConfig.convexURL)
  }

  func restoreSessionIfNeeded() async {
    guard !didAttemptRestore else { return }
    didAttemptRestore = true

    status = .loading
    errorMessage = nil

    do {
      guard let storedSession = try tokenStore.load() else {
        status = .signedOut
        return
      }

      // Optimistic restore for fast app launch: use local session immediately,
      // then verify it with backend in the background.
      currentSession = storedSession
      status = .signedIn

      // Load stored MMS session
      HRAPIService.shared.loadStoredMMSSession()

      let response: OtpSessionResponse = try await convexClient.mutation(
        "auth:restoreSession",
        with: ["sessionToken": storedSession.sessionToken]
      )

      let restoredSession = OtpSession(
        sessionToken: response.sessionToken,
        phoneNumber: response.phoneNumber,
        stackUserId: response.stackUserId,
        expiresAt: response.expiresAt
      )

      currentSession = restoredSession
      viewer = response.identity
      try tokenStore.save(restoredSession)
      _ = try await ensureCurrentUserInConvex()
      await configurePushNotificationsIfNeeded()
      await registerPushTokenIfPossible()
    } catch {
      try? tokenStore.clear()
      currentSession = nil
      viewer = nil
      registeredAPNSToken = nil
      status = .signedOut
    }
  }

  @discardableResult
  func requestOTP(phoneNumber: String) async throws -> String {
    let trimmedPhoneNumber = Self.normalizePhoneNumber(phoneNumber)
    guard !trimmedPhoneNumber.isEmpty else {
      throw AuthStoreError.invalidPhoneNumber
    }

    isRequestingOTP = true
    errorMessage = nil

    defer {
      isRequestingOTP = false
    }

    do {
      // Send OTP via MMS only — single SMS to user
      let digits = trimmedPhoneNumber.filter(\.isNumber)
      let mobileNumber = digits.count > 10 ? String(digits.suffix(10)) : digits

      let mmsResult = try await HRAPIService.shared.mmsOtpSend(mobileNumber: mobileNumber)
      guard mmsResult.sent == true else {
        throw AuthStoreError.smsDeliveryFailed(mmsResult.message ?? "Failed to send OTP")
      }

      return trimmedPhoneNumber
    } catch {
      errorMessage = error.localizedDescription
      throw error
    }
  }

  func verifyOTP(phoneNumber: String, code: String) async {
    let trimmedPhoneNumber = Self.normalizePhoneNumber(phoneNumber)
    let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedPhoneNumber.isEmpty else {
      errorMessage = AuthStoreError.invalidPhoneNumber.localizedDescription
      return
    }

    guard !trimmedCode.isEmpty else {
      errorMessage = AuthStoreError.invalidOTP.localizedDescription
      return
    }

    isAuthenticating = true
    errorMessage = nil

    defer {
      isAuthenticating = false
    }

    do {
      // Step 1: Verify OTP with MMS
      let digits = trimmedPhoneNumber.filter(\.isNumber)
      let mobileNumber = digits.count > 10 ? String(digits.suffix(10)) : digits

      let mmsResult = try await HRAPIService.shared.mmsOtpVerify(
        mobileNumber: mobileNumber,
        otp: trimmedCode
      )

      guard mmsResult.verified == true, let mmsUserId = mmsResult.userId, mmsUserId > 0 else {
        errorMessage = mmsResult.message ?? "Invalid OTP"
        return
      }

      // Store MMS session for HR features
      HRAPIService.shared.setMMSSession(from: mmsResult)

      // Step 2: Auto-create Convex session (silent — no SMS, no user interaction)
      // Retry up to 3 times to handle cooldown
      let convexOTP = Self.otpForPhoneNumber(trimmedPhoneNumber)
      var convexSessionCreated = false

      for attempt in 0..<3 {
        do {
          if attempt > 0 {
            try await Task.sleep(for: .seconds(2))
          }
          let _: ClientOtpChallengeResponse = try await convexClient.mutation(
            "auth:requestOtpFromClient",
            with: [
              "phoneNumber": trimmedPhoneNumber,
              "otp": convexOTP,
            ]
          )
          convexSessionCreated = true
          break
        } catch {
          let msg = error.localizedDescription
          if msg.contains("wait") || msg.contains("cooldown") {
            // Cooldown — wait and retry
            try? await Task.sleep(for: .seconds(5))
            continue
          }
          // Other error — skip Convex challenge, try verify directly
          convexSessionCreated = true
          break
        }
      }

      let convexResponse: OtpSessionResponse = try await convexClient.action(
        "auth:verifyOtp",
        with: [
          "phoneNumber": trimmedPhoneNumber,
          "otp": convexOTP,
        ]
      )

      let session = OtpSession(
        sessionToken: convexResponse.sessionToken,
        phoneNumber: convexResponse.phoneNumber,
        stackUserId: convexResponse.stackUserId,
        expiresAt: convexResponse.expiresAt
      )

      currentSession = session
      viewer = convexResponse.identity
      try tokenStore.save(session)
      _ = try await ensureCurrentUserInConvex()
      status = .signedIn
      await configurePushNotificationsIfNeeded()
      await registerPushTokenIfPossible()
    } catch {
      status = .signedOut
      errorMessage = error.localizedDescription
    }
  }

  func logout() async {
    await unregisterPushTokenIfPossible()
    await clearSession()
    HRAPIService.shared.clearMMSSession()
    status = .signedOut
  }

  func handleAPNSToken(_ token: String) async {
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedToken.isEmpty else { return }
    print(
      "\(Self.pushLogPrefix) APNs token received token=\(Self.maskAPNSToken(normalizedToken))"
    )
    lastKnownAPNSToken = normalizedToken
    await registerPushTokenIfPossible()
  }

  func configurePushNotificationsIfNeeded() async {
    guard status == .signedIn else { return }

    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    print(
      "\(Self.pushLogPrefix) notification auth status=\(String(describing: settings.authorizationStatus.rawValue))"
    )

    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      print("\(Self.pushLogPrefix) registering for remote notifications")
      UIApplication.shared.registerForRemoteNotifications()
    case .notDetermined:
      do {
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        print("\(Self.pushLogPrefix) permission prompt result granted=\(granted)")
        if granted {
          print("\(Self.pushLogPrefix) registering for remote notifications")
          UIApplication.shared.registerForRemoteNotifications()
        }
      } catch {
        print("\(Self.pushLogPrefix) permission request failed error=\(error.localizedDescription)")
      }
    case .denied:
      print("\(Self.pushLogPrefix) notifications denied in system settings")
      break
    @unknown default:
      print("\(Self.pushLogPrefix) unknown notification authorization status")
      break
    }
  }

  func fetchDirectoryUsers(search: String) async throws -> [DirectoryUser] {
    let sessionToken = try requireSessionToken()
    let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
    let publisher: AnyPublisher<[DirectoryUser]?, ClientError> = convexClient.subscribe(
      to: "users:list",
      with: [
        "sessionToken": sessionToken,
        "search": trimmedSearch,
      ],
      yielding: [DirectoryUser]?.self
    )

    for try await users in publisher.first().values {
      return users ?? []
    }

    throw AuthStoreError.emptyDirectoryResponse
  }

  func startDirectConversation(withStackUserID otherStackUserID: String) async throws
    -> StartDirectConversationResult
  {
    let sessionToken = try requireSessionToken()

    return try await convexClient.mutation(
      "conversations:startDirect",
      with: [
        "sessionToken": sessionToken,
        "otherStackUserId": otherStackUserID,
      ]
    )
  }

  func fetchConversations() async throws -> [ConvexConversationSummary] {
    let publisher = try subscribeConversations()

    for try await conversations in publisher.first().values {
      return conversations ?? []
    }

    throw AuthStoreError.emptyDirectoryResponse
  }

  func subscribeConversations() throws -> AnyPublisher<[ConvexConversationSummary]?, ClientError> {
    let sessionToken = try requireSessionToken()

    return convexClient.subscribe(
      to: "conversations:listForCurrentUser",
      with: ["sessionToken": sessionToken],
      yielding: [ConvexConversationSummary]?.self
    )
  }

  func fetchMessages(conversationID: String) async throws -> [ConvexChatMessage] {
    let publisher = try subscribeMessages(conversationID: conversationID)

    for try await messages in publisher.first().values {
      return messages ?? []
    }

    throw AuthStoreError.emptyDirectoryResponse
  }

  func fetchSharedFiles(
    search: String = "",
    typeFilter: String = "all"
  ) async throws -> [SharedFileItem] {
    let sessionToken = try requireSessionToken()
    let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
    let publisher: AnyPublisher<[SharedFileItem]?, ClientError> = convexClient.subscribe(
      to: "messages:listSharedFiles",
      with: [
        "sessionToken": sessionToken,
        "search": trimmedSearch,
        "type": typeFilter,
      ],
      yielding: [SharedFileItem]?.self
    )

    for try await files in publisher.first().values {
      return files ?? []
    }

    throw AuthStoreError.emptyDirectoryResponse
  }

  @discardableResult
  func savePrivateFile(
    storageId: String,
    attachmentType: String,
    fileName: String,
    mimeType: String,
    title: String? = nil,
    description: String? = nil,
    thumbnail: String? = nil
  ) async throws -> SavePrivateFileResult {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = [
      "sessionToken": sessionToken,
      "attachmentStorageId": storageId,
      "attachmentType": attachmentType,
      "attachmentFileName": fileName,
      "attachmentMimeType": mimeType,
    ]
    args["attachmentTitle"] = title
    args["attachmentDescription"] = description
    args["attachmentThumbnail"] = thumbnail
    return try await convexClient.mutation("messages:savePrivateFile", with: args)
  }

  @discardableResult
  func sharePrivateFileToConversation(
    fileID: String,
    conversationID: String
  ) async throws -> SharePrivateFileResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "messages:sharePrivateFileToConversation",
      with: [
        "sessionToken": sessionToken,
        "fileId": fileID,
        "conversationId": conversationID,
      ]
    )
  }

  func fetchChannels(search: String = "") async throws -> [ChannelSummary] {
    let sessionToken = try requireSessionToken()
    let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
    let publisher: AnyPublisher<[ChannelSummary]?, ClientError> = convexClient.subscribe(
      to: "channels:listForCurrentUser",
      with: [
        "sessionToken": sessionToken,
        "search": trimmedSearch,
      ],
      yielding: [ChannelSummary]?.self
    )

    for try await channels in publisher.first().values {
      return channels ?? []
    }

    throw AuthStoreError.emptyDirectoryResponse
  }

  func fetchChannelMembers(channelID: String) async throws -> [ChannelMember] {
    let sessionToken = try requireSessionToken()
    let publisher: AnyPublisher<[ChannelMember]?, ClientError> = convexClient.subscribe(
      to: "channels:listMembers",
      with: [
        "sessionToken": sessionToken,
        "channelId": channelID,
      ],
      yielding: [ChannelMember]?.self
    )

    for try await members in publisher.first().values {
      return members ?? []
    }

    throw AuthStoreError.emptyDirectoryResponse
  }

  func subscribeChannelMessages(channelID: String) throws
    -> AnyPublisher<[ChannelChatMessage]?, ClientError>
  {
    let sessionToken = try requireSessionToken()
    return convexClient.subscribe(
      to: "channels:listMessages",
      with: [
        "sessionToken": sessionToken,
        "channelId": channelID,
      ],
      yielding: [ChannelChatMessage]?.self
    )
  }

  @discardableResult
  func sendChannelMessage(channelID: String, content: String) async throws -> ChannelChatMessage {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "channels:sendMessage",
      with: [
        "sessionToken": sessionToken,
        "channelId": channelID,
        "content": content,
      ]
    )
  }

  @discardableResult
  func createChannel(name: String, description: String?) async throws -> CreateChannelResult {
    let sessionToken = try requireSessionToken()
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
    var args: [String: ConvexEncodable?] = [
      "sessionToken": sessionToken,
      "name": normalizedName,
    ]
    args["description"] = normalizedDescription

    return try await convexClient.mutation("channels:create", with: args)
  }

  @discardableResult
  func inviteMember(
    channelID: String,
    memberStackUserID: String
  ) async throws -> InviteChannelMemberResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "channels:inviteMember",
      with: [
        "sessionToken": sessionToken,
        "channelId": channelID,
        "memberStackUserId": memberStackUserID,
      ]
    )
  }

  func subscribeMessages(conversationID: String) throws -> AnyPublisher<[ConvexChatMessage]?, ClientError> {
    let sessionToken = try requireSessionToken()

    return convexClient.subscribe(
      to: "messages:listForConversation",
      with: [
        "sessionToken": sessionToken,
        "conversationId": conversationID,
      ],
      yielding: [ConvexChatMessage]?.self
    )
  }

  func deleteConversation(conversationID: String) async throws {
    let sessionToken = try requireSessionToken()
    struct DeleteResult: Decodable { let deleted: Bool }
    let _: DeleteResult = try await convexClient.mutation(
      "conversations:deleteForUser",
      with: [
        "sessionToken": sessionToken,
        "conversationId": conversationID,
      ]
    )
  }

  func markConversationSeen(conversationID: String, readAt: Date = Date()) async throws {
    let sessionToken = try requireSessionToken()
    let readAtMilliseconds = readAt.timeIntervalSince1970 * 1000
    let _: MarkConversationSeenResult = try await convexClient.mutation(
      "conversations:markSeen",
      with: [
        "sessionToken": sessionToken,
        "conversationId": conversationID,
        "readAt": readAtMilliseconds,
      ]
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
    let sessionToken = try requireSessionToken()

    var args: [String: ConvexEncodable] = [
      "sessionToken": sessionToken,
      "conversationId": conversationID,
      "role": ConvexChatRole.from(role).rawValue,
      "content": content,
    ]

    if let attachmentTitle {
      args["attachmentTitle"] = attachmentTitle
    }
    if let attachmentType {
      args["attachmentType"] = attachmentType
    }
    if let attachmentStorageId {
      args["attachmentStorageId"] = attachmentStorageId
    }
    if let attachmentFileName {
      args["attachmentFileName"] = attachmentFileName
    }
    if let attachmentMimeType {
      args["attachmentMimeType"] = attachmentMimeType
    }
    if let attachmentDescription {
      args["attachmentDescription"] = attachmentDescription
    }
    if let attachmentThumbnail {
      args["attachmentThumbnail"] = attachmentThumbnail
    }

    return try await convexClient.mutation("messages:send", with: args)
  }

  func generateAttachmentUploadURL() async throws -> URL {
    let sessionToken = try requireSessionToken()

    let response: ConvexUploadUrlResponse = try await convexClient.mutation(
      "messages:generateUploadUrl",
      with: ["sessionToken": sessionToken]
    )

    guard let url = URL(string: response.uploadUrl) else {
      throw URLError(.badURL)
    }
    return url
  }

  func uploadAttachmentData(
    _ data: Data,
    uploadURL: URL,
    mimeType: String
  ) async throws -> String {
    var request = URLRequest(url: uploadURL)
    request.httpMethod = "POST"
    request.httpBody = data
    request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

    let (responseData, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw URLError(.badServerResponse)
    }

    let uploadResponse = try JSONDecoder().decode(ConvexStorageUploadResult.self, from: responseData)
    return uploadResponse.storageId
  }

  // MARK: - Location Tracking API

    @discardableResult
    func recordLocation(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        speed: Double? = nil,
        heading: Double? = nil,
        recordedAt: Double
    ) async throws -> RecordLocationResult {
        let sessionToken = try requireSessionToken()
        var args: [String: ConvexEncodable?] = [
            "sessionToken": sessionToken,
            "latitude": latitude,
            "longitude": longitude,
            "recordedAt": recordedAt,
        ]
        args["altitude"] = altitude
        args["horizontalAccuracy"] = horizontalAccuracy
        args["speed"] = speed
        args["heading"] = heading
        return try await convexClient.mutation("locations:recordLocation", with: args)
    }

    @discardableResult
    func recordLocationBatch(points: String) async throws -> RecordBatchResult {
        let sessionToken = try requireSessionToken()
        return try await convexClient.mutation(
            "locations:recordBatch",
            with: [
                "sessionToken": sessionToken,
                "points": points,
            ]
        )
    }

    func fetchLocationHistory(
        targetStackUserId: String,
        startDate: Double,
        endDate: Double
    ) async throws -> [LocationPoint] {
        let sessionToken = try requireSessionToken()
        let publisher: AnyPublisher<[LocationPoint]?, ClientError> = convexClient.subscribe(
            to: "locations:listForUser",
            with: [
                "sessionToken": sessionToken,
                "targetStackUserId": targetStackUserId,
                "startDate": startDate,
                "endDate": endDate,
            ],
            yielding: [LocationPoint]?.self
        )
        for try await locations in publisher.first().values {
            return locations ?? []
        }
        throw AuthStoreError.emptyDirectoryResponse
    }

    func fetchTrackedUsers() async throws -> [TrackedUser] {
        let sessionToken = try requireSessionToken()
        let publisher: AnyPublisher<[TrackedUser]?, ClientError> = convexClient.subscribe(
            to: "locations:listTrackedUsers",
            with: ["sessionToken": sessionToken],
            yielding: [TrackedUser]?.self
        )
        for try await users in publisher.first().values {
            return users ?? []
        }
        throw AuthStoreError.emptyDirectoryResponse
    }

    @discardableResult
    func deleteLocationHistory(
        targetStackUserId: String,
        startDate: Double,
        endDate: Double
    ) async throws -> DeleteLocationsResult {
        let sessionToken = try requireSessionToken()
        return try await convexClient.mutation(
            "locations:deleteForUser",
            with: [
                "sessionToken": sessionToken,
                "targetStackUserId": targetStackUserId,
                "startDate": startDate,
                "endDate": endDate,
            ]
        )
    }

  // MARK: - Posts API

  func fetchPosts(category: String? = nil) async throws -> [ConvexPost] {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = ["sessionToken": sessionToken]
    args["category"] = category
    let publisher: AnyPublisher<[ConvexPost]?, ClientError> = convexClient.subscribe(
      to: "posts:list",
      with: args,
      yielding: [ConvexPost]?.self
    )
    for try await posts in publisher.first().values {
      return posts ?? []
    }
    throw AuthStoreError.emptyDirectoryResponse
  }

  func subscribePosts(category: String? = nil) throws -> AnyPublisher<[ConvexPost]?, ClientError> {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = ["sessionToken": sessionToken]
    args["category"] = category
    return convexClient.subscribe(
      to: "posts:list",
      with: args,
      yielding: [ConvexPost]?.self
    )
  }

  func fetchPostById(postId: String) async throws -> ConvexPost {
    let sessionToken = try requireSessionToken()
    let publisher: AnyPublisher<ConvexPost?, ClientError> = convexClient.subscribe(
      to: "posts:getById",
      with: ["sessionToken": sessionToken, "postId": postId],
      yielding: ConvexPost?.self
    )
    for try await post in publisher.first().values {
      guard let post else { throw AuthStoreError.emptyDirectoryResponse }
      return post
    }
    throw AuthStoreError.emptyDirectoryResponse
  }

  @discardableResult
  func createPost(
    title: String?,
    body: String,
    imageStorageIds: [String]? = nil,
    linkUrl: String? = nil,
    linkTitle: String? = nil,
    linkThumbnail: String? = nil,
    isPinned: Bool = false,
    isAnnouncement: Bool = false,
    category: String? = nil,
    scheduledAt: Double? = nil
  ) async throws -> CreatePostResult {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = [
      "sessionToken": sessionToken,
      "body": body,
      "isPinned": isPinned,
      "isAnnouncement": isAnnouncement,
    ]
    args["title"] = title
    args["category"] = category
    args["linkUrl"] = linkUrl
    args["linkTitle"] = linkTitle
    args["linkThumbnail"] = linkThumbnail
    args["scheduledAt"] = scheduledAt
    if let imageStorageIds, !imageStorageIds.isEmpty {
      args["imageStorageIds"] = imageStorageIds.joined(separator: ",")
    }
    return try await convexClient.mutation("posts:create", with: args)
  }

  @discardableResult
  func deletePost(postId: String) async throws -> DeletePostResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "posts:deletePost",
      with: ["sessionToken": sessionToken, "postId": postId]
    )
  }

  @discardableResult
  func addPostReaction(postId: String, emoji: String) async throws -> PostReactionResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "posts:addReaction",
      with: ["sessionToken": sessionToken, "postId": postId, "emoji": emoji]
    )
  }

  @discardableResult
  func addPostComment(postId: String, content: String, imageStorageId: String? = nil) async throws -> AddCommentResult {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = [
      "sessionToken": sessionToken,
      "postId": postId,
      "content": content,
    ]
    args["imageStorageId"] = imageStorageId
    return try await convexClient.mutation("posts:addComment", with: args)
  }

  @discardableResult
  func deletePostComment(commentId: String) async throws -> DeleteCommentResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "posts:deleteComment",
      with: ["sessionToken": sessionToken, "commentId": commentId]
    )
  }

  func fetchPostComments(postId: String) async throws -> [PostComment] {
    let sessionToken = try requireSessionToken()
    let publisher: AnyPublisher<[PostComment]?, ClientError> = convexClient.subscribe(
      to: "posts:listComments",
      with: ["sessionToken": sessionToken, "postId": postId],
      yielding: [PostComment]?.self
    )
    for try await comments in publisher.first().values {
      return comments ?? []
    }
    throw AuthStoreError.emptyDirectoryResponse
  }

  func subscribePostComments(postId: String) throws -> AnyPublisher<[PostComment]?, ClientError> {
    let sessionToken = try requireSessionToken()
    return convexClient.subscribe(
      to: "posts:listComments",
      with: ["sessionToken": sessionToken, "postId": postId],
      yielding: [PostComment]?.self
    )
  }

  @discardableResult
  func markPostRead(postId: String) async throws -> MarkPostReadResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "posts:markRead",
      with: ["sessionToken": sessionToken, "postId": postId]
    )
  }

  func fetchUnreadPostCount() async throws -> Int {
    let sessionToken = try requireSessionToken()
    let publisher: AnyPublisher<UnreadPostCount?, ClientError> = convexClient.subscribe(
      to: "posts:getUnreadCount",
      with: ["sessionToken": sessionToken],
      yielding: UnreadPostCount?.self
    )
    for try await result in publisher.first().values {
      return result?.count ?? 0
    }
    return 0
  }

  // MARK: - Presence API

  @discardableResult
  func sendPresenceHeartbeat() async throws -> HeartbeatResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "presence:heartbeat",
      with: ["sessionToken": sessionToken]
    )
  }

  @discardableResult
  func setPresenceStatus(
    status: PresenceStatus,
    customStatusText: String? = nil,
    customStatusEmoji: String? = nil
  ) async throws -> SetStatusResult {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = [
      "sessionToken": sessionToken,
      "status": status.rawValue,
    ]
    args["customStatusText"] = customStatusText
    args["customStatusEmoji"] = customStatusEmoji
    return try await convexClient.mutation("presence:setStatus", with: args)
  }

  func fetchPresence(for stackUserIds: [String]) async throws -> [UserPresenceInfo] {
    let sessionToken = try requireSessionToken()
    let joined = stackUserIds.joined(separator: ",")
    let publisher: AnyPublisher<[UserPresenceInfo]?, ClientError> = convexClient.subscribe(
      to: "presence:getForUsers",
      with: ["sessionToken": sessionToken, "stackUserIds": joined],
      yielding: [UserPresenceInfo]?.self
    )
    for try await presences in publisher.first().values {
      return presences ?? []
    }
    throw AuthStoreError.emptyDirectoryResponse
  }

  @discardableResult
  func clearPresenceStatus() async throws -> ClearStatusResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "presence:clearCustomStatus",
      with: ["sessionToken": sessionToken]
    )
  }

  // MARK: - Message Reactions API

  @discardableResult
  func addMessageReaction(messageId: String, messageSource: String, emoji: String) async throws -> MessageReactionResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "reactions:addMessageReaction",
      with: [
        "sessionToken": sessionToken,
        "messageId": messageId,
        "messageSource": messageSource,
        "emoji": emoji,
      ]
    )
  }

  func fetchMessageReactions(messageId: String, messageSource: String) async throws -> [MessageReactionInfo] {
    let sessionToken = try requireSessionToken()
    let publisher: AnyPublisher<[MessageReactionInfo]?, ClientError> = convexClient.subscribe(
      to: "reactions:listForMessage",
      with: [
        "sessionToken": sessionToken,
        "messageId": messageId,
        "messageSource": messageSource,
      ],
      yielding: [MessageReactionInfo]?.self
    )
    for try await reactions in publisher.first().values {
      return reactions ?? []
    }
    throw AuthStoreError.emptyDirectoryResponse
  }

  // MARK: - Message Edit & Delete API

  @discardableResult
  func editMessage(messageId: String, newContent: String) async throws -> EditMessageResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "messages:editMessage",
      with: [
        "sessionToken": sessionToken,
        "messageId": messageId,
        "newContent": newContent,
      ]
    )
  }

  @discardableResult
  func deleteMessage(messageId: String) async throws -> DeleteMessageResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "messages:deleteMessage",
      with: ["sessionToken": sessionToken, "messageId": messageId]
    )
  }

  @discardableResult
  func editChannelMessage(messageId: String, newContent: String) async throws -> EditMessageResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "channels:editMessage",
      with: [
        "sessionToken": sessionToken,
        "messageId": messageId,
        "newContent": newContent,
      ]
    )
  }

  @discardableResult
  func deleteChannelMessage(messageId: String) async throws -> DeleteMessageResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "channels:deleteMessage",
      with: ["sessionToken": sessionToken, "messageId": messageId]
    )
  }

  // MARK: - Notification Preferences API

  func fetchNotificationPreference(targetType: String, targetId: String) async throws -> NotificationPreference? {
    let sessionToken = try requireSessionToken()
    let publisher: AnyPublisher<NotificationPreference?, ClientError> = convexClient.subscribe(
      to: "notificationPrefs:get",
      with: [
        "sessionToken": sessionToken,
        "targetType": targetType,
        "targetId": targetId,
      ],
      yielding: NotificationPreference?.self
    )
    for try await pref in publisher.first().values {
      return pref
    }
    return nil
  }

  @discardableResult
  func upsertNotificationPreference(
    targetType: String,
    targetId: String,
    level: NotificationLevel,
    muteUntil: Double? = nil
  ) async throws -> UpsertNotificationPrefResult {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = [
      "sessionToken": sessionToken,
      "targetType": targetType,
      "targetId": targetId,
      "level": level.rawValue,
    ]
    args["muteUntil"] = muteUntil
    return try await convexClient.mutation("notificationPrefs:upsert", with: args)
  }

  // MARK: - Typing Indicators API

  func setTypingIndicator(conversationId: String? = nil, channelId: String? = nil) async throws {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = ["sessionToken": sessionToken]
    args["conversationId"] = conversationId
    args["channelId"] = channelId
    let _: TypingResult = try await convexClient.mutation("typing:setTyping", with: args)
  }

  func clearTypingIndicator(conversationId: String? = nil, channelId: String? = nil) async throws {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = ["sessionToken": sessionToken]
    args["conversationId"] = conversationId
    args["channelId"] = channelId
    let _: TypingResult = try await convexClient.mutation("typing:clearTyping", with: args)
  }

  func subscribeTypingUsers(conversationId: String? = nil, channelId: String? = nil) throws -> AnyPublisher<[TypingUser]?, ClientError> {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = ["sessionToken": sessionToken]
    args["conversationId"] = conversationId
    args["channelId"] = channelId
    return convexClient.subscribe(
      to: "typing:getTyping",
      with: args,
      yielding: [TypingUser]?.self
    )
  }

  // MARK: - Storage Folders API

  func fetchStorageFolders(parentFolderId: String? = nil) async throws -> [StorageFolder] {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = ["sessionToken": sessionToken]
    args["parentFolderId"] = parentFolderId
    let publisher: AnyPublisher<[StorageFolder]?, ClientError> = convexClient.subscribe(
      to: "storageFolders:list",
      with: args,
      yielding: [StorageFolder]?.self
    )
    for try await folders in publisher.first().values {
      return folders ?? []
    }
    throw AuthStoreError.emptyDirectoryResponse
  }

  @discardableResult
  func createStorageFolder(name: String, parentFolderId: String? = nil) async throws -> CreateFolderResult {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = [
      "sessionToken": sessionToken,
      "name": name,
    ]
    args["parentFolderId"] = parentFolderId
    return try await convexClient.mutation("storageFolders:create", with: args)
  }

  @discardableResult
  func deleteStorageFolder(folderId: String) async throws -> DeleteFolderResult {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "storageFolders:deleteFolder",
      with: ["sessionToken": sessionToken, "folderId": folderId]
    )
  }

  @discardableResult
  func moveFileToFolder(fileId: String, folderId: String?) async throws -> MoveFileResult {
    let sessionToken = try requireSessionToken()
    var args: [String: ConvexEncodable?] = [
      "sessionToken": sessionToken,
      "fileId": fileId,
    ]
    args["folderId"] = folderId
    return try await convexClient.mutation("storageFolders:moveFile", with: args)
  }

  // MARK: - Channel Description & Pins API

  func updateChannelDescription(channelId: String, description: String) async throws {
    let sessionToken = try requireSessionToken()
    let _: ChannelSummary = try await convexClient.mutation(
      "channels:updateDescription",
      with: [
        "sessionToken": sessionToken,
        "channelId": channelId,
        "description": description,
      ]
    )
  }

  func pinChannelMessage(channelId: String, messageId: String) async throws {
    let sessionToken = try requireSessionToken()
    let _: CreateChannelResult = try await convexClient.mutation(
      "channels:pinMessage",
      with: [
        "sessionToken": sessionToken,
        "channelId": channelId,
        "messageId": messageId,
      ]
    )
  }

  func unpinChannelMessage(channelId: String, messageId: String) async throws {
    let sessionToken = try requireSessionToken()
    let _: CreateChannelResult = try await convexClient.mutation(
      "channels:unpinMessage",
      with: [
        "sessionToken": sessionToken,
        "channelId": channelId,
        "messageId": messageId,
      ]
    )
  }

  @discardableResult
  private func ensureCurrentUserInConvex() async throws -> DirectoryUser {
    let sessionToken = try requireSessionToken()
    return try await convexClient.mutation(
      "users:ensureCurrentUser",
      with: ["sessionToken": sessionToken]
    )
  }

  private func requireSessionToken() throws -> String {
    guard let sessionToken = currentSession?.sessionToken else {
      throw AuthStoreError.sessionNotAvailable
    }
    return sessionToken
  }

  private func sendOTPViaAirtel(phoneNumber: String, otp: String) async throws {
    guard let endpointURL = URL(string: config.airtelSMSEndpoint) else {
      throw AuthStoreError.invalidSMSEndpoint
    }

    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "accept")
    request.setValue("application/json", forHTTPHeaderField: "content-type")

    let message = Self.renderOTPMessage(
      template: config.airtelOTPMessageTemplate,
      otp: otp
    )
    let payload: [String: Any] = [
      "customerId": config.airtelCustomerID,
      "destinationAddress": [phoneNumber],
      "dltTemplateId": config.airtelDLTTemplateID,
      "entityId": config.airtelEntityID,
      "message": message,
      "messageType": config.airtelMessageType,
      "sourceAddress": config.airtelSourceAddress,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

    let (responseData, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AuthStoreError.smsDeliveryFailed("Invalid SMS gateway response.")
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let responseBody = String(data: responseData, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      let detail = responseBody?.isEmpty == false ? responseBody! : "No error details."
      throw AuthStoreError.smsDeliveryFailed(
        "SMS request failed with status \(httpResponse.statusCode): \(detail)"
      )
    }
  }

  private static func generateOTPCode() -> String {
    String(Int.random(in: 100_000...999_999))
  }

  private static func otpForPhoneNumber(_ phoneNumber: String) -> String {
    if phoneNumber == adminPhoneNumber {
      return adminFixedOTP
    }
    return generateOTPCode()
  }

  private static func normalizePhoneNumber(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    if trimmed.hasPrefix("+") {
      let digits = trimmed.dropFirst().filter(\.isNumber)
      if digits.count >= 10, digits.count <= 15 {
        return "+\(digits)"
      }
      return trimmed
    }

    let digitsOnly = trimmed.filter(\.isNumber)
    if digitsOnly.count == 10 {
      return "+91\(digitsOnly)"
    }
    if digitsOnly.count >= 11, digitsOnly.count <= 15 {
      return "+\(digitsOnly)"
    }

    return trimmed
  }

  private static func renderOTPMessage(template: String, otp: String) -> String {
    if template.contains("{{OTP}}") {
      return template.replacingOccurrences(of: "{{OTP}}", with: otp)
    }
    return "\(otp) \(template)"
  }

  private func registerPushTokenIfPossible() async {
    guard status == .signedIn else {
      print("\(Self.pushLogPrefix) skip register token: user not signed in")
      return
    }
    guard let apnsToken = lastKnownAPNSToken, !apnsToken.isEmpty else {
      print("\(Self.pushLogPrefix) skip register token: APNs token missing")
      return
    }

    do {
      let sessionToken = try requireSessionToken()
      let _: PushTokenOperationResponse = try await convexClient.mutation(
        "notifications:registerPushToken",
        with: [
          "sessionToken": sessionToken,
          "apnsToken": apnsToken,
        ]
      )
      registeredAPNSToken = apnsToken
      print(
        "\(Self.pushLogPrefix) registered token in Convex token=\(Self.maskAPNSToken(apnsToken))"
      )
    } catch {
      print("\(Self.pushLogPrefix) failed to register token in Convex error=\(error.localizedDescription)")
    }
  }

  private func unregisterPushTokenIfPossible() async {
    guard let apnsToken = registeredAPNSToken ?? lastKnownAPNSToken else {
      return
    }
    guard let sessionToken = currentSession?.sessionToken else {
      return
    }

    do {
      let _: PushTokenOperationResponse = try await convexClient.mutation(
        "notifications:unregisterPushToken",
        with: [
          "sessionToken": sessionToken,
          "apnsToken": apnsToken,
        ]
      )
      print(
        "\(Self.pushLogPrefix) unregistered token from Convex token=\(Self.maskAPNSToken(apnsToken))"
      )
    } catch {
      print(
        "\(Self.pushLogPrefix) failed to unregister token error=\(error.localizedDescription)"
      )
    }
    registeredAPNSToken = nil
  }

  private static func maskAPNSToken(_ token: String) -> String {
    guard token.count > 12 else { return token }
    return "\(token.prefix(8))...\(token.suffix(4))"
  }


  private func clearSession() async {
    if let sessionToken = currentSession?.sessionToken {
      let _: LogoutResponse? = try? await convexClient.mutation(
        "auth:logout",
        with: ["sessionToken": sessionToken]
      )
    }

    try? tokenStore.clear()
    currentSession = nil
    viewer = nil
    errorMessage = nil
    isAuthenticating = false
    isRequestingOTP = false
    registeredAPNSToken = nil
  }
}

enum AuthStoreError: LocalizedError {
  case sessionNotAvailable
  case invalidPhoneNumber
  case invalidOTP
  case invalidSMSEndpoint
  case smsDeliveryFailed(String)
  case emptyDirectoryResponse

  var errorDescription: String? {
    switch self {
    case .sessionNotAvailable:
      return "Session is not available. Please sign in again."
    case .invalidPhoneNumber:
      return "Enter a valid phone number."
    case .invalidOTP:
      return "Enter the OTP you received."
    case .invalidSMSEndpoint:
      return "SMS gateway URL is invalid."
    case .smsDeliveryFailed(let message):
      return message
    case .emptyDirectoryResponse:
      return "Did not receive a response from Convex while loading users."
    }
  }
}
