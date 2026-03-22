import PhotosUI
import SwiftUI

struct ProfileView: View {
  @Environment(AuthStore.self) private var authStore

  @State private var selectedPhotoItem: PhotosPickerItem?
  @AppStorage("profile_photo_base64") private var profilePhotoBase64 = ""
  @AppStorage("notifications_enabled") private var notificationsEnabled = true
  @AppStorage("notification_sounds_enabled") private var notificationSoundsEnabled = true
  @AppStorage("mention_notifications_enabled") private var mentionNotificationsEnabled = true

  private var profileImage: UIImage? {
    guard let data = Data(base64Encoded: profilePhotoBase64) else { return nil }
    return UIImage(data: data)
  }

  var body: some View {
    List {
      Section {
        HStack(spacing: 16) {
          PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ProfileHeroAvatar(label: authStore.currentUserLabel, image: profileImage)
              .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                  .font(.caption2.weight(.bold))
                  .foregroundStyle(.white)
                  .frame(width: 22, height: 22)
                  .background(Color.blue, in: Circle())
              }
          }
          .buttonStyle(.plain)

          VStack(alignment: .leading, spacing: 4) {
            Text(authStore.currentUserLabel ?? "Manjugroups Member")
              .font(.headline)
            Text("Authenticated workspace access")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 8)
      }

      Section("Account") {
        LabeledContent("Phone", value: authStore.currentUserLabel ?? "Unavailable")

        if let subject = authStore.viewer?.subject {
          LabeledContent("User ID", value: subject)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      Section("Notifications") {
        Toggle("Enable notifications", isOn: $notificationsEnabled)
        Toggle("Sounds", isOn: $notificationSoundsEnabled)
          .disabled(!notificationsEnabled)
        Toggle("Mentions only", isOn: $mentionNotificationsEnabled)
          .disabled(!notificationsEnabled)
      }

      Section {
        Button(role: .destructive) {
          Task {
            await authStore.logout()
          }
        } label: {
          Text("Log Out")
            .frame(maxWidth: .infinity, alignment: .center)
        }
      }
    }
    .navigationTitle("Profile")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: selectedPhotoItem) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          profilePhotoBase64 = data.base64EncodedString()
        }
      }
    }
  }
}

private struct ProfileHeroAvatar: View {
  let label: String?
  let image: UIImage?

  private var initials: String {
    guard let label, !label.isEmpty else { return "MG" }
    let parts = label
      .split(whereSeparator: { !$0.isLetter })
      .prefix(2)
      .compactMap(\.first)

    let result = String(parts).uppercased()
    return result.isEmpty ? "MG" : result
  }

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Text(initials)
          .font(.title3.weight(.bold))
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
    }
    .frame(width: 64, height: 64)
    .clipShape(Circle())
  }
}

#Preview {
  NavigationStack {
    ProfileView()
      .environment(AuthStore())
  }
}
