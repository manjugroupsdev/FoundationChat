import Combine
import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ConversationDetailView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Environment(AuthStore.self) private var authStore

  @State var newMessage: String = ""
  @State var conversation: Conversation
  @State var scrollPosition: ScrollPosition = .init()
  @State var isGenerating: Bool = false
  @State private var messagesSubscription: AnyCancellable?
  @State private var conversationStatusSubscription: AnyCancellable?
  @State private var lastMarkedSeenAt: Date?
  @State private var pollingTask: Task<Void, Never>?
  @State private var lastPollTimestamp: Double = 0
  @State private var isAttachmentOptionsPresented = false
  @State private var isPhotoPickerPresented = false
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var isCameraPresented = false
  @State private var capturedCameraImage: UIImage?
  @State private var isFileImporterPresented = false
  @State private var activeDetailSheet: ActiveDetailSheet?
  @State private var replyTarget: Message?
  @State private var pendingImageAttachment: PendingImageAttachment?
  @State private var reactionTarget: Message?
  @State private var selectedMessageIDs: Set<PersistentIdentifier> = []
  @State private var highlightedRemoteMessageID: String?
  @State private var voiceRecorder: AVAudioRecorder?
  @State private var voiceRecordingURL: URL?
  @State private var isVoiceRecording = false
  @State private var isEmojiPanelVisible = false
  @State private var mentionUsers: [DirectoryUser] = []
  @State private var mentionSearchTask: Task<Void, Never>?
  @FocusState var isInputFocused: Bool

  enum ActiveDetailSheet: Identifiable {
    case media
    case search
    case info

    var id: String {
      switch self {
      case .media: return "media"
      case .search: return "search"
      case .info: return "info"
      }
    }
  }

  private var conversationTitle: String {
    if let participantDisplayName = conversation.participantDisplayName,
      !participantDisplayName.isEmpty
    {
      return participantDisplayName
    }

    if let summary = conversation.summary, !summary.isEmpty {
      return summary
    }

    return "Conversation"
  }

  private var conversationSubtitle: String {
    if let lastSeen = conversation.otherParticipantLastReadAt {
      return "Last seen \(lastSeen.formatted(date: .omitted, time: .shortened))"
    }
    return "Direct message"
  }

  private var lastOutgoingMessage: Message? {
    let currentUserStackUserId = authStore.viewer?.subject
    return conversation.sortedMessages.last { message in
      if let currentUserStackUserId {
        return message.senderStackUserId == currentUserStackUserId
      }
      return message.role == .user
    }
  }

  var body: some View {
    let sortedMessages = conversation.sortedMessages

    return ZStack {
      ChatWallpaper()
        .ignoresSafeArea()

      VStack(spacing: 0) {
        if selectedMessageIDs.isEmpty {
          conversationHeader
        } else {
          messageSelectionHeader
        }

        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(Array(sortedMessages.enumerated()), id: \.element.id) { index, message in
              if shouldShowTimestamp(at: index, in: sortedMessages) {
                MessageTimestampDivider(date: message.timestamp)
                  .padding(.top, index == 0 ? 12 : 16)
              }

              MessageView(
                message: message,
                otherParticipantLastReadAt: conversation.otherParticipantLastReadAt,
                isLastOutgoingMessage: message === lastOutgoingMessage,
                isHighlighted: message.remoteMessageID == highlightedRemoteMessageID,
                isSelected: selectedMessageIDs.contains(message.persistentModelID),
                isSelectionMode: !selectedMessageIDs.isEmpty,
                onReply: {
                  replyTarget = message
                  isInputFocused = true
                },
                onTapReplyPreview: {
                  scrollToRepliedMessage(from: message)
                },
                onShowReactions: {
                  guard message.remoteMessageID != nil, !message.isDeleted else { return }
                  withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    _ = selectedMessageIDs.insert(message.persistentModelID)
                  }
                },
                onToggleSelection: {
                  toggleMessageSelection(message)
                }
              )
              .id(message.id)
            }
          }
          .scrollTargetLayout()
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
      }

      if let reactionTarget {
        MessageReactionOverlay(
          message: reactionTarget,
          isOutgoing: isOutgoingMessage(reactionTarget),
          onDismiss: {
            withAnimation(.easeOut(duration: 0.18)) {
              self.reactionTarget = nil
            }
          },
          onReply: {
            replyTarget = reactionTarget
            isInputFocused = true
            selectedMessageIDs.removeAll()
          },
          onForward: {},
          onCopy: {
            UIPasteboard.general.string = reactionTarget.content
            selectedMessageIDs.removeAll()
          },
          onReact: { emoji in
            Task {
              await toggleReaction(emoji, for: reactionTarget)
            }
            selectedMessageIDs.removeAll()
          },
          onDelete: {
            Task {
              await deleteMessage(reactionTarget)
            }
            selectedMessageIDs.removeAll()
          }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(20)
      }
    }
    .onAppear {
      isInputFocused = true
      startMessagesSubscription()
      startConversationStatusSubscription()
      startPolling()
      withAnimation {
        scrollPosition.scrollTo(edge: .bottom)
      }
    }
    .onDisappear {
      messagesSubscription?.cancel()
      messagesSubscription = nil
      conversationStatusSubscription?.cancel()
      conversationStatusSubscription = nil
      pollingTask?.cancel()
      pollingTask = nil
    }
    .onChange(of: conversation.remoteConversationID) { _, _ in
      lastMarkedSeenAt = nil
      startMessagesSubscription()
      startConversationStatusSubscription()
    }
    .onChange(of: newMessage) { _, _ in
      scheduleMentionDirectoryLoad()
    }
    .scrollDismissesKeyboard(.interactively)
    .scrollPosition($scrollPosition, anchor: .bottom)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        if let replyTarget {
          ReplyComposerPreview(
            message: replyTarget,
            senderName: replySenderName(for: replyTarget),
            onClose: { self.replyTarget = nil }
          )
        }

        if let mentionQuery = activeMentionQuery {
          MentionSuggestionsView(
            users: mentionSuggestions(for: mentionQuery),
            onSelect: insertMention
          )
        }

        ConversationDetailInputView(
          newMessage: $newMessage,
          isGenerating: $isGenerating,
          isInputFocused: $isInputFocused,
          isVoiceRecording: isVoiceRecording,
          isEmojiPanelVisible: $isEmojiPanelVisible,
          onAddAttachment: {
            guard !isGenerating else { return }
            isInputFocused = false
            isEmojiPanelVisible = false
            isAttachmentOptionsPresented = true
          },
          onVoiceTap: {
            Task {
              if isVoiceRecording {
                await finishVoiceRecordingAndSend()
              } else {
                await startVoiceRecording()
              }
            }
          },
          onCancelVoiceRecording: {
            cancelVoiceRecording()
          },
          onSend: {
            isGenerating = true
            await streamNewMessage()
            isGenerating = false
          }
        )
      }
    }
    .sheet(item: $activeDetailSheet) { sheet in
      conversationDetailSheet(for: sheet)
    }
    .sheet(isPresented: $isAttachmentOptionsPresented) {
      AttachmentOptionsSheet(
        onPhotos: {
          isAttachmentOptionsPresented = false
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            isPhotoPickerPresented = true
          }
        },
        onCamera: {
          isAttachmentOptionsPresented = false
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            isCameraPresented = true
          }
        },
        onFiles: {
          isAttachmentOptionsPresented = false
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            isFileImporterPresented = true
          }
        },
        onDismiss: {
          isAttachmentOptionsPresented = false
        }
      )
      .presentationDetents([.height(390), .fraction(0.7)])
      .presentationDragIndicator(.visible)
      .presentationBackground(.clear)
    }
    .sheet(isPresented: $isCameraPresented) {
      ChatCameraPicker(image: $capturedCameraImage)
        .ignoresSafeArea()
    }
    .fullScreenCover(item: $pendingImageAttachment) { attachment in
      ImageAttachmentPreviewView(
        attachment: attachment,
        recipientName: conversationTitle,
        onCancel: {
          pendingImageAttachment = nil
        },
        onSend: { editedData, caption in
          pendingImageAttachment = nil
          await sendAttachment(
            data: editedData,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            attachmentType: attachment.attachmentType,
            attachmentTitle: nil,
            attachmentDescription: nil,
            caption: caption
          )
        }
      )
    }
    .photosPicker(
      isPresented: $isPhotoPickerPresented,
      selection: $selectedPhotoItem,
      matching: .any(of: [.images, .videos]),
      preferredItemEncoding: .automatic
    )
    .onChange(of: selectedPhotoItem) { _, newValue in
      guard let newValue else { return }
      Task {
        await handleSelectedMedia(newValue)
      }
    }
    .onChange(of: capturedCameraImage) { _, newValue in
      guard let newValue else { return }
      Task {
        await handleCapturedCameraImage(newValue)
      }
    }
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) { result in
      Task {
        await handleImportedFile(result)
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
  }

  private var conversationHeader: some View {
    HStack(spacing: 12) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Color(red: 0.43, green: 0.52, blue: 0.89))
          .frame(width: 32, height: 32)
          .background(Color.white.opacity(0.8), in: Circle())
      }
      .buttonStyle(.plain)

      Button {
        isInputFocused = false
        activeDetailSheet = .info
      } label: {
        HStack(spacing: 12) {
          Circle()
            .fill(
              LinearGradient(
                colors: [
                  Color(red: 0.92, green: 0.80, blue: 0.71),
                  Color(red: 0.70, green: 0.48, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 32, height: 32)
            .overlay(
              Text(String(conversationTitle.prefix(1)).uppercased())
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.8))
            )

          VStack(spacing: 1) {
            Text(conversationTitle)
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.9))
              .lineLimit(1)

            Text(conversationSubtitle)
              .font(.system(size: 12, weight: .regular))
              .foregroundStyle(Color.black.opacity(0.35))
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
      }
      .frame(maxWidth: .infinity)
      .buttonStyle(.plain)
      .disabled(conversation.remoteConversationID == nil)

      Menu {
        Button {
          isInputFocused = false
          activeDetailSheet = .search
        } label: {
          Label("Search Messages", systemImage: "magnifyingglass")
        }

        Button {
          isInputFocused = false
          activeDetailSheet = .media
        } label: {
          Label("Media, Files & Links", systemImage: "photo.on.rectangle")
        }

        Button {
          isInputFocused = false
          activeDetailSheet = .info
        } label: {
          Label("Conversation Info", systemImage: "info.circle")
        }
      } label: {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(Color(red: 0.43, green: 0.52, blue: 0.89))
          .frame(width: 32, height: 32)
          .background(Color.white.opacity(0.8), in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(conversation.remoteConversationID == nil)
    }
    .padding(.horizontal, 14)
    .padding(.top, 10)
    .padding(.bottom, 12)
    .background(Color.white.opacity(0.9))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.black.opacity(0.06))
        .frame(height: 1)
    }
  }

  private var messageSelectionHeader: some View {
    HStack(spacing: 12) {
      Button {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
          selectedMessageIDs.removeAll()
          reactionTarget = nil
        }
      } label: {
        Text("Cancel")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(Color(red: 0.05, green: 0.42, blue: 0.82))
          .padding(.horizontal, 14)
          .frame(height: 40)
          .background(Color.black.opacity(0.04), in: Capsule())
      }
      .buttonStyle(.plain)

      Text("\(selectedMessageIDs.count) selected")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.9))
        .frame(maxWidth: .infinity)

      Menu {
        Button {
          replyToSelectedMessage()
        } label: {
          Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
        .disabled(selectedMessages.count != 1)

        Button {
          copySelectedMessages()
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(selectedMessages.allSatisfy { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        Button {
          showReactionsForSelectedMessage()
        } label: {
          Label("React", systemImage: "face.smiling")
        }
        .disabled(selectedMessages.count != 1 || selectedMessages.first?.remoteMessageID == nil)

        Button(role: .destructive) {
          Task { await deleteSelectedMessages() }
        } label: {
          Label("Delete", systemImage: "trash")
        }
        .disabled(selectedMessages.isEmpty)
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(Color(red: 0.05, green: 0.42, blue: 0.82))
          .frame(width: 40, height: 40)
          .background(Color.black.opacity(0.04), in: Circle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 14)
    .padding(.top, 10)
    .padding(.bottom, 12)
    .background(Color.white.opacity(0.96))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.black.opacity(0.06))
        .frame(height: 1)
    }
    .transition(.move(edge: .top).combined(with: .opacity))
  }

  @ViewBuilder
  private func conversationDetailSheet(for sheet: ActiveDetailSheet) -> some View {
    if let remoteID = conversation.remoteConversationID {
      NavigationStack {
        switch sheet {
        case .media:
          ConversationMediaView(conversationID: remoteID, title: conversationTitle)
            .toolbar {
              ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { activeDetailSheet = nil }
              }
            }
        case .search:
          ConversationSearchView(
            conversationID: remoteID,
            title: conversationTitle,
            onSelectMessage: { message in
              highlightAndScroll(to: message.id)
            }
          )
            .toolbar {
              ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { activeDetailSheet = nil }
              }
            }
        case .info:
          ConversationInfoView(
            source: .conversation(id: remoteID),
            initialDisplayName: conversationTitle
          )
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button("Done") { activeDetailSheet = nil }
            }
          }
        }
      }
    }
  }

  private func shouldShowTimestamp(at index: Int, in messages: [Message]) -> Bool {
    guard messages.indices.contains(index) else { return false }
    if index == 0 { return true }

    let previousTimestamp = messages[index - 1].timestamp
    let currentTimestamp = messages[index].timestamp
    return currentTimestamp.timeIntervalSince(previousTimestamp) > 30 * 60
  }

  private var selectedMessages: [Message] {
    conversation.sortedMessages.filter { selectedMessageIDs.contains($0.persistentModelID) }
  }

  private func toggleMessageSelection(_ message: Message) {
    guard !message.isDeleted else { return }
    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
      if selectedMessageIDs.contains(message.persistentModelID) {
        selectedMessageIDs.remove(message.persistentModelID)
      } else {
        selectedMessageIDs.insert(message.persistentModelID)
      }

      if selectedMessageIDs.isEmpty {
        reactionTarget = nil
      }
    }
  }

  private func replyToSelectedMessage() {
    guard let message = selectedMessages.first, selectedMessages.count == 1 else { return }
    replyTarget = message
    isInputFocused = true
    selectedMessageIDs.removeAll()
    reactionTarget = nil
  }

  private func copySelectedMessages() {
    let copiedText = selectedMessages
      .map(\.content)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")

    guard !copiedText.isEmpty else { return }
    UIPasteboard.general.string = copiedText
    selectedMessageIDs.removeAll()
    reactionTarget = nil
  }

  private func showReactionsForSelectedMessage() {
    guard
      let message = selectedMessages.first,
      selectedMessages.count == 1,
      message.remoteMessageID != nil
    else { return }

    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
      reactionTarget = message
    }
  }

  @MainActor
  private func deleteSelectedMessages() async {
    let messages = selectedMessages
    guard !messages.isEmpty else { return }

    selectedMessageIDs.removeAll()
    reactionTarget = nil

    for message in messages {
      await deleteMessage(message)
    }
  }

  private var activeMentionQuery: String? {
    guard let lastToken = newMessage.split(separator: " ", omittingEmptySubsequences: false).last,
      lastToken.hasPrefix("@")
    else { return nil }
    return String(lastToken.dropFirst())
  }

  private func mentionSuggestions(for query: String) -> [DirectoryUser] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let candidates = mentionUsers.filter { user in
      guard !trimmed.isEmpty else { return true }
      return user.displayName.lowercased().contains(trimmed)
        || (user.email?.lowercased().contains(trimmed) == true)
    }
    return Array(candidates.prefix(6))
  }

  @MainActor
  private func scheduleMentionDirectoryLoad() {
    guard activeMentionQuery != nil, mentionUsers.isEmpty else { return }
    mentionSearchTask?.cancel()
    mentionSearchTask = Task {
      do {
        let users = try await authStore.fetchDirectoryUsers(search: "")
        guard !Task.isCancelled else { return }
        mentionUsers = users
      } catch {
        mentionUsers = []
      }
    }
  }

  private func insertMention(_ user: DirectoryUser) {
    var parts = newMessage.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    if parts.last?.hasPrefix("@") == true {
      parts.removeLast()
    }
    parts.append("@\(user.displayName)")
    newMessage = parts.joined(separator: " ") + " "
    isEmojiPanelVisible = false
    isInputFocused = true
  }

  private func mentionedStaffIds(in text: String) -> [String] {
    let lowerText = text.lowercased()
    return mentionUsers.compactMap { user in
      lowerText.contains("@\(user.displayName.lowercased())") ? user.stackUserId : nil
    }
  }
}

struct MentionSuggestionsView: View {
  let users: [DirectoryUser]
  let onSelect: (DirectoryUser) -> Void

  var body: some View {
    if !users.isEmpty {
      VStack(spacing: 0) {
        ForEach(users) { user in
          Button {
            onSelect(user)
          } label: {
            HStack(spacing: 10) {
              AvatarPlaceholder(initials: initials(for: user.displayName))
                .frame(width: 36, height: 36)
                .scaleEffect(36 / 52)

              VStack(alignment: .leading, spacing: 1) {
                Text(user.displayName)
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(.primary)
                if let email = user.email, !email.isEmpty {
                  Text(email)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }

              Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
          }
          .buttonStyle(.plain)
        }
      }
      .background(Color.white)
      .overlay(alignment: .top) {
        Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
      }
    }
  }

  private func initials(for name: String) -> String {
    let parts = name.split(whereSeparator: { !$0.isLetter }).prefix(2)
    let initials = String(parts.compactMap(\.first)).uppercased()
    return initials.isEmpty ? "U" : initials
  }
}

private struct MessageTimestampDivider: View {
  let date: Date

  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "E, d MMM 'at' h:mm a"
    return formatter
  }()

  var body: some View {
    Text(Self.formatter.string(from: date))
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(Color.black.opacity(0.6))
      .padding(.horizontal, 14)
      .padding(.vertical, 5)
      .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .stroke(Color.black.opacity(0.04), lineWidth: 1)
      )
      .frame(maxWidth: .infinity)
  }
}

private struct AttachmentOptionsSheet: View {
  let onPhotos: () -> Void
  let onCamera: () -> Void
  let onFiles: () -> Void
  let onDismiss: () -> Void

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

  var body: some View {
    VStack(spacing: 16) {
      LazyVGrid(columns: columns, spacing: 20) {
        AttachmentDrawerItem(icon: "photo.on.rectangle.angled", tint: Color(red: 0.20, green: 0.56, blue: 1.0), title: "Photos", action: onPhotos)
        AttachmentDrawerItem(icon: "camera.fill", tint: .white, title: "Camera", action: onCamera)
        AttachmentDrawerItem(icon: "mappin.circle.fill", tint: Color(red: 0.04, green: 0.78, blue: 0.55), title: "Location", action: onDismiss)
        AttachmentDrawerItem(icon: "person.crop.circle.fill", tint: Color.white.opacity(0.9), title: "Contact", action: onDismiss)
        AttachmentDrawerItem(icon: "doc.fill", tint: Color(red: 0.04, green: 0.64, blue: 1.0), title: "Document", action: onFiles)
        AttachmentDrawerItem(icon: "list.bullet.rectangle.fill", tint: Color(red: 1.0, green: 0.72, blue: 0.22), title: "Poll", action: onDismiss)
        AttachmentDrawerItem(icon: "calendar", tint: Color(red: 1.0, green: 0.02, blue: 0.30), title: "Event", action: onDismiss)
        AttachmentDrawerItem(icon: "photo.badge.sparkles", tint: Color(red: 0.20, green: 0.56, blue: 1.0), title: "AI images", action: onDismiss)
      }
      .padding(.horizontal, 20)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.clear)
    .padding(.top, 18)
  }
}

private struct AttachmentDrawerItem: View {
  let icon: String
  let tint: Color
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: icon)
          .font(.system(size: 27, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 62, height: 42)
          .background(.ultraThinMaterial, in: Capsule())
          .overlay(
            Capsule()
              .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
          )

        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.82))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
  }
}

private struct AttachmentOptionRow: View {
  let icon: String
  let tint: Color
  let title: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 25, weight: .regular))
        .foregroundStyle(tint)
        .frame(width: 42, height: 42)

      Text(title)
        .font(.system(size: 24, weight: .regular))
        .foregroundStyle(Color.black.opacity(0.92))

      Spacer()
    }
    .padding(.horizontal, 28)
    .frame(height: 72)
  }
}

private struct ReplyComposerPreview: View {
  let message: Message
  let senderName: String
  let onClose: () -> Void

  private var previewText: String {
    let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty { return text }
    if message.attachementMimeType?.hasPrefix("image/") == true || message.attachementType == "image" {
      return "Photo"
    }
    if let fileName = message.attachementFileName, !fileName.isEmpty {
      return fileName
    }
    return "Attachment"
  }

  var body: some View {
    HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .fill(Color(red: 0.05, green: 0.38, blue: 0.79))
        .frame(width: 4, height: 34)

      VStack(alignment: .leading, spacing: 3) {
        Text(senderName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color(red: 0.05, green: 0.38, blue: 0.79))
          .lineLimit(1)

        Text(previewText)
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(Color.black.opacity(0.56))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Color.black.opacity(0.42))
          .frame(width: 28, height: 28)
          .background(Color.black.opacity(0.06), in: Circle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .frame(height: 54)
    .background(Color.white)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Color.black.opacity(0.06))
        .frame(height: 1)
    }
  }
}

private struct PendingImageAttachment: Identifiable {
  let id = UUID()
  let data: Data
  let fileName: String
  let mimeType: String
  let attachmentType: String
  let image: UIImage
}

private struct ImageAttachmentPreviewView: View {
  let attachment: PendingImageAttachment
  let recipientName: String
  let onCancel: () -> Void
  let onSend: (Data, String) async -> Void

  @State private var caption = ""
  @State private var isSending = false
  @State private var workingImage: UIImage
  @State private var workingData: Data
  @State private var isCropPresented = false
  @State private var statusMessage: String?
  @FocusState private var isCaptionFocused: Bool

  init(
    attachment: PendingImageAttachment,
    recipientName: String,
    onCancel: @escaping () -> Void,
    onSend: @escaping (Data, String) async -> Void
  ) {
    self.attachment = attachment
    self.recipientName = recipientName
    self.onCancel = onCancel
    self.onSend = onSend
    _workingImage = State(initialValue: attachment.image)
    _workingData = State(initialValue: attachment.data)
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        previewHeader

        GeometryReader { proxy in
          Image(uiImage: workingImage)
            .resizable()
            .scaledToFit()
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }

        previewTools
        previewComposer
      }

      if let statusMessage {
        VStack {
          Text(statusMessage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.16), in: Capsule())
            .padding(.top, 72)
          Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .preferredColorScheme(.dark)
    .fullScreenCover(isPresented: $isCropPresented) {
      ImageCropEditorView(
        image: workingImage,
        onCancel: {
          isCropPresented = false
        },
        onDone: { croppedImage in
          workingImage = croppedImage
          workingData = encodedData(for: croppedImage)
          isCropPresented = false
          showStatus("Crop applied")
        }
      )
    }
  }

  private var previewHeader: some View {
    HStack(spacing: 12) {
      Button(action: onCancel) {
        Image(systemName: "xmark")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(Color.white.opacity(0.16), in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(isSending)

      VStack(alignment: .leading, spacing: 2) {
        Text(recipientName)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(1)

        Text("Photo")
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(.white.opacity(0.68))
      }

      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 10)
    .background(.ultraThinMaterial.opacity(0.35))
  }

  private var previewComposer: some View {
    HStack(spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: "photo")
          .font(.system(size: 18, weight: .regular))
          .foregroundStyle(.white.opacity(0.86))

        TextField("Add a caption...", text: $caption, axis: .vertical)
          .font(.system(size: 16, weight: .regular))
          .foregroundStyle(.white)
          .tint(.white)
          .lineLimit(1...4)
          .focused($isCaptionFocused)
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 52)
      .background(Color.white.opacity(0.12), in: Capsule())

      Button {
        guard !isSending else { return }
        isSending = true
        Task {
          await onSend(workingData, caption.trimmingCharacters(in: .whitespacesAndNewlines))
          isSending = false
        }
      } label: {
        Group {
          if isSending {
            ProgressView()
              .tint(.white)
          } else {
            Image(systemName: "paperplane.fill")
              .font(.system(size: 19, weight: .semibold))
          }
        }
        .foregroundStyle(.white)
        .frame(width: 54, height: 54)
        .background(Color(red: 0.05, green: 0.70, blue: 0.32), in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(isSending)
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 18)
    .background(.ultraThinMaterial.opacity(0.45))
  }

  private var previewTools: some View {
    HStack(spacing: 14) {
      PreviewToolButton(icon: "square.and.arrow.down", title: "Save") {
        UIImageWriteToSavedPhotosAlbum(workingImage, nil, nil, nil)
        showStatus("Saved to Photos")
      }
      PreviewToolButton(icon: "crop", title: "Crop") {
        isCropPresented = true
      }
      PreviewToolButton(icon: "pencil.tip", title: "Draw", isEnabled: false) {}
      PreviewToolButton(icon: "textformat", title: "Text", isEnabled: false) {}
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial.opacity(0.35))
  }

  private func encodedData(for image: UIImage) -> Data {
    if attachment.mimeType == "image/png", let data = image.pngData() {
      return data
    }
    return image.jpegData(compressionQuality: 0.9) ?? workingData
  }

  private func showStatus(_ message: String) {
    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
      statusMessage = message
    }

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.5))
      guard statusMessage == message else { return }
      withAnimation(.easeOut(duration: 0.2)) {
        statusMessage = nil
      }
    }
  }
}

private struct PreviewToolButton: View {
  let icon: String
  let title: String
  var isEnabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: icon)
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 34, height: 34)
          .background(Color.white.opacity(0.13), in: Circle())
        Text(title)
          .font(.system(size: 11, weight: .medium))
      }
      .foregroundStyle(.white.opacity(0.86))
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.42)
  }
}

private struct ImageCropEditorView: View {
  let image: UIImage
  let onCancel: () -> Void
  let onDone: (UIImage) -> Void

  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero

  var body: some View {
    GeometryReader { proxy in
      let cropSize = cropSize(in: proxy.size)

      VStack(spacing: 0) {
        HStack {
          Button("Cancel", action: onCancel)
            .foregroundStyle(.white)

          Spacer()

          Text("Crop")
            .font(.headline)
            .foregroundStyle(.white)

          Spacer()

          Button("Done") {
            if let croppedImage = renderCroppedImage(cropSize: cropSize) {
              onDone(croppedImage)
            } else {
              onCancel()
            }
          }
          .fontWeight(.semibold)
          .foregroundStyle(Color(red: 0.2, green: 0.7, blue: 1))
        }
        .padding(.horizontal, 18)
        .padding(.top, proxy.safeAreaInsets.top + 12)
        .padding(.bottom, 16)
        .background(Color.black.opacity(0.92))

        Spacer(minLength: 20)

        CropCanvasView(
          image: image,
          scale: scale,
          offset: offset,
          cropSize: cropSize,
          showsGrid: true
        )
        .gesture(dragGesture)
        .simultaneousGesture(magnificationGesture)

        Spacer(minLength: 20)

        Text("Pinch to zoom and drag to reposition")
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.72))
          .padding(.bottom, proxy.safeAreaInsets.bottom + 20)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .background(Color.black.ignoresSafeArea())
    }
    .preferredColorScheme(.dark)
  }

  private var dragGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        offset = CGSize(
          width: lastOffset.width + value.translation.width,
          height: lastOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        lastOffset = offset
      }
  }

  private var magnificationGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        scale = min(max(lastScale * value, 1), 5)
      }
      .onEnded { _ in
        lastScale = scale
      }
  }

  private func cropSize(in size: CGSize) -> CGFloat {
    max(220, min(size.width - 32, size.height - 230, 420))
  }

  @MainActor
  private func renderCroppedImage(cropSize: CGFloat) -> UIImage? {
    let renderer = ImageRenderer(
      content: CropCanvasView(
        image: image,
        scale: scale,
        offset: offset,
        cropSize: cropSize,
        showsGrid: false
      )
    )
    renderer.scale = UIScreen.main.scale
    return renderer.uiImage
  }
}

private struct CropCanvasView: View {
  let image: UIImage
  let scale: CGFloat
  let offset: CGSize
  let cropSize: CGFloat
  let showsGrid: Bool

  var body: some View {
    ZStack {
      Color.black

      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: cropSize, height: cropSize)
        .scaleEffect(scale)
        .offset(offset)

      if showsGrid {
        cropOverlay
      }
    }
    .frame(width: cropSize, height: cropSize)
    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .stroke(Color.white.opacity(0.92), lineWidth: 1.5)
    )
  }

  private var cropOverlay: some View {
    ZStack {
      ForEach([cropSize / 3, cropSize * 2 / 3], id: \.self) { position in
        Rectangle()
          .fill(Color.white.opacity(0.45))
          .frame(width: 1)
          .offset(x: position - cropSize / 2)

        Rectangle()
          .fill(Color.white.opacity(0.45))
          .frame(height: 1)
          .offset(y: position - cropSize / 2)
      }
    }
  }
}

private struct MessageReactionOverlay: View {
  let message: Message
  let isOutgoing: Bool
  let onDismiss: () -> Void
  let onReply: () -> Void
  let onForward: () -> Void
  let onCopy: () -> Void
  let onReact: (String) -> Void
  let onDelete: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.28)
        .ignoresSafeArea()
        .onTapGesture(perform: onDismiss)

      VStack(spacing: 12) {
        ReactionPreviewBubble(message: message, isOutgoing: isOutgoing)

        ReactionActionMenu(
          message: message,
          reactions: decodedReactions,
          onReply: {
            onReply()
            onDismiss()
          },
          onForward: {
            onForward()
            onDismiss()
          },
          onCopy: {
            onCopy()
            onDismiss()
          },
          onReact: { emoji in
            onReact(emoji)
            onDismiss()
          },
          onDelete: {
            onDelete()
            onDismiss()
          },
          onDismiss: onDismiss
        )
      }
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity)
    }
  }

  private var decodedReactions: [MessageReactionInfo] {
    guard let summary = message.reactionSummary, !summary.isEmpty else { return [] }
    return summary.split(separator: "|").compactMap { item in
      let parts = item.split(separator: ",", omittingEmptySubsequences: false)
      guard parts.count >= 3, let count = Int(parts[1]) else { return nil }
      return MessageReactionInfo(emoji: String(parts[0]), count: count, hasReacted: parts[2] == "1")
    }
  }
}

private struct ReactionActionMenu: View {
  let message: Message
  let reactions: [MessageReactionInfo]
  let onReply: () -> Void
  let onForward: () -> Void
  let onCopy: () -> Void
  let onReact: (String) -> Void
  let onDelete: () -> Void
  let onDismiss: () -> Void

  private let quickEmojis = ["❤️", "👍", "😂", "😮", "😢", "🙏"]

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        ForEach(quickEmojis, id: \.self) { emoji in
          Button {
            onReact(emoji)
          } label: {
            Text(emoji)
              .font(.system(size: 24))
              .frame(width: 34, height: 34)
              .background(reactions.first(where: { $0.emoji == emoji })?.hasReacted == true ? Color.white.opacity(0.22) : Color.clear, in: Circle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.bottom, 10)

      ReactionActionRow(icon: "arrowshape.turn.up.left", title: "Reply", tint: .white, action: onReply)
      ReactionActionRow(icon: "arrowshape.turn.up.right", title: "Forward", tint: .white, action: onForward)
      ReactionActionRow(icon: "doc.on.doc", title: "Copy", tint: .white, action: onCopy)
        .disabled(message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
      ForEach(reactions.filter(\.hasReacted)) { reaction in
        ReactionActionRow(icon: "minus.circle", title: "Remove \(reaction.emoji)", tint: .white, action: { onReact(reaction.emoji) })
      }
      ReactionActionRow(icon: "trash", title: "Delete", tint: Color(red: 1.0, green: 0.36, blue: 0.45), action: onDelete)
    }
    .padding(.horizontal, 26)
    .padding(.vertical, 16)
    .frame(maxWidth: 290)
    .background(Color.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
  }
}

private struct ReactionActionRow: View {
  let icon: String
  let title: String
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 18) {
        Image(systemName: icon)
          .font(.system(size: 18, weight: .regular))
          .frame(width: 24)

        Text(title)
          .font(.system(size: 18, weight: .regular))

        Spacer(minLength: 0)
      }
      .foregroundStyle(tint)
      .frame(height: 44)
    }
    .buttonStyle(.plain)
  }
}

private struct ReactionPreviewBubble: View {
  let message: Message
  let isOutgoing: Bool

  private var previewText: String {
    let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty { return text }
    if message.attachementMimeType?.hasPrefix("image/") == true || message.attachementType == "image" {
      return "Photo"
    }
    if let fileName = message.attachementFileName, !fileName.isEmpty {
      return fileName
    }
    return "Message"
  }

  var body: some View {
    Text(previewText)
      .font(.system(size: 15, weight: .regular))
      .foregroundStyle(isOutgoing ? .white : Color.black.opacity(0.9))
      .lineLimit(4)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: 260, alignment: .leading)
      .background(isOutgoing ? Color(red: 0.05, green: 0.38, blue: 0.79) : .white)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
      .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
      .padding(.horizontal, 28)
  }
}

extension ConversationDetailView {
  @MainActor
  private func handleCapturedCameraImage(_ image: UIImage) async {
    defer { capturedCameraImage = nil }

    guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
      conversation.messages.append(
        Message(
          content: "Failed to process captured photo.",
          role: .system,
          timestamp: Date()
        )
      )
      try? modelContext.save()
      return
    }

    let fileName = "Camera-\(Int(Date().timeIntervalSince1970)).jpg"
    pendingImageAttachment = PendingImageAttachment(
      data: jpegData,
      fileName: fileName,
      mimeType: "image/jpeg",
      attachmentType: "image",
      image: image
    )
  }

  @MainActor
  private func handleSelectedMedia(_ item: PhotosPickerItem) async {
    do {
      guard let mediaData = try await item.loadTransferable(type: Data.self) else { return }
      let contentType = item.supportedContentTypes.first
      let isVideo = contentType?.conforms(to: .movie) == true
      let attachmentType = isVideo ? "video" : "image"
      let mimeType = contentType?.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
      let fileExtension = contentType?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")
      let fileNamePrefix = isVideo ? "Video" : "Image"
      let fileName = "\(fileNamePrefix)-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"

      if !isVideo, let image = UIImage(data: mediaData) {
        pendingImageAttachment = PendingImageAttachment(
          data: mediaData,
          fileName: fileName,
          mimeType: mimeType,
          attachmentType: attachmentType,
          image: image
        )
        selectedPhotoItem = nil
        return
      }

      await sendAttachment(
        data: mediaData,
        fileName: fileName,
        mimeType: mimeType,
        attachmentType: attachmentType,
        attachmentTitle: nil,
        attachmentDescription: nil
      )
    } catch {
      conversation.messages.append(
        Message(
          content: "Failed to load selected media: \(error.localizedDescription)",
          role: .system,
          timestamp: Date()
        )
      )
      try? modelContext.save()
    }

    selectedPhotoItem = nil
  }

  @MainActor
  private func handleImportedFile(_ result: Result<[URL], any Error>) async {
    do {
      let urls = try result.get()
      for fileURL in Array(urls.prefix(5)) {
        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
          if hasAccess {
            fileURL.stopAccessingSecurityScopedResource()
          }
        }

        let fileData = try Data(contentsOf: fileURL)
        guard fileData.count <= 15 * 1024 * 1024 else {
          conversation.messages.append(
            Message(
              content: "\(fileURL.lastPathComponent) is larger than 15 MB.",
              role: .system,
              timestamp: Date()
            )
          )
          continue
        }
        let mimeType =
          UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
          ?? "application/octet-stream"
        let attachmentType: String
        if mimeType.hasPrefix("image/") {
          attachmentType = "image"
        } else if mimeType.hasPrefix("video/") {
          attachmentType = "video"
        } else {
          attachmentType = "file"
        }

        if urls.count == 1, attachmentType == "image", let image = UIImage(data: fileData) {
          pendingImageAttachment = PendingImageAttachment(
            data: fileData,
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType,
            attachmentType: attachmentType,
            image: image
          )
          return
        }

        await sendAttachment(
          data: fileData,
          fileName: fileURL.lastPathComponent,
          mimeType: mimeType,
          attachmentType: attachmentType,
          attachmentTitle: attachmentType == "file" ? fileURL.lastPathComponent : nil,
          attachmentDescription: nil
        )
      }
    } catch {
      conversation.messages.append(
        Message(
          content: "Failed to import file: \(error.localizedDescription)",
          role: .system,
          timestamp: Date()
        )
      )
      try? modelContext.save()
    }
  }

  @MainActor
  private func startVoiceRecording() async {
    guard !isVoiceRecording else { return }

    let granted = await requestMicrophonePermission()
    guard granted else {
      conversation.messages.append(
        Message(
          content: "Microphone permission is required to record voice messages.",
          role: .system,
          timestamp: Date()
        )
      )
      try? modelContext.save()
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
      try session.setActive(true)

      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Voice-\(Int(Date().timeIntervalSince1970)).m4a")
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
      ]
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.record()
      voiceRecorder = recorder
      voiceRecordingURL = url
      isVoiceRecording = true
      isInputFocused = false
    } catch {
      conversation.messages.append(
        Message(
          content: "Failed to start voice recording: \(error.localizedDescription)",
          role: .system,
          timestamp: Date()
        )
      )
      try? modelContext.save()
    }
  }

  @MainActor
  private func finishVoiceRecordingAndSend() async {
    guard isVoiceRecording, let url = voiceRecordingURL else { return }
    voiceRecorder?.stop()
    voiceRecorder = nil
    voiceRecordingURL = nil
    isVoiceRecording = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

    do {
      let data = try Data(contentsOf: url)
      guard !data.isEmpty else { return }
      await sendAttachment(
        data: data,
        fileName: url.lastPathComponent,
        mimeType: "audio/m4a",
        attachmentType: "audio",
        attachmentTitle: "Voice message",
        attachmentDescription: nil
      )
      try? FileManager.default.removeItem(at: url)
    } catch {
      conversation.messages.append(
        Message(
          content: "Failed to send voice message: \(error.localizedDescription)",
          role: .system,
          timestamp: Date()
        )
      )
      try? modelContext.save()
    }
  }

  @MainActor
  private func cancelVoiceRecording() {
    voiceRecorder?.stop()
    voiceRecorder = nil
    let url = voiceRecordingURL
    voiceRecordingURL = nil
    isVoiceRecording = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    if let url {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
  }

  @MainActor
  private func sendAttachment(
    data: Data,
    fileName: String,
    mimeType: String,
    attachmentType: String,
    attachmentTitle: String?,
    attachmentDescription: String?,
    caption: String = ""
  ) async {
    guard let remoteConversationID = conversation.remoteConversationID else {
      conversation.messages.append(
        Message(
          content: "Unable to attach file before conversation is ready.",
          role: .system,
          timestamp: Date()
        )
      )
      try? modelContext.save()
      return
    }

    isGenerating = true
    let messageContent = caption.trimmingCharacters(in: .whitespacesAndNewlines)
    let localPlaceholderMessage = Message(
      content: messageContent.isEmpty ? "Uploading..." : messageContent,
      role: .user,
      timestamp: Date(),
      senderStackUserId: authStore.viewer?.subject,
      attachementType: attachmentType,
      attachementFileName: fileName,
      attachementMimeType: mimeType,
      attachementTitle: attachmentTitle,
      attachementDescription: attachmentDescription
    )
    conversation.messages.append(localPlaceholderMessage)
    try? modelContext.save()

    do {
      let uploadURL = try await authStore.generateAttachmentUploadURL()
      let storageId = try await authStore.uploadAttachmentData(
        data,
        uploadURL: uploadURL,
        mimeType: mimeType
      )
      let savedMessage = try await authStore.sendMessage(
        conversationID: remoteConversationID,
        role: .user,
        content: messageContent,
        attachmentType: attachmentType,
        attachmentStorageId: storageId,
        attachmentFileName: fileName,
        attachmentMimeType: mimeType,
        attachmentFileSize: data.count,
        attachmentTitle: attachmentTitle,
        attachmentDescription: attachmentDescription
      )
      sync(savedMessage: savedMessage, into: localPlaceholderMessage)
    } catch {
      conversation.messages.removeAll(where: { $0 === localPlaceholderMessage })
      conversation.messages.append(
        Message(
          content: "Failed to upload attachment: \(error.localizedDescription)",
          role: .system,
          timestamp: Date()
        )
      )
    }

    withAnimation {
      scrollPosition.scrollTo(edge: .bottom)
    }
    try? modelContext.save()
    isGenerating = false
  }

  @MainActor
  private func startConversationStatusSubscription() {
    guard let remoteConversationID = conversation.remoteConversationID else { return }

    conversationStatusSubscription?.cancel()
    do {
      conversationStatusSubscription = try authStore
        .subscribeConversations()
        .receive(on: DispatchQueue.main)
        .sink(
          receiveCompletion: { completion in
            guard case .failure = completion else { return }
            Task { @MainActor in
              try? await Task.sleep(for: .seconds(1))
              startConversationStatusSubscription()
            }
          },
          receiveValue: { remoteConversations in
            guard
              let remoteConversation = remoteConversations?.first(where: {
                $0.id == remoteConversationID
              })
            else { return }
            conversation.unreadCount = remoteConversation.unreadCountValue
            conversation.otherParticipantLastReadAt = remoteConversation.otherParticipantLastReadDate
            try? modelContext.save()
          }
        )
    } catch {
      conversationStatusSubscription = nil
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        startConversationStatusSubscription()
      }
    }
  }

  @MainActor
  private func startMessagesSubscription() {
    guard let remoteConversationID = conversation.remoteConversationID else { return }

    messagesSubscription?.cancel()
    do {
      messagesSubscription = try authStore
        .subscribeMessages(conversationID: remoteConversationID)
        .receive(on: DispatchQueue.main)
        .sink(
          receiveCompletion: { completion in
            guard case let .failure(error) = completion else { return }
            conversation.messages.append(
              Message(
                content: "Failed to load messages: \(error.localizedDescription)",
                role: .system,
                timestamp: Date()
              )
            )
            try? modelContext.save()
            Task { @MainActor in
              try? await Task.sleep(for: .seconds(1))
              startMessagesSubscription()
            }
          },
          receiveValue: { remoteMessages in
            let messages = remoteMessages ?? []
            applyRemoteMessages(messages)
            markConversationAsSeenIfNeeded(messages)
            try? modelContext.save()
          }
        )
    } catch {
      messagesSubscription = nil
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        startMessagesSubscription()
      }
    }
  }

  @MainActor
  private func startPolling() {
    guard let remoteConversationID = conversation.remoteConversationID else { return }
    pollingTask?.cancel()
    pollingTask = Task {
      // Wait for initial load to complete before polling
      try? await Task.sleep(for: .seconds(3))
      while !Task.isCancelled {
        do {
          let newMessages = try await authStore.pollMessages(conversationId: remoteConversationID, after: lastPollTimestamp)
          if !newMessages.isEmpty {
            applyRemoteMessages(newMessages)
            if let last = newMessages.last?._creationTime {
              lastPollTimestamp = last
            }
            try? modelContext.save()
          }
        } catch {
          // Ignore polling errors silently
        }
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  private func streamNewMessage() async {
    let userInput = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !userInput.isEmpty else { return }

    let parentMessage = replyTarget
    let parentMessageId = parentMessage?.remoteMessageID
    let parentPreview = parentMessage.map { replyPreviewText(for: $0) }
    let parentSenderName = parentMessage.map { replySenderName(for: $0) }

    let localUserMessage = Message(
      content: userInput,
      role: .user,
      timestamp: Date(),
      senderStackUserId: authStore.viewer?.subject,
      replyToRemoteMessageID: parentMessageId,
      replyPreviewText: parentPreview,
      replySenderName: parentSenderName
    )
    conversation.messages.append(localUserMessage)
    try? modelContext.save()
    newMessage = ""
    replyTarget = nil

    if let remoteConversationID = conversation.remoteConversationID {
      do {
        let savedMessage = try await authStore.sendMessage(
          conversationID: remoteConversationID,
          role: .user,
          content: userInput,
          parentMessageId: parentMessageId,
          mentionedStaffIds: mentionedStaffIds(in: userInput)
        )
        sync(savedMessage: savedMessage, into: localUserMessage)
      } catch {
        conversation.messages.removeAll(where: { $0 === localUserMessage })
        conversation.messages.append(
          Message(
            content: "Failed to send message: \(error.localizedDescription)",
            role: .system,
            timestamp: Date()
          )
        )
        try? modelContext.save()
        return
      }
    }

    withAnimation {
      scrollPosition.scrollTo(edge: .bottom)
    }
    try? modelContext.save()
  }

  private func applyRemoteMessages(_ remoteMessages: [ConvexChatMessage]) {
    var existingByRemoteID: [String: Message] = [:]
    for message in conversation.messages {
      if let remoteMessageID = message.remoteMessageID {
        existingByRemoteID[remoteMessageID] = message
      }
    }

    var ordered: [Message] = []
    for remoteMessage in remoteMessages.sorted(by: { $0.createdAt < $1.createdAt }) {
      if let localMessage = existingByRemoteID[remoteMessage.id] {
        apply(remoteMessage, to: localMessage)
        ordered.append(localMessage)
      } else {
        let parent = parentMessage(for: remoteMessage.parentMessageId)
        ordered.append(
          Message(
            content: remoteMessage.content,
            role: remoteMessage.role.appRole,
            timestamp: remoteMessage.timestamp,
            remoteMessageID: remoteMessage.id,
            senderStackUserId: remoteMessage.senderStackUserId,
            attachementType: remoteMessage.attachmentType,
            attachementFileName: remoteMessage.attachmentFileName,
            attachementMimeType: remoteMessage.attachmentMimeType,
            attachementTitle: remoteMessage.attachmentTitle,
            attachementDescription: remoteMessage.attachmentDescription,
            attachementThumbnail: remoteMessage.attachmentThumbnail,
            attachementURL: remoteMessage.attachmentUrl,
            replyToRemoteMessageID: remoteMessage.parentMessageId,
            replyPreviewText: parent.map { replyPreviewText(for: $0) },
            replySenderName: parent.map { replySenderName(for: $0) },
            reactionSummary: encodeReactions(remoteMessage.reactions ?? []),
            isDeleted: remoteMessage.isDeleted == true
          )
        )
        if let localMessage = ordered.last, remoteMessage.isDeleted == true {
          clearDeletedMessagePayload(localMessage)
        }
      }
    }

    let unsyncedMessages = conversation.messages.filter {
      $0.remoteMessageID == nil && $0.role == .user
    }
    conversation.messages = ordered + unsyncedMessages
  }

  private func sync(savedMessage: ConvexChatMessage, into localMessage: Message) {
    apply(savedMessage, to: localMessage)
  }

  private func apply(_ remoteMessage: ConvexChatMessage, to localMessage: Message) {
    let isDeleted = remoteMessage.isDeleted == true
    localMessage.remoteMessageID = remoteMessage.id
    localMessage.senderStackUserId = remoteMessage.senderStackUserId
    localMessage.role = remoteMessage.role.appRole
    localMessage.timestamp = remoteMessage.timestamp
    localMessage.isDeleted = isDeleted

    if isDeleted {
      clearDeletedMessagePayload(localMessage)
      return
    }

    localMessage.content = remoteMessage.content
    localMessage.attachementType = remoteMessage.attachmentType
    localMessage.attachementFileName = remoteMessage.attachmentFileName
    localMessage.attachementMimeType = remoteMessage.attachmentMimeType
    localMessage.attachementTitle = remoteMessage.attachmentTitle
    localMessage.attachementDescription = remoteMessage.attachmentDescription
    localMessage.attachementThumbnail = remoteMessage.attachmentThumbnail
    localMessage.attachementURL = remoteMessage.attachmentUrl
    localMessage.replyToRemoteMessageID = remoteMessage.parentMessageId
    localMessage.reactionSummary = encodeReactions(remoteMessage.reactions ?? [])
    if let parent = parentMessage(for: remoteMessage.parentMessageId) {
      localMessage.replyPreviewText = replyPreviewText(for: parent)
      localMessage.replySenderName = replySenderName(for: parent)
    } else {
      localMessage.replyPreviewText = nil
      localMessage.replySenderName = nil
    }
  }

  private func clearDeletedMessagePayload(_ message: Message) {
    message.content = "This message was deleted"
    message.attachementType = nil
    message.attachementFileName = nil
    message.attachementMimeType = nil
    message.attachementTitle = nil
    message.attachementDescription = nil
    message.attachementThumbnail = nil
    message.attachementURL = nil
    message.replyToRemoteMessageID = nil
    message.replyPreviewText = nil
    message.replySenderName = nil
    message.reactionSummary = nil
  }

  private func isOutgoingMessage(_ message: Message) -> Bool {
    guard let currentUserStackUserId = authStore.viewer?.subject else {
      return message.role == .user
    }
    return message.senderStackUserId == currentUserStackUserId
  }

  private func encodeReactions(_ reactions: [MessageReactionInfo]) -> String? {
    let normalized = reactions
      .filter { $0.count > 0 }
      .map { "\($0.emoji),\($0.count),\($0.hasReacted ? "1" : "0")" }
    return normalized.isEmpty ? nil : normalized.joined(separator: "|")
  }

  private func decodedReactions(from message: Message) -> [MessageReactionInfo] {
    guard let summary = message.reactionSummary, !summary.isEmpty else { return [] }
    return summary.split(separator: "|").compactMap { item in
      let parts = item.split(separator: ",", omittingEmptySubsequences: false)
      guard parts.count >= 3, let count = Int(parts[1]) else { return nil }
      return MessageReactionInfo(
        emoji: String(parts[0]),
        count: count,
        hasReacted: parts[2] == "1"
      )
    }
  }

  @MainActor
  private func toggleReaction(_ emoji: String, for message: Message) async {
    guard let remoteMessageID = message.remoteMessageID else { return }

    let previousSummary = message.reactionSummary
    let existing = decodedReactions(from: message)
    let hadReacted = existing.first(where: { $0.emoji == emoji })?.hasReacted == true
    message.reactionSummary = encodeReactions(upsertReaction(emoji, hadReacted: hadReacted, in: existing))
    try? modelContext.save()

    do {
      _ = try await authStore.toggleMessageReaction(
        messageId: remoteMessageID,
        messageSource: "message",
        emoji: emoji
      )
      let reactions = try await authStore.fetchMessageReactions(
        messageId: remoteMessageID,
        messageSource: "message"
      )
      message.reactionSummary = encodeReactions(reactions)
      try? modelContext.save()
    } catch {
      message.reactionSummary = previousSummary
      try? modelContext.save()
    }
  }

  private func upsertReaction(
    _ emoji: String,
    hadReacted: Bool,
    in reactions: [MessageReactionInfo]
  ) -> [MessageReactionInfo] {
    var updated = reactions
    if let index = updated.firstIndex(where: { $0.emoji == emoji }) {
      let old = updated[index]
      let nextCount = max(0, old.count + (hadReacted ? -1 : 1))
      if nextCount == 0 {
        updated.remove(at: index)
      } else {
        updated[index] = MessageReactionInfo(
          emoji: emoji,
          count: nextCount,
          hasReacted: !hadReacted
        )
      }
    } else {
      updated.append(MessageReactionInfo(emoji: emoji, count: 1, hasReacted: true))
    }
    return updated
  }

  @MainActor
  private func deleteMessage(_ message: Message) async {
    guard !message.isDeleted else { return }

    guard let remoteMessageID = message.remoteMessageID else {
      conversation.messages.removeAll { $0 === message }
      try? modelContext.save()
      return
    }

    let previousContent = message.content
    let previousAttachmentType = message.attachementType
    let previousAttachmentFileName = message.attachementFileName
    let previousAttachmentMimeType = message.attachementMimeType
    let previousAttachmentTitle = message.attachementTitle
    let previousAttachmentDescription = message.attachementDescription
    let previousAttachmentThumbnail = message.attachementThumbnail
    let previousAttachmentURL = message.attachementURL
    let previousReplyToRemoteMessageID = message.replyToRemoteMessageID
    let previousReplyPreviewText = message.replyPreviewText
    let previousReplySenderName = message.replySenderName
    let previousReactionSummary = message.reactionSummary

    message.isDeleted = true
    clearDeletedMessagePayload(message)
    try? modelContext.save()

    do {
      try await authStore.deleteMessage(messageId: remoteMessageID)
    } catch {
      message.isDeleted = false
      message.content = previousContent
      message.attachementType = previousAttachmentType
      message.attachementFileName = previousAttachmentFileName
      message.attachementMimeType = previousAttachmentMimeType
      message.attachementTitle = previousAttachmentTitle
      message.attachementDescription = previousAttachmentDescription
      message.attachementThumbnail = previousAttachmentThumbnail
      message.attachementURL = previousAttachmentURL
      message.replyToRemoteMessageID = previousReplyToRemoteMessageID
      message.replyPreviewText = previousReplyPreviewText
      message.replySenderName = previousReplySenderName
      message.reactionSummary = previousReactionSummary
      try? modelContext.save()
    }
  }

  @MainActor
  private func scrollToRepliedMessage(from message: Message) {
    guard
      let parent = parentMessage(for: message.replyToRemoteMessageID),
      let parentRemoteMessageID = parent.remoteMessageID
    else { return }

    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
      scrollPosition.scrollTo(id: parent.id, anchor: .center)
      highlightedRemoteMessageID = parentRemoteMessageID
    }

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.4))
      if highlightedRemoteMessageID == parentRemoteMessageID {
        withAnimation(.easeOut(duration: 0.25)) {
          highlightedRemoteMessageID = nil
        }
      }
    }
  }

  @MainActor
  private func highlightAndScroll(to remoteMessageID: String) {
    guard let target = conversation.messages.first(where: { $0.remoteMessageID == remoteMessageID }) else {
      highlightedRemoteMessageID = remoteMessageID
      return
    }

    highlightedRemoteMessageID = remoteMessageID
    withAnimation(.snappy) {
      scrollPosition.scrollTo(id: target.id, anchor: .center)
    }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      if highlightedRemoteMessageID == remoteMessageID {
        highlightedRemoteMessageID = nil
      }
    }
  }

  private func parentMessage(for remoteMessageID: String?) -> Message? {
    guard let remoteMessageID else { return nil }
    return conversation.messages.first { $0.remoteMessageID == remoteMessageID }
  }

  private func replySenderName(for message: Message) -> String {
    if let currentUser = authStore.viewer?.subject {
      return message.senderStackUserId == currentUser ? "You" : conversationTitle
    }
    if message.role == .user {
      return "You"
    }
    return conversationTitle
  }

  private func replyPreviewText(for message: Message) -> String {
    let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty { return text }
    if message.attachementMimeType?.hasPrefix("image/") == true || message.attachementType == "image" {
      return "Photo"
    }
    if let fileName = message.attachementFileName, !fileName.isEmpty {
      return fileName
    }
    return "Attachment"
  }

  @MainActor
  private func markConversationAsSeenIfNeeded(_ remoteMessages: [ConvexChatMessage]) {
    guard
      let remoteConversationID = conversation.remoteConversationID,
      let currentUserStackUserId = authStore.viewer?.subject
    else { return }

    let latestIncomingDate = remoteMessages
      .filter { $0.senderStackUserId != currentUserStackUserId }
      .map(\.timestamp)
      .max()

    guard let latestIncomingDate else { return }
    if let lastMarkedSeenAt, latestIncomingDate <= lastMarkedSeenAt {
      return
    }

    conversation.unreadCount = 0
    lastMarkedSeenAt = latestIncomingDate

    Task {
      do {
        try await authStore.markConversationSeen(
          conversationID: remoteConversationID,
          readAt: latestIncomingDate
        )
      } catch {
        // Keep UI responsive; next subscription update will retry.
      }
    }
  }
}

private struct ChatCameraPicker: UIViewControllerRepresentable {
  @Binding var image: UIImage?
  @Environment(\.dismiss) private var dismiss

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.delegate = context.coordinator
    picker.allowsEditing = false
    picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    picker.cameraCaptureMode = .photo
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    private let parent: ChatCameraPicker

    init(_ parent: ChatCameraPicker) {
      self.parent = parent
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
      if let selectedImage = info[.originalImage] as? UIImage {
        parent.image = selectedImage
      }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}

private struct ChatWallpaper: View {
  private let symbolColor = Color(red: 0.73, green: 0.70, blue: 0.69).opacity(0.22)

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.97, green: 0.97, blue: 0.99),
          Color(red: 0.93, green: 0.94, blue: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      GeometryReader { proxy in
        let columns = stride(from: 24.0, through: proxy.size.width, by: 86.0).map { $0 }
        let rows = stride(from: 12.0, through: proxy.size.height, by: 92.0).map { $0 }

        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, y in
          ForEach(Array(columns.enumerated()), id: \.offset) { columnIndex, x in
            WallpaperSymbol(
              name: wallpaperSymbol(for: rowIndex + columnIndex),
              size: symbolSize(row: rowIndex, column: columnIndex),
              angle: symbolAngle(row: rowIndex, column: columnIndex),
              color: symbolColor,
              x: x,
              y: y
            )
          }
        }
      }
    }
  }

  private func wallpaperSymbol(for index: Int) -> String {
    let symbols = [
      "house",
      "key",
      "building.2",
      "doc",
      "message",
      "cloud",
      "mappin.and.ellipse"
    ]
    return symbols[index % symbols.count]
  }

  private func symbolSize(row: Int, column: Int) -> CGFloat {
    CGFloat(18 + ((row + column) % 3) * 6)
  }

  private func symbolAngle(row: Int, column: Int) -> Double {
    Double((row * 17 + column * 11) % 24) - 12
  }
}

private struct WallpaperSymbol: View {
  let name: String
  let size: CGFloat
  let angle: Double
  let color: Color
  let x: Double
  let y: Double

  var body: some View {
    Image(systemName: name)
      .font(.system(size: size, weight: .regular))
      .foregroundStyle(color)
      .rotationEffect(.degrees(angle))
      .position(x: x, y: y)
  }
}

#Preview {
  @Previewable var conversation: Conversation = .init(
    messages: [
      .init(
        content: "Hello world",
        role: .user,
        timestamp: Date()),
      .init(
        content: "How may I asist you today?",
        role: .assistant,
        timestamp: Date())
    ],
    summary: "A preview conversation")
  ConversationDetailView(conversation: conversation)
}
