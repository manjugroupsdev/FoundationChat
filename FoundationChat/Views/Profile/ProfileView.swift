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
  @State private var isConfirmingLogout = false
  @State private var hasLoadedStaffProfile = false

  private var selectedLanguage: ProfileLanguage {
    ProfileLanguage(rawValue: languagePreference) ?? .english
  }

  private var selectedAppearance: ProfileAppearance {
    ProfileAppearance(rawValue: appearancePreference) ?? .system
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        ProfileInfoHeader(
          label: authStore.currentUserLabel,
          photoURL: remotePhotoURL,
          phone: authStore.viewer?.phone ?? authStore.currentUserLabel
        )

        VStack(spacing: 0) {
          Button {
            isPresentingEdit = true
          } label: {
            ProfileMenuRow(title: "Edit Profile", systemImage: "square.and.pencil")
          }
          .buttonStyle(.plain)

          ProfileDivider()

          NavigationLink {
            AppearanceSettingsView(selection: $appearancePreference)
          } label: {
            ProfileMenuRow(
              title: "Appearance",
              value: selectedAppearance.title,
              systemImage: "circle.lefthalf.filled"
            )
          }
          .buttonStyle(.plain)

          ProfileDivider()

          NavigationLink {
            LanguageSettingsView(selection: $languagePreference)
          } label: {
            ProfileMenuRow(
              title: "Language",
              value: selectedLanguage.title,
              systemImage: "globe"
            )
          }
          .buttonStyle(.plain)

          ProfileDivider()

          HStack(spacing: 16) {
            Image(systemName: "bell")
              .font(.system(size: 21, weight: .medium))
              .foregroundStyle(Color(hex: 0x6B7280))
              .frame(width: 24)

            Text("Manage Notification")
              .font(.system(size: 18, weight: .regular))
              .foregroundStyle(Color(hex: 0x6B7280))

            Spacer()

            Toggle("", isOn: $notificationsEnabled)
              .labelsHidden()
              .tint(Color(hex: 0x0B61CA))
          }
          .frame(height: 56)
          .contentShape(Rectangle())

          ProfileDivider()

          ProfileMenuRow(
            title: "App Version",
            value: appVersionText,
            systemImage: "info.circle",
            showsChevron: false
          )

          ProfileDivider()

          Button(role: .destructive) {
            isConfirmingLogout = true
          } label: {
            ProfileMenuRow(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right", showsChevron: false)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 16)
      .padding(.bottom, 40)
    }
    .background(Color.appScreenBackground.ignoresSafeArea())
    .navigationTitle("Profile Overview")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
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
      .appLibraryNativeSheet([.height(690), .large])
      .presentationBackground(Color.appSurface)
    }
    .sheet(isPresented: $isConfirmingLogout) {
      LogoutConfirmationSheet {
        isConfirmingLogout = false
      } onLogout: {
        Task {
          await authStore.logout()
        }
      }
      .presentationDetents([.height(270)])
      .presentationDragIndicator(.hidden)
    }
  }

  private func loadRemoteAvatar() async {
    remotePhotoURL = await authStore.resolveProfilePhotoURL(authStore.viewer?.photo)
  }

  private func refreshStaffProfile() async {
    hasLoadedStaffProfile = true
    _ = try? await authStore.refreshMyStaffProfile()
    await loadRemoteAvatar()
  }

  private var appVersionText: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    if let version, !version.isEmpty {
      return build?.isEmpty == false ? "v.\(version)" : "v.\(version)"
    }
    return build?.isEmpty == false ? "v.\(build!)" : "v.1.0"
  }
}

struct LogoutConfirmationSheet: View {
  let onCancel: () -> Void
  let onLogout: () -> Void

  var body: some View {
    VStack(spacing: 18) {
      VStack(spacing: 10) {
        Image(systemName: "rectangle.portrait.and.arrow.right")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(Color(hex: 0xFF3B30))
          .frame(width: 56, height: 56)
          .background(Color(hex: 0xFFECEC), in: Circle())

        Text("Log out of FoundationChat?")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(Color(hex: 0x101828))
          .multilineTextAlignment(.center)

        Text("Your local session will be cleared and you will return to Login.")
          .font(.system(size: 15))
          .foregroundStyle(Color(hex: 0x667085))
          .multilineTextAlignment(.center)
          .lineSpacing(2)
      }

      VStack(spacing: 10) {
        Button(role: .destructive) {
          onLogout()
        } label: {
          Text("Log Out")
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Color(hex: 0xFF3B30))

        Button {
          onCancel()
        } label: {
          Text("Cancel")
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color(hex: 0x667085))
      }
    }
    .padding(.horizontal, 24)
    .padding(.top, 18)
    .padding(.bottom, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.appScreenBackground.ignoresSafeArea())
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

private struct ProfileMenuRow: View {
  let title: String
  var value: String? = nil
  let systemImage: String
  var showsChevron = true

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: systemImage)
        .font(.system(size: 21, weight: .medium))
        .foregroundStyle(Color(hex: 0x6B7280))
        .frame(width: 24)

      Text(title)
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(Color(hex: 0x6B7280))

      Spacer(minLength: 12)

      if let value, !value.isEmpty {
        Text(value)
          .font(.system(size: 14, weight: .regular))
          .foregroundStyle(Color(hex: 0x6B7280))
          .lineLimit(1)
      }

      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color(hex: 0x6B7280))
      }
    }
    .frame(height: 56)
    .contentShape(Rectangle())
  }
}

private struct ProfileDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color(hex: 0xF2F4F7))
      .frame(height: 1)
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
    case .system: return "Match the device setting"
    case .light: return "Always use the light theme"
    case .dark: return "Always use the dark theme"
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
      }
    }
    .navigationTitle("Language")
    .navigationBarTitleDisplayMode(.inline)
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
  let phone: String?

  private var displayName: String {
    guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return "Manjugroups Member"
    }
    return label
  }

  private var phoneText: String {
    let trimmed = phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "—" : trimmed
  }

  var body: some View {
    VStack(spacing: 4) {
      ProfileHeroAvatar(label: label, photoURL: photoURL, size: 140)
        .padding(.bottom, 0)

      Text(displayName)
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(Color(hex: 0x1F2A37))
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.82)

      Text(phoneText)
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(Color(hex: 0x6B7280))
        .multilineTextAlignment(.center)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
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
      .foregroundStyle(Color(hex: 0x0B61CA))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(hex: 0xEAF3FF))
  }
}

#Preview {
  NavigationStack {
    ProfileView()
      .environment(AuthStore())
  }
}
