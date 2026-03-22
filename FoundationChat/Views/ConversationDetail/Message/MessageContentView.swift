import SwiftUI

struct MessageContentView: View {
  let message: Message
  let isOutgoing: Bool

  var body: some View {
    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Text(message.content)
        .foregroundStyle(isOutgoing ? .white : .primary)
        .font(.system(size: 18))
        .contentTransition(.interpolate)
    }
  }
}
