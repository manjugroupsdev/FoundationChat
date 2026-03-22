import { internalQuery, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

async function getConversationForUser(ctx: any, conversationId: string, stackUserId: string) {
  const conversation = await ctx.db.get(conversationId);

  if (!conversation) {
    throw new Error("Conversation not found");
  }

  if (!conversation.participantStackUserIds.includes(stackUserId)) {
    throw new Error("Not allowed to access this conversation");
  }

  return conversation;
}

async function getReadPointer(ctx: any, conversationId: string, stackUserId: string) {
  try {
    return await ctx.db
      .query("conversationReads")
      .withIndex("by_conversation_stackUserId", (q: any) =>
        q.eq("conversationId", conversationId).eq("stackUserId", stackUserId)
      )
      .unique();
  } catch {
    return null;
  }
}

async function upsertConversationRead(
  ctx: any,
  conversationId: string,
  stackUserId: string,
  readAt: number
) {
  const now = Date.now();
  const existing = await getReadPointer(ctx, conversationId, stackUserId);

  if (existing) {
    if (readAt > existing.lastReadAt) {
      await ctx.db.patch(existing._id, {
        lastReadAt: readAt,
        updatedAt: now,
      });
      return readAt;
    }
    return existing.lastReadAt;
  }

  try {
    await ctx.db.insert("conversationReads", {
      conversationId,
      stackUserId,
      lastReadAt: readAt,
      createdAt: now,
      updatedAt: now,
    });
  } catch {
    // conversationReads table might not exist yet in some environments.
  }

  return readAt;
}

function toPublicParticipant(doc: any) {
  if (!doc) {
    return null;
  }

  return {
    stackUserId: doc.stackUserId,
    email: doc.email ?? null,
    name: doc.name ?? null,
    imageUrl: doc.imageUrl ?? null,
  };
}

async function resolveAttachmentThumbnail(ctx: any, doc: any) {
  if (doc.attachmentThumbnail) {
    return doc.attachmentThumbnail;
  }

  const isMediaAttachment =
    doc.attachmentType === "image"
    || doc.attachmentType === "video"
    || (typeof doc.attachmentMimeType === "string"
      && (doc.attachmentMimeType.startsWith("image/")
        || doc.attachmentMimeType.startsWith("video/")));

  if (!isMediaAttachment || !doc.attachmentStorageId) {
    return null;
  }

  try {
    const storageUrl = await ctx.storage.getUrl(doc.attachmentStorageId);
    return storageUrl ?? null;
  } catch {
    return null;
  }
}

async function resolveAttachmentUrl(ctx: any, doc: any) {
  if (!doc.attachmentStorageId) {
    return null;
  }

  try {
    const storageUrl = await ctx.storage.getUrl(doc.attachmentStorageId);
    return storageUrl ?? null;
  } catch {
    return null;
  }
}

async function toPublicLastMessage(ctx: any, doc: any) {
  if (!doc) {
    return null;
  }

  return {
    id: doc._id,
    conversationId: doc.conversationId,
    senderStackUserId: doc.senderStackUserId,
    role: doc.role,
    content: doc.content,
    attachmentType: doc.attachmentType ?? null,
    attachmentStorageId: doc.attachmentStorageId ?? null,
    attachmentFileName: doc.attachmentFileName ?? null,
    attachmentMimeType: doc.attachmentMimeType ?? null,
    attachmentTitle: doc.attachmentTitle ?? null,
    attachmentDescription: doc.attachmentDescription ?? null,
    attachmentThumbnail: await resolveAttachmentThumbnail(ctx, doc),
    attachmentUrl: await resolveAttachmentUrl(ctx, doc),
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
  };
}

export const listForCurrentUser = query({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const currentStackUserId = sessionContext.identity.subject;

    const allUsers = await ctx.db.query("users").collect();
    const usersByStackUserId = new Map(allUsers.map((user: any) => [user.stackUserId, user]));

    const allConversations = await ctx.db.query("conversations").collect();
    const currentUserConversations = allConversations.filter((conversation: any) =>
      conversation.participantStackUserIds.includes(currentStackUserId)
    );

    const allMessages = await ctx.db.query("messages").collect();
    const lastMessageByConversationId = new Map<string, any>();
    const messagesByConversationId = new Map<string, any[]>();
    for (const message of allMessages) {
      const existing = lastMessageByConversationId.get(message.conversationId);
      if (!existing || message.createdAt > existing.createdAt) {
        lastMessageByConversationId.set(message.conversationId, message);
      }

      const list = messagesByConversationId.get(message.conversationId) ?? [];
      list.push(message);
      messagesByConversationId.set(message.conversationId, list);
    }

    let allReadPointers: any[] = [];
    try {
      allReadPointers = await ctx.db.query("conversationReads").collect();
    } catch {
      allReadPointers = [];
    }

    const readPointerByKey = new Map<string, any>();
    for (const pointer of allReadPointers) {
      readPointerByKey.set(`${pointer.conversationId}|${pointer.stackUserId}`, pointer);
    }

    const result = await Promise.all(
      currentUserConversations.map(async (conversation: any) => {
        const otherStackUserId =
          conversation.participantStackUserIds.find(
            (stackUserId: string) => stackUserId !== currentStackUserId
          ) ?? currentStackUserId;

        const otherParticipant = usersByStackUserId.get(otherStackUserId);
        const lastMessage = lastMessageByConversationId.get(conversation._id);
        const myReadPointer = readPointerByKey.get(`${conversation._id}|${currentStackUserId}`);
        const otherReadPointer = readPointerByKey.get(`${conversation._id}|${otherStackUserId}`);
        const myLastReadAt = myReadPointer?.lastReadAt ?? 0;
        const unreadCount = (messagesByConversationId.get(conversation._id) ?? []).reduce(
          (count: number, message: any) =>
            count
            + (message.senderStackUserId !== currentStackUserId && message.createdAt > myLastReadAt
              ? 1
              : 0),
          0
        );
        const latestActivityAt = lastMessage?.createdAt ?? conversation.updatedAt;

        return {
          id: conversation._id,
          type: conversation.type,
          participantStackUserIds: conversation.participantStackUserIds,
          otherParticipant: toPublicParticipant(otherParticipant),
          lastMessage: await toPublicLastMessage(ctx, lastMessage),
          unreadCount,
          otherParticipantLastReadAt: otherReadPointer?.lastReadAt ?? null,
          latestActivityAt,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
        };
      })
    );

    result.sort((lhs: any, rhs: any) => rhs.latestActivityAt - lhs.latestActivityAt);
    return result;
  },
});

export const markSeen = mutation({
  args: {
    sessionToken: v.string(),
    conversationId: v.id("conversations"),
    readAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    await getConversationForUser(ctx, args.conversationId, sessionContext.identity.subject);

    const normalizedReadAt = Math.max(0, args.readAt ?? Date.now());
    const lastReadAt = await upsertConversationRead(
      ctx,
      args.conversationId,
      sessionContext.identity.subject,
      normalizedReadAt
    );

    return {
      conversationId: args.conversationId,
      stackUserId: sessionContext.identity.subject,
      lastReadAt,
    };
  },
});

export const deleteForUser = mutation({
  args: {
    sessionToken: v.string(),
    conversationId: v.id("conversations"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;
    const conversation = await getConversationForUser(ctx, args.conversationId, stackUserId);

    const remaining = conversation.participantStackUserIds.filter(
      (id: string) => id !== stackUserId
    );

    // Clean up read pointer for this user
    const readPointer = await ctx.db
      .query("conversationReads")
      .withIndex("by_conversation_stackUserId", (q: any) =>
        q.eq("conversationId", args.conversationId).eq("stackUserId", stackUserId)
      )
      .first();
    if (readPointer) {
      await ctx.db.delete(readPointer._id);
    }

    if (remaining.length === 0) {
      // No participants left — delete conversation and all its messages
      const messages = await ctx.db
        .query("messages")
        .withIndex("by_conversation_createdAt", (q: any) => q.eq("conversationId", args.conversationId))
        .collect();
      for (const message of messages) {
        await ctx.db.delete(message._id);
      }
      await ctx.db.delete(conversation._id);
    } else {
      // Remove this user from participants
      await ctx.db.patch(conversation._id, {
        participantStackUserIds: remaining,
        updatedAt: Date.now(),
      });
    }

    return { deleted: true };
  },
});

export const startDirect = mutation({
  args: {
    sessionToken: v.string(),
    otherStackUserId: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const currentStackUserId = sessionContext.identity.subject;

    if (args.otherStackUserId === currentStackUserId) {
      throw new Error("Cannot start a conversation with yourself");
    }

    const users = await ctx.db.query("users").collect();
    const otherUser = users.find((user: any) => user.stackUserId === args.otherStackUserId);

    if (!otherUser) {
      throw new Error("Selected user does not exist");
    }

    const participantStackUserIds = [currentStackUserId, args.otherStackUserId].sort();
    const pairKey = participantStackUserIds.join("|");

    const allConversations = await ctx.db.query("conversations").collect();
    const existingConversation = allConversations.find(
      (conversation: any) => conversation.pairKey === pairKey
    );

    const now = Date.now();

    if (existingConversation) {
      await ctx.db.patch(existingConversation._id, {
        updatedAt: now,
      });

      return {
        conversationId: existingConversation._id,
        pairKey,
        participantStackUserIds,
        created: false,
      };
    }

    const newConversationId = await ctx.db.insert("conversations", {
      type: "direct",
      pairKey,
      participantStackUserIds,
      createdByStackUserId: currentStackUserId,
      createdAt: now,
      updatedAt: now,
    });

    return {
      conversationId: newConversationId,
      pairKey,
      participantStackUserIds,
      created: true,
    };
  },
});

export const listAllInternal = internalQuery({
  handler: async (ctx) => {
    const conversations = await ctx.db.query("conversations").collect();
    const usersByStackId = new Map(
      (await ctx.db.query("users").collect()).map((u: any) => [u.stackUserId, u])
    );
    return conversations.map((c: any) => ({
      id: c._id,
      type: c.type,
      participantStackUserIds: c.participantStackUserIds,
      participants: c.participantStackUserIds.map((sid: string) => {
        const u = usersByStackId.get(sid);
        return { stackUserId: sid, name: u?.name ?? null };
      }),
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
    }));
  },
});
