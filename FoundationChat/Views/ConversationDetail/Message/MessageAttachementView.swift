import AVFoundation
import Combine
import SwiftUI
import UIKit

struct MessageAttachementView: View {
  let message: Message
  let isOutgoing: Bool
  @State private var isPresentingFullscreenImage = false

  private var isImageAttachment: Bool {
    message.attachementType == "image"
      || message.attachementMimeType?.hasPrefix("image/") == true
  }

  private var isVideoAttachment: Bool {
    message.attachementType == "video"
      || message.attachementMimeType?.hasPrefix("video/") == true
  }

  private var isAudioAttachment: Bool {
    message.attachementType == "audio"
      || message.attachementMimeType?.hasPrefix("audio/") == true
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

  var body: some View {
    if message.isDeleted {
      EmptyView()
    } else if isImageAttachment, let mediaURL {
      AsyncImage(url: mediaURL) { state in
        if let image = state.image {
          image
            .resizable()
            .scaledToFill()
            .frame(maxWidth: 242, maxHeight: 320)
            .clipped()
        } else if state.error == nil {
          ProgressView()
            .frame(width: 242, height: 180)
        } else {
          Image(systemName: "photo")
            .font(.system(size: 28, weight: .regular))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .frame(width: 242, height: 180)
            .background(Color.white.opacity(0.72))
        }
      }
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
    } else if isVideoAttachment, let mediaURL {
      VideoThumbnailPreview(url: mediaURL)
        .clipShape(.rect(cornerRadius: 16))
    } else if isAudioAttachment, let attachmentURL {
      AudioAttachmentPlaybackView(
        url: attachmentURL,
        title: displayFileName ?? "Voice message",
        isOutgoing: isOutgoing,
        durationOverride: audioDurationHint
      )
    } else if let displayFileName {
      HStack(spacing: 8) {
        Image(systemName: "doc")
          .foregroundStyle(isOutgoing ? .white.opacity(0.95) : .primary)
        Text(displayFileName)
          .foregroundStyle(isOutgoing ? .white : .primary)
          .font(.subheadline)
          .lineLimit(2)
        if let attachmentURL {
          ShareLink(item: attachmentURL) {
            Image(systemName: "square.and.arrow.up")
              .foregroundStyle(isOutgoing ? .white.opacity(0.95) : .primary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(isOutgoing ? .white.opacity(0.18) : Color.black.opacity(0.04))
      .clipShape(.rect(cornerRadius: 12))
      .onTapGesture {
        if let attachmentURL {
          UIApplication.shared.open(attachmentURL)
        }
      }
    }
  }
}

struct AudioAttachmentPlaybackView: View {
  let url: URL
  let title: String
  let isOutgoing: Bool
  let durationOverride: TimeInterval?

  @StateObject private var playbackController = VoicePlaybackController()

  init(
    url: URL,
    title: String,
    isOutgoing: Bool,
    durationOverride: TimeInterval? = nil
  ) {
    self.url = url
    self.title = title
    self.isOutgoing = isOutgoing
    self.durationOverride = durationOverride
  }

  var body: some View {
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

private struct VideoThumbnailPreview: View {
  let url: URL
  @State private var thumbnail: UIImage?

  var body: some View {
    ZStack {
      if let thumbnail {
        Image(uiImage: thumbnail)
          .resizable()
          .scaledToFill()
      } else {
        Color.secondary
      }

      Image(systemName: "play.circle.fill")
        .font(.system(size: 44))
        .foregroundStyle(.white)
        .shadow(radius: 4)
    }
    .frame(height: 220)
    .clipped()
    .task(id: url) {
      thumbnail = await generateThumbnail(for: url)
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
