import { internal } from "./_generated/api";
import { mutation, query } from "./_generated/server";
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

async function toPublicMessage(ctx: any, doc: any) {
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
    replyToId: doc.replyToId ?? null,
    editedAt: doc.editedAt ?? null,
    isDeleted: doc.isDeleted ?? false,
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
  };
}

async function toPublicFileRecord(ctx: any, doc: any) {
  return {
    id: doc._id,
    conversationId: null,
    senderStackUserId: doc.ownerStackUserId,
    storageId: doc.attachmentStorageId ?? null,
    attachmentType: doc.attachmentType ?? "file",
    fileName: doc.attachmentFileName ?? "File",
    mimeType: doc.attachmentMimeType ?? null,
    title: doc.attachmentTitle ?? null,
    description: doc.attachmentDescription ?? null,
    thumbnail: await resolveAttachmentThumbnail(ctx, doc),
    url: await resolveAttachmentUrl(ctx, doc),
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
  };
}

function normalizeOptionalString(value: string | null | undefined) {
  return typeof value === "string" ? value : undefined;
}

function normalizeOptionalAttachmentType(value: "image" | "video" | "file" | null | undefined) {
  return value === "image" || value === "video" || value === "file" ? value : undefined;
}

function previewBodyForPush(args: {
  content: string;
  attachmentType?: "image" | "video" | "file" | null;
  attachmentFileName?: string | null;
}) {
  const trimmed = args.content.trim();
  if (trimmed.length > 0) {
    return trimmed;
  }

  const fileName = args.attachmentFileName?.trim();
  if (args.attachmentType === "image") {
    return fileName ? `Sent photo: ${fileName}` : "Sent a photo";
  }
  if (args.attachmentType === "video") {
    return fileName ? `Sent video: ${fileName}` : "Sent a video";
  }
  if (args.attachmentType === "file") {
    return fileName ? `Sent file: ${fileName}` : "Sent a file";
  }

  return "New message";
}

export const generateUploadUrl = mutation({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    await requireSession(ctx, args.sessionToken);
    const uploadUrl = await ctx.storage.generateUploadUrl();
    return { uploadUrl };
  },
});

export const savePrivateFile = mutation({
  args: {
    sessionToken: v.string(),
    attachmentType: v.union(v.literal("image"), v.literal("video"), v.literal("file")),
    attachmentStorageId: v.id("_storage"),
    attachmentFileName: v.string(),
    attachmentMimeType: v.optional(v.union(v.string(), v.null())),
    attachmentTitle: v.optional(v.union(v.string(), v.null())),
    attachmentDescription: v.optional(v.union(v.string(), v.null())),
    attachmentThumbnail: v.optional(v.union(v.string(), v.null())),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const now = Date.now();
    const fileName = args.attachmentFileName.trim();
    if (!fileName) {
      throw new Error("Invalid file name.");
    }

    const fileId = await ctx.db.insert("userFiles", {
      ownerStackUserId: sessionContext.identity.subject,
      attachmentType: args.attachmentType,
      attachmentStorageId: args.attachmentStorageId,
      attachmentFileName: fileName,
      attachmentMimeType: normalizeOptionalString(args.attachmentMimeType),
      attachmentTitle: normalizeOptionalString(args.attachmentTitle),
      attachmentDescription: normalizeOptionalString(args.attachmentDescription),
      attachmentThumbnail: normalizeOptionalString(args.attachmentThumbnail),
      createdAt: now,
      updatedAt: now,
    });

    return { fileId };
  },
});

export const listForConversation = query({
  args: {
    sessionToken: v.string(),
    conversationId: v.id("conversations"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    await getConversationForUser(ctx, args.conversationId, sessionContext.identity.subject);

    const messages = await ctx.db
      .query("messages")
      .withIndex("by_conversation_createdAt", (q) => q.eq("conversationId", args.conversationId))
      .collect();

    return await Promise.all(messages.map((message) => toPublicMessage(ctx, message)));
  },
});

export const send = mutation({
  args: {
    sessionToken: v.string(),
    conversationId: v.id("conversations"),
    role: v.union(v.literal("user"), v.literal("assistant"), v.literal("system")),
    content: v.string(),
    attachmentType: v.optional(
      v.union(v.literal("image"), v.literal("video"), v.literal("file"), v.null())
    ),
    attachmentStorageId: v.optional(v.union(v.id("_storage"), v.null())),
    attachmentFileName: v.optional(v.union(v.string(), v.null())),
    attachmentMimeType: v.optional(v.union(v.string(), v.null())),
    attachmentTitle: v.optional(v.union(v.string(), v.null())),
    attachmentDescription: v.optional(v.union(v.string(), v.null())),
    attachmentThumbnail: v.optional(v.union(v.string(), v.null())),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const conversation = await getConversationForUser(
      ctx,
      args.conversationId,
      sessionContext.identity.subject
    );
    const now = Date.now();

    const messageId = await ctx.db.insert("messages", {
      conversationId: args.conversationId,
      senderStackUserId: sessionContext.identity.subject,
      role: args.role,
      content: args.content,
      attachmentType: normalizeOptionalAttachmentType(args.attachmentType),
      attachmentStorageId: args.attachmentStorageId ?? undefined,
      attachmentFileName: normalizeOptionalString(args.attachmentFileName),
      attachmentMimeType: normalizeOptionalString(args.attachmentMimeType),
      attachmentTitle: normalizeOptionalString(args.attachmentTitle),
      attachmentDescription: normalizeOptionalString(args.attachmentDescription),
      attachmentThumbnail: normalizeOptionalString(args.attachmentThumbnail),
      createdAt: now,
      updatedAt: now,
    });

    await ctx.db.patch(conversation._id, {
      updatedAt: now,
    });

    const message = await ctx.db.get(messageId);
    if (!message) {
      throw new Error("Unable to load saved message");
    }

    const recipientStackUserIds = conversation.participantStackUserIds.filter(
      (stackUserId: string) => stackUserId !== sessionContext.identity.subject
    );
    if (recipientStackUserIds.length > 0) {
      const senderName =
        sessionContext.user.name
        ?? sessionContext.user.email
        ?? sessionContext.identity.subject;

      await ctx.scheduler.runAfter(0, internal.notifications.sendMessagePush, {
        recipientStackUserIds,
        senderStackUserId: sessionContext.identity.subject,
        senderName,
        type: "direct_message",
        conversationId: args.conversationId,
        body: previewBodyForPush({
          content: args.content,
          attachmentType: args.attachmentType,
          attachmentFileName: args.attachmentFileName,
        }),
      });
    }

    return await toPublicMessage(ctx, message);
  },
});

export const sharePrivateFileToConversation = mutation({
  args: {
    sessionToken: v.string(),
    fileId: v.id("userFiles"),
    conversationId: v.id("conversations"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const file = await ctx.db.get(args.fileId);
    if (!file) {
      throw new Error("File not found.");
    }
    if (file.ownerStackUserId !== sessionContext.identity.subject) {
      throw new Error("You can only share your own files.");
    }

    const conversation = await getConversationForUser(
      ctx,
      args.conversationId,
      sessionContext.identity.subject
    );
    const now = Date.now();

    const messageId = await ctx.db.insert("messages", {
      conversationId: args.conversationId,
      senderStackUserId: sessionContext.identity.subject,
      role: "user",
      content: `Shared ${file.attachmentFileName}`,
      attachmentType: file.attachmentType,
      attachmentStorageId: file.attachmentStorageId,
      attachmentFileName: file.attachmentFileName,
      attachmentMimeType: file.attachmentMimeType,
      attachmentTitle: file.attachmentTitle ?? file.attachmentFileName,
      attachmentDescription: file.attachmentDescription,
      attachmentThumbnail: file.attachmentThumbnail,
      createdAt: now,
      updatedAt: now,
    });

    await ctx.db.patch(conversation._id, { updatedAt: now });

    const message = await ctx.db.get(messageId);
    if (!message) {
      throw new Error("Unable to load shared message.");
    }

    const recipientStackUserIds = conversation.participantStackUserIds.filter(
      (stackUserId: string) => stackUserId !== sessionContext.identity.subject
    );
    if (recipientStackUserIds.length > 0) {
      const senderName =
        sessionContext.user.name
        ?? sessionContext.user.email
        ?? sessionContext.identity.subject;

      await ctx.scheduler.runAfter(0, internal.notifications.sendMessagePush, {
        recipientStackUserIds,
        senderStackUserId: sessionContext.identity.subject,
        senderName,
        type: "direct_message",
        conversationId: args.conversationId,
        body: previewBodyForPush({
          content: message.content,
          attachmentType: message.attachmentType,
          attachmentFileName: message.attachmentFileName,
        }),
      });
    }

    return {
      shared: true,
      conversationId: args.conversationId,
      messageId: message._id,
    };
  },
});

export const listSharedFiles = query({
  args: {
    sessionToken: v.string(),
    search: v.optional(v.string()),
    type: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const searchTerm = (args.search ?? "").trim().toLowerCase();
    const typeFilter = (args.type ?? "all").trim().toLowerCase();
    const files = await ctx.db
      .query("userFiles")
      .withIndex("by_ownerStackUserId", (q: any) => q.eq("ownerStackUserId", sessionContext.identity.subject))
      .collect();
    const records = await Promise.all(files.map((file: any) => toPublicFileRecord(ctx, file)));

    const filtered = records.filter((record: any) => {
      if (typeFilter !== "all" && record.attachmentType !== typeFilter) {
        return false;
      }
      if (!searchTerm) {
        return true;
      }

      const haystack = `${record.fileName} ${record.title ?? ""} ${record.description ?? ""}`
        .toLowerCase();
      return haystack.includes(searchTerm);
    });

    filtered.sort((a: any, b: any) => b.createdAt - a.createdAt);
    return filtered;
  },
});

export const editMessage = mutation({
  args: {
    sessionToken: v.string(),
    messageId: v.id("messages"),
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

    return await toPublicMessage(ctx, updated);
  },
});

export const deleteMessage = mutation({
  args: {
    sessionToken: v.string(),
    messageId: v.id("messages"),
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

export const sendWithReply = mutation({
  args: {
    sessionToken: v.string(),
    conversationId: v.id("conversations"),
    role: v.union(v.literal("user"), v.literal("assistant"), v.literal("system")),
    content: v.string(),
    replyToId: v.optional(v.string()),
    attachmentType: v.optional(
      v.union(v.literal("image"), v.literal("video"), v.literal("file"), v.null())
    ),
    attachmentStorageId: v.optional(v.union(v.id("_storage"), v.null())),
    attachmentFileName: v.optional(v.union(v.string(), v.null())),
    attachmentMimeType: v.optional(v.union(v.string(), v.null())),
    attachmentTitle: v.optional(v.union(v.string(), v.null())),
    attachmentDescription: v.optional(v.union(v.string(), v.null())),
    attachmentThumbnail: v.optional(v.union(v.string(), v.null())),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const conversation = await getConversationForUser(
      ctx,
      args.conversationId,
      sessionContext.identity.subject
    );
    const now = Date.now();

    const messageId = await ctx.db.insert("messages", {
      conversationId: args.conversationId,
      senderStackUserId: sessionContext.identity.subject,
      role: args.role,
      content: args.content,
      replyToId: args.replyToId ?? undefined,
      attachmentType: normalizeOptionalAttachmentType(args.attachmentType),
      attachmentStorageId: args.attachmentStorageId ?? undefined,
      attachmentFileName: normalizeOptionalString(args.attachmentFileName),
      attachmentMimeType: normalizeOptionalString(args.attachmentMimeType),
      attachmentTitle: normalizeOptionalString(args.attachmentTitle),
      attachmentDescription: normalizeOptionalString(args.attachmentDescription),
      attachmentThumbnail: normalizeOptionalString(args.attachmentThumbnail),
      createdAt: now,
      updatedAt: now,
    });

    await ctx.db.patch(conversation._id, {
      updatedAt: now,
    });

    const message = await ctx.db.get(messageId);
    if (!message) {
      throw new Error("Unable to load saved message");
    }

    const recipientStackUserIds = conversation.participantStackUserIds.filter(
      (stackUserId: string) => stackUserId !== sessionContext.identity.subject
    );
    if (recipientStackUserIds.length > 0) {
      const senderName =
        sessionContext.user.name
        ?? sessionContext.user.email
        ?? sessionContext.identity.subject;

      await ctx.scheduler.runAfter(0, internal.notifications.sendMessagePush, {
        recipientStackUserIds,
        senderStackUserId: sessionContext.identity.subject,
        senderName,
        type: "direct_message",
        conversationId: args.conversationId,
        body: previewBodyForPush({
          content: args.content,
          attachmentType: args.attachmentType,
          attachmentFileName: args.attachmentFileName,
        }),
      });
    }

    return await toPublicMessage(ctx, message);
  },
});
