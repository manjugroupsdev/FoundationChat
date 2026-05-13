import SwiftUI

struct ConversationDetailInputView: View {
  @Binding var newMessage: String
  @Binding var isGenerating: Bool
  var isInputFocused: FocusState<Bool>.Binding

  let isVoiceRecording: Bool
  var onAddAttachment: () -> Void
  var onVoiceTap: () -> Void
  var onCancelVoiceRecording: () -> Void
  var onSend: () async throws -> Void

  private var canSend: Bool {
    !isGenerating && !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    HStack(spacing: 8) {
      Button(action: onAddAttachment) {
        Image(systemName: "plus")
          .font(.system(size: 19, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.8))
          .frame(width: 32, height: 32)
          .background(Color(red: 0.89, green: 0.90, blue: 0.92), in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(isVoiceRecording)

      HStack(spacing: 10) {
        if isVoiceRecording {
          Image(systemName: "waveform")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.red)

          Text("Recording voice...")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.78))

          Spacer(minLength: 0)

          Button(action: onCancelVoiceRecording) {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.35))
          }
          .buttonStyle(.plain)
        } else {
          TextField("Message ...", text: $newMessage, axis: .vertical)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(Color.black.opacity(0.85))
            .lineLimit(1...4)
            .focused(isInputFocused)

          Image(systemName: "face.smiling")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Color.black.opacity(0.45))
        }
      }
      .padding(.leading, 14)
      .padding(.trailing, 10)
      .frame(minHeight: 40)
      .background(Color.white, in: Capsule())
      .overlay(
        Capsule()
          .stroke(Color.black.opacity(0.08), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.05), radius: 10, y: 4)

      Button {
        if canSend {
          Task { try? await onSend() }
        } else {
          onVoiceTap()
        }
      } label: {
        Group {
          if isGenerating {
            ProgressView()
              .tint(.white)
          } else {
            Image(systemName: canSend || isVoiceRecording ? "paperplane.fill" : "mic.fill")
              .font(.system(size: 16, weight: .semibold))
          }
        }
        .foregroundStyle(.white)
        .frame(width: 36, height: 36)
        .background(isVoiceRecording ? Color.green : Color(red: 0.05, green: 0.38, blue: 0.79), in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(isGenerating)
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
    .padding(.bottom, 10)
    .background(Color.white)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Color.black.opacity(0.06))
        .frame(height: 1)
    }
  }
}

#Preview {
  @Previewable @State var text = ""
  @FocusState var isInputFocused: Bool

  VStack {
    Spacer()
    ConversationDetailInputView(
      newMessage: $text,
      isGenerating: .constant(false),
      isInputFocused: $isInputFocused,
      isVoiceRecording: false,
      onAddAttachment: {},
      onVoiceTap: {},
      onCancelVoiceRecording: {},
      onSend: {}
    )
  }
}
