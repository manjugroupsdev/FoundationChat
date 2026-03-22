import SwiftUI

struct NewConversationSheet: View {
  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  let onSelectUser: (DirectoryUser) async throws -> Void

  @State private var searchText = ""
  @State private var users: [DirectoryUser] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var startingUserID: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
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

        if isLoading, users.isEmpty {
          ProgressView("Loading users...")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if let errorMessage {
          ContentUnavailableView(
            "Could Not Load Users",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if users.isEmpty {
          ContentUnavailableView(
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? "No users found"
              : "No matching users",
            systemImage: "person.2"
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(users) { user in
            Button {
              Task {
                await selectUser(user)
              }
            } label: {
              HStack(spacing: 12) {
                Circle()
                  .fill(Color(.systemGray5))
                  .frame(width: 36, height: 36)
                  .overlay(
                    Text(String(user.displayName.prefix(1)).uppercased())
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(.primary)
                  )

                VStack(alignment: .leading, spacing: 2) {
                  Text(user.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                  if let email = user.email, email != user.displayName {
                    Text(email)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                }

                Spacer()

                if startingUserID == user.id {
                  ProgressView()
                }
              }
            }
            .buttonStyle(.plain)
            .disabled(startingUserID != nil)
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .navigationTitle("Start Conversation")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
      .task(id: searchText) {
        await loadUsers(search: searchText)
      }
    }
  }

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

  private func selectUser(_ user: DirectoryUser) async {
    startingUserID = user.id
    errorMessage = nil

    do {
      try await onSelectUser(user)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }

    startingUserID = nil
  }
}
