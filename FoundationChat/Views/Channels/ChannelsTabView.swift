import Combine
import SwiftUI

struct ChannelsTabView: View {
  private enum ChannelFilter: String, CaseIterable, Identifiable {
    case all
    case created
    case manageable

    var id: String { rawValue }

    var title: String {
      switch self {
      case .all:
        return "All"
      case .created:
        return "Created"
      case .manageable:
        return "Manage"
      }
    }
  }

  @Environment(AuthStore.self) private var authStore

  let openChannelID: String?
  let onOpenChannelHandled: () -> Void

  @State private var channels: [ChannelSummary] = []
  @State private var navigationPath: [String] = []
  @State private var searchText = ""
  @State private var selectedFilter: ChannelFilter = .all
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var isCreateSheetPresented = false

  private var visibleChannels: [ChannelSummary] {
    let sorted = channels.sorted { $0.lastMessageAt > $1.lastMessageAt }

    switch selectedFilter {
    case .all:
      return sorted
    case .created:
      guard let currentUser = authStore.viewer?.subject else { return [] }
      return sorted.filter { $0.createdByStackUserId == currentUser }
    case .manageable:
      return sorted.filter(\.canManage)
    }
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      VStack(spacing: 10) {
        GlassSearchField(placeholder: "Search channels", text: $searchText)
          .padding(.horizontal, 16)
          .padding(.top, 8)

        filtersBar
          .padding(.horizontal, 16)

        if isLoading, channels.isEmpty {
          ProgressView("Loading channels...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
          ContentUnavailableView(
            "Could Not Load Channels",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleChannels.isEmpty {
          ContentUnavailableView(
            "No channels yet",
            systemImage: "person.3"
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(visibleChannels) { channel in
            NavigationLink(value: channel.id) {
              VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                  .font(.body.weight(.semibold))

                if let description = channel.description, !description.isEmpty {
                  Text(channel.lastMessageContent ?? description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                } else if let lastMessageContent = channel.lastMessageContent,
                  !lastMessageContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                  Text(lastMessageContent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                } else {
                  Text("No messages yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .padding(.vertical, 4)
            }
          }
          .listStyle(.plain)
        }
      }
      .navigationDestination(for: String.self) { channelID in
        ChannelChatView(channel: channelSummary(for: channelID))
      }
      .navigationTitle("Channels")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if authStore.isAdmin {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button {
              isCreateSheetPresented = true
            } label: {
              Image(systemName: "plus")
            }
          }
        }
      }
      .sheet(isPresented: $isCreateSheetPresented) {
        CreateChannelSheet {
          await loadChannels()
        }
      }
      .task(id: "\(searchText)-\(selectedFilter.rawValue)") {
        await loadChannels()
      }
      .task(id: openChannelID) {
        guard let openChannelID else { return }
        await openChannelFromPush(channelID: openChannelID)
        onOpenChannelHandled()
      }
    }
  }

  private var filtersBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(ChannelFilter.allCases) { filter in
          Button {
            selectedFilter = filter
          } label: {
            Text(filter.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(selectedFilter == filter ? .white : .primary)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(
                selectedFilter == filter
                  ? Color.blue
                  : Color(.systemGray5),
                in: Capsule()
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @MainActor
  private func loadChannels() async {
    isLoading = true
    errorMessage = nil

    do {
      channels = try await authStore.fetchChannels(search: searchText)
    } catch {
      channels = []
      errorMessage = error.localizedDescription
    }

    isLoading = false
  }

  private func channelSummary(for channelID: String) -> ChannelSummary {
    if let existing = channels.first(where: { $0.id == channelID }) {
      return existing
    }
    let now = Date().timeIntervalSince1970 * 1000
    return ChannelSummary(
      id: channelID,
      name: "Channel",
      description: nil,
      memberCount: 0,
      lastMessageContent: nil,
      lastMessageAt: now,
      createdByStackUserId: "",
      myRole: "member",
      canManage: false,
      createdAt: now,
      updatedAt: now
    )
  }

  @MainActor
  private func openChannelFromPush(channelID: String) async {
    selectedFilter = .all
    if channels.first(where: { $0.id == channelID }) == nil {
      await loadChannels()
    }
    navigationPath = [channelID]
  }
}

struct ChannelChatView: View {
  @Environment(AuthStore.self) private var authStore
  let channel: ChannelSummary

  @State private var newMessage = ""
  @State private var messages: [ChannelChatMessage] = []
  @State private var errorMessage: String?
  @State private var isInviteSheetPresented = false
  @State private var isSendingMessage = false
  @State private var messagesSubscription: AnyCancellable?
  @FocusState private var isInputFocused: Bool

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 8) {
          if messages.isEmpty {
            ContentUnavailableView(
              "No messages yet",
              systemImage: "message",
              description: Text("Start the conversation in #\(channel.name).")
            )
            .padding(.top, 40)
          } else {
            ForEach(messages) { message in
              ChannelMessageRow(
                message: message,
                isMine: message.senderStackUserId == authStore.viewer?.subject
              )
              .id(message.id)
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 56)
      }
      .onChange(of: messages.map(\.id)) { _, messageIDs in
        guard let lastID = messageIDs.last else { return }
        withAnimation(.snappy) {
          proxy.scrollTo(lastID, anchor: .bottom)
        }
      }
    }
    .navigationTitle("#\(channel.name)")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if authStore.isAdmin {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            isInviteSheetPresented = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }

      ConversationDetailInputView(
        newMessage: $newMessage,
        isGenerating: $isSendingMessage,
        isInputFocused: $isInputFocused,
        onAddAttachment: {
          errorMessage = "Channel attachments are coming soon."
        },
        onSend: {
          await sendMessage()
        }
      )
    }
    .overlay(alignment: .top) {
      if let errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule())
          .padding(.top, 6)
      }
    }
    .sheet(isPresented: $isInviteSheetPresented) {
      InviteMemberSheet(channelID: channel.id) {
        startMessagesSubscription()
      }
    }
    .onAppear {
      startMessagesSubscription()
      isInputFocused = true
    }
    .onDisappear {
      messagesSubscription?.cancel()
      messagesSubscription = nil
    }
    .toolbar(.hidden, for: .tabBar)
  }

  @MainActor
  private func startMessagesSubscription() {
    messagesSubscription?.cancel()
    do {
      messagesSubscription = try authStore
        .subscribeChannelMessages(channelID: channel.id)
        .receive(on: DispatchQueue.main)
        .sink(
          receiveCompletion: { completion in
            guard case .failure = completion else { return }
            Task { @MainActor in
              try? await Task.sleep(for: .seconds(1))
              startMessagesSubscription()
            }
          },
          receiveValue: { remoteMessages in
            messages = (remoteMessages ?? []).sorted(by: { $0.createdAt < $1.createdAt })
          }
        )
    } catch {
      messagesSubscription = nil
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        startMessagesSubscription()
      }
    }
  }

  @MainActor
  private func sendMessage() async {
    let trimmed = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    isSendingMessage = true
    errorMessage = nil
    defer { isSendingMessage = false }

    do {
      _ = try await authStore.sendChannelMessage(channelID: channel.id, content: trimmed)
      newMessage = ""
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct ChannelMessageRow: View {
  let message: ChannelChatMessage
  let isMine: Bool

  var body: some View {
    VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
      if !isMine {
        Text(message.senderName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      Text(message.content)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(isMine ? .white : .primary)
        .background(
          isMine ? Color.blue : Color(.systemGray5),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )

      Text(message.createdDate.formatted(date: .omitted, time: .shortened))
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    .padding(.vertical, 2)
  }
}

struct CreateChannelSheet: View {
  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let onCreated: () async -> Void

  @State private var name = ""
  @State private var description = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("New Channel") {
          TextField("Channel name", text: $name)
          TextField("Description (optional)", text: $description, axis: .vertical)
            .lineLimit(3, reservesSpace: true)
        }

        if let errorMessage {
          Section {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Create Channel")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isSubmitting ? "Creating..." : "Create") {
            Task {
              await create()
            }
          }
          .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  @MainActor
  private func create() async {
    isSubmitting = true
    errorMessage = nil
    defer { isSubmitting = false }

    do {
      _ = try await authStore.createChannel(name: name, description: description)
      await onCreated()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct InviteMemberSheet: View {
  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let channelID: String
  let onInvited: () async -> Void

  @State private var searchText = ""
  @State private var users: [DirectoryUser] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var invitingUserID: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField("Search users", text: $searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)

        if isLoading, users.isEmpty {
          ProgressView("Loading users...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
          ContentUnavailableView(
            "Could Not Load Users",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if users.isEmpty {
          ContentUnavailableView("No users found", systemImage: "person.2")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(users) { user in
            Button {
              Task { await invite(user) }
            } label: {
              HStack {
                Text(user.displayName)
                  .foregroundStyle(.primary)
                Spacer()
                if invitingUserID == user.id {
                  ProgressView()
                }
              }
            }
            .buttonStyle(.plain)
            .disabled(invitingUserID != nil)
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Invite Member")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            dismiss()
          }
        }
      }
      .task(id: searchText) {
        await loadUsers()
      }
    }
  }

  @MainActor
  private func loadUsers() async {
    isLoading = true
    errorMessage = nil
    do {
      users = try await authStore.fetchDirectoryUsers(search: searchText)
    } catch {
      users = []
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  @MainActor
  private func invite(_ user: DirectoryUser) async {
    invitingUserID = user.id
    errorMessage = nil
    defer { invitingUserID = nil }

    do {
      _ = try await authStore.inviteMember(
        channelID: channelID,
        memberStackUserID: user.stackUserId
      )
      await onInvited()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview {
  ChannelsTabView(openChannelID: nil, onOpenChannelHandled: {})
    .environment(AuthStore())
}
