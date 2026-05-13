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
    case groups
    case favoriteChats
    case directChats

    var id: String { rawValue }

    var title: String {
      switch self {
      case .all:
        return "All"
      case .unread:
        return "Unread Chats"
      case .favoriteChats:
        return "Favourite Chats"
      case .groups:
        return "Group Chats"
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

  @State private var path: [Conversation] = []
  @State private var searchText = ""
  @State private var selectedFilter: ChatFilter = .all
  @State private var isNewConversationSheetPresented = false
  @State private var isCreateChannelSheetPresented = false
  @State private var channels: [ChannelSummary] = []
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
      case .favoriteChats, .directChats:
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
    return (conversationItems + channelItems).sorted { lhs, rhs in
      lastActivityDate(for: lhs) > lastActivityDate(for: rhs)
    }
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
      return filteredConversations.map(HomeItem.conversation)
    case .groups:
      return filteredChannels.map(HomeItem.channel)
    case .directChats:
      return filteredConversations.map(HomeItem.conversation)
    }
  }

  private var unreadBadgeCount: Int {
    filteredConversations.reduce(0) { $0 + $1.unreadCountValue } + filteredChannels.reduce(0) { $0 + $1.unreadCountValue }
  }

  var body: some View {
    NavigationStack(path: $path) {
      VStack(spacing: 0) {
        chatListHeader

        ChatListSearchField(text: $searchText)
          .padding(.horizontal, 8)
          .padding(.top, 10)

        chatFiltersBar
          .padding(.top, 29)

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
                  NavigationLink {
                    ChannelChatView(channel: channel)
                  } label: {
                    ChannelSummaryRow(channel: channel)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }
          .padding(.top, 18)
        }
      }
      .background(Color.white.ignoresSafeArea())
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
      .toolbar(.hidden, for: .navigationBar)
      .sheet(isPresented: $isNewConversationSheetPresented) {
        NewConversationSheet { selectedUser in
          try await startConversation(with: selectedUser)
        }
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
      HStack(spacing: 8) {
        ForEach(ChatFilter.allCases) { filter in
          Button {
            selectedFilter = filter
          } label: {
            HStack(spacing: 8) {
              Text(filter.title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(selectedFilter == filter ? .white : FoundationChatTheme.ink)

              if badgeCount(for: filter) > 0 {
                Text(badgeLabel(for: filter))
                  .font(.system(size: 9, weight: .semibold))
                  .foregroundStyle(selectedFilter == filter ? FoundationChatTheme.outgoingBubble : .white)
                  .padding(.horizontal, 6)
                  .frame(height: 18)
                  .background(selectedFilter == filter ? .white : FoundationChatTheme.outgoingBubble, in: Capsule())
              }
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
              selectedFilter == filter
                ? FoundationChatTheme.outgoingBubble
                : Color(red: 0.94, green: 0.96, blue: 0.98),
              in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 8)
    }
  }

  private var chatListHeader: some View {
    HStack(spacing: 12) {
      Button {
        selectedTab = .home
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 23, weight: .regular))
          .foregroundStyle(FoundationChatTheme.headerAccent)
          .frame(width: 63, height: 63)
          .background(Color(red: 0.96, green: 0.97, blue: 1.0), in: Circle())
      }
      .buttonStyle(.plain)

      Spacer()

      Text("Chats")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(FoundationChatTheme.ink)

      Spacer()

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
          .font(.system(size: 23, weight: .regular))
          .foregroundStyle(FoundationChatTheme.headerAccent)
          .frame(width: 63, height: 63)
          .background(Color(red: 0.96, green: 0.97, blue: 1.0), in: Circle())
      }
    }
    .frame(height: 100)
    .padding(.horizontal, 23.5)
    .background(Color.white)
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
    .buttonStyle(.plain)
  }

  private func badgeCount(for filter: ChatFilter) -> Int {
    switch filter {
    case .all:
      return filteredConversations.count + filteredChannels.count
    case .unread:
      return unreadBadgeCount
    case .favoriteChats:
      return conversations.filter(\.isFavorite).count
    case .groups:
      return channels.count
    case .directChats:
      return filteredConversations.count
    }
  }

  private func badgeLabel(for filter: ChatFilter) -> String {
    let count = badgeCount(for: filter)
    if count > 99 { return "99+" }
    if filter == .groups && count < 10 { return "0\(count)" }
    return "\(count)"
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

        Text(channel.lastMessageContent ?? channel.description ?? "No messages yet")
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(Color(red: 0.45, green: 0.46, blue: 0.48))
          .lineLimit(1)
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

private struct ChatListSearchField: View {
  @Binding var text: String

  var body: some View {
    HStack(spacing: 12) {
      TextField("Search Chats", text: $text)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(FoundationChatTheme.ink)
        .tint(FoundationChatTheme.outgoingBubble)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

      Spacer(minLength: 0)

      Button {
        if text.isEmpty {
          return
        }
        text = ""
      } label: {
        Image(systemName: text.isEmpty ? "magnifyingglass" : "xmark.circle.fill")
          .font(.system(size: text.isEmpty ? 28 : 21, weight: .regular))
          .foregroundStyle(text.isEmpty ? Color.black.opacity(0.88) : Color.black.opacity(0.28))
          .frame(width: 36, height: 36)
      }
      .buttonStyle(.plain)
    }
    .padding(.leading, 20)
    .padding(.trailing, 16)
    .frame(height: 50)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.black.opacity(0.12), lineWidth: 1)
    )
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
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 44, height: 44)
      .background(
        LinearGradient(
          colors: [
            Color(red: 0.77, green: 0.59, blue: 0.15),
            Color(red: 0.67, green: 0.45, blue: 0.09)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
  }
}
