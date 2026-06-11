import SwiftUI

struct ConversationInfoView: View {
  enum Source {
    case conversation(id: String)
    case channel(id: String, summary: ChannelSummary?)
  }

  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

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
  @State private var participantStaffIds: [String: String] = [:]
  @State private var participantStaffDetails: [String: ConvexStaffDetail] = [:]

  private var displayName: String {
    if case .channel = source, let channel {
      return "#\(channel.name)"
    }
    if case .conversation = source, let conversation {
      return conversationParticipantsToShow.first?.displayName
        ?? conversation.otherParticipant?.displayName
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
      let count = conversationParticipantsToShow.count
      if count > 1 {
        return "\(count) participants"
      }
      return nil
    }
  }

  private var conversationParticipantsToShow: [ConvexConversationParticipant] {
    guard let participants = conversation?.participants else { return [] }
    let filtered = participants.filter { !isCurrentUser($0) }
    return filtered.isEmpty ? participants : filtered
  }

  var body: some View {
    List {
      if case .channel = source {
        Section {
          headerCard
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
      }

      if case .conversation = source {
        conversationUserDetailsTopSection
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
  private var conversationUserDetailsTopSection: some View {
    let participants = conversationParticipantsToShow

    Section {
      if isLoading && participants.isEmpty {
        ProgressView()
      } else if participants.isEmpty {
        Text("No user details loaded")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(participants, id: \.stackUserId) { participant in
          ParticipantInlineProfileView(
            participant: participant,
            staff: participantStaffDetails[participant.stackUserId],
            onCall: { phone in
              if let url = phoneURL(phone) { openURL(url) }
            },
            onSMS: { phone in
              if let url = smsURL(phone) { openURL(url) }
            },
            onEmail: { email in
              if let url = emailURL(email) { openURL(url) }
            }
          )
          .padding(.vertical, 8)
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
        await loadParticipantStaffIds(for: summary.participants ?? [])
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

  private func staffDetailId(for participant: ConvexConversationParticipant) -> String {
    participantStaffIds[participant.stackUserId] ?? participant.stackUserId
  }

  private func isCurrentUser(_ participant: ConvexConversationParticipant) -> Bool {
    let participantId = participant.stackUserId.trimmingCharacters(in: .whitespacesAndNewlines)

    if participantId == authStore.viewer?.subject || participantId == authStore.currentSession?.user._id {
      return true
    }

    let currentName = authStore.currentUserLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !currentName.isEmpty && normalizedName(participant.displayName) == normalizedName(currentName)
  }

  @MainActor
  private func loadParticipantStaffIds(for participants: [ConvexConversationParticipant]) async {
    guard !participants.isEmpty, let token = authStore.currentSession?.token else { return }

    do {
      let staff = try await HRConvexAPIService.listAllStaff(token: token)
      var resolved: [String: String] = [:]

      for participant in participants {
        if let match = staff.first(where: { item in
          staffItem(item, matches: participant)
        }) {
          resolved[participant.stackUserId] = match._id
        }
      }

      participantStaffIds = resolved
      await loadParticipantStaffDetails(for: participants)
    } catch {
      // Keep navigation working with the original participant id if directory lookup is unavailable.
    }
  }

  @MainActor
  private func loadParticipantStaffDetails(for participants: [ConvexConversationParticipant]) async {
    guard let token = authStore.currentSession?.token else { return }

    var details = participantStaffDetails
    for participant in participants where !isCurrentUser(participant) {
      guard details[participant.stackUserId] == nil else { continue }
      do {
        let staff = try await HRConvexAPIService.getStaffDetail(
          token: token,
          id: staffDetailId(for: participant)
        )
        details[participant.stackUserId] = staff
      } catch {
        continue
      }
    }
    participantStaffDetails = details
  }

  private func staffItem(_ item: ConvexStaffListItem, matches participant: ConvexConversationParticipant) -> Bool {
    let participantId = participant.stackUserId.trimmingCharacters(in: .whitespacesAndNewlines)
    let participantName = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

    if item._id == participantId || item.employeeId == participantId {
      return true
    }

    if normalizedPhone(item.phone) == normalizedPhone(participantId) {
      return true
    }

    if normalizedName(item.displayName) == normalizedName(participantName) {
      return true
    }

    return false
  }

  private func normalizedPhone(_ value: String?) -> String {
    let digits = (value ?? "").filter(\.isNumber)
    if digits.count > 10, digits.hasPrefix("91") {
      return String(digits.suffix(10))
    }
    return digits
  }

  private func normalizedName(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private func phoneURL(_ phone: String) -> URL? {
    let digits = phone.filter { $0.isNumber || $0 == "+" }
    guard !digits.isEmpty else { return nil }
    return URL(string: "tel:\(digits)")
  }

  private func smsURL(_ phone: String) -> URL? {
    let digits = phone.filter { $0.isNumber || $0 == "+" }
    guard !digits.isEmpty else { return nil }
    return URL(string: "sms:\(digits)")
  }

  private func emailURL(_ email: String) -> URL? {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return URL(string: "mailto:\(trimmed)")
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

private struct ParticipantInlineProfileView: View {
  let participant: ConvexConversationParticipant
  let staff: ConvexStaffDetail?
  let onCall: (String) -> Void
  let onSMS: (String) -> Void
  let onEmail: (String) -> Void

  private var displayName: String {
    staff?.displayName ?? participant.displayName
  }

  var body: some View {
    VStack(spacing: 14) {
      profileHeader

      if let staff {
        contactActions(for: staff)
        detailGroup {
          detailRow("Phone", staff.phone)
          detailRow("Email", staff.email)
          detailRow("Gender", staff.gender)
          detailRow("Designation", staff.designation)
          detailRow("Department", staff.department)
          detailRow("Employee ID", staff.employeeId)
        }
      } else {
        ParticipantDetailsSkeleton()
      }
    }
  }

  private var profileHeader: some View {
    VStack(spacing: 10) {
      AvatarView(urlString: staff?.photo ?? participant.profilePhoto, initials: initials, size: 74)

      Text(displayName)
        .font(.title3.weight(.semibold))
        .multilineTextAlignment(.center)

      if let subtitle = staff?.headerSubtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      if let staff {
        Text(staff.isActive ? "Active" : "Inactive")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background((staff.isActive ? Color.green : Color.red).opacity(0.15), in: Capsule())
          .foregroundStyle(staff.isActive ? Color.green : Color.red)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private func contactActions(for staff: ConvexStaffDetail) -> some View {
    HStack(spacing: 10) {
      if let phone = staff.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        contactButton(title: "Call", systemImage: "phone.fill", color: .green) {
          onCall(phone)
        }
        contactButton(title: "SMS", systemImage: "message.fill", color: .blue) {
          onSMS(phone)
        }
      }

      if let email = staff.email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        contactButton(title: "Email", systemImage: "envelope.fill", color: .orange) {
          onEmail(email)
        }
      }
    }
  }

  private func contactButton(
    title: String,
    systemImage: String,
    color: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.title3)
        Text(title)
          .font(.caption.weight(.medium))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .foregroundStyle(color)
    }
    .buttonStyle(.plain)
  }

  private func detailGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
      content()
    }
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  @ViewBuilder
  private func detailRow(_ title: String, _ value: String?) -> some View {
    if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      HStack(alignment: .top, spacing: 12) {
        Text(title)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(width: 104, alignment: .leading)

        Text(value)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)

      Divider()
        .padding(.leading, 12)
    }
  }

  private var initials: String {
    let parts = displayName
      .split(whereSeparator: { !$0.isLetter })
      .prefix(2)
      .compactMap(\.first)
    let result = String(parts).uppercased()
    return result.isEmpty ? "?" : result
  }
}

private struct ParticipantDetailsSkeleton: View {
  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        ForEach(0..<3, id: \.self) { _ in
          SkeletonBlock()
            .frame(height: 54)
        }
      }

      VStack(spacing: 0) {
        ForEach(0..<4, id: \.self) { index in
          HStack(spacing: 12) {
            SkeletonBlock()
              .frame(width: 88, height: 12)
            SkeletonBlock()
              .frame(height: 12)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 10)

          if index < 3 {
            Divider()
              .padding(.leading, 12)
          }
        }
      }
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .allowsHitTesting(false)
  }
}

private struct SkeletonBlock: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(Color(.systemGray5))
      .redacted(reason: .placeholder)
  }
}

private struct AvatarView: View {
  let urlString: String?
  let initials: String
  var size: CGFloat = 36

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
              .font(.system(size: max(12, size * 0.34), weight: .semibold))
              .foregroundStyle(.white)
          }
        }
      } else {
        Text(initials)
          .font(.system(size: max(12, size * 0.34), weight: .semibold))
          .foregroundStyle(.white)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }

  private var url: URL? {
    guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return URL(string: urlString)
  }
}
