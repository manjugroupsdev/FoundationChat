import Foundation
import SwiftData

@Model
class Conversation {
  @Relationship(deleteRule: .cascade)
  var messages: [Message]
  var summary: String?
  var remoteConversationID: String?
  var participantDisplayName: String?
  var unreadCount: Int?
  var otherParticipantLastReadAt: Date?
  var isFavorite: Bool

  var lastMessageTimestamp: Date {
    messages.last?.timestamp ?? Date()
  }

  var unreadCountValue: Int {
    unreadCount ?? 0
  }

  var sortedMessages: [Message] {
    messages.sorted { $0.timestamp < $1.timestamp }
  }

  init(
    messages: [Message],
    summary: String?,
    remoteConversationID: String? = nil,
    participantDisplayName: String? = nil,
    unreadCount: Int = 0,
    otherParticipantLastReadAt: Date? = nil,
    isFavorite: Bool = false
  ) {
    self.messages = messages
    self.summary = summary
    self.remoteConversationID = remoteConversationID
    self.participantDisplayName = participantDisplayName
    self.unreadCount = unreadCount
    self.otherParticipantLastReadAt = otherParticipantLastReadAt
    self.isFavorite = isFavorite
  }
}
