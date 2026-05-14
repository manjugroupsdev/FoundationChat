import QuickLook
import SwiftData
import SwiftUI
import UIKit

struct ConversationMediaView: View {
  @Environment(AuthStore.self) private var authStore
  @Query private var localConversations: [Conversation]

  let conversationID: String?
  let channelID: String?
  let title: String

  @State private var attachments: [ConvexChatMessage] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var selectedFilter: MediaFilter = .all
  @State private var presentedAttachment: PreviewAttachment?

  init(conversationID: String? = nil, channelID: String? = nil, title: String = "Media") {
    self.conversationID = conversationID
    self.channelID = channelID
    self.title = title
  }

  enum MediaFilter: String, CaseIterable, Identifiable {
    case all
    case images
    case videos
    case files

    var id: String { rawValue }

    var label: String {
      switch self {
      case .all: return "All"
      case .images: return "Photos"
      case .videos: return "Videos"
      case .files: return "Files"
      }
    }
  }

  private var filteredAttachments: [ConvexChatMessage] {
    attachments.filter { message in
      switch selectedFilter {
      case .all:
        return message.attachments?.isEmpty == false
      case .images:
        return message.attachments?.contains { isImage($0) } == true
      case .videos:
        return message.attachments?.contains { isVideo($0) } == true
      case .files:
        return message.attachments?.contains { !isImage($0) && !isVideo($0) } == true
      }
    }
  }

  private var allMediaItems: [MediaAttachmentItem] {
    let localByMessageID = localAttachmentItems.reduce(into: [String: MediaAttachmentItem]()) { result, item in
      if let messageID = item.messageID {
        result[messageID] = item
      }
    }

    var seenKeys = Set<String>()
    var items: [MediaAttachmentItem] = []

    for message in filteredAttachments {
      for attachment in message.attachments ?? [] {
        var resolvedAttachment = attachment
        if let localItem = localByMessageID[message.id] {
          resolvedAttachment = attachment.mergingPreviewData(from: localItem.attachment)
        }

        let item = MediaAttachmentItem(
          messageID: message.id,
          attachment: resolvedAttachment,
          createdAt: message.timestamp,
          senderName: message.senderName
        )
        let key = item.dedupeKey
        guard !seenKeys.contains(key) else { continue }
        seenKeys.insert(key)
        items.append(item)
      }
    }

    for item in localAttachmentItems {
      let key = item.dedupeKey
      guard !seenKeys.contains(key) else { continue }
      seenKeys.insert(key)
      items.append(item)
    }

    return items.sorted { $0.createdAt > $1.createdAt }
  }

  private var imageAndVideoItems: [MediaAttachmentItem] {
    allMediaItems.filter { isImage($0.attachment) || isVideo($0.attachment) }
  }

  private var fileItems: [MediaAttachmentItem] {
    allMediaItems.filter { !isImage($0.attachment) && !isVideo($0.attachment) }
  }

  private var visibleItemCount: Int {
    selectedFilter == .files ? fileItems.count : imageAndVideoItems.count
  }

  private var localAttachmentItems: [MediaAttachmentItem] {
    guard let conversationID else { return [] }
    guard let conversation = localConversations.first(where: { $0.remoteConversationID == conversationID }) else {
      return []
    }

    return conversation.sortedMessages.compactMap { message in
      guard !message.isDeleted else { return nil }
      let hasAttachment = message.attachementType != nil
        || message.attachementMimeType != nil
        || message.attachementURL != nil
        || message.attachementThumbnail != nil
      guard hasAttachment else { return nil }

      let attachment = MessageAttachment(
        _id: message.remoteMessageID,
        messageId: message.remoteMessageID,
        fileName: message.attachementFileName,
        fileType: message.attachementMimeType ?? message.attachementType,
        storageId: nil,
        thumbnail: message.attachementThumbnail,
        url: message.attachementURL
      )

      switch selectedFilter {
      case .all:
        return MediaAttachmentItem(
          messageID: message.remoteMessageID,
          attachment: attachment,
          createdAt: message.timestamp,
          senderName: nil
        )
      case .images:
        guard isImage(attachment) else { return nil }
      case .videos:
        guard isVideo(attachment) else { return nil }
      case .files:
        guard !isImage(attachment) && !isVideo(attachment) else { return nil }
      }

      return MediaAttachmentItem(
        messageID: message.remoteMessageID,
        attachment: attachment,
        createdAt: message.timestamp,
        senderName: nil
      )
    }
  }

  private let gridColumns: [GridItem] = Array(
    repeating: GridItem(.flexible(), spacing: 2), count: 3
  )

  var body: some View {
    VStack(spacing: 0) {
      filterBar
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

      if isLoading, attachments.isEmpty {
        loadingSkeleton
      } else if let errorMessage {
        ContentUnavailableView(
          "Could Not Load Media",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if visibleItemCount == 0 {
        ContentUnavailableView(
          "No \(selectedFilter.label)",
          systemImage: "photo.on.rectangle",
          description: Text("Shared \(selectedFilter.label.lowercased()) will appear here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          if selectedFilter == .files {
            fileList
          } else {
            mediaGrid
          }
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
    .fullScreenCover(item: $presentedAttachment) { item in
      MediaPreviewView(attachment: item)
    }
  }

  private var filterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(MediaFilter.allCases) { filter in
          Button {
            selectedFilter = filter
          } label: {
            Text(filter.label)
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

  private var mediaGrid: some View {
    LazyVGrid(columns: gridColumns, spacing: 2) {
      ForEach(imageAndVideoItems) { entry in
        MediaGridCell(
          attachment: entry.attachment,
          isVideo: isVideo(entry.attachment)
        )
        .aspectRatio(1, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
          guard let preview = PreviewAttachment(attachment: entry.attachment, isVideo: isVideo(entry.attachment)) else { return }
          presentedAttachment = preview
        }
      }
    }
    .padding(.horizontal, 2)
  }

  private var fileList: some View {
    LazyVStack(spacing: 0) {
      ForEach(Array(fileItems.enumerated()), id: \.offset) { _, entry in
        FileRow(
          attachment: entry.attachment,
          createdAt: entry.createdAt,
          senderName: entry.senderName
        )
        .contentShape(Rectangle())
        .onTapGesture {
          guard let preview = PreviewAttachment(attachment: entry.attachment, isVideo: isVideo(entry.attachment)) else { return }
          presentedAttachment = preview
        }
        Divider().padding(.leading, 60)
      }
    }
  }

  private var loadingSkeleton: some View {
    ScrollView {
      if selectedFilter == .files {
        LazyVStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { _ in
            FileRowSkeleton()
            Divider().padding(.leading, 60)
          }
        }
      } else {
        LazyVGrid(columns: gridColumns, spacing: 2) {
          ForEach(0..<12, id: \.self) { _ in
            SkeletonBlock()
              .aspectRatio(1, contentMode: .fill)
          }
        }
        .padding(.horizontal, 2)
      }
    }
    .allowsHitTesting(false)
  }

  @MainActor
  private func load() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      attachments = try await authStore.fetchConversationAttachments(
        conversationID: conversationID,
        channelID: channelID
      )
    } catch {
      if Task.isCancelled || (error as? URLError)?.code == .cancelled {
        return
      }
      attachments = []
      errorMessage = error.localizedDescription
    }
  }

  private func isImage(_ attachment: MessageAttachment) -> Bool {
    let type = attachment.fileType?.lowercased() ?? ""
    return type == "image" || type.hasPrefix("image/")
  }

  private func isVideo(_ attachment: MessageAttachment) -> Bool {
    let type = attachment.fileType?.lowercased() ?? ""
    return type == "video" || type.hasPrefix("video/")
  }
}

private struct MediaAttachmentItem: Identifiable {
  let messageID: String?
  let attachment: MessageAttachment
  let createdAt: Date
  let senderName: String?

  var id: String {
    [
      messageID,
      attachment.id,
      attachment.url,
      attachment.thumbnail,
      attachment.fileName,
    ]
    .compactMap { $0 }
    .joined(separator: ":")
  }

  var dedupeKey: String {
    messageID ?? attachment.url ?? attachment.thumbnail ?? attachment.id
  }
}

private extension MessageAttachment {
  func mergingPreviewData(from local: MessageAttachment) -> MessageAttachment {
    MessageAttachment(
      _id: _id ?? local._id,
      messageId: messageId ?? local.messageId,
      fileName: fileName ?? local.fileName,
      fileType: fileType ?? local.fileType,
      fileSize: fileSize ?? local.fileSize,
      storageId: storageId ?? local.storageId,
      thumbnail: thumbnail ?? local.thumbnail,
      url: url ?? local.url
    )
  }
}

private struct MediaGridCell: View {
  let attachment: MessageAttachment
  let isVideo: Bool

  private var previewURL: URL? {
    let raw = attachment.thumbnail ?? attachment.url
    guard let raw else { return nil }
    return URL(string: raw)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        if let previewURL {
          MediaRemoteImage(
            url: previewURL,
            contentMode: .fill,
            placeholderSystemImage: isVideo ? "video" : "photo"
          )
          .frame(width: proxy.size.width, height: proxy.size.height)
          .clipped()
        } else {
          Color(.systemGray6)
            .overlay(
              Image(systemName: isVideo ? "video" : "photo")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            )
        }

        if isVideo {
          Image(systemName: "play.circle.fill")
            .font(.system(size: 28))
            .foregroundStyle(.white)
            .shadow(radius: 2)
        }
      }
    }
    .background(Color(.systemGray6))
    .clipped()
  }
}

private struct FileRow: View {
  let attachment: MessageAttachment
  let createdAt: Date
  let senderName: String?

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "doc")
        .font(.title2)
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .background(Color.blue, in: Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text(attachment.fileName ?? "File")
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        HStack(spacing: 6) {
          if let senderName, !senderName.isEmpty {
            Text(senderName)
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("·")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text(Self.dateFormatter.string(from: createdAt))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      if let urlString = attachment.url, let url = URL(string: urlString) {
        ShareLink(item: url) {
          Image(systemName: "square.and.arrow.up")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

private struct PreviewAttachment: Identifiable {
  let url: URL
  let previewURL: URL
  let fileName: String
  let isImage: Bool

  var id: String { url.absoluteString }

  init?(attachment: MessageAttachment, isVideo: Bool) {
    guard let urlString = attachment.url, let url = URL(string: urlString) else { return nil }
    let previewString = attachment.thumbnail ?? attachment.url
    guard let previewString, let previewURL = URL(string: previewString) else { return nil }
    self.url = url
    self.previewURL = previewURL
    self.fileName = attachment.fileName ?? url.lastPathComponent
    let type = attachment.fileType?.lowercased() ?? ""
    self.isImage = !isVideo && (type == "image" || type.hasPrefix("image/"))
  }
}

private struct MediaPreviewView: View {
  let attachment: PreviewAttachment
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    if attachment.isImage {
      ImagePreviewView(url: attachment.previewURL, originalURL: attachment.url)
    } else {
      RemoteQuickLookView(url: attachment.url, fileName: attachment.fileName)
    }
  }
}

private struct ImagePreviewView: View {
  let url: URL
  let originalURL: URL
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZoomableRemoteImage(url: url)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.black)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
            .foregroundStyle(.white)
        }
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: originalURL) {
            Image(systemName: "square.and.arrow.up")
              .foregroundStyle(.white)
          }
        }
      }
      .toolbarBackground(.black, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
  }
}

private struct MediaRemoteImage: View {
  let url: URL
  let contentMode: ContentMode
  let placeholderSystemImage: String

  @State private var image: UIImage?
  @State private var isLoading = false
  @State private var didFail = false

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else if isLoading {
        SkeletonBlock()
      } else {
        Color(.systemGray6)
          .overlay(
            Image(systemName: placeholderSystemImage)
              .font(.system(size: 24))
              .foregroundStyle(didFail ? Color.secondary : Color.secondary.opacity(0.6))
          )
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
      if Task.isCancelled || (error as? URLError)?.code == .cancelled {
        return
      }
      didFail = true
    }
  }
}

private struct ZoomableRemoteImage: View {
  let url: URL

  @Environment(\.dismiss) private var dismiss
  @State private var image: UIImage?
  @State private var isLoading = false
  @State private var didFail = false
  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1
  @State private var dragOffset: CGSize = .zero
  @State private var lastDragOffset: CGSize = .zero

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .scaleEffect(scale)
          .offset(dragOffset)
          .gesture(zoomGesture.simultaneously(with: panGesture))
          .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
              if scale > 1 {
                scale = 1
                lastScale = 1
                dragOffset = .zero
                lastDragOffset = .zero
              } else {
                scale = 2.2
                lastScale = 2.2
              }
            }
          }
          .padding(.horizontal, 8)
      } else if isLoading {
        ProgressView()
          .tint(.white)
      } else if didFail {
        ContentUnavailableView(
          "Cannot Preview",
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.white)
      }
    }
    .task(id: url) {
      await loadImage()
    }
  }

  private var zoomGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        scale = min(max(lastScale * value, 1), 4)
      }
      .onEnded { _ in
        lastScale = scale
        if scale <= 1.02 {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            scale = 1
            lastScale = 1
            dragOffset = .zero
            lastDragOffset = .zero
          }
        }
      }
  }

  private var panGesture: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        guard scale > 1 else { return }
        dragOffset = CGSize(
          width: lastDragOffset.width + value.translation.width,
          height: lastDragOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        lastDragOffset = dragOffset
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
      if Task.isCancelled || (error as? URLError)?.code == .cancelled {
        return
      }
      didFail = true
    }
  }
}

private struct RemoteQuickLookView: View {
  let url: URL
  let fileName: String

  @Environment(\.dismiss) private var dismiss
  @State private var localURL: URL?
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Group {
        if let localURL {
          QuickLookController(url: localURL)
        } else if let errorMessage {
          ContentUnavailableView(
            "Cannot Preview",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
        } else {
          SkeletonBlock()
            .frame(width: 120, height: 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: url) {
            Image(systemName: "square.and.arrow.up")
          }
        }
      }
    }
    .task(id: url) {
      await download()
    }
  }

  @MainActor
  private func download() async {
    errorMessage = nil
    localURL = nil

    if url.isFileURL {
      localURL = url
      return
    }

    do {
      let (downloadedURL, _) = try await URLSession.shared.download(from: url)
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(URL(fileURLWithPath: fileName).pathExtension)
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
}

private struct QuickLookController: UIViewControllerRepresentable {
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

private struct FileRowSkeleton: View {
  var body: some View {
    HStack(spacing: 12) {
      SkeletonBlock()
        .frame(width: 40, height: 40)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 6) {
        SkeletonBlock()
          .frame(width: 180, height: 14)
        SkeletonBlock()
          .frame(width: 120, height: 11)
      }

      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

private struct SkeletonBlock: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
      .fill(Color(.systemGray5))
      .redacted(reason: .placeholder)
  }
}
