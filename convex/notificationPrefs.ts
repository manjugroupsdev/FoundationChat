import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

export const get = query({
  args: {
    sessionToken: v.string(),
    targetType: v.union(v.literal("dm"), v.literal("channel")),
    targetId: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const pref = await ctx.db
      .query("notificationPreferences")
      .withIndex("by_stackUserId_target", (q: any) =>
        q.eq("stackUserId", stackUserId).eq("targetType", args.targetType).eq("targetId", args.targetId)
      )
      .first();

    if (!pref) {
      return {
        stackUserId,
        targetType: args.targetType,
        targetId: args.targetId,
        level: "all",
        muteUntil: null,
      };
    }

    return {
      stackUserId: pref.stackUserId,
      targetType: pref.targetType,
      targetId: pref.targetId,
      level: pref.level,
      muteUntil: pref.muteUntil ?? null,
    };
  },
});

export const upsert = mutation({
  args: {
    sessionToken: v.string(),
    targetType: v.union(v.literal("dm"), v.literal("channel")),
    targetId: v.string(),
    level: v.union(v.literal("all"), v.literal("mentions"), v.literal("none")),
    muteUntil: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();

    const existing = await ctx.db
      .query("notificationPreferences")
      .withIndex("by_stackUserId_target", (q: any) =>
        q.eq("stackUserId", stackUserId).eq("targetType", args.targetType).eq("targetId", args.targetId)
      )
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        level: args.level,
        muteUntil: args.muteUntil,
        updatedAt: now,
      });
      return { updated: true };
    }

    await ctx.db.insert("notificationPreferences", {
      stackUserId,
      targetType: args.targetType,
      targetId: args.targetId,
      level: args.level,
      muteUntil: args.muteUntil,
      updatedAt: now,
    });

    return { updated: true };
  },
});

export const listForUser = query({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const prefs = await ctx.db
      .query("notificationPreferences")
      .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
      .collect();

    return prefs.map((pref: any) => ({
      id: pref._id,
      stackUserId: pref.stackUserId,
      targetType: pref.targetType,
      targetId: pref.targetId,
      level: pref.level,
      muteUntil: pref.muteUntil ?? null,
      updatedAt: pref.updatedAt,
    }));
  },
});
