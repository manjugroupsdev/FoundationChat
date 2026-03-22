import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

function toPublicUser(doc: any) {
  return {
    id: doc?._id ?? "",
    stackUserId: doc?.stackUserId ?? "",
    email: doc?.email ?? null,
    name: doc?.name ?? null,
    imageUrl: doc?.imageUrl ?? null,
  };
}

export const addMessageReaction = mutation({
  args: {
    sessionToken: v.string(),
    messageId: v.string(),
    messageSource: v.union(v.literal("dm"), v.literal("channel")),
    emoji: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const existing = await ctx.db
      .query("messageReactions")
      .withIndex("by_messageId_stackUserId", (q: any) =>
        q.eq("messageId", args.messageId).eq("stackUserId", stackUserId)
      )
      .collect();

    const sameEmoji = existing.find(
      (r: any) => r.emoji === args.emoji && r.messageSource === args.messageSource
    );
    if (sameEmoji) {
      await ctx.db.delete(sameEmoji._id);
      return { toggled: "removed" };
    }

    const now = Date.now();
    await ctx.db.insert("messageReactions", {
      messageId: args.messageId,
      messageSource: args.messageSource,
      stackUserId,
      emoji: args.emoji,
      createdAt: now,
    });

    return { toggled: "added" };
  },
});

export const removeMessageReaction = mutation({
  args: {
    sessionToken: v.string(),
    messageId: v.string(),
    messageSource: v.union(v.literal("dm"), v.literal("channel")),
    emoji: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const existing = await ctx.db
      .query("messageReactions")
      .withIndex("by_messageId_stackUserId", (q: any) =>
        q.eq("messageId", args.messageId).eq("stackUserId", stackUserId)
      )
      .collect();

    const sameEmoji = existing.find(
      (r: any) => r.emoji === args.emoji && r.messageSource === args.messageSource
    );
    if (sameEmoji) {
      await ctx.db.delete(sameEmoji._id);
    }

    return { removed: true };
  },
});

export const listForMessage = query({
  args: {
    sessionToken: v.string(),
    messageId: v.string(),
    messageSource: v.union(v.literal("dm"), v.literal("channel")),
  },
  handler: async (ctx, args) => {
    await requireSession(ctx, args.sessionToken);

    const reactions = await ctx.db
      .query("messageReactions")
      .withIndex("by_messageId", (q: any) => q.eq("messageId", args.messageId))
      .collect();

    const filtered = reactions.filter((r: any) => r.messageSource === args.messageSource);

    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((user: any) => [user.stackUserId, user])
    );

    const grouped: Record<string, { emoji: string; count: number; users: any[] }> = {};
    for (const reaction of filtered) {
      if (!grouped[reaction.emoji]) {
        grouped[reaction.emoji] = { emoji: reaction.emoji, count: 0, users: [] };
      }
      grouped[reaction.emoji].count++;
      grouped[reaction.emoji].users.push(toPublicUser(usersByStackId.get(reaction.stackUserId)));
    }

    return Object.values(grouped);
  },
});
