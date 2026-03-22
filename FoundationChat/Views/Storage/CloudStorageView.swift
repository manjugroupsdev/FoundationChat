import SwiftUI

struct CloudStorageView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var folders: [StorageFolder] = []
    @State private var files: [SharedFileItem] = []
    @State private var currentFolderId: String? = nil
    @State private var breadcrumbs: [(id: String?, name: String)] = [("root", "My Files")]
    @State private var isLoading = true
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                } else {
                    if !folders.isEmpty {
                        Section("Folders") {
                            ForEach(folders) { folder in
                                Button {
                                    navigateToFolder(folder)
                                } label: {
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(Color.accentColor)
                                        Text(folder.name)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await deleteFolder(folder) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    if !files.isEmpty {
                        Section("Files") {
                            ForEach(files) { file in
                                HStack {
                                    fileIcon(for: file.attachmentType)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.fileName)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Text(file.createdDate, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    if folders.isEmpty && files.isEmpty {
                        ContentUnavailableView(
                            "Empty Folder",
                            systemImage: "folder",
                            description: Text("No files or folders here yet.")
                        )
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .navigationTitle(breadcrumbs.last?.name ?? "Files")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                if breadcrumbs.count > 1 {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            navigateBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("Folder Name", text: $newFolderName)
                Button("Create") {
                    Task { await createFolder() }
                }
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
            }
            .task {
                await loadContent()
            }
        }
    }

    private func fileIcon(for type: String) -> some View {
        Group {
            switch type {
            case "image":
                Image(systemName: "photo.fill")
                    .foregroundStyle(.green)
            case "video":
                Image(systemName: "video.fill")
                    .foregroundStyle(.purple)
            default:
                Image(systemName: "doc.fill")
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 32)
    }

    private func navigateToFolder(_ folder: StorageFolder) {
        breadcrumbs.append((id: folder.id, name: folder.name))
        currentFolderId = folder.id
        Task { await loadContent() }
    }

    private func navigateBack() {
        guard breadcrumbs.count > 1 else { return }
        breadcrumbs.removeLast()
        currentFolderId = breadcrumbs.last?.id == "root" ? nil : breadcrumbs.last?.id
        Task { await loadContent() }
    }

    private func loadContent() async {
        isLoading = true
        do {
            folders = try await authStore.fetchStorageFolders(parentFolderId: currentFolderId)
            files = try await authStore.fetchSharedFiles()
        } catch {}
        isLoading = false
    }

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newFolderName = ""
        do {
            try await authStore.createStorageFolder(name: name, parentFolderId: currentFolderId)
            await loadContent()
        } catch {}
    }

    private func deleteFolder(_ folder: StorageFolder) async {
        do {
            try await authStore.deleteStorageFolder(folderId: folder.id)
            await loadContent()
        } catch {}
    }
}
