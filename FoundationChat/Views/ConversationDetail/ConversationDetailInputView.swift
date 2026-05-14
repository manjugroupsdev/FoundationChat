import SwiftUI
import UIKit

struct ConversationDetailInputView: View {
  @Binding var newMessage: String
  @Binding var isGenerating: Bool
  @Binding var pendingVoicePreviewURL: URL?
  var isInputFocused: FocusState<Bool>.Binding

  let isVoiceRecording: Bool
  let voiceRecordingElapsed: TimeInterval
  @Binding var isEmojiPanelVisible: Bool
  var onAddAttachment: () -> Void
  var onVoiceTap: () -> Void
  var onVoiceRelease: () -> Void
  var onCancelVoiceRecording: () -> Void
  var onSendVoicePreview: () async throws -> Void
  var onDiscardVoicePreview: () -> Void
  var pendingVoicePreviewDuration: TimeInterval?
  var onSend: () async throws -> Void
  @State private var hasStartedVoiceDrag = false
  @State private var shouldCancelVoiceDrag = false

  private var canSend: Bool {
    !isGenerating && !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var hasVoicePreview: Bool {
    pendingVoicePreviewURL != nil
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
            .foregroundStyle(shouldCancelVoiceDrag ? Color.red : Color.black.opacity(0.78))

          Spacer(minLength: 0)

          Text(Self.formatDuration(voiceRecordingElapsed))
            .font(.system(size: 14, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.black.opacity(0.48))

          Button(action: onCancelVoiceRecording) {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.35))
          }
          .buttonStyle(.plain)
        } else if let pendingVoicePreviewURL {
          Button(action: onDiscardVoicePreview) {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.35))
          }
          .buttonStyle(.plain)

          AudioAttachmentPlaybackView(
            url: pendingVoicePreviewURL,
            title: "Voice preview",
            isOutgoing: false,
            durationOverride: pendingVoicePreviewDuration
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          TextField("Message ...", text: $newMessage, axis: .vertical)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(Color.black.opacity(0.85))
            .lineLimit(1...4)
            .focused(isInputFocused)
            .onTapGesture {
              isEmojiPanelVisible = false
            }

          Button {
            if isEmojiPanelVisible {
              isEmojiPanelVisible = false
              isInputFocused.wrappedValue = true
            } else {
              isEmojiPanelVisible = true
              isInputFocused.wrappedValue = false
            }
          } label: {
            Image(systemName: "face.smiling")
              .font(.system(size: 18, weight: .regular))
              .foregroundStyle(isEmojiPanelVisible ? Color(red: 0.05, green: 0.38, blue: 0.79) : Color.black.opacity(0.45))
              .frame(width: 24, height: 24)
          }
          .buttonStyle(.plain)
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
        if hasVoicePreview {
          Task { try? await onSendVoicePreview() }
        } else if canSend {
          Task { try? await onSend() }
        }
      } label: {
        Group {
          if isGenerating {
            ProgressView()
              .tint(.white)
          } else {
            Image(systemName: (canSend || hasVoicePreview) ? "paperplane.fill" : (shouldCancelVoiceDrag ? "xmark" : "mic.fill"))
              .font(.system(size: 16, weight: .semibold))
          }
        }
        .foregroundStyle(.white)
        .frame(width: 36, height: 36)
        .background(shouldCancelVoiceDrag ? Color.red : ((isVoiceRecording || hasVoicePreview) ? Color.green : Color(red: 0.05, green: 0.38, blue: 0.79)), in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(isGenerating)
      .simultaneousGesture(voiceDragGesture)
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
    .background {
      EmojiKeyboardInput(text: $newMessage, isFirstResponder: $isEmojiPanelVisible)
        .frame(width: 0, height: 0)
        .opacity(0.01)
        .allowsHitTesting(false)
    }
  }

  private var voiceDragGesture: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        guard !canSend, !hasVoicePreview, !isGenerating else { return }
        if !hasStartedVoiceDrag {
          hasStartedVoiceDrag = true
          shouldCancelVoiceDrag = false
          onVoiceTap()
        }
        shouldCancelVoiceDrag = value.translation.width < -72
      }
      .onEnded { _ in
        guard hasStartedVoiceDrag else { return }
        if shouldCancelVoiceDrag {
          onCancelVoiceRecording()
        } else {
          onVoiceRelease()
        }
        hasStartedVoiceDrag = false
        shouldCancelVoiceDrag = false
      }
  }

  private static func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    return "\(total / 60):\(String(format: "%02d", total % 60))"
  }
}

private struct EmojiKeyboardInput: UIViewRepresentable {
  @Binding var text: String
  @Binding var isFirstResponder: Bool

  func makeUIView(context: Context) -> EmojiTextField {
    let textField = EmojiTextField(frame: .zero)
    textField.delegate = context.coordinator
    textField.autocorrectionType = .no
    textField.autocapitalizationType = .none
    textField.tintColor = .clear
    textField.textColor = .clear
    textField.backgroundColor = .clear
    textField.returnKeyType = .default
    textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
    return textField
  }

  func updateUIView(_ textField: EmojiTextField, context: Context) {
    if textField.text != text {
      textField.text = text
    }

    if isFirstResponder, !textField.isFirstResponder {
      textField.becomeFirstResponder()
      textField.reloadInputViews()
    } else if !isFirstResponder, textField.isFirstResponder {
      textField.resignFirstResponder()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, isFirstResponder: $isFirstResponder)
  }

  final class Coordinator: NSObject, UITextFieldDelegate {
    @Binding private var text: String
    @Binding private var isFirstResponder: Bool

    init(text: Binding<String>, isFirstResponder: Binding<Bool>) {
      _text = text
      _isFirstResponder = isFirstResponder
    }

    @objc func textDidChange(_ textField: UITextField) {
      text = textField.text ?? ""
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
      if !isFirstResponder {
        textField.resignFirstResponder()
      }
    }
  }
}

private final class EmojiTextField: UITextField {
  override var textInputMode: UITextInputMode? {
    UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
  }
}

#Preview {
  @Previewable @State var text = ""
  @Previewable @State var emoji = false
  @FocusState var isInputFocused: Bool

  VStack {
    Spacer()
    ConversationDetailInputView(
      newMessage: $text,
      isGenerating: .constant(false),
      pendingVoicePreviewURL: .constant(nil),
      isInputFocused: $isInputFocused,
      isVoiceRecording: false,
      voiceRecordingElapsed: 0,
      isEmojiPanelVisible: $emoji,
      onAddAttachment: {},
      onVoiceTap: {},
      onVoiceRelease: {},
      onCancelVoiceRecording: {},
      onSendVoicePreview: {},
      onDiscardVoicePreview: {},
      pendingVoicePreviewDuration: nil,
      onSend: {}
    )
  }
}
