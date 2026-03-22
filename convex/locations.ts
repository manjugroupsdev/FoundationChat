import { internalMutation, internalQuery, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

const ADMIN_STACK_USER_ID = "phone:+916369487527";

export const recordLocation = mutation({
  args: {
    sessionToken: v.string(),
    latitude: v.number(),
    longitude: v.number(),
    altitude: v.optional(v.number()),
    horizontalAccuracy: v.optional(v.number()),
    speed: v.optional(v.number()),
    heading: v.optional(v.number()),
    recordedAt: v.number(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();

    await ctx.db.insert("userLocations", {
      stackUserId,
      latitude: args.latitude,
      longitude: args.longitude,
      altitude: args.altitude,
      horizontalAccuracy: args.horizontalAccuracy,
      speed: args.speed,
      heading: args.heading,
      recordedAt: args.recordedAt,
      createdAt: now,
    });

    return { recorded: true };
  },
});

export const recordBatch = mutation({
  args: {
    sessionToken: v.string(),
    points: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const now = Date.now();

    const parsedPoints = JSON.parse(args.points) as Array<{
      latitude: number;
      longitude: number;
      altitude?: number;
      horizontalAccuracy?: number;
      speed?: number;
      heading?: number;
      recordedAt: number;
    }>;

    for (const point of parsedPoints) {
      await ctx.db.insert("userLocations", {
        stackUserId,
        latitude: point.latitude,
        longitude: point.longitude,
        altitude: point.altitude,
        horizontalAccuracy: point.horizontalAccuracy,
        speed: point.speed,
        heading: point.heading,
        recordedAt: point.recordedAt,
        createdAt: now,
      });
    }

    return { recorded: parsedPoints.length };
  },
});

export const listForUser = query({
  args: {
    sessionToken: v.string(),
    targetStackUserId: v.string(),
    startDate: v.number(),
    endDate: v.number(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    if (stackUserId !== ADMIN_STACK_USER_ID) {
      throw new Error("Only admin can perform this action.");
    }

    const locations = await ctx.db
      .query("userLocations")
      .withIndex("by_stackUserId_recordedAt", (q) =>
        q
          .eq("stackUserId", args.targetStackUserId)
          .gte("recordedAt", args.startDate)
          .lte("recordedAt", args.endDate)
      )
      .order("asc")
      .collect();

    return locations.map((loc) => ({
      id: loc._id,
      stackUserId: loc.stackUserId,
      latitude: loc.latitude,
      longitude: loc.longitude,
      altitude: loc.altitude,
      horizontalAccuracy: loc.horizontalAccuracy,
      speed: loc.speed,
      heading: loc.heading,
      recordedAt: loc.recordedAt,
    }));
  },
});

export const listTrackedUsers = query({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    if (stackUserId !== ADMIN_STACK_USER_ID) {
      throw new Error("Only admin can perform this action.");
    }

    // Get all locations ordered by recordedAt desc to find latest per user
    const allLocations = await ctx.db
      .query("userLocations")
      .withIndex("by_recordedAt")
      .order("desc")
      .collect();

    // Group by stackUserId, keeping only the latest location per user
    const userLatestMap = new Map<
      string,
      { latitude: number; longitude: number; recordedAt: number }
    >();

    for (const loc of allLocations) {
      if (!userLatestMap.has(loc.stackUserId)) {
        userLatestMap.set(loc.stackUserId, {
          latitude: loc.latitude,
          longitude: loc.longitude,
          recordedAt: loc.recordedAt,
        });
      }
    }

    // Fetch user details for each tracked user
    const results = [];
    for (const [trackedUserId, lastLocation] of userLatestMap) {
      const user = await ctx.db
        .query("users")
        .withIndex("by_stackUserId", (q) => q.eq("stackUserId", trackedUserId))
        .first();

      results.push({
        stackUserId: trackedUserId,
        name: user?.name ?? null,
        imageUrl: user?.imageUrl ?? null,
        lastLocation,
      });
    }

    return results;
  },
});

export const deleteForUser = mutation({
  args: {
    sessionToken: v.string(),
    targetStackUserId: v.string(),
    startDate: v.number(),
    endDate: v.number(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    if (stackUserId !== ADMIN_STACK_USER_ID) {
      throw new Error("Only admin can perform this action.");
    }

    const locations = await ctx.db
      .query("userLocations")
      .withIndex("by_stackUserId_recordedAt", (q) =>
        q
          .eq("stackUserId", args.targetStackUserId)
          .gte("recordedAt", args.startDate)
          .lte("recordedAt", args.endDate)
      )
      .collect();

    for (const loc of locations) {
      await ctx.db.delete(loc._id);
    }

    return { deleted: locations.length };
  },
});

// ── Internal functions (called by HTTP admin API, no session auth) ──

export const listTrackedUsersInternal = internalQuery({
  handler: async (ctx) => {
    const allLocations = await ctx.db
      .query("userLocations")
      .withIndex("by_recordedAt")
      .order("desc")
      .collect();

    const userLatestMap = new Map<
      string,
      { latitude: number; longitude: number; recordedAt: number }
    >();
    for (const loc of allLocations) {
      if (!userLatestMap.has(loc.stackUserId)) {
        userLatestMap.set(loc.stackUserId, {
          latitude: loc.latitude,
          longitude: loc.longitude,
          recordedAt: loc.recordedAt,
        });
      }
    }

    const results = [];
    for (const [trackedUserId, lastLocation] of userLatestMap) {
      const user = await ctx.db
        .query("users")
        .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", trackedUserId))
        .first();
      results.push({
        stackUserId: trackedUserId,
        name: user?.name ?? null,
        imageUrl: user?.imageUrl ?? null,
        lastLocation,
      });
    }
    return results;
  },
});

export const listForUserInternal = internalQuery({
  args: {
    targetStackUserId: v.string(),
    startDate: v.number(),
    endDate: v.number(),
  },
  handler: async (ctx, args) => {
    const locations = await ctx.db
      .query("userLocations")
      .withIndex("by_stackUserId_recordedAt", (q: any) =>
        q
          .eq("stackUserId", args.targetStackUserId)
          .gte("recordedAt", args.startDate)
          .lte("recordedAt", args.endDate)
      )
      .order("asc")
      .collect();

    return locations.map((loc: any) => ({
      id: loc._id,
      stackUserId: loc.stackUserId,
      latitude: loc.latitude,
      longitude: loc.longitude,
      altitude: loc.altitude ?? null,
      horizontalAccuracy: loc.horizontalAccuracy ?? null,
      speed: loc.speed ?? null,
      heading: loc.heading ?? null,
      recordedAt: loc.recordedAt,
    }));
  },
});

export const deleteForUserInternal = internalMutation({
  args: {
    targetStackUserId: v.string(),
    startDate: v.number(),
    endDate: v.number(),
  },
  handler: async (ctx, args) => {
    const locations = await ctx.db
      .query("userLocations")
      .withIndex("by_stackUserId_recordedAt", (q: any) =>
        q
          .eq("stackUserId", args.targetStackUserId)
          .gte("recordedAt", args.startDate)
          .lte("recordedAt", args.endDate)
      )
      .collect();

    for (const loc of locations) {
      await ctx.db.delete(loc._id);
    }
    return { deleted: locations.length };
  },
});
