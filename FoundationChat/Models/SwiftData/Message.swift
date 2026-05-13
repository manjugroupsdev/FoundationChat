import Foundation
import SwiftData

@Model
final class Message {
  var remoteMessageID: String?
  var senderStackUserId: String?
  var content: String
  var role: Role
  var timestamp: Date

  var attachementType: String?
  var attachementFileName: String?
  var attachementMimeType: String?
  var attachementTitle: String?
  var attachementDescription: String?
  var attachementThumbnail: String?
  var attachementURL: String?
  var attachementSummary: String?
  var replyToRemoteMessageID: String?
  var replyPreviewText: String?
  var replySenderName: String?
  var reactionSummary: String?
  var isDeleted: Bool = false

  init(
    content: String, role: Role, timestamp: Date,
    remoteMessageID: String? = nil,
    senderStackUserId: String? = nil,
    attachementType: String? = nil,
    attachementFileName: String? = nil,
    attachementMimeType: String? = nil,
    attachementTitle: String? = nil,
    attachementDescription: String? = nil,
    attachementThumbnail: String? = nil,
    attachementURL: String? = nil,
    replyToRemoteMessageID: String? = nil,
    replyPreviewText: String? = nil,
    replySenderName: String? = nil,
    reactionSummary: String? = nil,
    isDeleted: Bool = false
  ) {
    self.remoteMessageID = remoteMessageID
    self.senderStackUserId = senderStackUserId
    self.content = content
    self.role = role
    self.timestamp = timestamp
    self.attachementType = attachementType
    self.attachementFileName = attachementFileName
    self.attachementMimeType = attachementMimeType
    self.attachementTitle = attachementTitle
    self.attachementDescription = attachementDescription
    self.attachementThumbnail = attachementThumbnail
    self.attachementURL = attachementURL
    self.replyToRemoteMessageID = replyToRemoteMessageID
    self.replyPreviewText = replyPreviewText
    self.replySenderName = replySenderName
    self.reactionSummary = reactionSummary
    self.isDeleted = isDeleted
  }
}
