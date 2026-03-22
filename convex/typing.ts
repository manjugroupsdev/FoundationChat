import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

const TYPING_EXPIRY_MS = 5000; // 5 seconds

export const setTyping = mutation({
  args: {
    sessionToken: v.string(),
    conversationId: v.optional(v.string()),
    channelId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();
    const expiresAt = now + TYPING_EXPIRY_MS;

    if (args.conversationId) {
      const existing = await ctx.db
        .query("typingIndicators")
        .withIndex("by_conversationId", (q: any) => q.eq("conversationId", args.conversationId))
        .collect();

      const mine = existing.find((t: any) => t.stackUserId === stackUserId);
      if (mine) {
        await ctx.db.patch(mine._id, { expiresAt });
      } else {
        await ctx.db.insert("typingIndicators", {
          conversationId: args.conversationId,
          stackUserId,
          expiresAt,
        });
      }
    } else if (args.channelId) {
      const existing = await ctx.db
        .query("typingIndicators")
        .withIndex("by_channelId", (q: any) => q.eq("channelId", args.channelId))
        .collect();

      const mine = existing.find((t: any) => t.stackUserId === stackUserId);
      if (mine) {
        await ctx.db.patch(mine._id, { expiresAt });
      } else {
        await ctx.db.insert("typingIndicators", {
          channelId: args.channelId,
          stackUserId,
          expiresAt,
        });
      }
    }

    return { set: true };
  },
});

export const clearTyping = mutation({
  args: {
    sessionToken: v.string(),
    conversationId: v.optional(v.string()),
    channelId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    if (args.conversationId) {
      const existing = await ctx.db
        .query("typingIndicators")
        .withIndex("by_conversationId", (q: any) => q.eq("conversationId", args.conversationId))
        .collect();

      const mine = existing.find((t: any) => t.stackUserId === stackUserId);
      if (mine) {
        await ctx.db.delete(mine._id);
      }
    } else if (args.channelId) {
      const existing = await ctx.db
        .query("typingIndicators")
        .withIndex("by_channelId", (q: any) => q.eq("channelId", args.channelId))
        .collect();

      const mine = existing.find((t: any) => t.stackUserId === stackUserId);
      if (mine) {
        await ctx.db.delete(mine._id);
      }
    }

    return { cleared: true };
  },
});

export const getTyping = query({
  args: {
    sessionToken: v.string(),
    conversationId: v.optional(v.string()),
    channelId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();

    let indicators: any[] = [];

    if (args.conversationId) {
      indicators = await ctx.db
        .query("typingIndicators")
        .withIndex("by_conversationId", (q: any) => q.eq("conversationId", args.conversationId))
        .collect();
    } else if (args.channelId) {
      indicators = await ctx.db
        .query("typingIndicators")
        .withIndex("by_channelId", (q: any) => q.eq("channelId", args.channelId))
        .collect();
    }

    const active = indicators.filter(
      (t: any) => t.expiresAt > now && t.stackUserId !== stackUserId
    );

    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((user: any) => [user.stackUserId, user])
    );

    return active.map((t: any) => {
      const user = usersByStackId.get(t.stackUserId);
      return {
        stackUserId: t.stackUserId,
        name: user?.name ?? user?.email ?? t.stackUserId,
      };
    });
  },
});
