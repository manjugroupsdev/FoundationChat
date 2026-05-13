import SwiftUI

struct MessageContentView: View {
  let message: Message
  let isOutgoing: Bool

  var body: some View {
    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Text(message.content)
        .foregroundStyle(isOutgoing ? .white : Color.black.opacity(0.92))
        .font(.system(size: 15.8, weight: .regular))
        .lineSpacing(2)
    }
  }
}
