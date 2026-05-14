import SwiftUI

struct ConversationSearchView: View {
  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let conversationID: String?
  let channelID: String?
  let title: String
  let onSelectMessage: ((ConvexChatMessage) -> Void)?

  init(
    conversationID: String? = nil,
    channelID: String? = nil,
    title: String = "Search",
    onSelectMessage: ((ConvexChatMessage) -> Void)? = nil
  ) {
    self.conversationID = conversationID
    self.channelID = channelID
    self.title = title
    self.onSelectMessage = onSelectMessage
  }

  @State private var query: String = ""
  @State private var results: [ConvexChatMessage] = []
  @State private var isSearching = false
  @State private var errorMessage: String?
  @State private var searchTask: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 0) {
      searchField
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)

      Divider()

      Group {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContentUnavailableView(
            "Search messages",
            systemImage: "magnifyingglass",
            description: Text("Find messages, files, and links in this conversation.")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isSearching, results.isEmpty {
          ProgressView("Searching...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
          ContentUnavailableView(
            "Search failed",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
          ContentUnavailableView(
            "No matches",
            systemImage: "magnifyingglass",
            description: Text("No messages match \"\(query)\".")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(results) { message in
            Button {
              onSelectMessage?(message)
              dismiss()
            } label: {
              SearchResultRow(message: message, query: query)
            }
            .buttonStyle(.plain)
            .listRowSeparator(.visible)
          }
          .listStyle(.plain)
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: query) { _, newValue in
      scheduleSearch(for: newValue)
    }
    .onDisappear {
      searchTask?.cancel()
      searchTask = nil
    }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Search messages", text: $query)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  @MainActor
  private func scheduleSearch(for newQuery: String) {
    searchTask?.cancel()
    let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      results = []
      errorMessage = nil
      isSearching = false
      return
    }

    isSearching = true
    errorMessage = nil

    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }

      do {
        let found = try await authStore.searchMessages(
          query: trimmed,
          conversationID: conversationID,
          channelID: channelID
        )
        guard !Task.isCancelled else { return }
        results = found
        isSearching = false
      } catch {
        guard !Task.isCancelled else { return }
        results = []
        errorMessage = error.localizedDescription
        isSearching = false
      }
    }
  }
}

private struct SearchResultRow: View {
  let message: ConvexChatMessage
  let query: String

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(message.senderName ?? "Unknown")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(Self.dateFormatter.string(from: message.timestamp))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(highlightedBody)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .lineLimit(3)
    }
    .padding(.vertical, 6)
  }

  private var highlightedBody: AttributedString {
    let body = message.content.isEmpty ? "(attachment)" : message.content
    var attributed = AttributedString(body)
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return attributed }

    let lowerBody = body.lowercased()
    let lowerQuery = trimmedQuery.lowercased()
    var searchRange = lowerBody.startIndex..<lowerBody.endIndex

    while let range = lowerBody.range(of: lowerQuery, options: [], range: searchRange) {
      if let attributedRange = Range(range, in: attributed) {
        attributed[attributedRange].backgroundColor = .yellow.opacity(0.4)
        attributed[attributedRange].font = .subheadline.weight(.semibold)
      }
      searchRange = range.upperBound..<lowerBody.endIndex
    }

    return attributed
  }
}
