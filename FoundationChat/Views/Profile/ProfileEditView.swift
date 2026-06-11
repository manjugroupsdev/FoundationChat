import PhotosUI
import SwiftUI

struct ProfileEditView: View {
  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var email = ""
  @State private var phone = ""
  @State private var pendingPhotoData: Data?
  @State private var pendingPhotoRemoved = false
  @State private var selectedItem: PhotosPickerItem?
  @State private var imageToCrop: UIImage?
  @State private var isLoadingPhoto = false
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var validationMessage: String?
  @State private var remotePhotoURL: URL?

  var onSaved: (() -> Void)?

  private var pendingImage: UIImage? {
    guard let pendingPhotoData else { return nil }
    return UIImage(data: pendingPhotoData)
  }

  var body: some View {
    Form {
      Section {
        HStack {
          Spacer()
          VStack(spacing: 10) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
              avatarView
                .overlay(alignment: .bottomTrailing) {
                  Image(systemName: "camera.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue, in: Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPhoto || isSaving)

            HStack(spacing: 16) {
              PhotosPicker(selection: $selectedItem, matching: .images) {
                Text(pendingPhotoData == nil && remotePhotoURL == nil ? "Add Photo" : "Change Photo")
              }
              .disabled(isLoadingPhoto || isSaving)

              if pendingPhotoData != nil || hasExistingRemotePhoto {
                Button("Remove", role: .destructive) {
                  pendingPhotoData = nil
                  pendingPhotoRemoved = true
                  selectedItem = nil
                }
                .disabled(isLoadingPhoto || isSaving)
              }
            }
            .font(.subheadline.weight(.semibold))
          }
          Spacer()
        }
        .padding(.vertical, 8)

        if isLoadingPhoto {
          HStack {
            Spacer()
            ProgressView("Preparing photo…")
              .font(.caption)
            Spacer()
          }
        }
      }

      Section("Details") {
        TextField("Full name", text: $name)
          .textContentType(.name)
          .autocorrectionDisabled()
        TextField("Email", text: $email)
          .textContentType(.emailAddress)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("Phone", text: $phone)
          .textContentType(.telephoneNumber)
          .keyboardType(.phonePad)
      }

      if let validationMessage {
        Section {
          Text(validationMessage)
            .foregroundStyle(.red)
            .font(.subheadline)
        }
      }

      if let errorMessage {
        Section {
          Text(errorMessage)
            .foregroundStyle(.red)
            .font(.subheadline)
        }
      }
    }
    .navigationTitle("Edit Profile")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
          .disabled(isSaving)
      }
      ToolbarItem(placement: .confirmationAction) {
        if isSaving {
          ProgressView()
        } else {
          Button("Save") { save() }
            .disabled(!canSubmit)
        }
      }
    }
    .onAppear(perform: hydrateFromSession)
    .task(id: authStore.viewer?.photo) {
      await loadRemoteAvatar()
    }
    .onChange(of: selectedItem) { _, item in
      guard let item else { return }
      Task { await handlePhotoPick(item: item) }
    }
    .sheet(isPresented: Binding(
      get: { imageToCrop != nil },
      set: { if !$0 { imageToCrop = nil } }
    )) {
      if let imageToCrop {
        ProfilePhotoCropView(image: imageToCrop) { croppedData in
          pendingPhotoData = croppedData
          pendingPhotoRemoved = false
          self.imageToCrop = nil
        }
      }
    }
  }

  // MARK: - Avatar

  @ViewBuilder
  private var avatarView: some View {
    Group {
      if let pendingImage {
        Image(uiImage: pendingImage)
          .resizable()
          .scaledToFill()
      } else if !pendingPhotoRemoved, let remotePhotoURL {
        AsyncImage(url: remotePhotoURL) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFill()
          case .failure:
            initialsView
          default:
            ProgressView()
          }
        }
      } else {
        initialsView
      }
    }
    .frame(width: 96, height: 96)
    .clipShape(Circle())
  }

  private var initialsView: some View {
    let label = (name.isEmpty ? authStore.currentUserLabel : name) ?? ""
    let initials = ProfileEditView.initials(from: label)
    return Text(initials)
      .font(.title.weight(.bold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        LinearGradient(
          colors: [
            Color(red: 0.25, green: 0.07, blue: 0.30),
            Color(red: 0.48, green: 0.18, blue: 0.50)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
  }

  private static func initials(from label: String) -> String {
    let parts = label
      .split(whereSeparator: { !$0.isLetter })
      .prefix(2)
      .compactMap(\.first)
    let result = String(parts).uppercased()
    return result.isEmpty ? "MG" : result
  }

  // MARK: - State

  private func hydrateFromSession() {
    let user = authStore.currentSession?.user
    if name.isEmpty { name = user?.name ?? "" }
    if email.isEmpty { email = user?.email ?? "" }
    if phone.isEmpty { phone = user?.phone ?? "" }
  }

  private func loadRemoteAvatar() async {
    guard let storageId = authStore.viewer?.photo, !storageId.isEmpty else {
      remotePhotoURL = nil
      return
    }
    remotePhotoURL = try? await authStore.resolveStorageURL(storageId: storageId)
  }

  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var trimmedPhone: String { phone.trimmingCharacters(in: .whitespacesAndNewlines) }

  private var canSubmit: Bool {
    !isSaving && !isLoadingPhoto && !trimmedName.isEmpty && !trimmedPhone.isEmpty
  }

  private var hasExistingRemotePhoto: Bool {
    guard !pendingPhotoRemoved else { return false }
    let photo = authStore.viewer?.photo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !photo.isEmpty
  }

  private func validate() -> String? {
    if trimmedName.isEmpty { return "Name is required." }
    if trimmedPhone.isEmpty { return "Phone is required." }
    let phoneDigits = trimmedPhone.filter(\.isNumber)
    if phoneDigits.count < 10 { return "Phone must be at least 10 digits." }
    if !trimmedEmail.isEmpty {
      let emailRegex = #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#
      if trimmedEmail.range(of: emailRegex, options: .regularExpression) == nil {
        return "Enter a valid email address."
      }
    }
    return nil
  }

  // MARK: - Photo

  private func handlePhotoPick(item: PhotosPickerItem) async {
    isLoadingPhoto = true
    errorMessage = nil
    defer { isLoadingPhoto = false }

    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        errorMessage = "Could not read selected image."
        return
      }
      guard let image = UIImage(data: data) else {
        errorMessage = "Could not prepare selected image."
        return
      }
      imageToCrop = image.normalizedForProfileCrop()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - Save

  private func save() {
    if let problem = validate() {
      validationMessage = problem
      return
    }
    validationMessage = nil
    errorMessage = nil
    isSaving = true

    Task {
      defer { isSaving = false }
      do {
        var newPhotoStorageId: String?
        if let pendingPhotoData {
          guard let token = authStore.currentSession?.token else {
            throw AuthStoreError.sessionNotAvailable
          }
          newPhotoStorageId = try await HRConvexAPIService.uploadPhoto(token: token, imageData: pendingPhotoData)
        }
        _ = try await authStore.updateProfile(
          name: trimmedName,
          email: trimmedEmail.isEmpty ? nil : trimmedEmail,
          phone: trimmedPhone,
          photoStorageId: nil
        )
        if let newPhotoStorageId {
          _ = try await authStore.setProfilePhoto(storageId: newPhotoStorageId)
        } else if pendingPhotoRemoved {
          _ = try await authStore.deleteProfilePhoto()
        }
        _ = try? await authStore.refreshMyStaffProfile()
        onSaved?()
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}

#Preview {
  NavigationStack {
    ProfileEditView()
      .environment(AuthStore())
  }
}
