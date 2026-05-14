import SwiftUI

struct NewConversationSheet: View {
  enum SelectionMode {
    case direct
    case group
  }

  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let onSelectUser: (DirectoryUser) async throws -> Void
  let onCreateGroup: ([DirectoryUser], String?) async throws -> Void
  let onCreateChannel: (() -> Void)?

  init(
    initialMode: SelectionMode = .direct,
    onSelectUser: @escaping (DirectoryUser) async throws -> Void,
    onCreateGroup: @escaping ([DirectoryUser], String?) async throws -> Void = { _, _ in },
    onCreateChannel: (() -> Void)? = nil
  ) {
    self.onSelectUser = onSelectUser
    self.onCreateGroup = onCreateGroup
    self.onCreateChannel = onCreateChannel
    _isGroupMode = State(initialValue: initialMode == .group)
  }

  @State private var searchText = ""
  @State private var groupName = ""
  @State private var users: [DirectoryUser] = []
  @State private var selectedUsers: [DirectoryUser] = []
  @State private var isGroupMode = false
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var isSubmitting = false

  private var canStart: Bool {
    selectedUsers.count >= 1
  }

  private var actionTitle: String {
    if isSubmitting {
      return isGroupMode && selectedUsers.count > 1 ? "Creating..." : "Starting..."
    }

    if isGroupMode && selectedUsers.count > 1 {
      return "Create Group"
    }

    return "Start Conversation"
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(spacing: 12) {
          if isGroupMode {
            groupModeHeader
          } else {
            createGroupEntry
          }

          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)

            TextField("Search people", text: $searchText)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()

            if !searchText.isEmpty {
              Button {
                searchText = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 12)
          .frame(height: 46)
          .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

          if isGroupMode, !selectedUsers.isEmpty {
            selectedPeopleStrip
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)

        Divider()

        content
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .navigationTitle(isGroupMode ? "Create Group" : "New Chat")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(actionTitle) {
            Task {
              await start()
            }
          }
          .disabled(!canStart || isSubmitting)
        }
      }
      .task(id: searchText) {
        await loadUsers(search: searchText)
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }

  private var groupModeHeader: some View {
    VStack(spacing: 10) {
      HStack(spacing: 12) {
        Image(systemName: "person.3.fill")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 36, height: 36)
          .background(FoundationChatTheme.outgoingBubble, in: Circle())

        VStack(alignment: .leading, spacing: 2) {
          Text(selectedUsers.count <= 1 ? "Select people" : "\(selectedUsers.count) selected")
            .font(.system(size: 15, weight: .semibold))
          Text(selectedUsers.count <= 1 ? "Choose one for a DM or more for a group" : "Add or remove people below")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      if selectedUsers.count > 1 {
        TextField("Group name (optional)", text: $groupName)
          .font(.system(size: 15, weight: .regular))
          .textInputAutocapitalization(.words)
          .padding(.horizontal, 12)
          .frame(height: 44)
          .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
  }

  private var createGroupEntry: some View {
    Button {
      withAnimation(.snappy) {
        isGroupMode = true
        selectedUsers.removeAll()
      }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "person.3.fill")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
          .background(FoundationChatTheme.outgoingBubble, in: Circle())

        VStack(alignment: .leading, spacing: 2) {
          Text("Create Group")
            .font(.system(size: 15, weight: .semibold))
          Text("Select multiple people")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .foregroundStyle(.primary)
      .padding(.vertical, 2)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var content: some View {
    if isLoading, users.isEmpty {
      ProgressView("Loading people...")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    } else if let errorMessage {
      ContentUnavailableView(
        "Could Not Load People",
        systemImage: "exclamationmark.triangle",
        description: Text(errorMessage)
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if users.isEmpty {
      ContentUnavailableView(
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No people found" : "No matching people",
        systemImage: "person.2"
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List(users) { user in
        Button {
          toggle(user)
        } label: {
          HStack(spacing: 12) {
            AvatarPlaceholder(initials: initials(for: user.displayName))
              .frame(width: 44, height: 44)
              .scaleEffect(44 / 52)

            VStack(alignment: .leading, spacing: 2) {
              Text(user.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

              Text(user.email?.isEmpty == false ? user.email! : "Tap to start a conversation")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Image(systemName: isSelected(user) ? "checkmark.circle.fill" : (isGroupMode ? "circle" : "chevron.right"))
              .font(.system(size: isGroupMode ? 22 : 14, weight: .semibold))
              .foregroundStyle(isSelected(user) ? FoundationChatTheme.outgoingBubble : Color.secondary.opacity(0.55))
          }
          .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
    }
  }

  private var selectedPeopleStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(selectedUsers) { user in
          Button {
            toggle(user)
          } label: {
            HStack(spacing: 6) {
              Text(user.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(FoundationChatTheme.outgoingBubble)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.white, in: Capsule())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @MainActor
  private func loadUsers(search: String) async {
    let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)

    if !trimmed.isEmpty {
      try? await Task.sleep(for: .milliseconds(250))
    }

    guard !Task.isCancelled else { return }

    isLoading = true
    errorMessage = nil

    do {
      users = try await authStore.fetchDirectoryUsers(search: trimmed)
    } catch {
      errorMessage = error.localizedDescription
      users = []
    }

    isLoading = false
  }

  private func toggle(_ user: DirectoryUser) {
    if !isGroupMode {
      selectedUsers = [user]
      return
    }

    if let index = selectedUsers.firstIndex(where: { $0.id == user.id }) {
      selectedUsers.remove(at: index)
    } else {
      selectedUsers.append(user)
    }
  }

  private func isSelected(_ user: DirectoryUser) -> Bool {
    selectedUsers.contains(where: { $0.id == user.id })
  }

  @MainActor
  private func start() async {
    guard canStart else { return }
    isSubmitting = true
    errorMessage = nil

    do {
      if isGroupMode, selectedUsers.count > 1 {
        try await onCreateGroup(
          selectedUsers,
          groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : groupName
        )
      } else if let user = selectedUsers.first {
        try await onSelectUser(user)
      }
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }

    isSubmitting = false
  }

  private func initials(for name: String) -> String {
    let parts = name.split(whereSeparator: { !$0.isLetter }).prefix(2)
    let initials = String(parts.compactMap(\.first)).uppercased()
    return initials.isEmpty ? "U" : initials
  }
}
