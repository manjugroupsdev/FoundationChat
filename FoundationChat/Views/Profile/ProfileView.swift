import SwiftUI

struct ProfileView: View {
  @Environment(AuthStore.self) private var authStore

  @AppStorage("notifications_enabled") private var notificationsEnabled = true
  @AppStorage("notification_sounds_enabled") private var notificationSoundsEnabled = true
  @AppStorage("mention_notifications_enabled") private var mentionNotificationsEnabled = true

  @State private var remotePhotoURL: URL?
  @State private var isPresentingEdit = false

  var body: some View {
    List {
      Section {
        HStack(spacing: 16) {
          ProfileHeroAvatar(label: authStore.currentUserLabel, photoURL: remotePhotoURL)

          VStack(alignment: .leading, spacing: 4) {
            Text(authStore.currentUserLabel ?? "Manjugroups Member")
              .font(.headline)
            Text("Authenticated workspace access")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button {
            isPresentingEdit = true
          } label: {
            Image(systemName: "pencil")
              .font(.body.weight(.semibold))
              .foregroundStyle(.white)
              .frame(width: 32, height: 32)
              .background(Color.blue, in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Edit profile")
        }
        .padding(.vertical, 8)
      }

      Section("Account") {
        if let name = authStore.viewer?.name, !name.isEmpty {
          LabeledContent("Name", value: name)
        }
        if let email = authStore.viewer?.email, !email.isEmpty {
          LabeledContent("Email", value: email)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        LabeledContent("Phone", value: authStore.viewer?.phone ?? authStore.currentUserLabel ?? "Unavailable")

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
    .task(id: authStore.viewer?.photo) {
      await loadRemoteAvatar()
    }
    .sheet(isPresented: $isPresentingEdit) {
      NavigationStack {
        ProfileEditView(onSaved: {
          Task { await loadRemoteAvatar() }
        })
      }
    }
  }

  private func loadRemoteAvatar() async {
    guard let storageId = authStore.viewer?.photo, !storageId.isEmpty else {
      remotePhotoURL = nil
      return
    }
    remotePhotoURL = try? await authStore.resolveStorageURL(storageId: storageId)
  }
}

private struct ProfileHeroAvatar: View {
  let label: String?
  let photoURL: URL?

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
      if let photoURL {
        AsyncImage(url: photoURL) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFill()
          case .failure:
            initialsBackground
          default:
            ProgressView()
          }
        }
      } else {
        initialsBackground
      }
    }
    .frame(width: 64, height: 64)
    .clipShape(Circle())
  }

  private var initialsBackground: some View {
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

#Preview {
  NavigationStack {
    ProfileView()
      .environment(AuthStore())
  }
}
