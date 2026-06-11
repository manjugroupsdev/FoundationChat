import AVFoundation
import AVKit
import Combine
import QuickLook
import SwiftUI
import UIKit

struct MessageAttachementView: View {
  let message: Message
  let isOutgoing: Bool
  @State private var isPresentingFullscreenImage = false
  @State private var previewAttachment: NativeAttachmentPreview?

  private var isImageAttachment: Bool {
    attachmentHints.contains("image")
      || message.attachementMimeType?.lowercased().hasPrefix("image/") == true
      || Self.imageExtensions.contains(fileExtensionHint)
  }

  private var isVideoAttachment: Bool {
    !isAudioAttachment && (
      attachmentHints.contains("video")
      || message.attachementMimeType?.lowercased().hasPrefix("video/") == true
      || Self.videoExtensions.contains(fileExtensionHint)
    )
  }

  private var isAudioAttachment: Bool {
    attachmentHints.contains { hint in
      hint == "audio" || hint == "voice" || hint.hasPrefix("audio/") || hint.contains("audio")
    } || Self.audioExtensions.contains(fileExtensionHint)
  }

  private var attachmentHints: [String] {
    [
      message.attachementType,
      message.attachementMimeType,
      message.attachementFileName,
      message.attachementTitle,
    ]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    .filter { !$0.isEmpty }
  }

  private var fileExtensionHint: String {
    if let name = message.attachementFileName, !name.isEmpty {
      return URL(fileURLWithPath: name).pathExtension.lowercased()
    }
    if let url = attachmentURL, !url.pathExtension.isEmpty {
      return url.pathExtension.lowercased()
    }
    return ""
  }

  private var mediaURL: URL? {
    let raw = message.attachementThumbnail ?? message.attachementURL
    guard let raw else { return nil }
    return URL(string: raw)
  }

  private var attachmentURL: URL? {
    guard let raw = message.attachementURL else { return nil }
    return URL(string: raw)
  }

  private var displayFileName: String? {
    if let name = message.attachementFileName, !name.isEmpty {
      return name
    }
    if let title = message.attachementTitle, !title.isEmpty {
      return title
    }
    return nil
  }

  private var audioDurationHint: TimeInterval? {
    guard let description = message.attachementDescription else { return nil }
    let rawValue = description.replacingOccurrences(of: "duration:", with: "")
    guard let seconds = Double(rawValue), seconds.isFinite, seconds > 0 else { return nil }
    return seconds
  }

  private var isPendingUpload: Bool {
    message.role == .user
      && message.remoteMessageID == nil
      && (isImageAttachment || isVideoAttachment || isAudioAttachment)
  }

  var body: some View {
    if message.isDeleted {
      EmptyView()
    } else if isImageAttachment, let mediaURL {
      ChatImagePreview(url: mediaURL, isPendingUpload: isPendingUpload)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Color.primary.opacity(0.12), lineWidth: 1)
      )
      .contentShape(Rectangle())
      .onTapGesture {
        isPresentingFullscreenImage = true
      }
      .fullScreenCover(isPresented: $isPresentingFullscreenImage) {
        FullscreenImageViewer(imageURL: mediaURL)
      }
    } else if isAudioAttachment, let attachmentURL {
      AudioAttachmentPlaybackView(
        url: attachmentURL,
        title: displayFileName ?? "Voice message",
        isOutgoing: isOutgoing,
        durationOverride: audioDurationHint,
        isPendingUpload: isPendingUpload
      )
    } else if isVideoAttachment, let previewURL = mediaURL, let attachmentURL {
      VideoInlinePreview(previewURL: previewURL, videoURL: attachmentURL, isPendingUpload: isPendingUpload)
        .clipShape(.rect(cornerRadius: 16))
    } else if isVideoAttachment, let mediaURL {
      VideoInlinePreview(previewURL: mediaURL, videoURL: mediaURL, isPendingUpload: isPendingUpload)
        .clipShape(.rect(cornerRadius: 16))
    } else if let displayFileName {
      DocumentAttachmentCard(
        fileName: displayFileName,
        fileExtension: fileExtensionHint,
        mimeType: message.attachementMimeType,
        fileSize: attachmentFileSize,
        url: attachmentURL,
        isOutgoing: isOutgoing,
        onOpen: {
          if let attachmentURL {
            previewAttachment = NativeAttachmentPreview(url: attachmentURL, fileName: displayFileName)
          }
        }
      )
      .sheet(item: $previewAttachment) { item in
        NativeAttachmentPreviewSheet(item: item)
      }
    }
  }

  private var attachmentFileSize: Int? {
    if let size = message.attachementFileSize, size > 0 {
      return size
    }
    guard let attachmentURL, attachmentURL.isFileURL else { return nil }
    let values = try? attachmentURL.resourceValues(forKeys: [.fileSizeKey])
    return values?.fileSize
  }

  private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp"]
  private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "webm"]
  private static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "caf", "aiff", "aif", "mp4", "webm", "ogg", "opus"]
}

private struct NativeAttachmentPreview: Identifiable {
  let id = UUID()
  let url: URL
  let fileName: String?
}

private struct DocumentAttachmentCard: View {
  let fileName: String
  let fileExtension: String
  let mimeType: String?
  let fileSize: Int?
  let url: URL?
  let isOutgoing: Bool
  let onOpen: () -> Void

  private var documentKind: String {
    let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if !ext.isEmpty { return ext }
    if mimeType?.lowercased() == "application/pdf" { return "PDF" }
    return "FILE"
  }

  private var metadataText: String {
    if let fileSize, fileSize > 0 {
      return "\(documentKind) · \(Self.byteFormatter.string(fromByteCount: Int64(fileSize)))"
    }
    return documentKind
  }

  private var cardBackground: Color {
    isOutgoing ? Color(red: 0.02, green: 0.42, blue: 0.82) : .white
  }

  private var topPanelBackground: Color {
    isOutgoing ? .white.opacity(0.10) : Color.black.opacity(0.035)
  }

  private var dividerColor: Color {
    isOutgoing ? .white.opacity(0.20) : Color.black.opacity(0.10)
  }

  private var primaryText: Color {
    isOutgoing ? .white : Color.black.opacity(0.92)
  }

  private var secondaryText: Color {
    isOutgoing ? .white.opacity(0.72) : Color.black.opacity(0.56)
  }

  var body: some View {
    VStack(spacing: 0) {
      Button(action: onOpen) {
        HStack(spacing: 14) {
          ZStack {
            Circle()
              .fill(isOutgoing ? .white.opacity(0.22) : Color(red: 0.91, green: 0.94, blue: 0.98))
              .frame(width: 54, height: 54)

            RoundedRectangle(cornerRadius: 13, style: .continuous)
              .fill(isOutgoing ? .white.opacity(0.92) : Color(red: 0.87, green: 0.93, blue: 1.0))
              .frame(width: 41, height: 34)

            Text(documentKind)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(Color(red: 0.02, green: 0.42, blue: 0.82))
              .lineLimit(1)
              .minimumScaleFactor(0.68)
          }
          .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 4) {
            Text(fileName)
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(primaryText)
              .lineLimit(2)
              .multilineTextAlignment(.leading)

            Text(metadataText)
              .font(.system(size: 15, weight: .regular))
              .foregroundStyle(secondaryText)
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(topPanelBackground)

      Divider()
        .background(dividerColor)

      HStack(spacing: 0) {
        Button("Open", action: onOpen)
          .frame(maxWidth: .infinity)

        Rectangle()
          .fill(dividerColor)
          .frame(width: 1)

        if let url {
          ShareLink(item: url) {
            Text("Save as...")
              .frame(maxWidth: .infinity)
          }
        } else {
          Text("Save as...")
            .foregroundStyle(Color.black.opacity(0.28))
            .frame(maxWidth: .infinity)
        }
      }
      .font(.system(size: 17, weight: .regular))
      .foregroundStyle(primaryText)
      .frame(height: 46)
    }
    .frame(maxWidth: 286)
    .background(cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(isOutgoing ? .white.opacity(0.16) : Color.black.opacity(0.08), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.06), radius: 7, y: 2)
  }

  private static let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter
  }()
}

private struct NativeAttachmentPreviewSheet: View {
  let item: NativeAttachmentPreview

  @Environment(\.dismiss) private var dismiss
  @State private var localURL: URL?
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Group {
        if let localURL {
          NativeQuickLookController(url: localURL)
        } else if let errorMessage {
          ContentUnavailableView(
            "Cannot Preview",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
        } else {
          VStack(spacing: 12) {
            ProgressView()
            Text("Loading Preview")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color(.systemBackground))
        }
      }
      .navigationTitle(item.fileName ?? "Attachment")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: item.url) {
            Image(systemName: "square.and.arrow.up")
          }
        }
      }
    }
    .task(id: item.id) {
      await preparePreview()
    }
  }

  @MainActor
  private func preparePreview() async {
    errorMessage = nil
    localURL = nil

    if item.url.isFileURL {
      localURL = item.url
      return
    }

    do {
      let (downloadedURL, response) = try await URLSession.shared.download(from: item.url)
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent(previewFileName(response: response))

      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: downloadedURL, to: destination)
      localURL = destination
    } catch {
      if Task.isCancelled || (error as? URLError)?.code == .cancelled {
        return
      }
      errorMessage = error.localizedDescription
    }
  }

  private func previewFileName(response: URLResponse) -> String {
    let rawName = item.fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackName = item.url.lastPathComponent.isEmpty ? "Attachment" : item.url.lastPathComponent
    let name = (rawName?.isEmpty == false ? rawName : fallbackName) ?? "Attachment"

    if !URL(fileURLWithPath: name).pathExtension.isEmpty {
      return "\(UUID().uuidString)-\(name)"
    }

    let fallbackExtension = Self.fileExtension(for: response.mimeType)
    guard !fallbackExtension.isEmpty else {
      return "\(UUID().uuidString)-\(name)"
    }
    return "\(UUID().uuidString)-\(name).\(fallbackExtension)"
  }

  private static func fileExtension(for mimeType: String?) -> String {
    switch mimeType?.lowercased() {
    case "application/pdf":
      return "pdf"
    case "application/msword":
      return "doc"
    case "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
      return "docx"
    case "application/vnd.ms-excel":
      return "xls"
    case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
      return "xlsx"
    case "application/vnd.ms-powerpoint":
      return "ppt"
    case "application/vnd.openxmlformats-officedocument.presentationml.presentation":
      return "pptx"
    case "text/plain":
      return "txt"
    case "text/csv":
      return "csv"
    case "image/jpeg":
      return "jpg"
    case "image/png":
      return "png"
    case "audio/mp4", "audio/x-m4a", "audio/m4a":
      return "m4a"
    case "audio/mpeg", "audio/mp3":
      return "mp3"
    case "video/mp4":
      return "mp4"
    default:
      return ""
    }
  }
}

private struct NativeQuickLookController: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> QLPreviewController {
    let controller = QLPreviewController()
    controller.dataSource = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
    context.coordinator.url = url
    uiViewController.reloadData()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(url: url)
  }

  final class Coordinator: NSObject, QLPreviewControllerDataSource {
    var url: URL

    init(url: URL) {
      self.url = url
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
      1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
      url as NSURL
    }
  }
}

private struct ChatImagePreview: View {
  let url: URL
  let isPendingUpload: Bool
  @State private var image: UIImage?
  @State private var isLoading = false
  @State private var didFail = false

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 242, height: 220)
          .clipped()
      } else if isLoading {
        ZStack {
          Color.white.opacity(0.72)
          ProgressView()
        }
        .frame(width: 242, height: 180)
      } else {
        ZStack {
          Color.white.opacity(didFail ? 0.72 : 0.46)
          Image(systemName: "photo")
            .font(.system(size: 28, weight: .regular))
            .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .frame(width: 242, height: 180)
      }

      if isPendingUpload {
        AttachmentPendingOverlay()
      }
    }
    .task(id: url) {
      await loadImage()
    }
  }

  @MainActor
  private func loadImage() async {
    image = nil
    didFail = false
    isLoading = true
    defer { isLoading = false }

    if url.isFileURL {
      if let data = try? Data(contentsOf: url), let loadedImage = UIImage(data: data) {
        image = loadedImage
      } else {
        didFail = true
      }
      return
    }

    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      if let loadedImage = UIImage(data: data) {
        image = loadedImage
      } else {
        didFail = true
      }
    } catch {
      didFail = true
    }
  }
}

struct AudioAttachmentPlaybackView: View {
  let url: URL
  let title: String
  let isOutgoing: Bool
  let durationOverride: TimeInterval?
  let isPendingUpload: Bool

  @StateObject private var playbackController = VoicePlaybackController()

  init(
    url: URL,
    title: String,
    isOutgoing: Bool,
    durationOverride: TimeInterval? = nil,
    isPendingUpload: Bool = false
  ) {
    self.url = url
    self.title = title
    self.isOutgoing = isOutgoing
    self.durationOverride = durationOverride
    self.isPendingUpload = isPendingUpload
  }

  var body: some View {
    ZStack {
      HStack(spacing: 10) {
        Button {
          playbackController.toggle(url: url)
        } label: {
          Group {
            if playbackController.isLoading {
              ProgressView()
                .controlSize(.small)
                .tint(isOutgoing ? Color(red: 0.05, green: 0.38, blue: 0.79) : .white)
            } else {
              Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
            }
          }
            .foregroundStyle(isOutgoing ? Color(red: 0.05, green: 0.38, blue: 0.79) : .white)
            .frame(width: 34, height: 34)
            .background(isOutgoing ? .white : Color(red: 0.05, green: 0.38, blue: 0.79), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(playbackController.isLoading)

        HStack(spacing: 3) {
          ForEach(0..<24, id: \.self) { index in
            Capsule()
              .fill(
                (isOutgoing ? Color.white : Color.black)
                  .opacity(playbackController.progress >= Double(index + 1) / 24.0 ? 0.88 : (index % 3 == 0 ? 0.58 : 0.32))
              )
              .frame(width: 3, height: CGFloat([8, 15, 11, 20, 13, 17, 9, 14][index % 8]))
          }
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity, alignment: .leading)

        Text(playbackController.displayTimeLabel)
          .font(.system(size: 12, weight: .medium))
          .monospacedDigit()
          .foregroundStyle(isOutgoing ? .white.opacity(0.72) : Color.black.opacity(0.48))
      }

      if isPendingUpload {
        AttachmentPendingOverlay()
      }
    }
    .frame(width: 226)
    .task(id: url) {
      if let durationOverride {
        playbackController.setKnownDuration(durationOverride, for: url)
      } else {
        await playbackController.prepareDuration(url: url)
      }
    }
    .onDisappear {
      playbackController.stop()
    }
  }
}

@MainActor
private final class VoicePlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @Published var isPlaying = false
  @Published var isLoading = false
  @Published var progress: Double = 0
  @Published var currentTimeLabel = "0:00"
  @Published var durationLabel = "0:00"

  private var player: AVAudioPlayer?
  private var cachedURL: URL?
  private var playbackTask: Task<Void, Never>?
  private var durationTask: Task<Void, Never>?
  private var progressTask: Task<Void, Never>?

  var displayTimeLabel: String {
    isPlaying ? currentTimeLabel : durationLabel
  }

  func setKnownDuration(_ duration: TimeInterval, for url: URL) {
    guard duration.isFinite, duration > 0 else { return }
    durationLabel = format(duration)
    VoiceDurationCache.setDuration(duration, for: url)
  }

  func prepareDuration(url: URL) async {
    if let cachedDuration = VoiceDurationCache.duration(for: url) {
      setKnownDuration(cachedDuration, for: url)
      return
    }

    durationTask?.cancel()
    durationTask = Task { [weak self] in
      await self?.loadDuration(url: url)
    }
  }

  func toggle(url: URL) {
    if isPlaying {
      player?.pause()
      isPlaying = false
      stopProgressUpdates()
      return
    }

    if let player {
      player.play()
      isPlaying = true
      startProgressUpdates()
      return
    }

    playbackTask?.cancel()
    playbackTask = Task { [weak self] in
      await self?.prepareAndPlay(url: url)
    }
  }

  func stop() {
    playbackTask?.cancel()
    stopProgressUpdates()
    player?.stop()
    player = nil
    isPlaying = false
    isLoading = false
    progress = 0
    currentTimeLabel = "0:00"
  }

  private func prepareAndPlay(url: URL) async {
    isLoading = true
    defer { isLoading = false }

    do {
      let localURL = try await localPlayableURL(for: url)
      guard !Task.isCancelled else { return }

      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
      try session.setActive(true)

      let audioPlayer = try AVAudioPlayer(contentsOf: localURL)
      audioPlayer.delegate = self
      audioPlayer.volume = 1
      audioPlayer.prepareToPlay()
      player = audioPlayer
      setKnownDuration(audioPlayer.duration, for: url)
      audioPlayer.play()
      isPlaying = true
      updateProgress()
      startProgressUpdates()
    } catch {
      isPlaying = false
    }
  }

  private func startProgressUpdates() {
    progressTask?.cancel()
    progressTask = Task { [weak self] in
      while !Task.isCancelled {
        await MainActor.run {
          self?.updateProgress()
        }
        try? await Task.sleep(for: .milliseconds(120))
      }
    }
  }

  private func stopProgressUpdates() {
    progressTask?.cancel()
    progressTask = nil
  }

  private func updateProgress() {
    guard let player else {
      progress = 0
      return
    }
    if player.duration > 0 {
      progress = min(1, max(0, player.currentTime / player.duration))
      currentTimeLabel = format(player.currentTime)
      durationLabel = format(player.duration)
    } else {
      progress = 0
      currentTimeLabel = format(player.currentTime)
    }
  }

  private func loadDuration(url: URL) async {
    do {
      let localURL = try await localPlayableURL(for: url)
      guard !Task.isCancelled else { return }
      let asset = AVURLAsset(url: localURL)
      let duration = try await asset.load(.duration)
      let seconds = CMTimeGetSeconds(duration)
      guard seconds.isFinite, seconds > 0 else { return }
      setKnownDuration(seconds, for: url)
    } catch {
      // Keep the compact 0:00 fallback if duration metadata is unavailable.
    }
  }

  private func format(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    return "\(total / 60):\(String(format: "%02d", total % 60))"
  }

  private func localPlayableURL(for url: URL) async throws -> URL {
    if url.isFileURL {
      return url
    }

    if let cachedURL, FileManager.default.fileExists(atPath: cachedURL.path) {
      return cachedURL
    }

    let (downloadedURL, _) = try await URLSession.shared.download(from: url)
    let fileExtension = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
    let destinationURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("VoicePlayback-\(UUID().uuidString).\(fileExtension)")

    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try FileManager.default.removeItem(at: destinationURL)
    }
    try FileManager.default.moveItem(at: downloadedURL, to: destinationURL)
    cachedURL = destinationURL
    return destinationURL
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in
      player.currentTime = 0
      isPlaying = false
      progress = 1
      currentTimeLabel = "0:00"
      stopProgressUpdates()
    }
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    Task { @MainActor in
      isPlaying = false
      self.player = nil
      stopProgressUpdates()
    }
  }
}

enum VoiceDurationCache {
  private static let key = "FoundationChat.VoiceDurationCache.secondsByURL"

  static func duration(for url: URL) -> TimeInterval? {
    let values = UserDefaults.standard.dictionary(forKey: key) as? [String: Double]
    guard let seconds = values?[url.absoluteString], seconds.isFinite, seconds > 0 else {
      return nil
    }
    return seconds
  }

  static func setDuration(_ duration: TimeInterval, for url: URL) {
    guard duration.isFinite, duration > 0 else { return }
    var values = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    values[url.absoluteString] = duration
    UserDefaults.standard.set(values, forKey: key)
  }

  static func removeDuration(for url: URL) {
    var values = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    values.removeValue(forKey: url.absoluteString)
    UserDefaults.standard.set(values, forKey: key)
  }
}

private struct FullscreenImageViewer: View {
  let imageURL: URL
  @Environment(\.dismiss) private var dismiss
  @State private var dragOffset: CGFloat = 0

  var body: some View {
    ZStack {
      Color.black
        .opacity(backgroundOpacity)
        .ignoresSafeArea()

      AsyncImage(url: imageURL) { state in
        if let image = state.image {
          image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        } else {
          ProgressView()
            .tint(.white)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 24)
      .offset(y: max(0, dragOffset))
      .gesture(
        DragGesture(minimumDistance: 8)
          .onChanged { value in
            if value.translation.height > 0 {
              dragOffset = value.translation.height
            }
          }
          .onEnded { value in
            if value.translation.height > 140 {
              dismiss()
              return
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
              dragOffset = 0
            }
          }
      )
    }
    .safeAreaInset(edge: .top) {
      HStack {
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.black.opacity(0.55), in: Circle())
            .overlay(
              Circle()
                .stroke(.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 6)
    }
  }

  private var backgroundOpacity: Double {
    let progress = min(max(dragOffset / 280, 0), 1)
    return 1 - (progress * 0.35)
  }
}

private struct VideoInlinePreview: View {
  let previewURL: URL
  let videoURL: URL
  let isPendingUpload: Bool
  @State private var thumbnail: UIImage?
  @State private var isPresentingFullscreenVideo = false

  var body: some View {
    ZStack {
      if let thumbnail {
        Image(uiImage: thumbnail)
          .resizable()
          .scaledToFill()
      } else {
        Color.secondary.opacity(0.35)
      }

      Image(systemName: "play.circle.fill")
        .font(.system(size: 44))
        .foregroundStyle(.white)
        .shadow(radius: 4)

      if isPendingUpload {
        AttachmentPendingOverlay()
      }
    }
    .frame(width: 242)
    .frame(height: 220)
    .clipped()
    .contentShape(Rectangle())
    .onTapGesture {
      isPresentingFullscreenVideo = true
    }
    .fullScreenCover(isPresented: $isPresentingFullscreenVideo) {
      FullscreenVideoPlayer(videoURL: videoURL)
    }
    .task(id: previewURL) {
      thumbnail = await generateThumbnail(for: previewURL)
    }
  }

  private func generateThumbnail(for url: URL) async -> UIImage? {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)

        do {
          let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
          continuation.resume(returning: UIImage(cgImage: cgImage))
        } catch {
          continuation.resume(returning: nil)
        }
      }
    }
  }
}

private struct AttachmentPendingOverlay: View {
  var body: some View {
    ZStack {
      Color.black.opacity(0.18)

      ProgressView()
        .controlSize(.regular)
        .tint(.white)
        .padding(10)
        .background(Color.black.opacity(0.42), in: Circle())
    }
  }
}

private struct FullscreenVideoPlayer: View {
  let videoURL: URL
  @Environment(\.dismiss) private var dismiss
  @State private var player: AVPlayer?

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.black
        .ignoresSafeArea()

      if let player {
        VideoPlayer(player: player)
          .ignoresSafeArea()
          .onAppear {
            player.play()
          }
      } else {
        ProgressView()
          .tint(.white)
      }

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 34, height: 34)
          .background(.black.opacity(0.55), in: Circle())
          .overlay(
            Circle()
              .stroke(.white.opacity(0.25), lineWidth: 0.5)
          )
          .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
      }
      .padding(.top, 16)
      .padding(.trailing, 16)
    }
    .onAppear {
      player = AVPlayer(url: videoURL)
    }
    .onDisappear {
      player?.pause()
      player = nil
    }
  }
}
