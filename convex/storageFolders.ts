import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

export const list = query({
  args: {
    sessionToken: v.string(),
    parentFolderId: v.optional(v.id("storageFolders")),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const allFolders = await ctx.db
      .query("storageFolders")
      .withIndex("by_ownerStackUserId", (q: any) => q.eq("ownerStackUserId", stackUserId))
      .collect();

    const filtered = allFolders.filter((folder: any) => {
      if (args.parentFolderId) {
        return folder.parentFolderId === args.parentFolderId;
      }
      return !folder.parentFolderId;
    });

    return filtered.map((folder: any) => ({
      id: folder._id,
      name: folder.name,
      parentFolderId: folder.parentFolderId ?? null,
      sharedWithStackUserIds: folder.sharedWithStackUserIds ?? [],
      createdAt: folder.createdAt,
      updatedAt: folder.updatedAt,
    }));
  },
});

export const create = mutation({
  args: {
    sessionToken: v.string(),
    name: v.string(),
    parentFolderId: v.optional(v.id("storageFolders")),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const trimmedName = args.name.trim();
    if (!trimmedName) {
      throw new Error("Folder name cannot be empty.");
    }

    if (args.parentFolderId) {
      const parentFolder = await ctx.db.get(args.parentFolderId);
      if (!parentFolder) {
        throw new Error("Parent folder not found.");
      }
      if (parentFolder.ownerStackUserId !== stackUserId) {
        throw new Error("You do not own the parent folder.");
      }
    }

    const now = Date.now();
    const folderId = await ctx.db.insert("storageFolders", {
      ownerStackUserId: stackUserId,
      name: trimmedName,
      parentFolderId: args.parentFolderId,
      createdAt: now,
      updatedAt: now,
    });

    return { folderId };
  },
});

export const rename = mutation({
  args: {
    sessionToken: v.string(),
    folderId: v.id("storageFolders"),
    name: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const folder = await ctx.db.get(args.folderId);
    if (!folder) {
      throw new Error("Folder not found.");
    }
    if (folder.ownerStackUserId !== stackUserId) {
      throw new Error("You do not own this folder.");
    }

    const trimmedName = args.name.trim();
    if (!trimmedName) {
      throw new Error("Folder name cannot be empty.");
    }

    const now = Date.now();
    await ctx.db.patch(args.folderId, {
      name: trimmedName,
      updatedAt: now,
    });

    return { renamed: true };
  },
});

export const deleteFolder = mutation({
  args: {
    sessionToken: v.string(),
    folderId: v.id("storageFolders"),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const folder = await ctx.db.get(args.folderId);
    if (!folder) {
      throw new Error("Folder not found.");
    }
    if (folder.ownerStackUserId !== stackUserId) {
      throw new Error("You do not own this folder.");
    }

    const childFolders = await ctx.db
      .query("storageFolders")
      .withIndex("by_parentFolderId", (q: any) => q.eq("parentFolderId", args.folderId))
      .first();
    if (childFolders) {
      throw new Error("Folder is not empty. Remove subfolders first.");
    }

    const filesInFolder = await ctx.db
      .query("userFiles")
      .withIndex("by_ownerStackUserId", (q: any) => q.eq("ownerStackUserId", stackUserId))
      .collect();
    const hasFiles = filesInFolder.some((file: any) => file.folderId === args.folderId);
    if (hasFiles) {
      throw new Error("Folder is not empty. Move files out first.");
    }

    await ctx.db.delete(args.folderId);

    return { deleted: true };
  },
});

export const moveFile = mutation({
  args: {
    sessionToken: v.string(),
    fileId: v.id("userFiles"),
    folderId: v.optional(v.id("storageFolders")),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const file = await ctx.db.get(args.fileId);
    if (!file) {
      throw new Error("File not found.");
    }
    if (file.ownerStackUserId !== stackUserId) {
      throw new Error("You do not own this file.");
    }

    if (args.folderId) {
      const folder = await ctx.db.get(args.folderId);
      if (!folder) {
        throw new Error("Folder not found.");
      }
      if (folder.ownerStackUserId !== stackUserId) {
        throw new Error("You do not own this folder.");
      }
    }

    const now = Date.now();
    await ctx.db.patch(args.fileId, {
      folderId: args.folderId,
      updatedAt: now,
    });

    return { moved: true };
  },
});

export const listFilesInFolder = query({
  args: {
    sessionToken: v.string(),
    folderId: v.optional(v.id("storageFolders")),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const stackUserId = sessionContext.identity.subject;

    const files = await ctx.db
      .query("userFiles")
      .withIndex("by_ownerStackUserId", (q: any) => q.eq("ownerStackUserId", stackUserId))
      .collect();

    const filtered = files.filter((file: any) => {
      if (args.folderId) {
        return file.folderId === args.folderId;
      }
      return !file.folderId;
    });

    const results = await Promise.all(
      filtered.map(async (file: any) => {
        let url: string | null = null;
        try {
          url = await ctx.storage.getUrl(file.attachmentStorageId) ?? null;
        } catch {
          // skip
        }

        return {
          id: file._id,
          ownerStackUserId: file.ownerStackUserId,
          attachmentType: file.attachmentType,
          attachmentFileName: file.attachmentFileName,
          attachmentMimeType: file.attachmentMimeType ?? null,
          folderId: file.folderId ?? null,
          url,
          createdAt: file.createdAt,
          updatedAt: file.updatedAt,
        };
      })
    );

    results.sort((a: any, b: any) => b.createdAt - a.createdAt);
    return results;
  },
});
