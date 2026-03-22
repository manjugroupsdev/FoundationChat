import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

const PRESENCE_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes

export const heartbeat = mutation({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();

    const existing = await ctx.db
      .query("userPresence")
      .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        status: "online",
        lastHeartbeatAt: now,
        updatedAt: now,
      });
    } else {
      await ctx.db.insert("userPresence", {
        stackUserId,
        status: "online",
        lastHeartbeatAt: now,
        updatedAt: now,
      });
    }

    return { status: "online" };
  },
});

export const setStatus = mutation({
  args: {
    sessionToken: v.string(),
    status: v.union(v.literal("online"), v.literal("away"), v.literal("busy"), v.literal("offline")),
    customStatusText: v.optional(v.string()),
    customStatusEmoji: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();

    const existing = await ctx.db
      .query("userPresence")
      .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        status: args.status,
        customStatusText: args.customStatusText?.trim() || undefined,
        customStatusEmoji: args.customStatusEmoji?.trim() || undefined,
        lastHeartbeatAt: now,
        updatedAt: now,
      });
    } else {
      await ctx.db.insert("userPresence", {
        stackUserId,
        status: args.status,
        customStatusText: args.customStatusText?.trim() || undefined,
        customStatusEmoji: args.customStatusEmoji?.trim() || undefined,
        lastHeartbeatAt: now,
        updatedAt: now,
      });
    }

    return { status: args.status };
  },
});

export const getForUsers = query({
  args: {
    sessionToken: v.string(),
    stackUserIds: v.string(),
  },
  handler: async (ctx, args) => {
    await requireSession(ctx, args.sessionToken);
    const now = Date.now();
    const userIds = args.stackUserIds.split(",").map((s) => s.trim()).filter(Boolean);

    const results: any[] = [];

    for (const stackUserId of userIds) {
      const presence = await ctx.db
        .query("userPresence")
        .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
        .first();

      if (!presence) {
        results.push({
          stackUserId,
          status: "offline",
          customStatusText: null,
          customStatusEmoji: null,
          lastHeartbeatAt: null,
        });
        continue;
      }

      const isTimedOut = now - presence.lastHeartbeatAt > PRESENCE_TIMEOUT_MS;
      results.push({
        stackUserId,
        status: isTimedOut ? "offline" : presence.status,
        customStatusText: presence.customStatusText ?? null,
        customStatusEmoji: presence.customStatusEmoji ?? null,
        lastHeartbeatAt: presence.lastHeartbeatAt,
      });
    }

    return results;
  },
});

export const clearCustomStatus = mutation({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();

    const existing = await ctx.db
      .query("userPresence")
      .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        customStatusText: undefined,
        customStatusEmoji: undefined,
        updatedAt: now,
      });
    }

    return { cleared: true };
  },
});
