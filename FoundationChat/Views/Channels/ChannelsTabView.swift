import Combine
import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChannelsTabView: View {
  private enum ChannelFilter: String, CaseIterable, Identifiable {
    case all
    case created
    case manageable

    var id: String { rawValue }

    var title: String {
      switch self {
      case .all:
        return "All"
      case .created:
        return "Created"
      case .manageable:
        return "Manage"
      }
    }
  }

  @Environment(AuthStore.self) private var authStore

  let openChannelID: String?
  let onOpenChannelHandled: () -> Void

  @State private var channels: [ChannelSummary] = []
  @State private var navigationPath: [String] = []
  @State private var searchText = ""
  @State private var selectedFilter: ChannelFilter = .all
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var isCreateSheetPresented = false

  private var visibleChannels: [ChannelSummary] {
    let sorted = channels.sorted { $0.lastMessageAt > $1.lastMessageAt }

    switch selectedFilter {
    case .all:
      return sorted
    case .created:
      guard let currentUser = authStore.viewer?.subject else { return [] }
      return sorted.filter { $0.createdByStackUserId == currentUser }
    case .manageable:
      return sorted.filter(\.canManage)
    }
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      VStack(spacing: 10) {
        GlassSearchField(placeholder: "Search channels", text: $searchText)
          .padding(.horizontal, 16)
          .padding(.top, 8)

        filtersBar
          .padding(.horizontal, 16)

        if isLoading, channels.isEmpty {
          ProgressView("Loading channels...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
          ContentUnavailableView(
            "Could Not Load Channels",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleChannels.isEmpty {
          ContentUnavailableView(
            "No channels yet",
            systemImage: "person.3"
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(visibleChannels) { channel in
            NavigationLink(value: channel.id) {
              VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                  .font(.body.weight(.semibold))

                if let description = channel.description, !description.isEmpty {
                  Text(channel.lastMessageContent ?? description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                } else if let lastMessageContent = channel.lastMessageContent,
                  !lastMessageContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                  Text(lastMessageContent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                } else {
                  Text("No messages yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .padding(.vertical, 4)
            }
          }
          .listStyle(.plain)
        }
      }
      .navigationDestination(for: String.self) { channelID in
        ChannelChatView(channel: channelSummary(for: channelID))
      }
      .navigationTitle("Channels")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if authStore.isAdmin {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button {
              isCreateSheetPresented = true
            } label: {
              Image(systemName: "plus")
            }
          }
        }
      }
      .sheet(isPresented: $isCreateSheetPresented) {
        CreateChannelSheet {
          await loadChannels()
        }
      }
      .task(id: "\(searchText)-\(selectedFilter.rawValue)") {
        await loadChannels()
      }
      .task(id: openChannelID) {
        guard let openChannelID else { return }
        await openChannelFromPush(channelID: openChannelID)
        onOpenChannelHandled()
      }
    }
  }

  private var filtersBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(ChannelFilter.allCases) { filter in
          Button {
            selectedFilter = filter
          } label: {
            Text(filter.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(selectedFilter == filter ? .white : .primary)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(
                selectedFilter == filter
                  ? Color.blue
                  : Color(.systemGray5),
                in: Capsule()
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @MainActor
  private func loadChannels() async {
    isLoading = true
    errorMessage = nil

    do {
      channels = try await authStore.fetchChannels(search: searchText)
    } catch {
      channels = []
      errorMessage = error.localizedDescription
    }

    isLoading = false
  }

  private func channelSummary(for channelID: String) -> ChannelSummary {
    if let existing = channels.first(where: { $0.id == channelID }) {
      return existing
    }
    return ChannelSummary(
      _id: channelID,
      name: "Channel",
      slug: nil,
      description: nil,
      type: "public",
      createdBy: nil,
      isArchived: false,
      memberCount: 0,
      role: "member",
      muted: false,
      unreadCount: 0
    )
  }

  @MainActor
  private func openChannelFromPush(channelID: String) async {
    selectedFilter = .all
    if channels.first(where: { $0.id == channelID }) == nil {
      await loadChannels()
    }
    navigationPath = [channelID]
  }
}

struct ChannelChatView: View {
  @Environment(AuthStore.self) private var authStore
  let channel: ChannelSummary

  @State private var newMessage = ""
  @State private var messages: [ChannelChatMessage] = []
  @State private var errorMessage: String?
  @State private var isInviteSheetPresented = false
  @State private var isSendingMessage = false
  @State private var isEmojiPanelVisible = false
  @State private var pendingVoicePreviewURL: URL?
  @State private var pendingVoicePreviewDuration: TimeInterval?
  @State private var isAttachmentOptionsPresented = false
  @State private var isPhotoPickerPresented = false
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var isCameraPresented = false
  @State private var capturedCameraImage: UIImage?
  @State private var isFileImporterPresented = false
  @State private var voiceRecorder: AVAudioRecorder?
  @State private var voiceRecordingURL: URL?
  @State private var isVoiceRecording = false
  @State private var voiceRecordingElapsed: TimeInterval = 0
  @State private var voiceRecordingTimerTask: Task<Void, Never>?
  @State private var voiceTypingTask: Task<Void, Never>?
  @State private var lastTypingSignalAt: Date?
  @State private var mentionUsers: [DirectoryUser] = []
  @State private var mentionSearchTask: Task<Void, Never>?
  @State private var messagesSubscription: AnyCancellable?
  @State private var pollingTask: Task<Void, Never>?
  @State private var lastPollTimestamp: Double = 0
  @FocusState private var isInputFocused: Bool

  var body: some View {
    let currentUserStackUserId = authStore.viewer?.subject

    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 8) {
          if messages.isEmpty {
            ContentUnavailableView(
              "No messages yet",
              systemImage: "message",
              description: Text("Start the conversation in #\(channel.name).")
            )
            .padding(.top, 40)
          } else {
            ForEach(messages) { message in
              ChannelMessageRow(
                message: message,
                isMine: message.senderStackUserId == currentUserStackUserId
              )
              .id(message.id)
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 56)
      }
      .onChange(of: messages.map(\.id)) { _, messageIDs in
        guard let lastID = messageIDs.last else { return }
        withAnimation(.snappy) {
          proxy.scrollTo(lastID, anchor: .bottom)
        }
      }
    }
    .navigationTitle("#\(channel.name)")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if authStore.isAdmin {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            isInviteSheetPresented = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        if let mentionQuery = activeMentionQuery {
          MentionSuggestionsView(users: mentionSuggestions(for: mentionQuery), onSelect: insertMention)
        }

        ConversationDetailInputView(
          newMessage: $newMessage,
          isGenerating: $isSendingMessage,
          pendingVoicePreviewURL: $pendingVoicePreviewURL,
          isInputFocused: $isInputFocused,
          isVoiceRecording: isVoiceRecording,
          voiceRecordingElapsed: voiceRecordingElapsed,
          isEmojiPanelVisible: $isEmojiPanelVisible,
          onAddAttachment: {
            guard !isSendingMessage else { return }
            isInputFocused = false
            isEmojiPanelVisible = false
            isAttachmentOptionsPresented = true
          },
          onVoiceTap: {
            Task {
              await startVoiceRecording()
            }
          },
          onVoiceRelease: {
            Task {
              await finishVoiceRecordingForPreview()
            }
          },
          onCancelVoiceRecording: {
            cancelVoiceRecording()
          },
          onSendVoicePreview: {
            await sendVoicePreview()
          },
          onDiscardVoicePreview: {
            discardVoicePreview()
          },
          pendingVoicePreviewDuration: pendingVoicePreviewDuration,
          onSend: {
            await sendMessage()
          }
        )
      }
    }
    .overlay(alignment: .top) {
      if let errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule())
          .padding(.top, 6)
      }
    }
    .sheet(isPresented: $isInviteSheetPresented) {
      InviteMemberSheet(channelID: channel.id) {
        startMessagesSubscription()
      }
    }
    .sheet(isPresented: $isAttachmentOptionsPresented) {
      ChannelAttachmentOptionsSheet(
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
        }
      )
      .presentationDetents([.height(250)])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $isCameraPresented) {
      ChannelCameraPicker(image: $capturedCameraImage)
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
      Task { await handleSelectedMedia(newValue) }
    }
    .onChange(of: capturedCameraImage) { _, newValue in
      guard let newValue else { return }
      Task { await handleCapturedCameraImage(newValue) }
    }
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) { result in
      Task { await handleImportedFile(result) }
    }
    .onAppear {
      startMessagesSubscription()
      startPolling()
      isInputFocused = true
    }
    .onChange(of: newMessage) { _, _ in
      scheduleMentionDirectoryLoad()
      sendTypingSignalIfNeeded()
    }
    .onDisappear {
      messagesSubscription?.cancel()
      messagesSubscription = nil
      pollingTask?.cancel()
      pollingTask = nil
      voiceTypingTask?.cancel()
      voiceTypingTask = nil
      cancelVoiceRecording()
      discardVoicePreview()
    }
    .toolbar(.hidden, for: .tabBar)
  }

  @MainActor
  private func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task {
      try? await Task.sleep(for: .seconds(3))
      while !Task.isCancelled {
        do {
          let newMessages = try await authStore.pollMessages(channelId: channel.id, after: lastPollTimestamp)
          if !newMessages.isEmpty {
            let mapped = newMessages.map(ChannelChatMessage.init)
            for msg in mapped where !messages.contains(where: { $0.id == msg.id }) {
              messages.append(msg)
            }
            messages.sort(by: { $0.createdAt < $1.createdAt })
            if let last = newMessages.last?._creationTime {
              lastPollTimestamp = last
            }
          }
        } catch {
          // Ignore polling errors
        }
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  @MainActor
  private func startMessagesSubscription() {
    messagesSubscription?.cancel()
    do {
      messagesSubscription = try authStore
        .subscribeChannelMessages(channelID: channel.id)
        .receive(on: DispatchQueue.main)
        .sink(
          receiveCompletion: { completion in
            guard case .failure = completion else { return }
            Task { @MainActor in
              try? await Task.sleep(for: .seconds(1))
              startMessagesSubscription()
            }
          },
          receiveValue: { remoteMessages in
            messages = (remoteMessages ?? []).sorted(by: { $0.createdAt < $1.createdAt })
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
  private func sendMessage() async {
    let trimmed = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    isSendingMessage = true
    errorMessage = nil
    defer { isSendingMessage = false }

    do {
      _ = try await authStore.sendChannelMessage(
        channelID: channel.id,
        content: trimmed,
        mentionedStaffIds: mentionedStaffIds(in: trimmed)
      )
      newMessage = ""
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func handleCapturedCameraImage(_ image: UIImage) async {
    defer { capturedCameraImage = nil }

    guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
      errorMessage = "Failed to process captured photo."
      return
    }

    await sendAttachment(
      data: jpegData,
      fileName: "Camera-\(Int(Date().timeIntervalSince1970)).jpg",
      mimeType: "image/jpeg",
      attachmentType: "image"
    )
  }

  @MainActor
  private func handleSelectedMedia(_ item: PhotosPickerItem) async {
    defer { selectedPhotoItem = nil }

    do {
      guard let mediaData = try await item.loadTransferable(type: Data.self) else { return }
      let contentType = item.supportedContentTypes.first
      let isVideo = contentType?.conforms(to: .movie) == true
      let mimeType = contentType?.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
      let fileExtension = contentType?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")
      let fileNamePrefix = isVideo ? "Video" : "Image"

      await sendAttachment(
        data: mediaData,
        fileName: "\(fileNamePrefix)-\(Int(Date().timeIntervalSince1970)).\(fileExtension)",
        mimeType: mimeType,
        attachmentType: isVideo ? "video" : "image"
      )
    } catch {
      errorMessage = "Failed to load selected media: \(error.localizedDescription)"
    }
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
          errorMessage = "\(fileURL.lastPathComponent) is larger than 15 MB."
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

        await sendAttachment(
          data: fileData,
          fileName: fileURL.lastPathComponent,
          mimeType: mimeType,
          attachmentType: attachmentType
        )
      }
    } catch {
      errorMessage = "Failed to import file: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func sendAttachment(
    data: Data,
    fileName: String,
    mimeType: String,
    attachmentType: String,
    caption: String = ""
  ) async {
    guard !data.isEmpty else { return }

    isSendingMessage = true
    errorMessage = nil
    defer { isSendingMessage = false }

    do {
      let uploadURL = try await authStore.generateAttachmentUploadURL()
      let storageId = try await authStore.uploadAttachmentData(
        data,
        uploadURL: uploadURL,
        mimeType: mimeType
      )
      let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
      let sentMessage = try await authStore.sendChannelMessage(
        channelID: channel.id,
        content: trimmedCaption,
        mentionedStaffIds: trimmedCaption.isEmpty ? nil : mentionedStaffIds(in: trimmedCaption),
        attachments: [[
          "storageId": storageId,
          "fileName": fileName,
          "fileType": mimeType,
          "fileSize": data.count
        ]]
      )
      appendOrReplace(sentMessage)
    } catch {
      errorMessage = "Failed to upload attachment: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func startVoiceRecording() async {
    guard !isVoiceRecording, pendingVoicePreviewURL == nil else { return }

    let granted = await requestMicrophonePermission()
    guard granted else {
      errorMessage = "Microphone permission is required to record voice messages."
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
      try session.setActive(true)

      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Channel-Voice-\(Int(Date().timeIntervalSince1970)).m4a")
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
      ]
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.prepareToRecord()
      recorder.record()
      voiceRecorder = recorder
      voiceRecordingURL = url
      isVoiceRecording = true
      errorMessage = nil
      startVoiceRecordingTimer()
      startVoiceTypingBroadcast()
      isInputFocused = false
    } catch {
      errorMessage = "Failed to start voice recording: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func finishVoiceRecordingForPreview() async {
    guard isVoiceRecording, let url = voiceRecordingURL else { return }
    voiceRecorder?.stop()
    voiceRecorder = nil
    voiceRecordingURL = nil
    isVoiceRecording = false
    stopVoiceRecordingTimer()
    stopVoiceTypingBroadcast()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let fileSize = attributes[.size] as? NSNumber
      guard fileSize?.intValue ?? 0 > 0 else {
        try? FileManager.default.removeItem(at: url)
        return
      }
      pendingVoicePreviewDuration = audioDuration(for: url)
      pendingVoicePreviewURL = url
    } catch {
      try? FileManager.default.removeItem(at: url)
    }
  }

  @MainActor
  private func sendVoicePreview() async {
    guard let url = pendingVoicePreviewURL else { return }
    pendingVoicePreviewURL = nil
    pendingVoicePreviewDuration = nil

    do {
      let data = try Data(contentsOf: url)
      await sendAttachment(
        data: data,
        fileName: url.lastPathComponent,
        mimeType: "audio/m4a",
        attachmentType: "audio"
      )
      try? FileManager.default.removeItem(at: url)
    } catch {
      errorMessage = "Failed to send voice message: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func discardVoicePreview() {
    let url = pendingVoicePreviewURL
    pendingVoicePreviewURL = nil
    pendingVoicePreviewDuration = nil
    if let url {
      try? FileManager.default.removeItem(at: url)
    }
  }

  @MainActor
  private func cancelVoiceRecording() {
    voiceRecorder?.stop()
    voiceRecorder = nil
    let url = voiceRecordingURL
    voiceRecordingURL = nil
    isVoiceRecording = false
    stopVoiceRecordingTimer()
    stopVoiceTypingBroadcast()
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
  private func startVoiceRecordingTimer() {
    voiceRecordingTimerTask?.cancel()
    voiceRecordingElapsed = 0
    let startDate = Date()
    voiceRecordingTimerTask = Task { @MainActor in
      while !Task.isCancelled {
        voiceRecordingElapsed = Date().timeIntervalSince(startDate)
        try? await Task.sleep(for: .milliseconds(200))
      }
    }
  }

  @MainActor
  private func stopVoiceRecordingTimer() {
    voiceRecordingTimerTask?.cancel()
    voiceRecordingTimerTask = nil
    voiceRecordingElapsed = 0
  }

  @MainActor
  private func startVoiceTypingBroadcast() {
    voiceTypingTask?.cancel()
    voiceTypingTask = Task { @MainActor in
      while !Task.isCancelled {
        do {
          try await authStore.setTypingIndicator(channelId: channel.id)
        } catch {
          // Typing status is best-effort while recording.
        }
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  @MainActor
  private func stopVoiceTypingBroadcast() {
    voiceTypingTask?.cancel()
    voiceTypingTask = nil
  }

  private func audioDuration(for url: URL) -> TimeInterval? {
    let asset = AVURLAsset(url: url)
    let seconds = CMTimeGetSeconds(asset.duration)
    guard seconds.isFinite, seconds > 0 else { return nil }
    return seconds
  }

  private func sendTypingSignalIfNeeded() {
    guard isInputFocused else { return }
    guard !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let now = Date()
    if let lastTypingSignalAt, now.timeIntervalSince(lastTypingSignalAt) < 2 {
      return
    }
    lastTypingSignalAt = now

    Task {
      try? await authStore.setTypingIndicator(channelId: channel.id)
    }
  }

  @MainActor
  private func appendOrReplace(_ message: ChannelChatMessage) {
    if let index = messages.firstIndex(where: { $0.id == message.id }) {
      messages[index] = message
    } else {
      messages.append(message)
    }
    messages.sort(by: { $0.createdAt < $1.createdAt })
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

private struct ChannelAttachmentOptionsSheet: View {
  let onPhotos: () -> Void
  let onCamera: () -> Void
  let onFiles: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      ChannelAttachmentOptionRow(
        icon: "photo.on.rectangle.angled",
        tint: Color(red: 0.66, green: 0.25, blue: 0.95),
        title: "Photos or videos",
        action: onPhotos
      )

      ChannelAttachmentOptionRow(
        icon: "camera.fill",
        tint: Color(red: 0.02, green: 0.70, blue: 0.48),
        title: "Camera",
        action: onCamera
      )

      ChannelAttachmentOptionRow(
        icon: "doc",
        tint: Color(red: 0.05, green: 0.45, blue: 1.0),
        title: "Attach a file",
        action: onFiles
      )
    }
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .top)
  }
}

private struct ChannelAttachmentOptionRow: View {
  let icon: String
  let tint: Color
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 18) {
        Image(systemName: icon)
          .font(.system(size: 25, weight: .regular))
          .foregroundStyle(tint)
          .frame(width: 46, height: 46)

        Text(title)
          .font(.system(size: 24, weight: .regular))
          .foregroundStyle(Color.black.opacity(0.92))

        Spacer()
      }
      .padding(.horizontal, 30)
      .frame(height: 72)
    }
    .buttonStyle(.plain)
  }
}

private struct ChannelCameraPicker: UIViewControllerRepresentable {
  @Binding var image: UIImage?
  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.delegate = context.coordinator
    picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    picker.allowsEditing = false
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let parent: ChannelCameraPicker

    init(parent: ChannelCameraPicker) {
      self.parent = parent
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      parent.image = info[.originalImage] as? UIImage
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}

private struct ChannelMessageRow: View {
  let message: ChannelChatMessage
  let isMine: Bool

  var body: some View {
    VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
      if !isMine {
        Text(message.senderName ?? "Unknown")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(message.content)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .foregroundStyle(isMine ? .white : .primary)
          .background(
            isMine ? Color.blue : Color(.systemGray5),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
      }

      if message.attachmentType != nil || message.attachmentFileName != nil {
        MessageAttachementView(message: attachmentMessage, isOutgoing: isMine)
          .frame(maxWidth: 260, alignment: isMine ? .trailing : .leading)
      }

      if let reactions = message.reactions?.filter({ $0.count > 0 }), !reactions.isEmpty {
        HStack(spacing: 3) {
          ForEach(reactions.prefix(3)) { reaction in
            Text(reaction.emoji)
              .font(.system(size: 12))
          }
          let total = reactions.reduce(0) { $0 + $1.count }
          if total > 1 {
            Text("\(total)")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.55))
          }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
      }

      Text(message.createdDate.formatted(date: .omitted, time: .shortened))
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    .padding(.vertical, 2)
  }

  private var attachmentMessage: Message {
    Message(
      content: "",
      role: isMine ? .user : .assistant,
      timestamp: message.createdDate,
      remoteMessageID: message.id,
      senderStackUserId: message.senderStackUserId,
      attachementType: message.attachmentType,
      attachementFileName: message.attachmentFileName,
      attachementMimeType: message.attachmentMimeType,
      attachementFileSize: message.attachmentFileSize,
      attachementURL: message.attachmentUrl,
      isDeleted: message.isDeleted == true
    )
  }
}

struct CreateChannelSheet: View {
  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let onCreated: () async -> Void

  @State private var name = ""
  @State private var description = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("New Channel") {
          TextField("Channel name", text: $name)
          TextField("Description (optional)", text: $description, axis: .vertical)
            .lineLimit(3, reservesSpace: true)
        }

        if let errorMessage {
          Section {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Create Channel")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isSubmitting ? "Creating..." : "Create") {
            Task {
              await create()
            }
          }
          .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  @MainActor
  private func create() async {
    isSubmitting = true
    errorMessage = nil
    defer { isSubmitting = false }

    do {
      _ = try await authStore.createChannel(name: name, description: description)
      await onCreated()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct InviteMemberSheet: View {
  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let channelID: String
  let onInvited: () async -> Void

  @State private var searchText = ""
  @State private var users: [DirectoryUser] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var invitingUserID: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField("Search users", text: $searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)

        if isLoading, users.isEmpty {
          ProgressView("Loading users...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
          ContentUnavailableView(
            "Could Not Load Users",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if users.isEmpty {
          ContentUnavailableView("No users found", systemImage: "person.2")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(users) { user in
            Button {
              Task { await invite(user) }
            } label: {
              HStack {
                Text(user.displayName)
                  .foregroundStyle(.primary)
                Spacer()
                if invitingUserID == user.id {
                  ProgressView()
                }
              }
            }
            .buttonStyle(.plain)
            .disabled(invitingUserID != nil)
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Invite Member")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            dismiss()
          }
        }
      }
      .task(id: searchText) {
        await loadUsers()
      }
    }
  }

  @MainActor
  private func loadUsers() async {
    isLoading = true
    errorMessage = nil
    do {
      users = try await authStore.fetchDirectoryUsers(search: searchText)
    } catch {
      users = []
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  @MainActor
  private func invite(_ user: DirectoryUser) async {
    invitingUserID = user.id
    errorMessage = nil
    defer { invitingUserID = nil }

    do {
      _ = try await authStore.inviteMember(
        channelID: channelID,
        memberStackUserID: user.stackUserId
      )
      await onInvited()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview {
  ChannelsTabView(openChannelID: nil, onOpenChannelHandled: {})
    .environment(AuthStore())
}
