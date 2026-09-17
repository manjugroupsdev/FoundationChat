import SwiftUI

struct MessageContentView: View {
  let message: Message
  let isOutgoing: Bool

  var body: some View {
    if message.isDeleted {
      Text("This message was deleted")
        .foregroundStyle(Color.secondary)
        .font(.system(size: 14.5, weight: .regular))
        .italic()
    } else if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      if let payload = ChatLocationPayload(messageBody: message.content) {
        ChatLocationCard(payload: payload, isOutgoing: isOutgoing)
      } else {
        Text(message.content)
          .foregroundStyle(isOutgoing ? .white : Color.appPrimaryText)
          .font(.system(size: 15.8, weight: .regular))
          .lineSpacing(2)
      }
    }
  }
}
