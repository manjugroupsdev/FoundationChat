import { internal } from "./_generated/api";
import { internalQuery, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

const ADMIN_STACK_USER_ID = "phone:+916369487527";

function ensureAdmin(stackUserId: string) {
  if (stackUserId !== ADMIN_STACK_USER_ID) {
    throw new Error("Only admin can perform this action.");
  }
}

async function requireChannelMembership(ctx: any, channelId: string, stackUserId: string) {
  const membership = await ctx.db
    .query("channelMembers")
    .withIndex("by_channelId_stackUserId", (q: any) =>
      q.eq("channelId", channelId).eq("stackUserId", stackUserId)
    )
    .first();

  if (!membership) {
    throw new Error("You are not a member of this channel.");
  }

  return membership;
}

function toPublicUser(doc: any) {
  return {
    id: doc?._id ?? "",
    stackUserId: doc?.stackUserId ?? "",
    email: doc?.email ?? null,
    name: doc?.name ?? null,
    imageUrl: doc?.imageUrl ?? null,
  };
}

function toPublicChannelMessage(message: any, senderDoc: any) {
  return {
    id: message._id,
    channelId: message.channelId,
    senderStackUserId: message.senderStackUserId,
    senderName: senderDoc?.name ?? senderDoc?.email ?? message.senderStackUserId,
    content: message.content,
    replyToId: message.replyToId ?? null,
    editedAt: message.editedAt ?? null,
    isDeleted: message.isDeleted ?? false,
    createdAt: message.createdAt,
    updatedAt: message.updatedAt,
  };
}

export const listForCurrentUser = query({
  args: {
    sessionToken: v.string(),
    search: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const searchTerm = (args.search ?? "").trim().toLowerCase();

    const memberships = await ctx.db
      .query("channelMembers")
      .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
      .collect();

    const channelIds = memberships.map((membership: any) => membership.channelId);
    const membershipByChannelId = new Map(
      memberships.map((membership: any) => [membership.channelId, membership])
    );

    const channels = (
      await Promise.all(channelIds.map((channelId: any) => ctx.db.get(channelId)))
    ).filter(Boolean);

    const enriched = await Promise.all(
      channels.map(async (channel: any) => {
        const members = await ctx.db
          .query("channelMembers")
          .withIndex("by_channelId", (q: any) => q.eq("channelId", channel._id))
          .collect();
        const lastMessage = await ctx.db
          .query("channelMessages")
          .withIndex("by_channelId_createdAt", (q: any) => q.eq("channelId", channel._id))
          .order("desc")
          .first();

        const currentMembership = membershipByChannelId.get(channel._id);
        const lastMessageAt = lastMessage?.createdAt ?? channel.updatedAt;
        return {
          id: channel._id,
          name: channel.name,
          description: channel.description ?? null,
          memberCount: members.length,
          lastMessageContent: lastMessage?.content ?? null,
          lastMessageAt,
          createdByStackUserId: channel.createdByStackUserId,
          myRole: currentMembership?.role ?? "member",
          canManage: stackUserId === ADMIN_STACK_USER_ID,
          createdAt: channel.createdAt,
          updatedAt: channel.updatedAt,
        };
      })
    );

    const filtered = enriched.filter((channel: any) => {
      if (!searchTerm) {
        return true;
      }

      const haystack = `${channel.name} ${channel.description ?? ""} ${channel.lastMessageContent ?? ""}`
        .toLowerCase();
      return haystack.includes(searchTerm);
    });

    filtered.sort((a: any, b: any) => b.lastMessageAt - a.lastMessageAt);
    return filtered;
  },
});

export const listMembers = query({
  args: {
    sessionToken: v.string(),
    channelId: v.id("channels"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    if (stackUserId !== ADMIN_STACK_USER_ID) {
      await requireChannelMembership(ctx, args.channelId, stackUserId);
    }

    const memberships = await ctx.db
      .query("channelMembers")
      .withIndex("by_channelId", (q: any) => q.eq("channelId", args.channelId))
      .collect();

    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((user: any) => [user.stackUserId, user])
    );

    return memberships.map((membership: any) => {
      const userDoc = usersByStackId.get(membership.stackUserId);
      return {
        channelId: membership.channelId,
        stackUserId: membership.stackUserId,
        role: membership.role,
        invitedByStackUserId: membership.invitedByStackUserId ?? null,
        user: toPublicUser(userDoc),
        createdAt: membership.createdAt,
        updatedAt: membership.updatedAt,
      };
    });
  },
});

export const create = mutation({
  args: {
    sessionToken: v.string(),
    name: v.string(),
    description: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    ensureAdmin(stackUserId);

    const trimmedName = args.name.trim();
    if (trimmedName.length < 2) {
      throw new Error("Channel name must be at least 2 characters.");
    }

    const normalizedDescription = args.description?.trim() || undefined;
    const now = Date.now();

    const channelId = await ctx.db.insert("channels", {
      name: trimmedName,
      description: normalizedDescription,
      createdByStackUserId: stackUserId,
      createdAt: now,
      updatedAt: now,
    });

    await ctx.db.insert("channelMembers", {
      channelId,
      stackUserId,
      role: "admin",
      invitedByStackUserId: stackUserId,
      createdAt: now,
      updatedAt: now,
    });

    return {
      channelId,
      name: trimmedName,
      description: normalizedDescription ?? null,
      createdAt: now,
    };
  },
});

export const inviteMember = mutation({
  args: {
    sessionToken: v.string(),
    channelId: v.id("channels"),
    memberStackUserId: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    ensureAdmin(stackUserId);

    const channel = await ctx.db.get(args.channelId);
    if (!channel) {
      throw new Error("Channel not found.");
    }

    const memberStackUserId = args.memberStackUserId.trim();
    if (!memberStackUserId) {
      throw new Error("Invalid member.");
    }

    const user = await ctx.db
      .query("users")
      .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", memberStackUserId))
      .first();
    if (!user) {
      throw new Error("User not found.");
    }

    const existingMembership = await ctx.db
      .query("channelMembers")
      .withIndex("by_channelId_stackUserId", (q: any) =>
        q.eq("channelId", args.channelId).eq("stackUserId", memberStackUserId)
      )
      .first();
    if (existingMembership) {
      return {
        channelId: args.channelId,
        memberStackUserId,
        invited: false,
      };
    }

    const now = Date.now();
    await ctx.db.insert("channelMembers", {
      channelId: args.channelId,
      stackUserId: memberStackUserId,
      role: "member",
      invitedByStackUserId: stackUserId,
      createdAt: now,
      updatedAt: now,
    });

    await ctx.db.patch(channel._id, { updatedAt: now });

    return {
      channelId: args.channelId,
      memberStackUserId,
      invited: true,
    };
  },
});

export const listMessages = query({
  args: {
    sessionToken: v.string(),
    channelId: v.id("channels"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    await requireChannelMembership(ctx, args.channelId, stackUserId);

    const messages = await ctx.db
      .query("channelMessages")
      .withIndex("by_channelId_createdAt", (q: any) => q.eq("channelId", args.channelId))
      .collect();

    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((user: any) => [user.stackUserId, user])
    );

    return messages.map((message: any) =>
      toPublicChannelMessage(message, usersByStackId.get(message.senderStackUserId))
    );
  },
});

export const sendMessage = mutation({
  args: {
    sessionToken: v.string(),
    channelId: v.id("channels"),
    content: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    await requireChannelMembership(ctx, args.channelId, stackUserId);

    const channel = await ctx.db.get(args.channelId);
    if (!channel) {
      throw new Error("Channel not found.");
    }

    const content = args.content.trim();
    if (!content) {
      throw new Error("Message cannot be empty.");
    }

    const now = Date.now();

    const messageId = await ctx.db.insert("channelMessages", {
      channelId: args.channelId,
      senderStackUserId: stackUserId,
      content,
      createdAt: now,
      updatedAt: now,
    });

    await ctx.db.patch(channel._id, { updatedAt: now });

    const createdMessage = await ctx.db.get(messageId);
    if (!createdMessage) {
      throw new Error("Failed to load channel message.");
    }
    const senderDoc = await ctx.db
      .query("users")
      .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
      .first();
    const senderName = senderDoc?.name ?? senderDoc?.email ?? stackUserId;

    const memberships = await ctx.db
      .query("channelMembers")
      .withIndex("by_channelId", (q: any) => q.eq("channelId", args.channelId))
      .collect();
    const recipientStackUserIds = memberships
      .map((membership: any) => membership.stackUserId)
      .filter((memberStackUserId: string) => memberStackUserId !== stackUserId);

    if (recipientStackUserIds.length > 0) {
      await ctx.scheduler.runAfter(0, internal.notifications.sendMessagePush, {
        recipientStackUserIds,
        senderStackUserId: stackUserId,
        senderName: `#${channel.name}`,
        type: "channel_message",
        channelId: args.channelId,
        body: `${senderName}: ${content}`,
      });
    }

    return toPublicChannelMessage(createdMessage, senderDoc);
  },
});

export const updateDescription = mutation({
  args: {
    sessionToken: v.string(),
    channelId: v.id("channels"),
    description: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    ensureAdmin(stackUserId);

    const channel = await ctx.db.get(args.channelId);
    if (!channel) {
      throw new Error("Channel not found.");
    }

    const now = Date.now();
    await ctx.db.patch(args.channelId, {
      description: args.description.trim() || undefined,
      updatedAt: now,
    });

    return { updated: true };
  },
});

export const pinMessage = mutation({
  args: {
    sessionToken: v.string(),
    channelId: v.id("channels"),
    messageId: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    ensureAdmin(stackUserId);

    const channel = await ctx.db.get(args.channelId);
    if (!channel) {
      throw new Error("Channel not found.");
    }

    const pinnedIds = channel.pinnedMessageIds ?? [];
    if (pinnedIds.includes(args.messageId)) {
      return { pinned: false };
    }

    const now = Date.now();
    await ctx.db.patch(args.channelId, {
      pinnedMessageIds: [...pinnedIds, args.messageId],
      updatedAt: now,
    });

    return { pinned: true };
  },
});

export const unpinMessage = mutation({
  args: {
    sessionToken: v.string(),
    channelId: v.id("channels"),
    messageId: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    ensureAdmin(stackUserId);

    const channel = await ctx.db.get(args.channelId);
    if (!channel) {
      throw new Error("Channel not found.");
    }

    const pinnedIds = channel.pinnedMessageIds ?? [];
    const updated = pinnedIds.filter((id: string) => id !== args.messageId);

    const now = Date.now();
    await ctx.db.patch(args.channelId, {
      pinnedMessageIds: updated.length > 0 ? updated : undefined,
      updatedAt: now,
    });

    return { unpinned: true };
  },
});

export const getPinnedMessages = query({
  args: {
    sessionToken: v.string(),
    channelId: v.id("channels"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    await requireChannelMembership(ctx, args.channelId, stackUserId);

    const channel = await ctx.db.get(args.channelId);
    if (!channel) {
      throw new Error("Channel not found.");
    }

    const pinnedIds = channel.pinnedMessageIds ?? [];
    if (pinnedIds.length === 0) {
      return [];
    }

    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((user: any) => [user.stackUserId, user])
    );

    const pinnedMessages: any[] = [];
    for (const messageId of pinnedIds) {
      const message = await ctx.db.get(messageId as any);
      if (message && "senderStackUserId" in message) {
        pinnedMessages.push(
          toPublicChannelMessage(message, usersByStackId.get((message as any).senderStackUserId))
        );
      }
    }

    return pinnedMessages;
  },
});

export const editMessage = mutation({
  args: {
    sessionToken: v.string(),
    messageId: v.id("channelMessages"),
    newContent: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const message = await ctx.db.get(args.messageId);
    if (!message) {
      throw new Error("Message not found.");
    }

    if (message.senderStackUserId !== stackUserId) {
      throw new Error("You can only edit your own messages.");
    }

    const now = Date.now();
    const fifteenMinutes = 15 * 60 * 1000;
    if (now - message.createdAt > fifteenMinutes) {
      throw new Error("Messages can only be edited within 15 minutes of sending.");
    }

    const content = args.newContent.trim();
    if (!content) {
      throw new Error("Message content cannot be empty.");
    }

    await ctx.db.patch(args.messageId, {
      content,
      editedAt: now,
      updatedAt: now,
    });

    const updated = await ctx.db.get(args.messageId);
    if (!updated) {
      throw new Error("Unable to load updated message.");
    }

    const senderDoc = await ctx.db
      .query("users")
      .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
      .first();

    return toPublicChannelMessage(updated, senderDoc);
  },
});

export const deleteMessage = mutation({
  args: {
    sessionToken: v.string(),
    messageId: v.id("channelMessages"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const message = await ctx.db.get(args.messageId);
    if (!message) {
      throw new Error("Message not found.");
    }

    if (message.senderStackUserId !== stackUserId) {
      throw new Error("You can only delete your own messages.");
    }

    const now = Date.now();
    await ctx.db.patch(args.messageId, {
      content: "",
      isDeleted: true,
      updatedAt: now,
    });

    return { deleted: true };
  },
});

export const listAllInternal = internalQuery({
  handler: async (ctx) => {
    const channels = await ctx.db.query("channels").collect();
    return await Promise.all(
      channels.map(async (ch: any) => {
        const members = await ctx.db
          .query("channelMembers")
          .withIndex("by_channelId", (q: any) => q.eq("channelId", ch._id))
          .collect();
        return {
          id: ch._id,
          name: ch.name,
          description: ch.description ?? null,
          memberCount: members.length,
          createdByStackUserId: ch.createdByStackUserId,
          createdAt: ch.createdAt,
          updatedAt: ch.updatedAt,
        };
      })
    );
  },
});
