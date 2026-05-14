import SwiftUI

struct ConversationInfoView: View {
  enum Source {
    case conversation(id: String)
    case channel(id: String, summary: ChannelSummary?)
  }

  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let source: Source
  let initialDisplayName: String?
  let onPinToggle: ((Bool) -> Void)?

  init(
    source: Source,
    initialDisplayName: String? = nil,
    onPinToggle: ((Bool) -> Void)? = nil
  ) {
    self.source = source
    self.initialDisplayName = initialDisplayName
    self.onPinToggle = onPinToggle
  }

  @State private var conversation: ConvexConversationSummary?
  @State private var channel: ChannelSummary?
  @State private var members: [ChannelMember] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var isMuted: Bool = false
  @State private var isMutating: Bool = false
  @State private var showLeaveConfirm: Bool = false
  @State private var showMediaSheet = false
  @State private var showSearchSheet = false

  private var displayName: String {
    if case .channel = source, let channel {
      return "#\(channel.name)"
    }
    if case .conversation = source, let conversation {
      return conversation.otherParticipant?.displayName
        ?? conversation.displayName
        ?? initialDisplayName
        ?? "Conversation"
    }
    return initialDisplayName ?? "Conversation"
  }

  private var subtitle: String? {
    switch source {
    case .channel:
      if let memberCount = channel?.memberCount {
        return "\(memberCount) member\(memberCount == 1 ? "" : "s")"
      }
      return channel?.description
    case .conversation:
      let count = conversation?.participants?.count ?? 0
      if count > 1 {
        return "\(count) participants"
      }
      return nil
    }
  }

  var body: some View {
    List {
      Section {
        headerCard
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
      }

      Section {
        Button {
          showSearchSheet = true
        } label: {
          InfoActionRow(systemImage: "magnifyingglass", tint: .blue, title: "Search Messages")
        }

        Button {
          showMediaSheet = true
        } label: {
          InfoActionRow(systemImage: "photo.on.rectangle", tint: .purple, title: "Media, Files & Links")
        }
      }

      Section("Notifications") {
        Toggle(isOn: muteBinding) {
          Label("Mute notifications", systemImage: isMuted ? "bell.slash.fill" : "bell.fill")
        }
        .disabled(isMutating)
      }

      if case .channel = source {
        membersSection
      }

      if case .conversation = source {
        conversationParticipantsSection
      }

      if case .channel = source {
        Section {
          Button(role: .destructive) {
            showLeaveConfirm = true
          } label: {
            Label("Leave Channel", systemImage: "rectangle.portrait.and.arrow.right")
              .foregroundStyle(.red)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Info")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
    .alert("Leave Channel?", isPresented: $showLeaveConfirm) {
      Button("Cancel", role: .cancel) {}
      Button("Leave", role: .destructive) {
        Task { await leaveChannel() }
      }
    } message: {
      Text("You will stop receiving messages from this channel.")
    }
    .sheet(isPresented: $showSearchSheet) {
      NavigationStack {
        searchView
      }
    }
    .sheet(isPresented: $showMediaSheet) {
      NavigationStack {
        mediaView
      }
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
  }

  private var headerCard: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(
            LinearGradient(
              colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 88, height: 88)

        Text(initials)
          .font(.title.weight(.bold))
          .foregroundStyle(.white)
      }

      Text(displayName)
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)

      if let subtitle {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
    .padding(.horizontal, 16)
  }

  @ViewBuilder
  private var searchView: some View {
    switch source {
    case .conversation(let id):
      ConversationSearchView(conversationID: id, title: displayName)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { showSearchSheet = false }
          }
        }
    case .channel(let id, _):
      ConversationSearchView(channelID: id, title: displayName)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { showSearchSheet = false }
          }
        }
    }
  }

  @ViewBuilder
  private var mediaView: some View {
    switch source {
    case .conversation(let id):
      ConversationMediaView(conversationID: id, title: displayName)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { showMediaSheet = false }
          }
        }
    case .channel(let id, _):
      ConversationMediaView(channelID: id, title: displayName)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { showMediaSheet = false }
          }
        }
    }
  }

  @ViewBuilder
  private var conversationParticipantsSection: some View {
    let participants = conversation?.participants ?? []

    Section(participants.count > 1 ? "People (\(participants.count))" : "User Details") {
      if isLoading && participants.isEmpty {
        ProgressView()
      } else if participants.isEmpty {
        Text("No user details loaded")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(participants, id: \.stackUserId) { participant in
          NavigationLink {
            StaffDetailView(staffId: participant.stackUserId)
          } label: {
            ParticipantInfoRow(participant: participant)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var membersSection: some View {
    Section("Members (\(members.count))") {
      if members.isEmpty {
        Text("No members loaded")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(members) { member in
          HStack(spacing: 12) {
            ZStack {
              Circle()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 36)
              Text(memberInitials(member))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
              Text(member.staffName ?? member.id)
                .font(.subheadline.weight(.semibold))
              if let role = member.role, !role.isEmpty {
                Text(role.capitalized)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }

            Spacer()
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  private var initials: String {
    let candidate = displayName.replacingOccurrences(of: "#", with: "")
    let parts = candidate.split(whereSeparator: { !$0.isLetter }).prefix(2).compactMap(\.first)
    let result = String(parts).uppercased()
    return result.isEmpty ? "?" : result
  }

  private func memberInitials(_ member: ChannelMember) -> String {
    let name = member.staffName ?? member.id
    let parts = name.split(whereSeparator: { !$0.isLetter }).prefix(2).compactMap(\.first)
    return String(parts).uppercased()
  }

  private var muteBinding: Binding<Bool> {
    Binding(
      get: { isMuted },
      set: { newValue in
        Task { await toggleMute(to: newValue) }
      }
    )
  }

  @MainActor
  private func load() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    switch source {
    case .conversation(let id):
      do {
        let summary = try await authStore.fetchConversation(conversationID: id)
        conversation = summary
        isMuted = summary.muted ?? false
      } catch {
        errorMessage = error.localizedDescription
      }
    case .channel(let id, let initialSummary):
      channel = initialSummary
      do {
        async let summary = authStore.fetchChannel(channelID: id)
        async let memberList = authStore.fetchChannelMembers(channelID: id)
        let resolved = try await summary
        channel = resolved
        isMuted = resolved.muted ?? false
        members = (try? await memberList) ?? []
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  @MainActor
  private func toggleMute(to newValue: Bool) async {
    isMutating = true
    let previous = isMuted
    isMuted = newValue
    defer { isMutating = false }

    do {
      switch source {
      case .conversation(let id):
        try await authStore.toggleConversationMute(conversationID: id, muted: newValue)
      case .channel(let id, _):
        try await authStore.toggleChannelMute(channelID: id, muted: newValue)
      }
    } catch {
      isMuted = previous
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func leaveChannel() async {
    guard case .channel(let id, _) = source else { return }
    do {
      try await authStore.leaveChannel(channelID: id)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct InfoActionRow: View {
  let systemImage: String
  let tint: Color
  let title: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 30, height: 30)
        .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

      Text(title)
        .foregroundStyle(.primary)

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
  }
}

private struct ParticipantInfoRow: View {
  let participant: ConvexConversationParticipant

  var body: some View {
    HStack(spacing: 12) {
      AvatarView(urlString: participant.profilePhoto, initials: initials)

      VStack(alignment: .leading, spacing: 2) {
        Text(participant.displayName)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)

        Text("View staff details")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(.vertical, 4)
  }

  private var initials: String {
    let parts = participant.displayName
      .split(whereSeparator: { !$0.isLetter })
      .prefix(2)
      .compactMap(\.first)
    let result = String(parts).uppercased()
    return result.isEmpty ? "?" : result
  }
}

private struct AvatarView: View {
  let urlString: String?
  let initials: String

  var body: some View {
    ZStack {
      Circle()
        .fill(Color(.systemGray4))

      if let url {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
          default:
            Text(initials)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white)
          }
        }
      } else {
        Text(initials)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
      }
    }
    .frame(width: 36, height: 36)
    .clipShape(Circle())
  }

  private var url: URL? {
    guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return URL(string: urlString)
  }
}
