import SwiftUI

struct ConversationDetailInputView: ToolbarContent {
  @Binding var newMessage: String
  @Binding var isGenerating: Bool
  var isInputFocused: FocusState<Bool>.Binding

  var onAddAttachment: () -> Void
  var onSend: () async throws -> Void

  var body: some ToolbarContent {
    let canSend = !isGenerating && !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    ToolbarItemGroup(placement: .bottomBar) {
      Button(action: onAddAttachment) {
        Image(systemName: "plus")
      }

      TextField("iMessage", text: $newMessage, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1...4)
        .focused(isInputFocused)

      if canSend {
        Button {
          Task {
            try? await onSend()
          }
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .foregroundStyle(.blue)
        }
      } else if isGenerating {
        ProgressView()
      } else {
        Image(systemName: "mic.fill")
          .foregroundStyle(.secondary)
      }
    }
  }
}

#Preview {
  @FocusState var isInputFocused: Bool
  
  NavigationStack {
    List {
      Text("Hello")
    }
    .toolbar {
      ConversationDetailInputView(newMessage: .constant(""),
                                  isGenerating: .constant(false),
                                  isInputFocused: $isInputFocused,
                                  onAddAttachment: {},
                                  onSend: { })
    }
  }
}
