import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  users: defineTable({
    stackUserId: v.string(),
    email: v.optional(v.string()),
    name: v.optional(v.string()),
    imageUrl: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_stackUserId", ["stackUserId"]),

  authSessions: defineTable({
    sessionToken: v.string(),
    stackUserId: v.string(),
    phoneNumber: v.string(),
    createdAt: v.number(),
    updatedAt: v.number(),
    expiresAt: v.number(),
  })
    .index("by_sessionToken", ["sessionToken"])
    .index("by_stackUserId", ["stackUserId"]),

  otpChallenges: defineTable({
    phoneNumber: v.string(),
    code: v.string(),
    attempts: v.number(),
    maxAttempts: v.number(),
    expiresAt: v.number(),
    consumedAt: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_phoneNumber_createdAt", ["phoneNumber", "createdAt"]),

  conversations: defineTable({
    type: v.literal("direct"),
    pairKey: v.string(),
    participantStackUserIds: v.array(v.string()),
    createdByStackUserId: v.string(),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_pairKey", ["pairKey"]),

  messages: defineTable({
    conversationId: v.id("conversations"),
    senderStackUserId: v.string(),
    role: v.union(v.literal("user"), v.literal("assistant"), v.literal("system")),
    content: v.string(),
    attachmentType: v.optional(v.union(v.literal("image"), v.literal("video"), v.literal("file"))),
    attachmentStorageId: v.optional(v.id("_storage")),
    attachmentFileName: v.optional(v.string()),
    attachmentMimeType: v.optional(v.string()),
    attachmentTitle: v.optional(v.string()),
    attachmentDescription: v.optional(v.string()),
    attachmentThumbnail: v.optional(v.string()),
    replyToId: v.optional(v.string()),
    editedAt: v.optional(v.number()),
    isDeleted: v.optional(v.boolean()),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_conversation_createdAt", ["conversationId", "createdAt"]),

  userFiles: defineTable({
    ownerStackUserId: v.string(),
    attachmentType: v.union(v.literal("image"), v.literal("video"), v.literal("file")),
    attachmentStorageId: v.id("_storage"),
    attachmentFileName: v.string(),
    attachmentMimeType: v.optional(v.string()),
    attachmentTitle: v.optional(v.string()),
    attachmentDescription: v.optional(v.string()),
    attachmentThumbnail: v.optional(v.string()),
    folderId: v.optional(v.id("storageFolders")),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_ownerStackUserId", ["ownerStackUserId", "createdAt"])
    .index("by_ownerStackUserId_fileName", ["ownerStackUserId", "attachmentFileName"]),

  conversationReads: defineTable({
    conversationId: v.id("conversations"),
    stackUserId: v.string(),
    lastReadAt: v.number(),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_conversation_stackUserId", ["conversationId", "stackUserId"])
    .index("by_stackUserId", ["stackUserId"]),

  channels: defineTable({
    name: v.string(),
    description: v.optional(v.string()),
    createdByStackUserId: v.string(),
    pinnedMessageIds: v.optional(v.array(v.string())),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_createdAt", ["createdAt"])
    .index("by_createdByStackUserId", ["createdByStackUserId"]),

  channelMembers: defineTable({
    channelId: v.id("channels"),
    stackUserId: v.string(),
    role: v.union(v.literal("admin"), v.literal("member")),
    invitedByStackUserId: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_channelId", ["channelId"])
    .index("by_stackUserId", ["stackUserId"])
    .index("by_channelId_stackUserId", ["channelId", "stackUserId"]),

  channelMessages: defineTable({
    channelId: v.id("channels"),
    senderStackUserId: v.string(),
    content: v.string(),
    replyToId: v.optional(v.string()),
    editedAt: v.optional(v.number()),
    isDeleted: v.optional(v.boolean()),
    attachmentType: v.optional(v.union(v.literal("image"), v.literal("video"), v.literal("file"))),
    attachmentStorageId: v.optional(v.id("_storage")),
    attachmentFileName: v.optional(v.string()),
    attachmentMimeType: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_channelId_createdAt", ["channelId", "createdAt"])
    .index("by_createdAt", ["createdAt"]),

  pushTokens: defineTable({
    stackUserId: v.string(),
    apnsToken: v.string(),
    platform: v.literal("ios"),
    createdAt: v.number(),
    updatedAt: v.number(),
    lastSeenAt: v.number(),
  })
    .index("by_stackUserId", ["stackUserId"])
    .index("by_apnsToken", ["apnsToken"]),

  apnsProviderTokens: defineTable({
    cacheKey: v.string(),
    bearerToken: v.string(),
    issuedAt: v.number(),
    expiresAt: v.number(),
    updatedAt: v.number(),
  }).index("by_cacheKey", ["cacheKey"]),

  messageReactions: defineTable({
    messageId: v.string(),
    messageSource: v.union(v.literal("dm"), v.literal("channel")),
    stackUserId: v.string(),
    emoji: v.string(),
    createdAt: v.number(),
  })
    .index("by_messageId", ["messageId"])
    .index("by_messageId_stackUserId", ["messageId", "stackUserId"]),

  userPresence: defineTable({
    stackUserId: v.string(),
    status: v.union(v.literal("online"), v.literal("away"), v.literal("busy"), v.literal("offline")),
    customStatusText: v.optional(v.string()),
    customStatusEmoji: v.optional(v.string()),
    lastHeartbeatAt: v.number(),
    updatedAt: v.number(),
  }).index("by_stackUserId", ["stackUserId"]),

  notificationPreferences: defineTable({
    stackUserId: v.string(),
    targetType: v.union(v.literal("dm"), v.literal("channel")),
    targetId: v.string(),
    muteUntil: v.optional(v.number()),
    level: v.union(v.literal("all"), v.literal("mentions"), v.literal("none")),
    updatedAt: v.number(),
  })
    .index("by_stackUserId", ["stackUserId"])
    .index("by_stackUserId_target", ["stackUserId", "targetType", "targetId"]),

  posts: defineTable({
    authorStackUserId: v.string(),
    title: v.optional(v.string()),
    body: v.string(),
    imageStorageIds: v.optional(v.array(v.string())),
    linkUrl: v.optional(v.string()),
    linkTitle: v.optional(v.string()),
    linkThumbnail: v.optional(v.string()),
    isPinned: v.boolean(),
    isAnnouncement: v.boolean(),
    category: v.optional(v.string()),
    scheduledAt: v.optional(v.number()),
    publishedAt: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_createdAt", ["createdAt"])
    .index("by_authorStackUserId", ["authorStackUserId"])
    .index("by_publishedAt", ["publishedAt"]),

  postReactions: defineTable({
    postId: v.id("posts"),
    stackUserId: v.string(),
    emoji: v.string(),
    createdAt: v.number(),
  })
    .index("by_postId", ["postId"])
    .index("by_postId_stackUserId", ["postId", "stackUserId"]),

  postComments: defineTable({
    postId: v.id("posts"),
    authorStackUserId: v.string(),
    content: v.string(),
    imageStorageId: v.optional(v.id("_storage")),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_postId", ["postId"]),

  postReadReceipts: defineTable({
    postId: v.id("posts"),
    stackUserId: v.string(),
    readAt: v.number(),
  })
    .index("by_postId", ["postId"])
    .index("by_stackUserId_postId", ["stackUserId", "postId"]),

  storageFolders: defineTable({
    ownerStackUserId: v.string(),
    name: v.string(),
    parentFolderId: v.optional(v.id("storageFolders")),
    sharedWithStackUserIds: v.optional(v.array(v.string())),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_ownerStackUserId", ["ownerStackUserId"])
    .index("by_parentFolderId", ["parentFolderId"]),

  typingIndicators: defineTable({
    conversationId: v.optional(v.string()),
    channelId: v.optional(v.string()),
    stackUserId: v.string(),
    expiresAt: v.number(),
  })
    .index("by_conversationId", ["conversationId"])
    .index("by_channelId", ["channelId"]),

  userLocations: defineTable({
    stackUserId: v.string(),
    latitude: v.number(),
    longitude: v.number(),
    altitude: v.optional(v.number()),
    horizontalAccuracy: v.optional(v.number()),
    speed: v.optional(v.number()),
    heading: v.optional(v.number()),
    recordedAt: v.number(),
    createdAt: v.number(),
  })
    .index("by_stackUserId_recordedAt", ["stackUserId", "recordedAt"])
    .index("by_recordedAt", ["recordedAt"]),
});
