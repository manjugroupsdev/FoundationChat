import SwiftUI

struct ConversationRowView: View {
  let conversation: Conversation

  private var title: String {
    conversation.participantDisplayName
      ?? conversation.summary
      ?? "New conversation"
  }

  private var subtitle: String {
    if let lastMessage = conversation.messages.last {
      let text = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty {
        return text
      }
      if lastMessage.attachementType == "image"
        || lastMessage.attachementMimeType?.hasPrefix("image/") == true
      {
        return "Photo"
      }
      if lastMessage.attachementType == "video"
        || lastMessage.attachementMimeType?.hasPrefix("video/") == true
      {
        return "Video"
      }
      if let name = lastMessage.attachementFileName, !name.isEmpty {
        return name
      }
      if let title = lastMessage.attachementTitle, !title.isEmpty {
        return title
      }
      return "Attachment"
    }
    return "No messages yet"
  }

  var body: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading) {
        Text(title)
          .font(.headline)
          .fontWeight(.bold)
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .contentTransition(.interpolate)
          .lineLimit(1)
      }
      .animation(.bouncy, value: conversation.summary)
      Spacer()
      VStack(alignment: .trailing, spacing: 6) {
        if let timestamp = conversation.messages.last?.timestamp {
          Text(
            timestamp.formatted(
              date: .omitted, time: .shortened)
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if conversation.unreadCountValue > 0 {
          Text(conversation.unreadCountValue > 99 ? "99+" : "\(conversation.unreadCountValue)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.blue, in: Capsule())
        }
      }
    }
  }
}
