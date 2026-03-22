import SwiftUI

struct PostCardView: View {
    let post: ConvexPost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author row
            HStack(spacing: 10) {
                authorAvatar
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(post.authorName ?? "Unknown")
                            .font(.subheadline.weight(.semibold))
                        if post.isAnnouncement {
                            Image(systemName: "megaphone.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(post.publishedDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let category = post.category {
                    Text(category)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray5), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                if !post.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }

            // Title
            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
            }

            // Body preview
            Text(post.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            // Images preview
            if let imageUrls = post.imageUrls, !imageUrls.isEmpty {
                imagePreview(imageUrls)
            }

            // Link preview
            if let linkUrl = post.linkUrl, !linkUrl.isEmpty {
                linkPreview
            }

            // Footer: reactions + comments
            HStack(spacing: 16) {
                if let reactions = post.reactionCounts, !reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(reactions.prefix(3)) { reaction in
                            Text(reaction.emoji)
                                .font(.caption)
                        }
                        let total = reactions.reduce(0) { $0 + $1.count }
                        Text("\(total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if post.commentCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .font(.caption)
                        Text("\(post.commentCount)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var authorAvatar: some View {
        Group {
            if let imageUrl = post.authorImageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color(.systemGray4))
            .overlay {
                Text(String((post.authorName ?? "?").prefix(1)).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private func imagePreview(_ urls: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(urls.prefix(4), id: \.self) { urlString in
                if let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Rectangle().fill(Color(.systemGray5))
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        case .empty:
                            Rectangle().fill(Color(.systemGray5))
                                .overlay { ProgressView() }
                        @unknown default:
                            Rectangle().fill(Color(.systemGray5))
                        }
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var linkPreview: some View {
        HStack(spacing: 10) {
            if let thumbnail = post.linkThumbnail, let url = URL(string: thumbnail) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color(.systemGray5))
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                if let linkTitle = post.linkTitle {
                    Text(linkTitle)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                Text(post.linkUrl ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }
}
