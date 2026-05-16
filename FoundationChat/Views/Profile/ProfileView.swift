import SwiftUI

struct ProfileView: View {
  @Environment(AuthStore.self) private var authStore

  @AppStorage("notifications_enabled") private var notificationsEnabled = true
  @AppStorage("notification_sounds_enabled") private var notificationSoundsEnabled = true
  @AppStorage("mention_notifications_enabled") private var mentionNotificationsEnabled = true

  @State private var remotePhotoURL: URL?
  @State private var isPresentingEdit = false
  @State private var hasLoadedStaffProfile = false

  var body: some View {
    List {
      Section {
        ProfileInfoHeader(
          label: authStore.currentUserLabel,
          photoURL: remotePhotoURL,
          designation: authStore.currentSession?.user.designation,
          department: authStore.currentSession?.user.department,
          status: authStore.currentSession?.user.status
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.white)
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
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          isPresentingEdit = true
        } label: {
          Image(systemName: "pencil")
        }
        .accessibilityLabel("Edit profile")
      }
    }
    .task(id: authStore.viewer?.photo) {
      await loadRemoteAvatar()
    }
    .task {
      if !hasLoadedStaffProfile {
        await refreshStaffProfile()
      }
    }
    .sheet(isPresented: $isPresentingEdit) {
      NavigationStack {
        ProfileEditView(onSaved: {
          Task { await refreshStaffProfile() }
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

  private func refreshStaffProfile() async {
    hasLoadedStaffProfile = true
    _ = try? await authStore.refreshMyStaffProfile()
    await loadRemoteAvatar()
  }
}

private struct ProfileInfoHeader: View {
  let label: String?
  let photoURL: URL?
  let designation: String?
  let department: String?
  let status: String?

  private var displayName: String {
    guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return "Manjugroups Member"
    }
    return label
  }

  private var subtitle: String {
    [designation, department]
      .compactMap { value in
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
      }
      .joined(separator: " · ")
  }

  private var normalizedStatus: String {
    let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "Active" : trimmed.capitalized
  }

  private var isActive: Bool {
    normalizedStatus.localizedCaseInsensitiveContains("active")
      && !normalizedStatus.localizedCaseInsensitiveContains("inactive")
  }

  var body: some View {
    VStack(spacing: 16) {
      ProfileHeroAvatar(label: label, photoURL: photoURL, size: 104)

      VStack(spacing: 10) {
        Text(displayName.uppercased())
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(Color.black)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .minimumScaleFactor(0.78)

        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Color.gray)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }

        Text(normalizedStatus)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(isActive ? Color.green : Color.red)
          .padding(.horizontal, 18)
          .padding(.vertical, 7)
          .background((isActive ? Color.green : Color.red).opacity(0.16), in: Capsule())
      }
    }
    .padding(.horizontal, 24)
  }
}

private struct ProfileHeroAvatar: View {
  let label: String?
  let photoURL: URL?
  var size: CGFloat = 64

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
    .frame(width: size, height: size)
    .clipShape(Circle())
  }

  private var initialsBackground: some View {
    Text(initials)
      .font(.system(size: size * 0.38, weight: .bold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        LinearGradient(
          colors: [
            Color(red: 0.24, green: 0.06, blue: 0.32),
            Color(red: 0.47, green: 0.12, blue: 0.52)
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
