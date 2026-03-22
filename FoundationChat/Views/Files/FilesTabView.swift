import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FilesTabView: View {
  private enum FileFilter: String, CaseIterable, Identifiable {
    case all
    case image
    case video
    case file

    var id: String { rawValue }

    var title: String {
      switch self {
      case .all:
        return "All"
      case .image:
        return "Images"
      case .video:
        return "Videos"
      case .file:
        return "Docs"
      }
    }
  }

  private struct PendingFileUpload {
    let data: Data
    let fileName: String
    let mimeType: String
    let attachmentType: String
  }

  @Environment(AuthStore.self) private var authStore

  @State private var searchText = ""
  @State private var selectedFilter: FileFilter = .all
  @State private var files: [SharedFileItem] = []
  @State private var isLoading = false
  @State private var isUploading = false
  @State private var errorMessage: String?

  @State private var isUploadOptionsPresented = false
  @State private var isMediaPickerPresented = false
  @State private var selectedMediaItem: PhotosPickerItem?
  @State private var isFileImporterPresented = false

  @State private var pendingUpload: PendingFileUpload?
  @State private var sharingFile: SharedFileItem?
  @State private var isShareToUserSheetPresented = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 10) {
        GlassSearchField(placeholder: "Search files", text: $searchText)
          .padding(.horizontal, 16)
          .padding(.top, 8)

        filtersBar
          .padding(.horizontal, 16)

        if isLoading, files.isEmpty {
          ProgressView("Loading files...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
          ContentUnavailableView(
            "Could Not Load Files",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
          ContentUnavailableView(
            "No shared files yet",
            systemImage: "folder"
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(files) { file in
            FileRowView(file: file) {
              sharingFile = file
              isShareToUserSheetPresented = true
            }
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Files")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            isUploadOptionsPresented = true
          } label: {
            Image(systemName: "plus")
          }
          .disabled(isUploading)
        }
      }
      .confirmationDialog("Upload File", isPresented: $isUploadOptionsPresented, titleVisibility: .visible)
      {
        Button("Photo or Video") {
          isMediaPickerPresented = true
        }
        Button("Document") {
          isFileImporterPresented = true
        }
        Button("Cancel", role: .cancel) {}
      }
      .photosPicker(
        isPresented: $isMediaPickerPresented,
        selection: $selectedMediaItem,
        matching: .any(of: [.images, .videos])
      )
      .onChange(of: selectedMediaItem) { _, item in
        guard let item else { return }
        Task {
          await prepareMediaUpload(from: item)
          selectedMediaItem = nil
        }
      }
      .fileImporter(
        isPresented: $isFileImporterPresented,
        allowedContentTypes: [.item],
        allowsMultipleSelection: false
      ) { result in
        Task {
          await prepareDocumentUpload(from: result)
        }
      }
      .sheet(isPresented: $isShareToUserSheetPresented) {
        if let selectedFile = sharingFile {
          SharePrivateFileSheet(file: selectedFile) {
            sharingFile = nil
            isShareToUserSheetPresented = false
          }
          .environment(authStore)
        }
      }
      .overlay {
        if isUploading {
          ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            ProgressView("Uploading file...")
              .padding(.horizontal, 18)
              .padding(.vertical, 14)
              .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
          }
        }
      }
      .task(id: "\(searchText)-\(selectedFilter.rawValue)") {
        await loadFiles()
      }
    }
  }

  private var filtersBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(FileFilter.allCases) { filter in
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
  private func loadFiles() async {
    isLoading = true
    errorMessage = nil

    do {
      files = try await authStore.fetchSharedFiles(
        search: searchText,
        typeFilter: selectedFilter.rawValue
      )
    } catch {
      errorMessage = error.localizedDescription
      files = []
    }

    isLoading = false
  }

  @MainActor
  private func prepareMediaUpload(from item: PhotosPickerItem) async {
    errorMessage = nil

    do {
      guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
        throw URLError(.cannotDecodeRawData)
      }

      let contentType = item.supportedContentTypes.first
      let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
      let attachmentType = attachmentTypeFromMime(mimeType)
      let fileExtension =
        contentType?.preferredFilenameExtension
        ?? defaultExtension(for: attachmentType)
      let fileName = "Upload-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"

      pendingUpload = PendingFileUpload(
        data: data,
        fileName: fileName,
        mimeType: mimeType,
        attachmentType: attachmentType
      )

      await uploadPendingFilePrivately()
    } catch {
      pendingUpload = nil
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func prepareDocumentUpload(from result: Result<[URL], any Error>) async {
    errorMessage = nil

    do {
      let selectedURLs = try result.get()
      guard let selectedURL = selectedURLs.first else {
        throw URLError(.fileDoesNotExist)
      }
      let hasAccess = selectedURL.startAccessingSecurityScopedResource()
      defer {
        if hasAccess {
          selectedURL.stopAccessingSecurityScopedResource()
        }
      }

      let fileData = try Data(contentsOf: selectedURL)
      guard !fileData.isEmpty else {
        throw URLError(.zeroByteResource)
      }

      let values = try selectedURL.resourceValues(forKeys: [.contentTypeKey, .nameKey])
      let contentType = values.contentType
      let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
      let fileName = values.name ?? selectedURL.lastPathComponent

      pendingUpload = PendingFileUpload(
        data: fileData,
        fileName: fileName,
        mimeType: mimeType,
        attachmentType: attachmentTypeFromMime(mimeType)
      )

      await uploadPendingFilePrivately()
    } catch {
      pendingUpload = nil
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func uploadPendingFilePrivately() async {
    guard let pendingUpload else { return }

    isUploading = true
    errorMessage = nil
    defer { isUploading = false }

    do {
      let uploadURL = try await authStore.generateAttachmentUploadURL()
      let storageId = try await authStore.uploadAttachmentData(
        pendingUpload.data,
        uploadURL: uploadURL,
        mimeType: pendingUpload.mimeType
      )

      _ = try await authStore.savePrivateFile(
        storageId: storageId,
        attachmentType: pendingUpload.attachmentType,
        fileName: pendingUpload.fileName,
        mimeType: pendingUpload.mimeType,
        title: pendingUpload.fileName
      )

      self.pendingUpload = nil
      await loadFiles()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func attachmentTypeFromMime(_ mimeType: String) -> String {
    if mimeType.hasPrefix("image/") {
      return "image"
    }
    if mimeType.hasPrefix("video/") {
      return "video"
    }
    return "file"
  }

  private func defaultExtension(for attachmentType: String) -> String {
    switch attachmentType {
    case "image":
      return "jpg"
    case "video":
      return "mp4"
    default:
      return "dat"
    }
  }
}

private struct FileRowView: View {
  let file: SharedFileItem
  let onShareInApp: () -> Void

  private var iconName: String {
    switch file.attachmentType {
    case "image":
      return "photo.fill"
    case "video":
      return "video.fill"
    default:
      return "doc.fill"
    }
  }

  private var shareURL: URL? {
    guard let urlString = file.url else { return nil }
    return URL(string: urlString)
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: iconName)
        .font(.headline)
        .foregroundStyle(.white)
        .frame(width: 36, height: 36)
        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(file.fileName)
          .font(.body.weight(.semibold))
          .lineLimit(1)

        Text(file.createdDate.formatted(date: .abbreviated, time: .shortened))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button(action: onShareInApp) {
        Image(systemName: "paperplane.fill")
          .font(.subheadline.weight(.semibold))
          .padding(8)
      }
      .buttonStyle(.borderless)

      if let shareURL {
        ShareLink(item: shareURL) {
          Image(systemName: "square.and.arrow.up")
            .font(.subheadline.weight(.semibold))
            .padding(8)
        }
        .buttonStyle(.borderless)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct SharePrivateFileSheet: View {
  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let file: SharedFileItem
  let onShared: () -> Void

  @State private var searchText = ""
  @State private var users: [DirectoryUser] = []
  @State private var isLoading = false
  @State private var isSharing = false
  @State private var errorMessage: String?

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
              Task { await share(file, with: user) }
            } label: {
              HStack {
                Text(user.displayName)
                  .foregroundStyle(.primary)
                Spacer()
                if isSharing {
                  ProgressView()
                }
              }
            }
            .buttonStyle(.plain)
            .disabled(isSharing)
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Share File")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
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
      let allUsers = try await authStore.fetchDirectoryUsers(search: searchText)
      let myStackUserId = authStore.viewer?.subject
      users = allUsers.filter { $0.stackUserId != myStackUserId }
    } catch {
      users = []
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  @MainActor
  private func share(_ file: SharedFileItem, with user: DirectoryUser) async {
    guard !isSharing else { return }
    isSharing = true
    errorMessage = nil
    defer { isSharing = false }

    do {
      let conversation = try await authStore.startDirectConversation(withStackUserID: user.stackUserId)
      _ = try await authStore.sharePrivateFileToConversation(
        fileID: file.id,
        conversationID: conversation.conversationId
      )
      onShared()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview {
  FilesTabView()
    .environment(AuthStore())
}
