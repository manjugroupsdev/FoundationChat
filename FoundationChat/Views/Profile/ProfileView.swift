import SwiftUI

struct ProfileView: View {
  @Environment(AuthStore.self) private var authStore

  @AppStorage("notifications_enabled") private var notificationsEnabled = true
  @AppStorage("notification_sounds_enabled") private var notificationSoundsEnabled = true
  @AppStorage("mention_notifications_enabled") private var mentionNotificationsEnabled = true
  @AppStorage("app.language") private var languagePreference = ProfileLanguage.english.rawValue
  @AppStorage("app.appearance") private var appearancePreference = ProfileAppearance.system.rawValue

  @State private var remotePhotoURL: URL?
  @State private var isPresentingEdit = false
  @State private var isPresentingLanguage = false
  @State private var isPresentingAppearance = false
  @State private var isConfirmingLogout = false
  @State private var hasLoadedStaffProfile = false

  private var selectedLanguage: ProfileLanguage {
    ProfileLanguage(rawValue: languagePreference) ?? .english
  }

  private var selectedAppearance: ProfileAppearance {
    ProfileAppearance(rawValue: appearancePreference) ?? .system
  }

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

      Section("Preferences") {
        Button {
          isPresentingLanguage = true
        } label: {
          SettingsDisclosureRow(
            title: "Language",
            value: selectedLanguage.title,
            systemImage: "globe"
          )
        }
        .buttonStyle(.plain)

        Button {
          isPresentingAppearance = true
        } label: {
          SettingsDisclosureRow(
            title: "Appearance",
            value: selectedAppearance.title,
            systemImage: selectedAppearance.systemImage
          )
        }
        .buttonStyle(.plain)
      }

      Section {
        Button(role: .destructive) {
          isConfirmingLogout = true
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
    .sheet(isPresented: $isPresentingLanguage) {
      NavigationStack {
        LanguageSettingsView(selection: $languagePreference)
      }
    }
    .sheet(isPresented: $isPresentingAppearance) {
      NavigationStack {
        AppearanceSettingsView(selection: $appearancePreference)
      }
    }
    .confirmationDialog(
      "Log out of FoundationChat?",
      isPresented: $isConfirmingLogout,
      titleVisibility: .visible
    ) {
      Button("Log Out", role: .destructive) {
        Task {
          await authStore.logout()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your local session will be cleared and you will return to Login.")
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

enum ProfileLanguage: String, CaseIterable, Identifiable {
  case english = "en"
  case tamil = "ta"
  case hindi = "hi"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .english: return "English"
    case .tamil: return "Tamil"
    case .hindi: return "Hindi"
    }
  }

  var subtitle: String {
    switch self {
    case .english: return "Default app language"
    case .tamil: return "தமிழ்"
    case .hindi: return "हिन्दी"
    }
  }
}

enum ProfileAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }

  var subtitle: String {
    switch self {
    case .system: return "Follow device setting"
    case .light: return "Use light mode"
    case .dark: return "Use dark mode"
    }
  }

  var systemImage: String {
    switch self {
    case .system: return "circle.lefthalf.filled"
    case .light: return "sun.max"
    case .dark: return "moon"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}

private struct SettingsDisclosureRow: View {
  let title: String
  let value: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.body.weight(.semibold))
        .foregroundStyle(.blue)
        .frame(width: 26)

      Text(title)
        .foregroundStyle(.primary)

      Spacer()

      Text(value)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
  }
}

private struct LanguageSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: String

  var body: some View {
    List {
      Section {
        ForEach(ProfileLanguage.allCases) { language in
          Button {
            selection = language.rawValue
            dismiss()
          } label: {
            PreferenceOptionRow(
              title: language.title,
              subtitle: language.subtitle,
              systemImage: "globe",
              isSelected: selection == language.rawValue
            )
          }
          .buttonStyle(.plain)
        }
      } footer: {
        Text("The selected language is saved for the app session and future localized screens.")
      }
    }
    .navigationTitle("Language")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") { dismiss() }
      }
    }
  }
}

private struct AppearanceSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: String

  var body: some View {
    List {
      Section {
        ForEach(ProfileAppearance.allCases) { appearance in
          Button {
            selection = appearance.rawValue
            dismiss()
          } label: {
            PreferenceOptionRow(
              title: appearance.title,
              subtitle: appearance.subtitle,
              systemImage: appearance.systemImage,
              isSelected: selection == appearance.rawValue
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
    .navigationTitle("Appearance")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") { dismiss() }
      }
    }
  }
}

private struct PreferenceOptionRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.body.weight(.semibold))
        .foregroundStyle(.blue)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .foregroundStyle(.primary)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.blue)
      }
    }
    .contentShape(Rectangle())
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
