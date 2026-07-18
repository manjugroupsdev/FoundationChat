import PhotosUI
import SwiftUI
import UIKit

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
  let onChannelExited: (() -> Void)?

  init(
    source: Source,
    initialDisplayName: String? = nil,
    onPinToggle: ((Bool) -> Void)? = nil,
    onChannelExited: (() -> Void)? = nil
  ) {
    self.source = source
    self.initialDisplayName = initialDisplayName
    self.onPinToggle = onPinToggle
    self.onChannelExited = onChannelExited
  }

  @State private var conversation: ConvexConversationSummary?
  @State private var channel: ChannelSummary?
  @State private var members: [ChannelMember] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var isMuted: Bool = false
  @State private var isMutating: Bool = false
  @State private var showLeaveConfirm: Bool = false
  @State private var showDeleteConfirm: Bool = false
  @State private var showMediaSheet = false
  @State private var showSearchSheet = false
  @State private var showEditGroupSheet = false
  @State private var showAddMemberSheet = false
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var isUploadingPhoto = false
  @State private var selectedMemberForActions: ChannelMember?
  @State private var showMemberActions = false
  @State private var memberToRemove: ChannelMember?
  @State private var showRemoveMemberConfirm = false
  @State private var memberActionID: String?
  @State private var participantStaffIds: [String: String] = [:]
  @State private var participantStaffDetails: [String: ConvexStaffDetail] = [:]

  private var displayName: String {
    if case .channel = source, let channel {
      return channel.type?.lowercased() == "public" ? "#\(channel.name)" : channel.name
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
      let count = members.isEmpty ? channel?.memberCount : members.count
      if let count {
        return "Group · \(count) member\(count == 1 ? "" : "s")"
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

  private var channelID: String? {
    guard case .channel(let id, _) = source else { return nil }
    return id
  }

  private var currentUserIDs: Set<String> {
    let values = [
      authStore.viewer?.subject,
      authStore.currentSession?.user._id,
      authStore.currentSession?.user.staffId,
      authStore.currentSession?.user.employeeId,
      authStore.currentSession?.user.phone,
    ]

    return Set(values.compactMap { value in
      let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed?.isEmpty == false ? trimmed : nil
    })
  }

  private var currentChannelMember: ChannelMember? {
    members.first { member in
      currentUserIDs.contains(member.stackUserId) || currentUserIDs.contains(member.id)
    }
  }

  private var canManageChannel: Bool {
    guard case .channel = source else { return false }
    let role = (currentChannelMember?.role ?? channel?.role)?.lowercased()
    if role == "admin" || role == "owner" { return true }
    if let createdBy = channel?.createdBy, currentUserIDs.contains(createdBy) { return true }
    return false
  }

  private var isCurrentUserChannelCreator: Bool {
    guard let createdBy = channel?.createdBy else { return false }
    return currentUserIDs.contains(createdBy)
  }

  private var isAloneChannelCreator: Bool {
    guard isCurrentUserChannelCreator, !members.isEmpty else { return false }
    return members.allSatisfy(isCurrentChannelMember)
  }

  private var existingMemberIDs: Set<String> {
    Set(members.flatMap { member in
      [member.id, member.staffId].compactMap { $0 }
    })
  }

  private var sortedChannelMembers: [ChannelMember] {
    members.sorted { lhs, rhs in
      let lhsRank = memberSortRank(lhs)
      let rhsRank = memberSortRank(rhs)
      if lhsRank != rhsRank { return lhsRank < rhsRank }
      return memberDisplayName(lhs).localizedCaseInsensitiveCompare(memberDisplayName(rhs)) == .orderedAscending
    }
  }

  private func memberSortRank(_ member: ChannelMember) -> Int {
    if isCurrentChannelMember(member) { return 0 }
    if normalizedRole(member.role) == "admin" { return 1 }
    return 2
  }

  private func normalizedRole(_ role: String?) -> String {
    role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "member"
  }

  private func memberDisplayName(_ member: ChannelMember?) -> String {
    guard let member else { return "Member" }
    if isCurrentChannelMember(member) { return "You" }
    let name = member.staffName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return name?.isEmpty == false ? name! : member.id
  }

  private func isCurrentChannelMember(_ member: ChannelMember) -> Bool {
    currentUserIDs.contains(member.stackUserId) || currentUserIDs.contains(member.id)
  }

  private func isChannelCreator(_ member: ChannelMember) -> Bool {
    guard let createdBy = channel?.createdBy else { return false }
    return member.staffId == createdBy || member.id == createdBy
  }

  private func canManageMember(_ member: ChannelMember) -> Bool {
    canManageChannel && !isCurrentChannelMember(member) && !isChannelCreator(member)
  }

  @ViewBuilder
  private func memberManagementButtons(for member: ChannelMember) -> some View {
    if normalizedRole(member.role) == "admin" {
      Button("Dismiss as Admin") {
        Task { await setRole("member", for: member) }
      }
    } else {
      Button("Make Group Admin") {
        Task { await setRole("admin", for: member) }
      }
    }

    Button("Remove from Group", role: .destructive) {
      memberToRemove = member
      showRemoveMemberConfirm = true
    }
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

        if case .channel = source, canManageChannel {
          Button {
            showEditGroupSheet = true
          } label: {
            InfoActionRow(systemImage: "pencil", tint: .orange, title: "Edit Group")
          }

          Button {
            showAddMemberSheet = true
          } label: {
            InfoActionRow(systemImage: "person.badge.plus", tint: .green, title: "Add Member")
          }
        }
      }

      if case .channel = source {
        channelDescriptionSection
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
            Label("Exit Group", systemImage: "rectangle.portrait.and.arrow.right")
              .foregroundStyle(.red)
          }

          if isAloneChannelCreator {
            Button(role: .destructive) {
              showDeleteConfirm = true
            } label: {
              Label("Delete Group", systemImage: "trash")
                .foregroundStyle(.red)
            }
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
      Button("Exit Group", role: .destructive) {
        Task { await leaveChannel() }
      }
    } message: {
      Text("You'll stop receiving messages from \"\(displayName)\".")
    }
    .alert("Delete Group?", isPresented: $showDeleteConfirm) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        Task { await deleteChannel() }
      }
    } message: {
      Text("\"\(displayName)\" and its message history will be permanently deleted.")
    }
    .alert("Remove Member?", isPresented: $showRemoveMemberConfirm, presenting: memberToRemove) { member in
      Button("Cancel", role: .cancel) {}
      Button("Remove", role: .destructive) {
        Task { await removeMember(member) }
      }
    } message: { member in
      Text("\(memberDisplayName(member)) will no longer see this group's messages.")
    }
    .confirmationDialog(
      memberDisplayName(selectedMemberForActions),
      isPresented: $showMemberActions,
      titleVisibility: .visible
    ) {
      if let member = selectedMemberForActions {
        if normalizedRole(member.role) == "admin" {
          Button("Dismiss as Admin") {
            Task { await setRole("member", for: member) }
          }
        } else {
          Button("Make Group Admin") {
            Task { await setRole("admin", for: member) }
          }
        }

        Button("Remove from Group", role: .destructive) {
          memberToRemove = member
          showRemoveMemberConfirm = true
        }
      }
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
    .sheet(isPresented: $showEditGroupSheet) {
      NavigationStack {
        EditGroupSheet(
          name: displayName.replacingOccurrences(of: "#", with: ""),
          description: channel?.description ?? "",
          onSave: { name, description in
            await updateGroup(name: name, description: description)
          }
        )
      }
    }
    .sheet(isPresented: $showAddMemberSheet) {
      if let channelID {
        InviteMemberSheet(channelID: channelID, excludedMemberIds: existingMemberIDs) {
          await load()
        }
      }
    }
    .onChange(of: selectedPhotoItem) { _, newValue in
      guard let newValue else { return }
      Task { await uploadGroupPhoto(from: newValue) }
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
      ZStack(alignment: .bottomTrailing) {
        AvatarView(urlString: channel?.avatarUrl, initials: initials, size: 96)

        if case .channel = source, canManageChannel {
          PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Image(systemName: isUploadingPhoto ? "arrow.triangle.2.circlepath" : "camera.fill")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 34, height: 34)
              .background(Color.blue, in: Circle())
              .overlay(
                Circle()
                  .stroke(Color(.systemGroupedBackground), lineWidth: 3)
              )
          }
          .disabled(isUploadingPhoto)
        }

        if isUploadingPhoto {
          Circle()
            .fill(.black.opacity(0.35))
            .frame(width: 96, height: 96)
          ProgressView()
            .tint(.white)
            .frame(width: 96, height: 96)
        }
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
  private var channelDescriptionSection: some View {
    let description = channel?.description?.trimmingCharacters(in: .whitespacesAndNewlines)

    Section("Description") {
      Text(description?.isEmpty == false ? description! : (canManageChannel ? "Add group description" : "No description"))
        .font(.subheadline)
        .foregroundStyle(description?.isEmpty == false ? .primary : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
        ForEach(sortedChannelMembers) { member in
          ChannelMemberInfoRow(
            member: member,
            initials: memberInitials(member),
            isCurrentUser: isCurrentChannelMember(member),
            isCreator: isChannelCreator(member),
            canManage: canManageMember(member),
            isBusy: memberActionID == member.id
          )
          .contentShape(Rectangle())
          .onTapGesture {
            guard canManageMember(member) else { return }
            selectedMemberForActions = member
            showMemberActions = true
          }
          .contextMenu {
            if canManageMember(member) {
              memberManagementButtons(for: member)
            }
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canManageMember(member) {
              Button(role: .destructive) {
                memberToRemove = member
                showRemoveMemberConfirm = true
              } label: {
                Label("Remove", systemImage: "person.crop.circle.badge.minus")
              }

              Button {
                Task {
                  await setRole(normalizedRole(member.role) == "admin" ? "member" : "admin", for: member)
                }
              } label: {
                Label(normalizedRole(member.role) == "admin" ? "Dismiss" : "Admin", systemImage: "person.badge.key")
              }
              .tint(.blue)
            }
          }
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
    let result = String(parts).uppercased()
    return result.isEmpty ? "?" : result
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
    isMutating = true
    errorMessage = nil
    defer { isMutating = false }

    do {
      try await authStore.leaveChannel(channelID: id)
      dismiss()
      onChannelExited?()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func deleteChannel() async {
    guard let channelID else { return }
    isMutating = true
    errorMessage = nil
    defer { isMutating = false }

    do {
      try await authStore.deleteChannel(channelID: channelID)
      dismiss()
      onChannelExited?()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func updateGroup(name: String, description: String) async {
    guard let channelID else { return }
    isMutating = true
    errorMessage = nil
    defer { isMutating = false }

    do {
      try await authStore.updateChannel(
        channelID: channelID,
        name: name,
        description: description
      )
      showEditGroupSheet = false
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func setRole(_ role: String, for member: ChannelMember) async {
    guard let channelID else { return }
    memberActionID = member.id
    errorMessage = nil
    defer { memberActionID = nil }

    do {
      try await authStore.setChannelMemberRole(
        channelID: channelID,
        memberStackUserID: member.stackUserId,
        role: role
      )
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func removeMember(_ member: ChannelMember) async {
    guard let channelID else { return }
    memberActionID = member.id
    errorMessage = nil
    defer {
      memberActionID = nil
      memberToRemove = nil
    }

    do {
      try await authStore.removeMember(channelID: channelID, memberStackUserID: member.stackUserId)
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func uploadGroupPhoto(from item: PhotosPickerItem) async {
    guard let channelID else { return }
    isUploadingPhoto = true
    errorMessage = nil
    defer {
      isUploadingPhoto = false
      selectedPhotoItem = nil
    }

    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        throw AuthStoreError.invalidUploadURL
      }

      let uploadData: Data
      if let image = UIImage(data: data), let jpegData = image.jpegData(compressionQuality: 0.86) {
        uploadData = jpegData
      } else {
        uploadData = data
      }

      try await authStore.uploadChannelAvatar(channelID: channelID, imageData: uploadData)
      await load()
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

private struct ChannelMemberInfoRow: View {
  let member: ChannelMember
  let initials: String
  let isCurrentUser: Bool
  let isCreator: Bool
  let canManage: Bool
  let isBusy: Bool

  private var displayName: String {
    if isCurrentUser { return "You" }
    let name = member.staffName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return name?.isEmpty == false ? name! : member.id
  }

  private var subtitle: String? {
    let designation = member.staffDesignation?.trimmingCharacters(in: .whitespacesAndNewlines)
    if designation?.isEmpty == false { return designation }
    let role = member.staffRole?.trimmingCharacters(in: .whitespacesAndNewlines)
    if role?.isEmpty == false { return role }
    return nil
  }

  private var roleLabel: String? {
    if isCreator { return "Creator" }
    if member.role?.lowercased() == "admin" { return "Admin" }
    return nil
  }

  var body: some View {
    HStack(spacing: 12) {
      AvatarView(urlString: member.profilePhoto, initials: initials, size: 42)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(displayName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)

          if let roleLabel {
            Text(roleLabel)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(roleLabel == "Creator" ? .purple : .blue)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(
                (roleLabel == "Creator" ? Color.purple : Color.blue).opacity(0.12),
                in: Capsule()
              )
          }
        }

        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()

      if isBusy {
        ProgressView()
      } else if canManage {
        Image(systemName: "ellipsis")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct EditGroupSheet: View {
  @Environment(\.dismiss) private var dismiss

  let onSave: (String, String) async -> Void

  @State private var name: String
  @State private var description: String
  @State private var isSaving = false

  init(name: String, description: String, onSave: @escaping (String, String) async -> Void) {
    self._name = State(initialValue: name)
    self._description = State(initialValue: description)
    self.onSave = onSave
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    Form {
      Section("Group Name") {
        TextField("Group name", text: $name)
          .textInputAutocapitalization(.words)
      }

      Section("Description") {
        TextField("Group description", text: $description, axis: .vertical)
          .lineLimit(3...6)
      }
    }
    .navigationTitle("Edit Group")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
        .disabled(isSaving)
      }

      ToolbarItem(placement: .confirmationAction) {
        Button {
          Task {
            isSaving = true
            await onSave(trimmedName, description.trimmingCharacters(in: .whitespacesAndNewlines))
            isSaving = false
          }
        } label: {
          if isSaving {
            ProgressView()
          } else {
            Text("Save")
          }
        }
        .disabled(trimmedName.isEmpty || isSaving)
      }
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
