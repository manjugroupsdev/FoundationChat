import Combine
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
        conversationHeader

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
                isLastOutgoingMessage: message === lastOutgoingMessage
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
    .scrollDismissesKeyboard(.interactively)
    .scrollPosition($scrollPosition, anchor: .bottom)
    .safeAreaInset(edge: .bottom, spacing: 0) {
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
      .presentationDetents([.fraction(0.5), .large])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $isCameraPresented) {
      ChatCameraPicker(image: $capturedCameraImage)
        .ignoresSafeArea()
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
      allowsMultipleSelection: false
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
          ConversationSearchView(conversationID: remoteID, title: conversationTitle)
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

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: onFiles) {
        AttachmentOptionRow(
          icon: "doc",
          tint: Color(red: 0.04, green: 0.42, blue: 1.0),
          title: "Attach a file"
        )
      }
      .buttonStyle(.plain)

      Button(action: onPhotos) {
          AttachmentOptionRow(
            icon: "photo",
            tint: Color(red: 0.67, green: 0.23, blue: 1.0),
            title: "Photos or videos"
          )
      }
      .buttonStyle(.plain)

      Button(action: onCamera) {
        AttachmentOptionRow(
          icon: "camera",
          tint: Color(red: 0.0, green: 0.72, blue: 0.47),
          title: "Camera"
        )
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .shadow(color: .black.opacity(0.24), radius: 24, y: 8)
    .padding(.horizontal, 24)
    .padding(.bottom, 16)
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
    await sendAttachment(
      data: jpegData,
      fileName: fileName,
      mimeType: "image/jpeg",
      attachmentType: "image",
      attachmentTitle: nil,
      attachmentDescription: nil
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

    let unsyncedMessages = conversation.messages.filter {
      $0.remoteMessageID == nil && $0.role == .user
    }
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
