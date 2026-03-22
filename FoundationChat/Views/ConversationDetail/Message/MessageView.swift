import SwiftUI

struct MessageView: View {
  @Environment(AuthStore.self) private var authStore

  let message: Message
  let otherParticipantLastReadAt: Date?
  let isLastOutgoingMessage: Bool

  private var isOutgoing: Bool {
    guard let currentUserStackUserId = authStore.viewer?.subject else {
      return message.role == .user
    }
    return message.senderStackUserId == currentUserStackUserId
  }

  private var isSeen: Bool {
    guard
      isOutgoing,
      message.remoteMessageID != nil,
      let otherParticipantLastReadAt
    else { return false }
    return message.timestamp <= otherParticipantLastReadAt
  }

  private var deliveryStatusText: String? {
    guard isOutgoing, isLastOutgoingMessage, message.remoteMessageID != nil else { return nil }
    return isSeen ? "Seen" : "Delivered"
  }

  private var bubbleColor: Color {
    isOutgoing ? .blue : Color(uiColor: .systemGray5)
  }

  private var hasTextContent: Bool {
    !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var isImageAttachment: Bool {
    message.attachementType == "image"
      || message.attachementMimeType?.hasPrefix("image/") == true
  }

  private var shouldRenderImageWithoutBubble: Bool {
    isImageAttachment && !hasTextContent
  }

  var body: some View {
    HStack {
      if isOutgoing {
        Spacer(minLength: 56)
      }
      VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
        if shouldRenderImageWithoutBubble {
          MessageAttachementView(message: message, isOutgoing: isOutgoing)
        } else {
          VStack(alignment: .leading, spacing: 8) {
            MessageContentView(message: message, isOutgoing: isOutgoing)
            MessageAttachementView(message: message, isOutgoing: isOutgoing)
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(bubbleColor)
          .clipShape(
            UnevenRoundedRectangle(
              cornerRadii: .init(
                topLeading: 22,
                bottomLeading: isOutgoing ? 22 : 6,
                bottomTrailing: isOutgoing ? 6 : 22,
                topTrailing: 22
              ),
              style: .continuous
            )
          )
        }

        if let deliveryStatusText {
          MessageDeliveryStatusView(text: deliveryStatusText)
            .padding(.trailing, 6)
        }
      }
      .padding(.horizontal, 12)
      .animation(.bouncy, value: message.content)
      if !isOutgoing {
        Spacer(minLength: 56)
      }
    }
  }
}

private struct MessageDeliveryStatusView: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(.secondary)
  }
}

#Preview {
  LazyVStack {
    MessageView(message: .init(content: "Hello world this is a short message",
                               role: .user,
                               timestamp: Date()),
                otherParticipantLastReadAt: nil,
                isLastOutgoingMessage: true)
    MessageView(message: .init(content: "Hello world this is a short message",
                               role: .assistant,
                               timestamp: Date()),
                otherParticipantLastReadAt: nil,
                isLastOutgoingMessage: false)
  }
}
