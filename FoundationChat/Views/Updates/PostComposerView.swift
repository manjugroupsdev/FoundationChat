import SwiftUI
import PhotosUI

struct PostComposerView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedCategory: String? = nil
    @State private var isPinned = false
    @State private var isAnnouncement = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImageData: [Data] = []

    private let categories = ["Announcement", "HR", "Engineering", "Social"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional)", text: $title)
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if bodyText.isEmpty {
                                Text("What's happening?")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { cat in
                                FilterChip(title: cat, isSelected: selectedCategory == cat) {
                                    selectedCategory = selectedCategory == cat ? nil : cat
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("Media") {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 4, matching: .images) {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    if !selectedImageData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedImageData.indices, id: \.self) { index in
                                    if let uiImage = UIImage(data: selectedImageData[index]) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    selectedImageData.remove(at: index)
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.caption)
                                                        .foregroundStyle(.white, .black.opacity(0.5))
                                                }
                                                .offset(x: 4, y: -4)
                                            }
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section("Options") {
                    Toggle("Pin to Top", isOn: $isPinned)
                    Toggle("Mark as Announcement", isOn: $isAnnouncement)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task { await createPost() }
                    }
                    .fontWeight(.semibold)
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
            }
            .disabled(isPosting)
            .overlay {
                if isPosting {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                        .overlay { ProgressView("Posting...") }
                }
            }
            .onChange(of: selectedPhotos) {
                Task { await loadPhotos() }
            }
        }
    }

    private func loadPhotos() async {
        var newData: [Data] = []
        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self) {
                newData.append(data)
            }
        }
        selectedImageData = newData
    }

    private func createPost() async {
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        isPosting = true
        errorMessage = nil

        do {
            var imageStorageIds: [String] = []
            for imageData in selectedImageData {
                let uploadURL = try await authStore.generateAttachmentUploadURL()
                let storageId = try await authStore.uploadAttachmentData(imageData, uploadURL: uploadURL, mimeType: "image/jpeg")
                imageStorageIds.append(storageId)
            }

            try await authStore.createPost(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: trimmedBody,
                imageStorageIds: imageStorageIds.isEmpty ? nil : imageStorageIds,
                isPinned: isPinned,
                isAnnouncement: isAnnouncement,
                category: selectedCategory
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isPosting = false
    }
}
