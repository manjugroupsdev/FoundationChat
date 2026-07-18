import SwiftUI

struct ConversationRowView: View {
  let conversation: Conversation

  private var title: String {
    conversation.participantDisplayName
      ?? conversation.summary
      ?? "New conversation"
  }

  private var subtitle: String {
    if let lastMessage = conversation.sortedMessages.last {
      let text = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty {
        if ChatLocationPayload(messageBody: text) != nil {
          return "Current Location"
        }
        return text
      }
      if lastMessage.attachementType == "image"
        || lastMessage.attachementMimeType?.hasPrefix("image/") == true
      {
        return "Photo"
      }
      if lastMessage.attachementType == "video"
        || lastMessage.attachementMimeType?.hasPrefix("video/") == true
      {
        return "Video"
      }
      if let name = lastMessage.attachementFileName, !name.isEmpty {
        return name
      }
      if let title = lastMessage.attachementTitle, !title.isEmpty {
        return title
      }
      return "Attachment"
    }
    return "No messages yet"
  }

  private var formattedTime: String? {
    guard let timestamp = conversation.sortedMessages.last?.timestamp else { return nil }
    return timestamp.formatted(date: .omitted, time: .shortened)
  }

  private var initials: String {
    let source = title.split(whereSeparator: { !$0.isLetter }).prefix(2)
    let built = String(source.compactMap(\.first)).uppercased()
    return built.isEmpty ? "DM" : built
  }

  var body: some View {
    HStack(spacing: 12) {
      ConversationAvatarView(initials: initials, source: conversation.participantAvatarSource)

      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(FoundationChatTheme.ink)
            .lineLimit(1)

          Spacer(minLength: 8)

          if let formattedTime {
            Text(formattedTime)
              .font(.system(size: 14, weight: .regular))
              .foregroundStyle(FoundationChatTheme.ink)
          }
        }

        HStack(spacing: 8) {
          subtitleView

          Spacer(minLength: 8)

          if conversation.unreadCountValue > 0 {
            Text(conversation.unreadCountValue > 99 ? "99+" : "\(conversation.unreadCountValue)")
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

extension ConversationRowView {
  @ViewBuilder
  private var subtitleView: some View {
    HStack(spacing: 6) {
      if subtitle == "Current Location" || subtitle.localizedCaseInsensitiveContains("[LOCATION:") {
        Image(systemName: "location.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Color.black)
      } else if subtitle.localizedCaseInsensitiveContains("call") {
        Image(systemName: subtitle.localizedCaseInsensitiveContains("video") ? "video.fill" : "phone.arrow.up.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.52))
      } else if subtitle.localizedCaseInsensitiveContains(".") || subtitle == "Attachment" {
        Image(systemName: "doc.text.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.52))
      }

      Text(subtitle)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(Color(red: 0.45, green: 0.46, blue: 0.48))
        .lineLimit(1)
    }
  }
}

struct ConversationAvatarView: View {
  @Environment(AuthStore.self) private var authStore
  let initials: String
  let source: String?
  var size: CGFloat = 52
  @State private var resolvedURL: URL?

  var body: some View {
    ZStack {
      AvatarPlaceholder(initials: initials, size: size)

      if let resolvedURL {
        AsyncImage(url: resolvedURL) { phase in
          if case .success(let image) = phase {
            image
              .resizable()
              .scaledToFill()
          }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
          Circle()
            .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
      }
    }
    .task(id: source ?? "") {
      resolvedURL = await authStore.resolveProfilePhotoURL(source)
    }
  }
}

struct AvatarPlaceholder: View {
  let initials: String
  var size: CGFloat = 52

  var body: some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [
              Color(red: 0.93, green: 0.95, blue: 0.98),
              Color(red: 0.86, green: 0.90, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .frame(width: size, height: size)
        .overlay(
          Circle()
            .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )

      Text(initials)
        .font(.system(size: size * 0.35, weight: .semibold))
        .foregroundStyle(Color(red: 0.18, green: 0.42, blue: 0.78))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .accessibilityLabel(initials)
  }
}
