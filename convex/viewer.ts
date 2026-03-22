import { query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";

export const viewer = query({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    return sessionContext.identity;
  },
});
