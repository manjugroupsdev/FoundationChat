import Combine
import SwiftData
import SwiftUI

struct ConversationsListView: View {
  private enum HomeItem: Identifiable {
    case conversation(Conversation)
    case channel(ChannelSummary)

    var id: String {
      switch self {
      case .conversation(let conversation):
        return "conversation:\(conversation.persistentModelID)"
      case .channel(let channel):
        return "channel:\(channel.id)"
      }
    }
  }

  enum ChatFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case favourites
    case channels

    var id: String { rawValue }

    var title: String {
      switch self {
      case .all:
        return "All"
      case .unread:
        return "Unread"
      case .favourites:
        return "Favourites"
      case .channels:
        return "Channels"
      }
    }
  }

  @Environment(\.modelContext) private var modelContext
  @Environment(AuthStore.self) private var authStore
  @Query private var conversations: [Conversation]
  @Binding var selectedTab: AppTab
  let openConversationID: String?
  let onOpenConversationHandled: () -> Void

  @State private var path: [Conversation] = []
  @State private var searchText = ""
  @State private var selectedFilter: ChatFilter = .all
  @State private var isNewConversationSheetPresented = false
  @State private var isCreateChannelSheetPresented = false
  @State private var channels: [ChannelSummary] = []
  @State private var conversationsSubscription: AnyCancellable?

  private var filteredConversations: [Conversation] {
    let sorted = conversations.sorted(by: { $0.lastMessageTimestamp > $1.lastMessageTimestamp })
    let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    return sorted.filter { conversation in
      switch selectedFilter {
      case .all:
        break
      case .unread:
        guard conversation.unreadCountValue > 0 else { return false }
      case .favourites:
        guard conversation.isFavorite else { return false }
      case .channels:
        return false
      }

      guard !trimmedSearch.isEmpty else { return true }

      let lastMessage = conversation.messages.last
      let haystack = [
        conversation.participantDisplayName,
        conversation.summary,
        lastMessage?.content,
        lastMessage?.attachementFileName,
        lastMessage?.attachementTitle,
      ]
      .compactMap { $0?.lowercased() }
      .joined(separator: " ")

      return haystack.contains(trimmedSearch)
    }
  }

  private var filteredChannels: [ChannelSummary] {
    let sorted = channels.sorted(by: { $0.lastMessageAt > $1.lastMessageAt })
    let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmedSearch.isEmpty else { return sorted }

    return sorted.filter { channel in
      let haystack = [
        channel.name.lowercased(),
        channel.description?.lowercased(),
        channel.lastMessageContent?.lowercased(),
      ]
      .compactMap { $0 }
      .joined(separator: " ")
      return haystack.contains(trimmedSearch)
    }
  }

  private var allHomeItems: [HomeItem] {
    let conversationItems = filteredConversations.map(HomeItem.conversation)
    let channelItems = filteredChannels.map(HomeItem.channel)
    return (conversationItems + channelItems).sorted { lhs, rhs in
      lastActivityDate(for: lhs) > lastActivityDate(for: rhs)
    }
  }

  var body: some View {
    NavigationStack(path: $path) {
      VStack(spacing: 10) {
        chatFiltersBar
          .padding(.horizontal, 16)
          .padding(.top, 8)

        List {
          if selectedFilter == .channels {
            ForEach(filteredChannels) { channel in
              NavigationLink {
                ChannelChatView(channel: channel)
              } label: {
                ChannelSummaryRow(channel: channel)
              }
            }
            .listSectionSeparator(.hidden, edges: .top)
          } else if selectedFilter == .all {
            ForEach(allHomeItems) { item in
              switch item {
              case .conversation(let conversation):
                conversationNavigationRow(for: conversation)
              case .channel(let channel):
                NavigationLink {
                  ChannelChatView(channel: channel)
                } label: {
                  ChannelSummaryRow(channel: channel)
                }
              }
            }
            .listSectionSeparator(.hidden, edges: .top)
          } else {
            ForEach(filteredConversations) { conversation in
              conversationNavigationRow(for: conversation)
            }
            .listSectionSeparator(.hidden, edges: .top)
          }
        }
        .listStyle(.plain)
      }
      .navigationDestination(for: Conversation.self) { conversation in
        ConversationDetailView(conversation: conversation)
      }
      .onAppear {
        startConversationsSubscription()
        Task {
          await loadChannels(search: searchText)
        }
      }
      .onDisappear {
        conversationsSubscription?.cancel()
        conversationsSubscription = nil
      }
      .navigationTitle("Chats")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          HStack(spacing: 12) {
            Menu {
              Button {
                isNewConversationSheetPresented = true
              } label: {
                Label("New Conversation", systemImage: "message.fill")
              }

              Button {
                selectedTab = .channels
              } label: {
                Label("Open Channels", systemImage: "person.3.fill")
              }

              if authStore.isAdmin {
                Button {
                  isCreateChannelSheetPresented = true
                } label: {
                  Label("Create Channel", systemImage: "plus.bubble.fill")
                }
              }
            } label: {
              Image(systemName: "plus")
            }

            NavigationLink {
              ProfileView()
            } label: {
              ProfileAvatarView(label: authStore.currentUserLabel)
            }
          }
        }
      }
      .sheet(isPresented: $isNewConversationSheetPresented) {
        NewConversationSheet { selectedUser in
          try await startConversation(with: selectedUser)
        }
      }
      .sheet(isPresented: $isCreateChannelSheetPresented) {
        CreateChannelSheet {
          await loadChannels(search: searchText)
          selectedTab = .channels
        }
      }
      .task(id: searchText) {
        await loadChannels(search: searchText)
      }
      .task(id: openConversationID) {
        guard let openConversationID else { return }
        await openConversationFromPush(remoteConversationID: openConversationID)
        onOpenConversationHandled()
      }
    }
  }

  private var chatFiltersBar: some View {
    VStack(spacing: 10) {
      GlassSearchField(placeholder: "Search chats", text: $searchText)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(ChatFilter.allCases) { filter in
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
  }

  @MainActor
  private func startConversationsSubscription() {
    conversationsSubscription?.cancel()
    do {
      conversationsSubscription = try authStore
        .subscribeConversations()
        .receive(on: DispatchQueue.main)
        .sink(
          receiveCompletion: { completion in
            guard case .failure = completion else { return }
            Task { @MainActor in
              try? await Task.sleep(for: .seconds(1))
              startConversationsSubscription()
            }
          },
          receiveValue: { remoteConversations in
            applyRemoteConversations(remoteConversations ?? [])
          }
        )
    } catch {
      conversationsSubscription = nil
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        startConversationsSubscription()
      }
    }
  }

  @MainActor
  private func applyRemoteConversations(_ remoteConversations: [ConvexConversationSummary]) {
    var localByRemoteID: [String: Conversation] = [:]
    for conversation in conversations {
      if let remoteID = conversation.remoteConversationID {
        localByRemoteID[remoteID] = conversation
      }
    }

    for remoteConversation in remoteConversations {
      let displayName = remoteConversation.otherParticipant?.displayName
      let localConversation: Conversation

      if let existing = localByRemoteID[remoteConversation.id] {
        localConversation = existing
      } else {
        localConversation = Conversation(
          messages: [],
          summary: displayName,
          remoteConversationID: remoteConversation.id,
          participantDisplayName: displayName
        )
        modelContext.insert(localConversation)
        localByRemoteID[remoteConversation.id] = localConversation
      }

      if let displayName, !displayName.isEmpty {
        localConversation.participantDisplayName = displayName
        if localConversation.summary?.isEmpty ?? true {
          localConversation.summary = displayName
        }
      }

      localConversation.unreadCount = remoteConversation.unreadCountValue
      localConversation.otherParticipantLastReadAt = remoteConversation.otherParticipantLastReadDate

      if let lastMessage = remoteConversation.lastMessage {
        upsertMessage(lastMessage, into: localConversation)
      }
    }

    try? modelContext.save()
  }

  @MainActor
  private func upsertMessage(_ remoteMessage: ConvexChatMessage, into conversation: Conversation) {
    if let existing = conversation.messages.first(where: { $0.remoteMessageID == remoteMessage.id }) {
      existing.content = remoteMessage.content
      existing.senderStackUserId = remoteMessage.senderStackUserId
      existing.role = remoteMessage.role.appRole
      existing.timestamp = remoteMessage.timestamp
      existing.attachementType = remoteMessage.attachmentType
      existing.attachementFileName = remoteMessage.attachmentFileName
      existing.attachementMimeType = remoteMessage.attachmentMimeType
      existing.attachementTitle = remoteMessage.attachmentTitle
      existing.attachementDescription = remoteMessage.attachmentDescription
      existing.attachementThumbnail = remoteMessage.attachmentThumbnail
      existing.attachementURL = remoteMessage.attachmentUrl
      return
    }

    conversation.messages.append(
      Message(
        content: remoteMessage.content,
        role: remoteMessage.role.appRole,
        timestamp: remoteMessage.timestamp,
        remoteMessageID: remoteMessage.id,
        senderStackUserId: remoteMessage.senderStackUserId,
        attachementType: remoteMessage.attachmentType,
        attachementFileName: remoteMessage.attachmentFileName,
        attachementMimeType: remoteMessage.attachmentMimeType,
        attachementTitle: remoteMessage.attachmentTitle,
        attachementDescription: remoteMessage.attachmentDescription,
        attachementThumbnail: remoteMessage.attachmentThumbnail,
        attachementURL: remoteMessage.attachmentUrl
      )
    )
  }

  @MainActor
  private func startConversation(with user: DirectoryUser) async throws {
    let result = try await authStore.startDirectConversation(withStackUserID: user.stackUserId)

    if let existing = conversations.first(where: { $0.remoteConversationID == result.conversationId }) {
      path.append(existing)
      return
    }

    let conversation = Conversation(
      messages: [],
      summary: user.displayName,
      remoteConversationID: result.conversationId,
      participantDisplayName: user.displayName
    )
    modelContext.insert(conversation)
    try modelContext.save()
    path.append(conversation)
  }

  @MainActor
  private func openConversationFromPush(remoteConversationID: String) async {
    selectedFilter = .all

    if let existing = conversations.first(where: { $0.remoteConversationID == remoteConversationID }) {
      path = [existing]
      return
    }

    let conversation = Conversation(
      messages: [],
      summary: "Conversation",
      remoteConversationID: remoteConversationID,
      participantDisplayName: nil
    )
    modelContext.insert(conversation)
    try? modelContext.save()
    path = [conversation]
  }

  private func lastActivityDate(for item: HomeItem) -> Date {
    switch item {
    case .conversation(let conversation):
      return conversation.lastMessageTimestamp
    case .channel(let channel):
      return channel.lastMessageDate
    }
  }

  private func conversationNavigationRow(for conversation: Conversation) -> some View {
    NavigationLink(value: conversation) {
      ConversationRowView(conversation: conversation)
        .swipeActions {
          Button(role: .destructive) {
            let remoteID = conversation.remoteConversationID
            modelContext.delete(conversation)
            try? modelContext.save()
            if let remoteID {
              Task {
                try? await authStore.deleteConversation(conversationID: remoteID)
              }
            }
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
          Button {
            conversation.isFavorite.toggle()
            try? modelContext.save()
          } label: {
            Label(
              conversation.isFavorite ? "Unfavorite" : "Favorite",
              systemImage: conversation.isFavorite ? "star.slash.fill" : "star.fill"
            )
          }
          .tint(.yellow)
        }
    }
  }

  @MainActor
  private func loadChannels(search: String) async {
    let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)

    if !trimmedSearch.isEmpty {
      try? await Task.sleep(for: .milliseconds(250))
    }

    guard !Task.isCancelled else { return }

    do {
      channels = try await authStore.fetchChannels(search: trimmedSearch)
    } catch {
      channels = []
    }
  }
}

private struct ChannelSummaryRow: View {
  let channel: ChannelSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("#\(channel.name)")
        .font(.body.weight(.semibold))

      if let lastMessage = channel.lastMessageContent,
        !lastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        Text(lastMessage)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else if let description = channel.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else {
        Text("No messages yet")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct ProfileAvatarView: View {
  let label: String?

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
    Text(initials)
      .font(.caption.weight(.bold))
      .foregroundStyle(.white)
      .frame(width: 32, height: 32)
      .background(
        LinearGradient(
          colors: [
            Color(red: 0.25, green: 0.07, blue: 0.30),
            Color(red: 0.48, green: 0.18, blue: 0.50)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        in: Circle()
      )
  }
}
