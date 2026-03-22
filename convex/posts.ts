import { internalQuery, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

const ADMIN_STACK_USER_ID = "phone:+916369487527";

function toPublicUser(doc: any) {
  return {
    id: doc?._id ?? "",
    stackUserId: doc?.stackUserId ?? "",
    email: doc?.email ?? null,
    name: doc?.name ?? null,
    imageUrl: doc?.imageUrl ?? null,
  };
}

export const list = query({
  args: {
    sessionToken: v.string(),
    category: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();

    const allPosts = await ctx.db
      .query("posts")
      .withIndex("by_createdAt")
      .order("desc")
      .collect();

    const publishedPosts = allPosts.filter((post: any) => {
      if (post.publishedAt !== undefined && post.publishedAt !== null) {
        return post.publishedAt <= now;
      }
      return true;
    });

    const filtered = args.category
      ? publishedPosts.filter((post: any) => post.category === args.category)
      : publishedPosts;

    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((user: any) => [user.stackUserId, user])
    );

    const enriched = await Promise.all(
      filtered.map(async (post: any) => {
        const reactions = await ctx.db
          .query("postReactions")
          .withIndex("by_postId", (q: any) => q.eq("postId", post._id))
          .collect();

        const comments = await ctx.db
          .query("postComments")
          .withIndex("by_postId", (q: any) => q.eq("postId", post._id))
          .collect();

        const readReceipt = await ctx.db
          .query("postReadReceipts")
          .withIndex("by_stackUserId_postId", (q: any) =>
            q.eq("stackUserId", stackUserId).eq("postId", post._id)
          )
          .first();

        const reactionCountsMap: Record<string, number> = {};
        const userReactedEmojis = new Set<string>();
        for (const reaction of reactions) {
          reactionCountsMap[reaction.emoji] = (reactionCountsMap[reaction.emoji] || 0) + 1;
          if (reaction.stackUserId === stackUserId) {
            userReactedEmojis.add(reaction.emoji);
          }
        }
        const reactionCounts = Object.entries(reactionCountsMap).map(([emoji, count]) => ({
          emoji,
          count,
          hasReacted: userReactedEmojis.has(emoji),
        }));

        const imageUrls: string[] = [];
        if (post.imageStorageIds) {
          for (const storageId of post.imageStorageIds) {
            try {
              const url = await ctx.storage.getUrl(storageId as any);
              if (url) imageUrls.push(url);
            } catch {
              // skip missing storage
            }
          }
        }

        const authorDoc = usersByStackId.get(post.authorStackUserId);
        return {
          id: post._id,
          authorStackUserId: post.authorStackUserId,
          authorName: authorDoc?.name ?? authorDoc?.email ?? null,
          authorImageUrl: authorDoc?.imageUrl ?? null,
          title: post.title ?? null,
          body: post.body,
          imageUrls: imageUrls.length > 0 ? imageUrls : null,
          linkUrl: post.linkUrl ?? null,
          linkTitle: post.linkTitle ?? null,
          linkThumbnail: post.linkThumbnail ?? null,
          isPinned: post.isPinned,
          isAnnouncement: post.isAnnouncement,
          category: post.category ?? null,
          reactionCounts: reactionCounts.length > 0 ? reactionCounts : null,
          commentCount: comments.length,
          isRead: !!readReceipt,
          publishedAt: post.publishedAt ?? post.createdAt,
          createdAt: post.createdAt,
          updatedAt: post.updatedAt,
        };
      })
    );

    enriched.sort((a: any, b: any) => b.publishedAt - a.publishedAt);
    return enriched;
  },
});

export const getById = query({
  args: {
    sessionToken: v.string(),
    postId: v.id("posts"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const post = await ctx.db.get(args.postId);
    if (!post) {
      throw new Error("Post not found.");
    }

    const authorDoc = await ctx.db
      .query("users")
      .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", post.authorStackUserId))
      .first();

    const reactions = await ctx.db
      .query("postReactions")
      .withIndex("by_postId", (q: any) => q.eq("postId", post._id))
      .collect();

    const comments = await ctx.db
      .query("postComments")
      .withIndex("by_postId", (q: any) => q.eq("postId", post._id))
      .collect();

    const readReceipt = await ctx.db
      .query("postReadReceipts")
      .withIndex("by_stackUserId_postId", (q: any) =>
        q.eq("stackUserId", stackUserId).eq("postId", post._id)
      )
      .first();

    const reactionCountsMap: Record<string, number> = {};
    const userReactedEmojis = new Set<string>();
    for (const reaction of reactions) {
      reactionCountsMap[reaction.emoji] = (reactionCountsMap[reaction.emoji] || 0) + 1;
      if (reaction.stackUserId === stackUserId) {
        userReactedEmojis.add(reaction.emoji);
      }
    }
    const reactionCounts = Object.entries(reactionCountsMap).map(([emoji, count]) => ({
      emoji,
      count,
      hasReacted: userReactedEmojis.has(emoji),
    }));

    const imageUrls: string[] = [];
    if (post.imageStorageIds) {
      for (const storageId of post.imageStorageIds) {
        try {
          const url = await ctx.storage.getUrl(storageId);
          if (url) imageUrls.push(url);
        } catch {
          // skip missing storage
        }
      }
    }

    return {
      id: post._id,
      authorStackUserId: post.authorStackUserId,
      authorName: authorDoc?.name ?? authorDoc?.email ?? null,
      authorImageUrl: authorDoc?.imageUrl ?? null,
      title: post.title ?? null,
      body: post.body,
      imageUrls: imageUrls.length > 0 ? imageUrls : null,
      linkUrl: post.linkUrl ?? null,
      linkTitle: post.linkTitle ?? null,
      linkThumbnail: post.linkThumbnail ?? null,
      isPinned: post.isPinned,
      isAnnouncement: post.isAnnouncement,
      category: post.category ?? null,
      scheduledAt: post.scheduledAt ?? null,
      reactionCounts: reactionCounts.length > 0 ? reactionCounts : null,
      commentCount: comments.length,
      isRead: !!readReceipt,
      publishedAt: post.publishedAt ?? post.createdAt,
      createdAt: post.createdAt,
      updatedAt: post.updatedAt,
    };
  },
});

export const create = mutation({
  args: {
    sessionToken: v.string(),
    title: v.optional(v.string()),
    body: v.string(),
    imageStorageIds: v.optional(v.string()),
    linkUrl: v.optional(v.string()),
    linkTitle: v.optional(v.string()),
    linkThumbnail: v.optional(v.string()),
    isPinned: v.boolean(),
    isAnnouncement: v.boolean(),
    category: v.optional(v.string()),
    scheduledAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    if (stackUserId !== ADMIN_STACK_USER_ID) {
      throw new Error("Only admin can create posts.");
    }

    const now = Date.now();
    const isScheduledFuture = args.scheduledAt && args.scheduledAt > now;

    // Parse comma-separated storage IDs from iOS client
    const parsedImageStorageIds = args.imageStorageIds
      ? args.imageStorageIds.split(",").map((s) => s.trim()).filter(Boolean)
      : undefined;

    const postId = await ctx.db.insert("posts", {
      authorStackUserId: stackUserId,
      title: args.title?.trim() || undefined,
      body: args.body,
      imageStorageIds: parsedImageStorageIds,
      linkUrl: args.linkUrl?.trim() || undefined,
      linkTitle: args.linkTitle?.trim() || undefined,
      linkThumbnail: args.linkThumbnail?.trim() || undefined,
      isPinned: args.isPinned,
      isAnnouncement: args.isAnnouncement,
      category: args.category?.trim() || undefined,
      scheduledAt: args.scheduledAt,
      publishedAt: isScheduledFuture ? undefined : now,
      createdAt: now,
      updatedAt: now,
    });

    return { postId };
  },
});

export const update = mutation({
  args: {
    sessionToken: v.string(),
    postId: v.id("posts"),
    title: v.optional(v.string()),
    body: v.optional(v.string()),
    isPinned: v.optional(v.boolean()),
    isAnnouncement: v.optional(v.boolean()),
    category: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const post = await ctx.db.get(args.postId);
    if (!post) {
      throw new Error("Post not found.");
    }

    if (post.authorStackUserId !== stackUserId) {
      throw new Error("Only the author can update this post.");
    }

    const now = Date.now();
    const updates: any = { updatedAt: now };

    if (args.title !== undefined) updates.title = args.title.trim() || undefined;
    if (args.body !== undefined) updates.body = args.body;
    if (args.isPinned !== undefined) updates.isPinned = args.isPinned;
    if (args.isAnnouncement !== undefined) updates.isAnnouncement = args.isAnnouncement;
    if (args.category !== undefined) updates.category = args.category.trim() || undefined;

    await ctx.db.patch(args.postId, updates);

    return { updated: true };
  },
});

export const deletePost = mutation({
  args: {
    sessionToken: v.string(),
    postId: v.id("posts"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const post = await ctx.db.get(args.postId);
    if (!post) {
      throw new Error("Post not found.");
    }

    if (post.authorStackUserId !== stackUserId && stackUserId !== ADMIN_STACK_USER_ID) {
      throw new Error("Only the author or admin can delete this post.");
    }

    const reactions = await ctx.db
      .query("postReactions")
      .withIndex("by_postId", (q: any) => q.eq("postId", args.postId))
      .collect();
    for (const reaction of reactions) {
      await ctx.db.delete(reaction._id);
    }

    const comments = await ctx.db
      .query("postComments")
      .withIndex("by_postId", (q: any) => q.eq("postId", args.postId))
      .collect();
    for (const comment of comments) {
      await ctx.db.delete(comment._id);
    }

    const readReceipts = await ctx.db
      .query("postReadReceipts")
      .withIndex("by_postId", (q: any) => q.eq("postId", args.postId))
      .collect();
    for (const receipt of readReceipts) {
      await ctx.db.delete(receipt._id);
    }

    await ctx.db.delete(args.postId);

    return { deleted: true };
  },
});

export const addReaction = mutation({
  args: {
    sessionToken: v.string(),
    postId: v.id("posts"),
    emoji: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const post = await ctx.db.get(args.postId);
    if (!post) {
      throw new Error("Post not found.");
    }

    const existing = await ctx.db
      .query("postReactions")
      .withIndex("by_postId_stackUserId", (q: any) =>
        q.eq("postId", args.postId).eq("stackUserId", stackUserId)
      )
      .collect();

    const sameEmoji = existing.find((r: any) => r.emoji === args.emoji);
    if (sameEmoji) {
      await ctx.db.delete(sameEmoji._id);
      return { toggled: "removed" };
    }

    const now = Date.now();
    await ctx.db.insert("postReactions", {
      postId: args.postId,
      stackUserId,
      emoji: args.emoji,
      createdAt: now,
    });

    return { toggled: "added" };
  },
});

export const removeReaction = mutation({
  args: {
    sessionToken: v.string(),
    postId: v.id("posts"),
    emoji: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const existing = await ctx.db
      .query("postReactions")
      .withIndex("by_postId_stackUserId", (q: any) =>
        q.eq("postId", args.postId).eq("stackUserId", stackUserId)
      )
      .collect();

    const sameEmoji = existing.find((r: any) => r.emoji === args.emoji);
    if (sameEmoji) {
      await ctx.db.delete(sameEmoji._id);
    }

    return { removed: true };
  },
});

export const listReactions = query({
  args: {
    sessionToken: v.string(),
    postId: v.id("posts"),
  },
  handler: async (ctx, args) => {
    await requireSession(ctx, args.sessionToken);

    const reactions = await ctx.db
      .query("postReactions")
      .withIndex("by_postId", (q: any) => q.eq("postId", args.postId))
      .collect();

    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((user: any) => [user.stackUserId, user])
    );

    const grouped: Record<string, { emoji: string; count: number; users: any[] }> = {};
    for (const reaction of reactions) {
      if (!grouped[reaction.emoji]) {
        grouped[reaction.emoji] = { emoji: reaction.emoji, count: 0, users: [] };
      }
      grouped[reaction.emoji].count++;
      grouped[reaction.emoji].users.push(toPublicUser(usersByStackId.get(reaction.stackUserId)));
    }

    return Object.values(grouped);
  },
});

export const addComment = mutation({
  args: {
    sessionToken: v.string(),
    postId: v.id("posts"),
    content: v.string(),
    imageStorageId: v.optional(v.id("_storage")),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const post = await ctx.db.get(args.postId);
    if (!post) {
      throw new Error("Post not found.");
    }

    const content = args.content.trim();
    if (!content) {
      throw new Error("Comment cannot be empty.");
    }

    const now = Date.now();
    const commentId = await ctx.db.insert("postComments", {
      postId: args.postId,
      authorStackUserId: stackUserId,
      content,
      imageStorageId: args.imageStorageId,
      createdAt: now,
      updatedAt: now,
    });

    return { commentId };
  },
});

export const deleteComment = mutation({
  args: {
    sessionToken: v.string(),
    commentId: v.id("postComments"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const comment = await ctx.db.get(args.commentId);
    if (!comment) {
      throw new Error("Comment not found.");
    }

    if (comment.authorStackUserId !== stackUserId && stackUserId !== ADMIN_STACK_USER_ID) {
      throw new Error("Only the comment author or admin can delete this comment.");
    }

    await ctx.db.delete(args.commentId);

    return { deleted: true };
  },
});

export const listComments = query({
  args: {
    sessionToken: v.string(),
    postId: v.id("posts"),
  },
  handler: async (ctx, args) => {
    await requireSession(ctx, args.sessionToken);

    const comments = await ctx.db
      .query("postComments")
      .withIndex("by_postId", (q: any) => q.eq("postId", args.postId))
      .collect();

    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((user: any) => [user.stackUserId, user])
    );

    return comments.map((comment: any) => {
      const authorDoc = usersByStackId.get(comment.authorStackUserId);
      return {
        id: comment._id,
        postId: comment.postId,
        authorStackUserId: comment.authorStackUserId,
        authorName: authorDoc?.name ?? authorDoc?.email ?? null,
        authorImageUrl: authorDoc?.imageUrl ?? null,
        content: comment.content,
        imageUrl: comment.imageStorageId ? null : null, // resolved below if needed
        createdAt: comment.createdAt,
        updatedAt: comment.updatedAt,
      };
    });
  },
});

export const markRead = mutation({
  args: {
    sessionToken: v.string(),
    postId: v.id("posts"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const existing = await ctx.db
      .query("postReadReceipts")
      .withIndex("by_stackUserId_postId", (q: any) =>
        q.eq("stackUserId", stackUserId).eq("postId", args.postId)
      )
      .first();

    if (existing) {
      return { marked: true };
    }

    const now = Date.now();
    await ctx.db.insert("postReadReceipts", {
      postId: args.postId,
      stackUserId,
      readAt: now,
    });

    return { marked: true };
  },
});

export const getUnreadCount = query({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();

    const allPosts = await ctx.db
      .query("posts")
      .withIndex("by_createdAt")
      .collect();

    const publishedPosts = allPosts.filter((post: any) => {
      if (post.publishedAt !== undefined && post.publishedAt !== null) {
        return post.publishedAt <= now;
      }
      return true;
    });

    const readReceipts = await ctx.db
      .query("postReadReceipts")
      .withIndex("by_stackUserId_postId", (q: any) => q.eq("stackUserId", stackUserId))
      .collect();

    const readPostIds = new Set(readReceipts.map((r: any) => r.postId.toString()));
    const unreadCount = publishedPosts.filter(
      (post: any) => !readPostIds.has(post._id.toString())
    ).length;

    return { unreadCount };
  },
});

export const listAllInternal = internalQuery({
  handler: async (ctx) => {
    const posts = await ctx.db.query("posts").order("desc").collect();
    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((u: any) => [u.stackUserId, u])
    );
    return posts.map((post: any) => {
      const author = usersByStackId.get(post.authorStackUserId);
      return {
        id: post._id,
        authorStackUserId: post.authorStackUserId,
        authorName: author?.name ?? null,
        title: post.title ?? null,
        body: post.body,
        isPinned: post.isPinned,
        isAnnouncement: post.isAnnouncement,
        category: post.category ?? null,
        publishedAt: post.publishedAt ?? null,
        createdAt: post.createdAt,
      };
    });
  },
});
