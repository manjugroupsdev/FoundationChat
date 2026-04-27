import SwiftUI

struct ConversationMediaView: View {
  @Environment(AuthStore.self) private var authStore

  let conversationID: String?
  let channelID: String?
  let title: String

  @State private var attachments: [ConvexChatMessage] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var selectedFilter: MediaFilter = .all
  @State private var presentedAttachmentURL: IdentifiableURL?

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

  private var imageAndVideoItems: [(message: ConvexChatMessage, attachment: MessageAttachment)] {
    filteredAttachments.flatMap { message -> [(ConvexChatMessage, MessageAttachment)] in
      (message.attachments ?? [])
        .filter { isImage($0) || isVideo($0) }
        .map { (message, $0) }
    }
  }

  private var fileItems: [(message: ConvexChatMessage, attachment: MessageAttachment)] {
    filteredAttachments.flatMap { message -> [(ConvexChatMessage, MessageAttachment)] in
      (message.attachments ?? [])
        .filter { !isImage($0) && !isVideo($0) }
        .map { (message, $0) }
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
        ProgressView("Loading media...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let errorMessage {
        ContentUnavailableView(
          "Could Not Load Media",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if filteredAttachments.isEmpty {
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
    .fullScreenCover(item: $presentedAttachmentURL) { item in
      MediaQuickLookView(url: item.url)
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
      ForEach(Array(imageAndVideoItems.enumerated()), id: \.offset) { _, entry in
        MediaGridCell(
          attachment: entry.attachment,
          isVideo: isVideo(entry.attachment)
        )
        .aspectRatio(1, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
          guard let urlString = entry.attachment.url, let url = URL(string: urlString) else { return }
          presentedAttachmentURL = IdentifiableURL(url: url)
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
          createdAt: entry.message.timestamp,
          senderName: entry.message.senderName
        )
        .contentShape(Rectangle())
        .onTapGesture {
          guard let urlString = entry.attachment.url, let url = URL(string: urlString) else { return }
          presentedAttachmentURL = IdentifiableURL(url: url)
        }
        Divider().padding(.leading, 60)
      }
    }
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

private struct MediaGridCell: View {
  let attachment: MessageAttachment
  let isVideo: Bool

  var body: some View {
    ZStack {
      if let urlString = attachment.url, let url = URL(string: urlString) {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFill()
          default:
            Color(.systemGray6)
              .overlay(ProgressView())
          }
        }
      } else {
        Color(.systemGray6)
      }

      if isVideo {
        Image(systemName: "play.circle.fill")
          .font(.system(size: 28))
          .foregroundStyle(.white)
          .shadow(radius: 2)
      }
    }
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

private struct IdentifiableURL: Identifiable {
  let url: URL
  var id: String { url.absoluteString }
}

private struct MediaQuickLookView: View {
  let url: URL
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFit()
        case .failure:
          ContentUnavailableView(
            "Cannot Preview",
            systemImage: "exclamationmark.triangle"
          )
        default:
          ProgressView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.black)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
            .foregroundStyle(.white)
        }
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: url) {
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
