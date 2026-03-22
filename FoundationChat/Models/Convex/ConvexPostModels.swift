import Foundation

struct ConvexPost: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let authorStackUserId: String
    let authorName: String?
    let authorImageUrl: String?
    let title: String?
    let body: String
    let imageUrls: [String]?
    let linkUrl: String?
    let linkTitle: String?
    let linkThumbnail: String?
    let isPinned: Bool
    let isAnnouncement: Bool
    let category: String?
    let reactionCounts: [ReactionCount]?
    let commentCount: Int
    let isRead: Bool
    let publishedAt: Double?
    let createdAt: Double
    let updatedAt: Double

    var publishedDate: Date {
        Date(timeIntervalSince1970: (publishedAt ?? createdAt) / 1000)
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000)
    }
}

struct ReactionCount: Decodable, Equatable, Sendable, Identifiable {
    let emoji: String
    let count: Int
    let hasReacted: Bool

    var id: String { emoji }
}

struct PostComment: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let postId: String
    let authorStackUserId: String
    let authorName: String?
    let authorImageUrl: String?
    let content: String
    let imageUrl: String?
    let createdAt: Double
    let updatedAt: Double

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000)
    }
}

struct PostReactionDetail: Decodable, Identifiable, Equatable, Sendable {
    let emoji: String
    let count: Int
    let users: [ReactionUser]

    var id: String { emoji }
}

struct ReactionUser: Decodable, Equatable, Sendable, Identifiable {
    let stackUserId: String
    let name: String?

    var id: String { stackUserId }
    var displayName: String { name ?? stackUserId }
}

struct CreatePostResult: Decodable, Sendable {
    let postId: String
}

struct DeletePostResult: Decodable, Sendable {
    let deleted: Bool
}

struct PostReactionResult: Decodable, Sendable {
    let added: Bool?
    let removed: Bool?
}

struct AddCommentResult: Decodable, Sendable {
    let commentId: String
}

struct DeleteCommentResult: Decodable, Sendable {
    let deleted: Bool
}

struct MarkPostReadResult: Decodable, Sendable {
    let marked: Bool
}

struct UnreadPostCount: Decodable, Sendable {
    let count: Int
}
