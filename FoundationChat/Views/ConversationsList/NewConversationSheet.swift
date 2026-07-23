import SwiftUI

struct NewConversationSheet: View {
  enum SelectionMode {
    case direct
    case group
  }

  private enum FocusedField: Hashable {
    case groupName
  }

  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let mode: SelectionMode
  let onSelectUser: (DirectoryUser) async throws -> Void
  let onCreateGroup: ([DirectoryUser], String?) async throws -> Void

  init(
    initialMode: SelectionMode = .direct,
    onSelectUser: @escaping (DirectoryUser) async throws -> Void,
    onCreateGroup: @escaping ([DirectoryUser], String?) async throws -> Void = { _, _ in }
  ) {
    mode = initialMode
    self.onSelectUser = onSelectUser
    self.onCreateGroup = onCreateGroup
  }

  @State private var searchText = ""
  @State private var groupName = ""
  @State private var users: [DirectoryUser] = []
  @State private var selectedUsers: [DirectoryUser] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var isSubmitting = false
  @FocusState private var focusedField: FocusedField?

  private var isGroupMode: Bool {
    switch mode {
    case .direct: false
    case .group: true
    }
  }

  private var trimmedGroupName: String {
    groupName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canStart: Bool {
    if isGroupMode {
      return selectedUsers.count >= 2 && !trimmedGroupName.isEmpty
    }
    return selectedUsers.count == 1
  }

  private var actionTitle: String {
    if isSubmitting {
      return isGroupMode ? "Creating..." : "Starting..."
    }

    if isGroupMode {
      return "Create"
    }

    return "Start Conversation"
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(spacing: 12) {
          if isGroupMode {
            groupModeHeader
          }

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
      .searchable(
        text: $searchText,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Search by name or email"
      )
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
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
    .presentationDragIndicator(.hidden)
    .appFormActivity()
  }

  private var groupModeHeader: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Image(systemName: "person.3.fill")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 42, height: 42)
          .background(
            LinearGradient(
              colors: [FoundationChatTheme.headerAccent, FoundationChatTheme.outgoingBubble],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            in: Circle()
          )

        VStack(alignment: .leading, spacing: 3) {
          Text("Group details")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(FoundationChatTheme.ink)
          Text(selectedUsers.count < 2 ? "Name the group and select at least 2 people" : "\(selectedUsers.count) people selected")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("Group name")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.secondary)

        HStack(spacing: 10) {
          Image(systemName: "person.3")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(FoundationChatTheme.outgoingBubble)

          TextField("Enter group name", text: $groupName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(FoundationChatTheme.ink)
            .textInputAutocapitalization(.words)
            .submitLabel(.next)
            .focused($focusedField, equals: .groupName)
            .onSubmit { focusedField = nil }

          if !groupName.isEmpty {
            Button {
              groupName = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.secondary.opacity(0.65))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(
              focusedField == .groupName ? FoundationChatTheme.outgoingBubble : Color.black.opacity(0.10),
              lineWidth: focusedField == .groupName ? 1.5 : 1
            )
        }
        .shadow(color: Color.black.opacity(0.035), radius: 5, y: 2)
      }
    }
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
            ConversationAvatarView(
              initials: initials(for: user.displayName),
              source: user.imageUrl,
              size: 44
            )

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
              ConversationAvatarView(
                initials: initials(for: user.displayName),
                source: user.imageUrl,
                size: 22
              )

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
      if isGroupMode {
        guard selectedUsers.count >= 2 else {
          errorMessage = "Select at least 2 members"
          isSubmitting = false
          return
        }
        guard !trimmedGroupName.isEmpty else {
          errorMessage = "Give the group a name"
          isSubmitting = false
          return
        }
        try await onCreateGroup(selectedUsers, trimmedGroupName)
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
