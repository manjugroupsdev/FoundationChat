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

    var selectionID: String {
      switch self {
      case .conversation(let conversation):
        return "conversation:\(conversation.remoteConversationID ?? conversation.persistentModelID.id.hashValue.description)"
      case .channel(let channel):
        return "channel:\(channel.id)"
      }
    }

    var title: String {
      switch self {
      case .conversation(let conversation):
        return conversation.participantDisplayName ?? conversation.summary ?? "New conversation"
      case .channel(let channel):
        return channel.name
      }
    }

    var unreadCount: Int {
      switch self {
      case .conversation(let conversation):
        return conversation.unreadCountValue
      case .channel(let channel):
        return channel.unreadCountValue
      }
    }
  }

  enum ChatFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case groups
    case favoriteChats
    case directChats

    var id: String { rawValue }

    var title: String {
      switch self {
      case .all:
        return "All"
      case .unread:
        return "Unread"
      case .favoriteChats:
        return "Favourites"
      case .groups:
        return "Groups"
      case .directChats:
        return "DM"
      }
    }
  }

  @Environment(\.modelContext) private var modelContext
  @Environment(AuthStore.self) private var authStore
  @Query private var conversations: [Conversation]
  @Binding var selectedTab: AppTab
  let openConversationID: String?
  let onOpenConversationHandled: () -> Void

  @State private var path = NavigationPath()
  @State private var searchText = ""
  @State private var selectedFilter: ChatFilter = .all
  @State private var isNewConversationSheetPresented = false
  @State private var isCreateChannelSheetPresented = false
  @State private var channels: [ChannelSummary] = []
  @State private var favoriteChannelIDs: Set<String> = []
  @State private var selectedHomeItemIDs: Set<String> = []
  @State private var longPressSelectionGuards: Set<String> = []
  @State private var conversationsSubscription: AnyCancellable?

  private var filteredConversations: [Conversation] {
    let remoteBackedConversations = conversations.filter {
      guard let remoteID = $0.remoteConversationID?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        return false
      }
      return !remoteID.isEmpty
    }
    let sorted = remoteBackedConversations.sorted(by: { $0.lastMessageTimestamp > $1.lastMessageTimestamp })
    let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    return sorted.filter { conversation in
      let filterMatch: Bool
      switch selectedFilter {
      case .all, .directChats:
        filterMatch = true
      case .unread:
        filterMatch = conversation.unreadCountValue > 0
      case .favoriteChats:
        filterMatch = conversation.isFavorite
      case .groups:
        filterMatch = false
      }

      guard filterMatch else { return false }
      guard !trimmedSearch.isEmpty else { return true }

      let lastMessage = conversation.sortedMessages.last
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

    return sorted.filter { channel in
      let filterMatch: Bool
      switch selectedFilter {
      case .all, .groups:
        filterMatch = true
      case .unread:
        filterMatch = channel.unreadCountValue > 0
      case .favoriteChats:
        filterMatch = favoriteChannelIDs.contains(channel.id)
      case .directChats:
        filterMatch = false
      }

      guard filterMatch else { return false }
      guard !trimmedSearch.isEmpty else { return true }

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
    return sortHomeItems(conversationItems + channelItems)
  }

  private var currentItems: [HomeItem] {
    switch selectedFilter {
    case .all, .unread:
      return allHomeItems.filter { item in
        switch item {
        case .conversation(let conversation):
          return selectedFilter != .unread || conversation.unreadCountValue > 0
        case .channel(let channel):
          return selectedFilter != .unread || channel.unreadCountValue > 0
        }
      }
    case .favoriteChats:
      return sortHomeItems(filteredConversations.map(HomeItem.conversation) + filteredChannels.map(HomeItem.channel))
    case .groups:
      return sortHomeItems(filteredChannels.map(HomeItem.channel))
    case .directChats:
      return sortHomeItems(filteredConversations.map(HomeItem.conversation))
    }
  }

  private var isSelectionMode: Bool {
    !selectedHomeItemIDs.isEmpty
  }

  var body: some View {
    NavigationStack(path: $path) {
      VStack(spacing: 0) {
        chatFiltersBar
          .padding(.top, 8)

        ScrollView {
          LazyVStack(spacing: 0) {
            if currentItems.isEmpty {
              EmptyChatState(filter: selectedFilter) {
                switch selectedFilter {
                case .groups:
                  isCreateChannelSheetPresented = true
                case .directChats:
                  isNewConversationSheetPresented = true
                case .favoriteChats:
                  selectedFilter = .all
                case .all, .unread:
                  break
                }
              }
              .padding(.top, 74)
            } else {
              ForEach(currentItems) { item in
                switch item {
                case .conversation(let conversation):
                  conversationNavigationRow(for: conversation)
                case .channel(let channel):
                  let item = HomeItem.channel(channel)
                  Button {
                    handlePrimaryTap(on: item)
                  } label: {
                    ChannelSummaryRow(channel: channel)
                      .overlaySelection(
                        isSelected: selectedHomeItemIDs.contains(item.selectionID),
                        isSelectionMode: isSelectionMode
                      )
                  }
                  .buttonStyle(.plain)
                  .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                      .onEnded { _ in selectFromLongPress(item) }
                  )
                  .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                      toggleFavoriteChannel(channel.id)
                    } label: {
                      Label(
                        favoriteChannelIDs.contains(channel.id) ? "Unfavorite" : "Favorite",
                        systemImage: favoriteChannelIDs.contains(channel.id) ? "star.slash.fill" : "star.fill"
                      )
                    }
                    .tint(.yellow)
                  }
                }
              }
            }
          }
          .padding(.top, 18)
        }
      }
      .background(Color.white.ignoresSafeArea())
      .searchable(
        text: $searchText,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Search Chats"
      )
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .navigationDestination(for: Conversation.self) { conversation in
        ConversationDetailView(conversation: conversation)
      }
      .navigationDestination(for: String.self) { channelID in
        ChannelChatView(channel: channelSummary(for: channelID))
      }
      .navigationTitle(isSelectionMode ? "\(selectedHomeItemIDs.count) selected" : "Chats")
      .navigationBarTitleDisplayMode(.inline)
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
      .toolbar {
        if isSelectionMode {
          ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") {
              withAnimation(.snappy) {
                selectedHomeItemIDs.removeAll()
              }
            }
          }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
          HStack(spacing: 12) {
            if isSelectionMode {
              Menu {
                Button {
                  toggleFavoritesForSelection()
                } label: {
                  Label(selectionIsAllFavorite ? "Remove Favourites" : "Add Favourites", systemImage: "star.fill")
                }

                Button(role: .destructive) {
                  deleteSelectedConversations()
                } label: {
                  Label("Delete Direct Chats", systemImage: "trash")
                }
                .disabled(selectedConversationCount == 0)
              } label: {
                Image(systemName: "ellipsis")
                  .font(.system(size: 18, weight: .semibold))
                  .foregroundStyle(Color(red: 0.05, green: 0.38, blue: 0.79))
                  .frame(width: 32, height: 32)
                  .background(Color(red: 0.93, green: 0.96, blue: 1.0), in: Circle())
              }
              .buttonStyle(.plain)
            } else {
            Menu {
              Button {
                isNewConversationSheetPresented = true
              } label: {
                Label("Direct Messages", systemImage: "message.fill")
              }

              Button {
                selectedFilter = .groups
              } label: {
                Label("Group Chats", systemImage: "person.3.fill")
              }

              if authStore.isAdmin {
                Button {
                  isCreateChannelSheetPresented = true
                } label: {
                  Label("Create Group", systemImage: "plus.bubble.fill")
                }
              }
            } label: {
              Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            }

            NavigationLink {
              ProfileView()
            } label: {
              ProfileAvatarView(label: authStore.currentUserLabel)
            }
            }
          }
        }
      }
      .sheet(isPresented: $isNewConversationSheetPresented) {
        NewConversationSheet(
          onSelectUser: { selectedUser in
            try await startConversation(with: selectedUser)
          },
          onCreateGroup: { selectedUsers, groupName in
            try await startGroupConversation(with: selectedUsers, name: groupName)
          },
          onCreateChannel: authStore.isAdmin ? {
            isCreateChannelSheetPresented = true
          } : nil
        )
      }
      .sheet(isPresented: $isCreateChannelSheetPresented) {
        CreateChannelSheet {
          await loadChannels(search: searchText)
          selectedFilter = .groups
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
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(ChatFilter.allCases) { filter in
          Button {
            selectedFilter = filter
          } label: {
            Text(filter.title)
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(selectedFilter == filter ? .white : FoundationChatTheme.ink)
              .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
              selectedFilter == filter
                ? FoundationChatTheme.outgoingBubble
                : Color(red: 0.94, green: 0.96, blue: 0.98),
              in: Capsule()
            )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16)
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
    let remoteIDs = Set(remoteConversations.map(\.id))

    // Keep the local SwiftData cache aligned with the latest Convex response.
    // This prevents stale/hardcoded-looking rows from surviving across runs.
    for conversation in conversations {
      guard let remoteID = conversation.remoteConversationID?.trimmingCharacters(in: .whitespacesAndNewlines),
        !remoteID.isEmpty
      else {
        modelContext.delete(conversation)
        continue
      }

      if !remoteIDs.contains(remoteID) {
        modelContext.delete(conversation)
      }
    }

    var localByRemoteID: [String: Conversation] = [:]
    for conversation in conversations {
      if let remoteID = conversation.remoteConversationID?.trimmingCharacters(in: .whitespacesAndNewlines),
        !remoteID.isEmpty,
        remoteIDs.contains(remoteID)
      {
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
        let asChatMessage = ConvexChatMessage(
          _id: lastMessage._id, channelId: nil, conversationId: remoteConversation.id,
          senderId: nil, senderName: lastMessage.senderName, body: lastMessage.body,
          isEdited: false, isDeleted: false, replyCount: 0, lastReplyAt: nil,
          parentMessageId: nil, _creationTime: lastMessage._creationTime, attachments: nil
        )
        upsertMessage(asChatMessage, into: localConversation)
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
      existing.isDeleted = remoteMessage.isDeleted == true
      existing.attachementType = remoteMessage.attachmentType
      existing.attachementFileName = remoteMessage.attachmentFileName
      existing.attachementMimeType = remoteMessage.attachmentMimeType
      existing.attachementTitle = remoteMessage.attachmentTitle
      existing.attachementDescription = remoteMessage.attachmentDescription
      existing.attachementThumbnail = remoteMessage.attachmentThumbnail
      existing.attachementURL = remoteMessage.attachmentUrl
      if existing.isDeleted {
        clearDeletedMessagePayload(existing)
      }
      return
    }

    let localMessage = Message(
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
      attachementURL: remoteMessage.attachmentUrl,
      isDeleted: remoteMessage.isDeleted == true
    )
    if localMessage.isDeleted {
      clearDeletedMessagePayload(localMessage)
    }
    conversation.messages.append(
      localMessage
    )
  }

  private func clearDeletedMessagePayload(_ message: Message) {
    message.content = "This message was deleted"
    message.attachementType = nil
    message.attachementFileName = nil
    message.attachementMimeType = nil
    message.attachementTitle = nil
    message.attachementDescription = nil
    message.attachementThumbnail = nil
    message.attachementURL = nil
    message.replyToRemoteMessageID = nil
    message.replyPreviewText = nil
    message.replySenderName = nil
    message.reactionSummary = nil
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
  private func startGroupConversation(with users: [DirectoryUser], name: String?) async throws {
    let result = try await authStore.createGroupConversation(
      memberIds: users.map(\.stackUserId),
      name: name
    )

    if let existing = conversations.first(where: { $0.remoteConversationID == result.conversationId }) {
      path.append(existing)
      return
    }

    let fallbackName = users.map(\.displayName).prefix(3).joined(separator: ", ")
    let conversation = Conversation(
      messages: [],
      summary: name ?? fallbackName,
      remoteConversationID: result.conversationId,
      participantDisplayName: name ?? fallbackName
    )
    modelContext.insert(conversation)
    try modelContext.save()
    path.append(conversation)
  }

  @MainActor
  private func openConversationFromPush(remoteConversationID: String) async {
    selectedFilter = .all

    if let existing = conversations.first(where: { $0.remoteConversationID == remoteConversationID }) {
      path = NavigationPath()
      path.append(existing)
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
    path = NavigationPath()
    path.append(conversation)
  }

  private func lastActivityDate(for item: HomeItem) -> Date {
    switch item {
    case .conversation(let conversation):
      return conversation.lastMessageTimestamp
    case .channel(let channel):
      return channel.lastMessageDate
    }
  }

  private func sortHomeItems(_ items: [HomeItem]) -> [HomeItem] {
    items.sorted { lhs, rhs in
      let lhsUnread = lhs.unreadCount > 0
      let rhsUnread = rhs.unreadCount > 0
      if lhsUnread != rhsUnread {
        return lhsUnread && !rhsUnread
      }
      let lhsDate = lastActivityDate(for: lhs)
      let rhsDate = lastActivityDate(for: rhs)
      if lhsDate != rhsDate {
        return lhsDate > rhsDate
      }
      return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
  }

  private func conversationNavigationRow(for conversation: Conversation) -> some View {
    let item = HomeItem.conversation(conversation)
    return Button {
      handlePrimaryTap(on: item)
    } label: {
      ConversationRowView(conversation: conversation)
        .overlaySelection(
          isSelected: selectedHomeItemIDs.contains(item.selectionID),
          isSelectionMode: isSelectionMode
        )
        .swipeActions {
          Button(role: .destructive) {
            let remoteID = conversation.remoteConversationID
            selectedHomeItemIDs.remove(item.selectionID)
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
    .buttonStyle(.plain)
    .simultaneousGesture(
      LongPressGesture(minimumDuration: 0.45)
        .onEnded { _ in selectFromLongPress(item) }
    )
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

  private func channelSummary(for channelID: String) -> ChannelSummary {
    if let existing = channels.first(where: { $0.id == channelID }) {
      return existing
    }
    return ChannelSummary(
      _id: channelID,
      name: "Channel",
      slug: nil,
      description: nil,
      type: "public",
      createdBy: nil,
      isArchived: false,
      memberCount: 0,
      role: "member",
      muted: false,
      unreadCount: 0
    )
  }

  private func toggleSelection(for item: HomeItem) {
    let id = item.selectionID
    withAnimation(.snappy) {
      if selectedHomeItemIDs.contains(id) {
        selectedHomeItemIDs.remove(id)
      } else {
        selectedHomeItemIDs.insert(id)
      }
    }
  }

  private func handlePrimaryTap(on item: HomeItem) {
    let id = item.selectionID
    if longPressSelectionGuards.contains(id) {
      longPressSelectionGuards.remove(id)
      return
    }

    if isSelectionMode {
      toggleSelection(for: item)
    } else {
      switch item {
      case .conversation(let conversation):
        path.append(conversation)
      case .channel(let channel):
        path.append(channel.id)
      }
    }
  }

  private func selectFromLongPress(_ item: HomeItem) {
    let id = item.selectionID
    longPressSelectionGuards.insert(id)

    withAnimation(.snappy) {
      _ = selectedHomeItemIDs.insert(id)
    }

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(450))
      longPressSelectionGuards.remove(id)
    }
  }

  private func toggleFavoriteChannel(_ id: String) {
    withAnimation(.snappy) {
      if favoriteChannelIDs.contains(id) {
        favoriteChannelIDs.remove(id)
      } else {
        favoriteChannelIDs.insert(id)
      }
    }
  }

  private var selectionIsAllFavorite: Bool {
    guard !selectedHomeItemIDs.isEmpty else { return false }
    return selectedHomeItemIDs.allSatisfy { id in
      if id.hasPrefix("channel:") {
        return favoriteChannelIDs.contains(String(id.dropFirst("channel:".count)))
      }
      return conversations.contains { conversation in
        HomeItem.conversation(conversation).selectionID == id && conversation.isFavorite
      }
    }
  }

  private var selectedConversationCount: Int {
    conversations.filter { selectedHomeItemIDs.contains(HomeItem.conversation($0).selectionID) }.count
  }

  private func toggleFavoritesForSelection() {
    let shouldRemove = selectionIsAllFavorite
    for conversation in conversations {
      let id = HomeItem.conversation(conversation).selectionID
      guard selectedHomeItemIDs.contains(id) else { continue }
      conversation.isFavorite = !shouldRemove
    }

    for selectedID in selectedHomeItemIDs where selectedID.hasPrefix("channel:") {
      let channelID = String(selectedID.dropFirst("channel:".count))
      if shouldRemove {
        favoriteChannelIDs.remove(channelID)
      } else {
        favoriteChannelIDs.insert(channelID)
      }
    }

    try? modelContext.save()
    withAnimation(.snappy) {
      selectedHomeItemIDs.removeAll()
    }
  }

  private func deleteSelectedConversations() {
    let selectedIDs = selectedHomeItemIDs
    let selectedConversations = conversations.filter { selectedIDs.contains(HomeItem.conversation($0).selectionID) }
    guard !selectedConversations.isEmpty else {
      withAnimation(.snappy) {
        selectedHomeItemIDs.removeAll()
      }
      return
    }

    for conversation in selectedConversations {
      let remoteID = conversation.remoteConversationID
      modelContext.delete(conversation)
      if let remoteID {
        Task {
          try? await authStore.deleteConversation(conversationID: remoteID)
        }
      }
    }
    try? modelContext.save()
    withAnimation(.snappy) {
      selectedHomeItemIDs.removeAll()
    }
  }
}

private struct ChannelSummaryRow: View {
  let channel: ChannelSummary

  var body: some View {
    HStack(spacing: 12) {
      AvatarPlaceholder(initials: "#")

      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(channel.name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(FoundationChatTheme.ink)
            .lineLimit(1)
          Spacer()
          Text(channel.lastMessageDate.formatted(date: .omitted, time: .shortened))
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(FoundationChatTheme.ink)
        }

        HStack(spacing: 8) {
          Text(channel.lastMessageContent ?? channel.description ?? "No messages yet")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Color(red: 0.45, green: 0.46, blue: 0.48))
            .lineLimit(1)

          Spacer(minLength: 8)

          if channel.unreadCountValue > 0 {
            Text(channel.unreadCountValue > 99 ? "99+" : "\(channel.unreadCountValue)")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 20, height: 20)
              .background(Color(red: 0.10, green: 0.72, blue: 0.04), in: Circle())
          }
        }
      }
    }
    .frame(height: 80)
    .padding(.horizontal, 12)
    .background(Color.white)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.black.opacity(0.06))
        .frame(height: 1)
        .padding(.leading, 76)
    }
  }
}

private struct HomeRowSelectionOverlay: ViewModifier {
  let isSelected: Bool
  let isSelectionMode: Bool

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .background(isSelected ? Color(red: 0.05, green: 0.38, blue: 0.79).opacity(0.08) : Color.clear)
      .overlay(alignment: .topLeading) {
        if isSelectionMode {
          ZStack {
            Circle()
              .fill(isSelected ? Color(red: 0.05, green: 0.38, blue: 0.79) : Color.white)
              .frame(width: 22, height: 22)
              .overlay(
                Circle()
                  .stroke(isSelected ? Color.white : Color.black.opacity(0.22), lineWidth: 2)
              )

            if isSelected {
              Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
            }
          }
          .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
          .padding(.leading, 49)
          .padding(.top, 48)
            .transition(.scale.combined(with: .opacity))
        }
      }
  }
}

private extension View {
  func overlaySelection(isSelected: Bool, isSelectionMode: Bool) -> some View {
    modifier(HomeRowSelectionOverlay(isSelected: isSelected, isSelectionMode: isSelectionMode))
  }
}

private struct EmptyChatState: View {
  let filter: ConversationsListView.ChatFilter
  let action: () -> Void

  private var title: String {
    switch filter {
    case .groups:
      return "No Groups Yet"
    case .directChats:
      return "No Direct Message Yet"
    case .unread:
      return "No Unread Message Yet"
    case .favoriteChats:
      return "No Favourite Message Yet"
    case .all:
      return "No Message Yet"
    }
  }

  private var buttonTitle: String? {
    switch filter {
    case .groups:
      return "Create Group"
    case .directChats:
      return "Direct Messages"
    case .favoriteChats:
      return "Add Favorites"
    case .all, .unread:
      return nil
    }
  }

  var body: some View {
    VStack(spacing: 26) {
      NativeGroupsIllustration()
        .frame(width: 163, height: 159)

      Text(title)
        .font(.system(size: 20, weight: .regular))
        .foregroundStyle(Color.black)

      Text("Stay organized by creating or joining teams. Groups help you manage tasks, track progress, and collaborate with your team in one place.")
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(Color(red: 0.45, green: 0.46, blue: 0.48))
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .padding(.horizontal, 28)

      if let buttonTitle {
        Button(action: action) {
          HStack(spacing: 18) {
            Image(systemName: "plus")
              .font(.system(size: 28, weight: .regular))
            Text(buttonTitle)
              .font(.system(size: 16, weight: .semibold))
          }
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          .background(Color(red: 0.09, green: 0.76, blue: 0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 25)
        .padding(.top, 32)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

private struct NativeGroupsIllustration: View {
  var body: some View {
    ZStack {
      Image(systemName: "person.3.fill")
        .font(.system(size: 66, weight: .regular))
        .foregroundStyle(Color(red: 0.38, green: 0.72, blue: 0.30))
        .offset(y: 14)

      Image(systemName: "checklist")
        .font(.system(size: 47, weight: .regular))
        .foregroundStyle(Color(red: 0.22, green: 0.25, blue: 0.22))
        .offset(x: 48, y: -34)
        .rotationEffect(.degrees(11))

      Image(systemName: "text.bubble")
        .font(.system(size: 38, weight: .regular))
        .foregroundStyle(Color(red: 0.22, green: 0.25, blue: 0.22))
        .offset(x: -52, y: -32)

      Image(systemName: "folder")
        .font(.system(size: 42, weight: .regular))
        .foregroundStyle(Color(red: 0.22, green: 0.25, blue: 0.22))
        .offset(x: -70, y: 48)

      Image(systemName: "calendar")
        .font(.system(size: 41, weight: .regular))
        .foregroundStyle(Color(red: 0.22, green: 0.25, blue: 0.22))
        .offset(x: 66, y: 50)

      Circle()
        .stroke(Color(red: 0.22, green: 0.25, blue: 0.22), lineWidth: 2)
        .frame(width: 44, height: 44)
        .overlay {
          Image(systemName: "plus")
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(Color(red: 0.09, green: 0.76, blue: 0.02))
        }
        .background(Color.white, in: Circle())
        .offset(y: 68)
    }
  }
}

struct ProfileAvatarView: View {
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
