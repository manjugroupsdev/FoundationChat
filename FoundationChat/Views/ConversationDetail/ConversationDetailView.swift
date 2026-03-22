import Combine
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ConversationDetailView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(AuthStore.self) private var authStore

  @State var newMessage: String = ""
  @State var conversation: Conversation
  @State var scrollPosition: ScrollPosition = .init()
  @State var isGenerating: Bool = false
  @State private var messagesSubscription: AnyCancellable?
  @State private var conversationStatusSubscription: AnyCancellable?
  @State private var lastMarkedSeenAt: Date?
  @State private var isAttachmentOptionsPresented = false
  @State private var isPhotoPickerPresented = false
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var isFileImporterPresented = false
  @FocusState var isInputFocused: Bool

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

    return VStack(spacing: 0) {
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(Array(sortedMessages.enumerated()), id: \.element.id) { index, message in
            if shouldShowTimestamp(at: index, in: sortedMessages) {
              MessageTimestampDivider(date: message.timestamp)
                .padding(.top, index == 0 ? 8 : 12)
            }

            MessageView(
              message: message,
              otherParticipantLastReadAt: conversation.otherParticipantLastReadAt,
              isLastOutgoingMessage: message === lastOutgoingMessage
            )
            .id(message.id)
          }
        }
        .scrollTargetLayout()
        .padding(.bottom, 50)
      }
      .scrollIndicators(.hidden)
    }
    .background(Color(uiColor: .systemBackground))
    .onAppear {
      isInputFocused = true
      startMessagesSubscription()
      startConversationStatusSubscription()
      withAnimation {
        scrollPosition.scrollTo(edge: .bottom)
      }
    }
    .onDisappear {
      messagesSubscription?.cancel()
      messagesSubscription = nil
      conversationStatusSubscription?.cancel()
      conversationStatusSubscription = nil
    }
    .onChange(of: conversation.remoteConversationID) { _, _ in
      lastMarkedSeenAt = nil
      startMessagesSubscription()
      startConversationStatusSubscription()
    }
    .scrollDismissesKeyboard(.interactively)
    .scrollPosition($scrollPosition, anchor: .bottom)
    .navigationTitle(conversationTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ConversationDetailInputView(
        newMessage: $newMessage,
        isGenerating: $isGenerating,
        isInputFocused: $isInputFocused,
        onAddAttachment: {
          guard !isGenerating else { return }
          isInputFocused = false
          isAttachmentOptionsPresented = true
        },
        onSend: {
          isGenerating = true
          await streamNewMessage()
          isGenerating = false
        }
      )
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
      .presentationDetents([.fraction(0.5), .large])
      .presentationDragIndicator(.visible)
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
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.item],
      allowsMultipleSelection: false
    ) { result in
      Task {
        await handleImportedFile(result)
      }
    }
    .toolbar(.hidden, for: .tabBar)
  }

  private func shouldShowTimestamp(at index: Int, in messages: [Message]) -> Bool {
    guard messages.indices.contains(index) else { return false }
    if index == 0 { return true }

    let previousTimestamp = messages[index - 1].timestamp
    let currentTimestamp = messages[index].timestamp
    return currentTimestamp.timeIntervalSince(previousTimestamp) > 30 * 60
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
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
  }
}

private struct AttachmentOptionsSheet: View {
  let onPhotos: () -> Void
  let onFiles: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    NavigationStack {
      List {
        Button(action: onPhotos) {
          AttachmentOptionRow(
            icon: "photo.on.rectangle.angled",
            tint: .blue,
            title: "Photos"
          )
        }
        .buttonStyle(.plain)

        Button(action: onFiles) {
          AttachmentOptionRow(
            icon: "doc",
            tint: .orange,
            title: "Files"
          )
        }
        .buttonStyle(.plain)
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Attachments")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done", action: onDismiss)
        }
      }
    }
  }
}

private struct AttachmentOptionRow: View {
  let icon: String
  let tint: Color
  let title: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(tint, in: Circle())

      Text(title)
        .font(.title3)
        .foregroundStyle(.primary)

      Spacer()
    }
    .padding(.vertical, 4)
  }
}

extension ConversationDetailView {
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
      guard let fileURL = urls.first else { return }

      let hasAccess = fileURL.startAccessingSecurityScopedResource()
      defer {
        if hasAccess {
          fileURL.stopAccessingSecurityScopedResource()
        }
      }

      let fileData = try Data(contentsOf: fileURL)
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

      await sendAttachment(
        data: fileData,
        fileName: fileURL.lastPathComponent,
        mimeType: mimeType,
        attachmentType: attachmentType,
        attachmentTitle: attachmentType == "file" ? fileURL.lastPathComponent : nil,
        attachmentDescription: nil
      )
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
  private func sendAttachment(
    data: Data,
    fileName: String,
    mimeType: String,
    attachmentType: String,
    attachmentTitle: String?,
    attachmentDescription: String?
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
    let localPlaceholderMessage = Message(
      content: "Uploading...",
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
        content: "",
        attachmentType: attachmentType,
        attachmentStorageId: storageId,
        attachmentFileName: fileName,
        attachmentMimeType: mimeType,
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

  private func streamNewMessage() async {
    let userInput = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !userInput.isEmpty else { return }

    let localUserMessage = Message(
      content: userInput,
      role: .user,
      timestamp: Date(),
      senderStackUserId: authStore.viewer?.subject
    )
    conversation.messages.append(localUserMessage)
    try? modelContext.save()
    newMessage = ""

    if let remoteConversationID = conversation.remoteConversationID {
      do {
        let savedMessage = try await authStore.sendMessage(
          conversationID: remoteConversationID,
          role: .user,
          content: userInput
        )
        sync(savedMessage: savedMessage, into: localUserMessage)
      } catch {
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
        localMessage.content = remoteMessage.content
        localMessage.senderStackUserId = remoteMessage.senderStackUserId
        localMessage.role = remoteMessage.role.appRole
        localMessage.timestamp = remoteMessage.timestamp
        localMessage.attachementType = remoteMessage.attachmentType
        localMessage.attachementFileName = remoteMessage.attachmentFileName
        localMessage.attachementMimeType = remoteMessage.attachmentMimeType
        localMessage.attachementTitle = remoteMessage.attachmentTitle
        localMessage.attachementDescription = remoteMessage.attachmentDescription
        localMessage.attachementThumbnail = remoteMessage.attachmentThumbnail
        localMessage.attachementURL = remoteMessage.attachmentUrl
        ordered.append(localMessage)
      } else {
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
            attachementURL: remoteMessage.attachmentUrl
          )
        )
      }
    }

    let unsyncedMessages = conversation.messages.filter { $0.remoteMessageID == nil }
    conversation.messages = ordered + unsyncedMessages
  }

  private func sync(savedMessage: ConvexChatMessage, into localMessage: Message) {
    localMessage.remoteMessageID = savedMessage.id
    localMessage.senderStackUserId = savedMessage.senderStackUserId
    localMessage.timestamp = savedMessage.timestamp
    localMessage.content = savedMessage.content
    localMessage.role = savedMessage.role.appRole
    localMessage.attachementType = savedMessage.attachmentType
    localMessage.attachementFileName = savedMessage.attachmentFileName
    localMessage.attachementMimeType = savedMessage.attachmentMimeType
    localMessage.attachementTitle = savedMessage.attachmentTitle
    localMessage.attachementDescription = savedMessage.attachmentDescription
    localMessage.attachementThumbnail = savedMessage.attachmentThumbnail
    localMessage.attachementURL = savedMessage.attachmentUrl
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
