import SwiftUI
import Combine
import ConvexMobile

struct PostDetailView: View {
    let postId: String
    @Environment(AuthStore.self) private var authStore
    @State private var post: ConvexPost?
    @State private var comments: [PostComment] = []
    @State private var newComment = ""
    @State private var isLoadingPost = true
    @State private var isSendingComment = false
    @State private var showReactionPicker = false
    @State private var commentsCancellable: AnyCancellable?

    private let quickReactions = ["👍", "❤️", "🎉", "😂", "🔥", "👏"]

    var body: some View {
        Group {
            if let post {
                postContent(post)
            } else if isLoadingPost {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Post Not Found", systemImage: "newspaper")
            }
        }
        .navigationTitle(post?.title ?? "Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let post, (post.authorStackUserId == authStore.viewer?.subject || authStore.isAdmin) {
                Menu {
                    Button(role: .destructive) {
                        Task { await deletePost() }
                    } label: {
                        Label("Delete Post", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await loadPost()
            await subscribeToComments()
        }
    }

    private func postContent(_ post: ConvexPost) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Author
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(String((post.authorName ?? "?").prefix(1)).uppercased())
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.authorName ?? "Unknown")
                                .font(.subheadline.weight(.semibold))
                            Text(post.publishedDate, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if post.isPinned {
                            Label("Pinned", systemImage: "pin.fill")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }

                    // Title
                    if let title = post.title, !title.isEmpty {
                        Text(title)
                            .font(.title2.weight(.bold))
                    }

                    // Body
                    Text(post.body)
                        .font(.body)

                    // Images
                    if let imageUrls = post.imageUrls, !imageUrls.isEmpty {
                        ForEach(imageUrls, id: \.self) { urlString in
                            if let url = URL(string: urlString) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Rectangle().fill(Color(.systemGray5))
                                        .frame(height: 200)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                    Divider()

                    // Quick reactions
                    HStack(spacing: 12) {
                        ForEach(quickReactions, id: \.self) { emoji in
                            let reacted = post.reactionCounts?.first(where: { $0.emoji == emoji })?.hasReacted ?? false
                            let count = post.reactionCounts?.first(where: { $0.emoji == emoji })?.count ?? 0
                            Button {
                                Task { try? await authStore.addPostReaction(postId: post.id, emoji: emoji) }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(emoji)
                                        .font(.body)
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(reacted ? Color.accentColor : Color.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(reacted ? Color.accentColor.opacity(0.12) : Color(.systemGray6), in: Capsule())
                            }
                        }
                    }

                    Divider()

                    // Comments section
                    Text("Comments (\(comments.count))")
                        .font(.headline)

                    if comments.isEmpty {
                        Text("No comments yet. Be the first!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment, canDelete: comment.authorStackUserId == authStore.viewer?.subject || authStore.isAdmin) {
                                Task { try? await authStore.deletePostComment(commentId: comment.id) }
                            }
                        }
                    }
                }
                .padding()
            }

            // Comment input
            commentInputBar
        }
    }

    private var commentInputBar: some View {
        HStack(spacing: 10) {
            TextField("Add a comment...", text: $newComment, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20))

            Button {
                Task { await sendComment() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
            }
            .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingComment)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func loadPost() async {
        isLoadingPost = true
        do {
            post = try await authStore.fetchPostById(postId: postId)
            try? await authStore.markPostRead(postId: postId)
        } catch {}
        isLoadingPost = false
    }

    private func subscribeToComments() async {
        do {
            let publisher = try authStore.subscribePostComments(postId: postId)
            commentsCancellable = publisher.receive(on: DispatchQueue.main).sink(
                receiveCompletion: { _ in },
                receiveValue: { newComments in
                    if let newComments { self.comments = newComments }
                }
            )
        } catch {}
    }

    private func sendComment() async {
        let content = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isSendingComment = true
        newComment = ""
        do {
            try await authStore.addPostComment(postId: postId, content: content)
        } catch {}
        isSendingComment = false
    }

    private func deletePost() async {
        do {
            try await authStore.deletePost(postId: postId)
        } catch {}
    }
}

struct CommentRow: View {
    let comment: PostComment
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 28, height: 28)
                .overlay {
                    Text(String((comment.authorName ?? "?").prefix(1)).uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName ?? "Unknown")
                        .font(.caption.weight(.semibold))
                    Text(comment.createdDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(comment.content)
                    .font(.subheadline)
            }

            Spacer()

            if canDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
