import SwiftUI

struct MessageView: View {
  @Environment(AuthStore.self) private var authStore

  let message: Message
  let otherParticipantLastReadAt: Date?
  let isLastOutgoingMessage: Bool
  let onReply: () -> Void

  @State private var horizontalDragOffset: CGFloat = 0

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
    isOutgoing ? Color(red: 0.05, green: 0.38, blue: 0.79) : .white
  }

  private var textColor: Color {
    isOutgoing ? .white : Color.black.opacity(0.92)
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
    ZStack(alignment: isOutgoing ? .trailing : .leading) {
      Image(systemName: "arrowshape.turn.up.left.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color(red: 0.05, green: 0.38, blue: 0.79))
        .frame(width: 36, height: 36)
        .background(Color.white.opacity(0.92), in: Circle())
        .opacity(abs(horizontalDragOffset) > 14 ? 1 : 0)
        .scaleEffect(abs(horizontalDragOffset) > 52 ? 1.08 : 0.9)
        .padding(.horizontal, 18)

      HStack {
        if isOutgoing {
          Spacer(minLength: 48)
        }
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 6) {
          if shouldRenderImageWithoutBubble {
            MessageAttachementView(message: message, isOutgoing: isOutgoing)
          } else {
            VStack(alignment: .leading, spacing: 8) {
              if message.replyPreviewText?.isEmpty == false {
                ReplySnippetView(
                  sender: message.replySenderName,
                  preview: message.replyPreviewText ?? "",
                  isOutgoing: isOutgoing
                )
              }
              MessageContentView(message: message, isOutgoing: isOutgoing)
              MessageAttachementView(message: message, isOutgoing: isOutgoing)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: isOutgoing ? .bottomTrailing : .bottomLeading) {
              BubbleTail(isOutgoing: isOutgoing)
                .offset(x: isOutgoing ? 8 : -8, y: 2)
            }
            .overlay(
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(isOutgoing ? 0.04 : 0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
          }

          if let deliveryStatusText {
            MessageDeliveryStatusView(text: deliveryStatusText)
              .padding(.trailing, 6)
          }
        }
        .padding(.horizontal, 16)
        if !isOutgoing {
          Spacer(minLength: 48)
        }
      }
      .offset(x: horizontalDragOffset)
      .gesture(replyDragGesture)
    }
  }

  private var replyDragGesture: some Gesture {
    DragGesture(minimumDistance: 16, coordinateSpace: .local)
      .onChanged { value in
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        let translation = value.translation.width
        let desiredDirection = isOutgoing ? min(0, translation) : max(0, translation)
        horizontalDragOffset = max(-72, min(72, desiredDirection * 0.55))
      }
      .onEnded { _ in
        let shouldReply = abs(horizontalDragOffset) > 38
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
          horizontalDragOffset = 0
        }
        if shouldReply {
          onReply()
        }
      }
  }
}

private struct ReplySnippetView: View {
  let sender: String?
  let preview: String
  let isOutgoing: Bool

  var body: some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .fill(isOutgoing ? .white.opacity(0.75) : Color(red: 0.05, green: 0.38, blue: 0.79))
        .frame(width: 3)

      VStack(alignment: .leading, spacing: 2) {
        if let sender, !sender.isEmpty {
          Text(sender)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOutgoing ? .white.opacity(0.92) : Color(red: 0.05, green: 0.38, blue: 0.79))
            .lineLimit(1)
        }

        Text(preview)
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(isOutgoing ? .white.opacity(0.72) : Color.black.opacity(0.55))
          .lineLimit(2)
      }

      Spacer(minLength: 0)
    }
    .padding(8)
    .background(isOutgoing ? .white.opacity(0.14) : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct BubbleTail: View {
  let isOutgoing: Bool

  var body: some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
      .fill(isOutgoing ? Color(red: 0.05, green: 0.38, blue: 0.79) : .white)
      .frame(width: 14, height: 14)
      .rotationEffect(.degrees(45))
  }
}

private struct MessageDeliveryStatusView: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(Color.black.opacity(0.38))
  }
}

#Preview {
  LazyVStack {
    MessageView(message: .init(content: "Hello world this is a short message",
                               role: .user,
                               timestamp: Date()),
                otherParticipantLastReadAt: nil,
                isLastOutgoingMessage: true,
                onReply: {})
    MessageView(message: .init(content: "Hello world this is a short message",
                               role: .assistant,
                               timestamp: Date()),
                otherParticipantLastReadAt: nil,
                isLastOutgoingMessage: false,
                onReply: {})
  }
}
