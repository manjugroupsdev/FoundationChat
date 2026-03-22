import { internalQuery, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

function toPublicUser(doc: {
  _id: string;
  stackUserId: string;
  email?: string | null;
  name?: string | null;
  imageUrl?: string | null;
}) {
  return {
    id: doc._id,
    stackUserId: doc.stackUserId,
    email: doc.email ?? null,
    name: doc.name ?? null,
    imageUrl: doc.imageUrl ?? null,
  };
}

export const ensureCurrentUser = mutation({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    return toPublicUser(sessionContext.user);
  },
});

export const list = query({
  args: {
    sessionToken: v.string(),
    search: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);

    const term = (args.search ?? "").trim().toLowerCase();
    const allUsers = await ctx.db.query("users").collect();

    const filtered = allUsers.filter((user: any) => {
      if (user.stackUserId === sessionContext.identity.subject) {
        return false;
      }

      if (term.length === 0) {
        return true;
      }

      const name = user.name?.toLowerCase() ?? "";
      const email = user.email?.toLowerCase() ?? "";
      const stackUserId = user.stackUserId?.toLowerCase() ?? "";

      return name.includes(term) || email.includes(term) || stackUserId.includes(term);
    });

    filtered.sort((a: any, b: any) => {
      const lhs = (a.name ?? a.email ?? a.stackUserId).toLowerCase();
      const rhs = (b.name ?? b.email ?? b.stackUserId).toLowerCase();
      return lhs.localeCompare(rhs);
    });

    return filtered.map(toPublicUser);
  },
});

export const listAllInternal = internalQuery({
  handler: async (ctx) => {
    const allUsers = await ctx.db.query("users").collect();
    return allUsers.map(toPublicUser);
  },
});
