export const OTP_IDENTITY_ISSUER = "foundationchat-otp";

export type SessionIdentity = {
  tokenIdentifier: string;
  subject: string;
  issuer: string;
  email: string | null;
  name: string | null;
};

export async function requireSession(ctx: any, sessionToken: string) {
  const normalizedToken = sessionToken.trim();
  if (!normalizedToken) {
    throw new Error("Missing session token");
  }

  const session = await ctx.db
    .query("authSessions")
    .withIndex("by_sessionToken", (q: any) => q.eq("sessionToken", normalizedToken))
    .first();

  if (!session) {
    throw new Error("Invalid session");
  }

  const now = Date.now();
  if (session.expiresAt <= now) {
    await ctx.db.delete(session._id);
    throw new Error("Session expired");
  }

  const user = await ctx.db
    .query("users")
    .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", session.stackUserId))
    .first();

  if (!user) {
    throw new Error("Session user not found");
  }

  const identity: SessionIdentity = {
    tokenIdentifier: `otp:${session.stackUserId}`,
    subject: session.stackUserId,
    issuer: OTP_IDENTITY_ISSUER,
    email: user.email ?? null,
    name: user.name ?? null,
  };

  return {
    session,
    user,
    identity,
  };
}
