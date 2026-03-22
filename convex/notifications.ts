import { internal } from "./_generated/api";
import { internalAction, internalMutation, internalQuery, mutation } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./authHelpers";
import { SignJWT, importPKCS8 } from "jose";

const APNS_TOKEN_PATTERN = /^[0-9a-fA-F]{64,}$/;
const APNS_JWT_ALGORITHM = "ES256";
const APNS_TOKEN_MAX_AGE_SECONDS = 50 * 60;
const APNS_TOKEN_REFRESH_BUFFER_MS = 5 * 60 * 1000;
const PUSH_LOG_PREFIX = "[push]";

type PushNotificationKind = "direct_message" | "channel_message";

type ApnsConfig = {
  teamId: string;
  keyId: string;
  bundleId: string;
  privateKey: string;
  useSandbox: boolean;
};

type PreparedPushPayload = {
  aps: {
    alert: {
      title: string;
      body: string;
    };
    sound: string;
  };
  type: PushNotificationKind;
  conversationId?: string;
  channelId?: string;
  senderStackUserId: string;
};

const cachedApnsJwtByEnvironment = new Map<string, { token: string; expiresAtMs: number }>();

function maskToken(token: string) {
  if (token.length <= 12) {
    return token;
  }
  return `${token.slice(0, 8)}...${token.slice(-4)}`;
}

function normalizeToken(raw: string) {
  return raw.trim().replace(/\s+/g, "").toLowerCase();
}

function normalizePrivateKey(raw: string) {
  return raw.replace(/\\n/g, "\n").trim();
}

function providerTokenCacheKey(config: ApnsConfig) {
  return `${config.teamId}:${config.keyId}:${config.useSandbox ? "sandbox" : "production"}`;
}

function truncateForAlert(raw: string, maxLength = 160) {
  const trimmed = raw.trim();
  if (!trimmed) {
    return "New message";
  }
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return `${trimmed.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
}

function readApnsConfig(): ApnsConfig | null {
  const teamId = process.env.APNS_TEAM_ID?.trim() ?? "";
  const keyId = process.env.APNS_KEY_ID?.trim() ?? "";
  const bundleId = process.env.APNS_BUNDLE_ID?.trim() ?? "";
  const privateKey = normalizePrivateKey(process.env.APNS_PRIVATE_KEY ?? "");
  const useSandbox = (process.env.APNS_USE_SANDBOX ?? "true").trim().toLowerCase() !== "false";

  if (!teamId || !keyId || !bundleId || !privateKey) {
    return null;
  }

  return {
    teamId,
    keyId,
    bundleId,
    privateKey,
    useSandbox,
  };
}

async function getApnsBearerToken(ctx: any, config: ApnsConfig) {
  const cacheKey = providerTokenCacheKey(config);
  const nowMs = Date.now();
  const cached = cachedApnsJwtByEnvironment.get(cacheKey);
  if (cached && cached.expiresAtMs > nowMs) {
    console.log(`${PUSH_LOG_PREFIX} using cached APNs JWT`);
    return cached.token;
  }

  const persisted = await ctx.runQuery(internal.notifications.getCachedApnsProviderToken, {
    cacheKey,
  });
  if (persisted && persisted.expiresAt > nowMs + APNS_TOKEN_REFRESH_BUFFER_MS) {
    cachedApnsJwtByEnvironment.set(cacheKey, {
      token: persisted.bearerToken,
      expiresAtMs: persisted.expiresAt,
    });
    console.log(`${PUSH_LOG_PREFIX} using persisted APNs JWT`);
    return persisted.bearerToken;
  }

  const privateKey = await importPKCS8(config.privateKey, APNS_JWT_ALGORITHM);
  const issuedAtSeconds = Math.floor(nowMs / 1000);

  const token = await new SignJWT({})
    .setProtectedHeader({ alg: APNS_JWT_ALGORITHM, kid: config.keyId })
    .setIssuer(config.teamId)
    .setIssuedAt(issuedAtSeconds)
    .sign(privateKey);

  const expiresAtMs = nowMs + APNS_TOKEN_MAX_AGE_SECONDS * 1000;
  cachedApnsJwtByEnvironment.set(cacheKey, {
    token,
    expiresAtMs,
  });
  await ctx.runMutation(internal.notifications.upsertCachedApnsProviderToken, {
    cacheKey,
    bearerToken: token,
    issuedAt: nowMs,
    expiresAt: expiresAtMs,
  });

  console.log(`${PUSH_LOG_PREFIX} generated new APNs JWT`, {
    teamId: config.teamId,
    keyId: config.keyId,
  });

  return token;
}

function parseApnsFailureReason(rawBody: string) {
  try {
    const parsed = JSON.parse(rawBody);
    if (typeof parsed?.reason === "string" && parsed.reason.length > 0) {
      return parsed.reason;
    }
  } catch {
    // Ignore invalid JSON and fallback below.
  }
  return rawBody.trim() || "Unknown";
}

function isTokenInvalidReason(reason: string) {
  return (
    reason === "Unregistered"
    || reason === "DeviceTokenNotForTopic"
  );
}

async function sendApnsAlert(
  apnsToken: string,
  payload: PreparedPushPayload,
  config: ApnsConfig,
  bearerToken: string
) {
  const host = config.useSandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  let response: Response;
  try {
    response = await fetch(`https://${host}/3/device/${apnsToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${bearerToken}`,
        "apns-topic": config.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      ok: false as const,
      status: 0,
      reason: `FetchError:${message}`,
    };
  }

  if (response.ok) {
    return { ok: true as const };
  }

  const rawBody = await response.text();
  return {
    ok: false as const,
    status: response.status,
    reason: parseApnsFailureReason(rawBody),
  };
}

async function sendWithEnvironmentFallback(
  ctx: any,
  apnsToken: string,
  payload: PreparedPushPayload,
  config: ApnsConfig,
  bearerToken: string
) {
  const primaryResult = await sendApnsAlert(apnsToken, payload, config, bearerToken);
  if (primaryResult.ok || primaryResult.reason !== "BadDeviceToken") {
    return primaryResult;
  }

  const fallbackConfig: ApnsConfig = {
    ...config,
    useSandbox: !config.useSandbox,
  };
  console.warn(`${PUSH_LOG_PREFIX} retrying with alternate APNs environment`, {
    token: maskToken(apnsToken),
    primaryUseSandbox: config.useSandbox,
    fallbackUseSandbox: fallbackConfig.useSandbox,
  });

  const fallbackBearerToken = await getApnsBearerToken(ctx, fallbackConfig);
  const fallbackResult = await sendApnsAlert(
    apnsToken,
    payload,
    fallbackConfig,
    fallbackBearerToken
  );
  if (fallbackResult.ok) {
    console.log(`${PUSH_LOG_PREFIX} fallback APNs environment succeeded`, {
      token: maskToken(apnsToken),
      useSandbox: fallbackConfig.useSandbox,
    });
  }
  return fallbackResult;
}

export const listPushTokensForUsers = internalQuery({
  args: {
    stackUserIds: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const uniqueStackIds = [...new Set(args.stackUserIds)];
    const tokenSet = new Set<string>();
    console.log(`${PUSH_LOG_PREFIX} lookup tokens`, {
      recipientCount: uniqueStackIds.length,
      recipients: uniqueStackIds,
    });

    for (const stackUserId of uniqueStackIds) {
      const records = await ctx.db
        .query("pushTokens")
        .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
        .collect();

      console.log(`${PUSH_LOG_PREFIX} tokens for user`, {
        stackUserId,
        count: records.length,
      });

      for (const record of records) {
        tokenSet.add(record.apnsToken);
      }
    }

    console.log(`${PUSH_LOG_PREFIX} token lookup complete`, {
      uniqueTokenCount: tokenSet.size,
      tokens: [...tokenSet].map(maskToken),
    });
    return [...tokenSet];
  },
});

export const getCachedApnsProviderToken = internalQuery({
  args: {
    cacheKey: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("apnsProviderTokens")
      .withIndex("by_cacheKey", (q: any) => q.eq("cacheKey", args.cacheKey))
      .first();
  },
});

export const upsertCachedApnsProviderToken = internalMutation({
  args: {
    cacheKey: v.string(),
    bearerToken: v.string(),
    issuedAt: v.number(),
    expiresAt: v.number(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("apnsProviderTokens")
      .withIndex("by_cacheKey", (q: any) => q.eq("cacheKey", args.cacheKey))
      .first();
    const now = Date.now();

    if (existing) {
      await ctx.db.patch(existing._id, {
        bearerToken: args.bearerToken,
        issuedAt: args.issuedAt,
        expiresAt: args.expiresAt,
        updatedAt: now,
      });
      return { updated: true };
    }

    await ctx.db.insert("apnsProviderTokens", {
      cacheKey: args.cacheKey,
      bearerToken: args.bearerToken,
      issuedAt: args.issuedAt,
      expiresAt: args.expiresAt,
      updatedAt: now,
    });
    return { updated: false };
  },
});

export const registerPushToken = mutation({
  args: {
    sessionToken: v.string(),
    apnsToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const normalizedToken = normalizeToken(args.apnsToken);
    console.log(`${PUSH_LOG_PREFIX} register token request`, {
      stackUserId: sessionContext.identity.subject,
      token: maskToken(normalizedToken),
      tokenLength: normalizedToken.length,
    });
    if (!APNS_TOKEN_PATTERN.test(normalizedToken)) {
      throw new Error("Invalid APNs token format.");
    }

    const now = Date.now();
    const existingForToken = await ctx.db
      .query("pushTokens")
      .withIndex("by_apnsToken", (q: any) => q.eq("apnsToken", normalizedToken))
      .collect();

    if (existingForToken.length > 0) {
      for (const record of existingForToken) {
        await ctx.db.patch(record._id, {
          stackUserId: sessionContext.identity.subject,
          platform: "ios",
          lastSeenAt: now,
          updatedAt: now,
        });
      }
      return {
        registered: true,
        reused: true,
      };
    }

    await ctx.db.insert("pushTokens", {
      stackUserId: sessionContext.identity.subject,
      apnsToken: normalizedToken,
      platform: "ios",
      createdAt: now,
      updatedAt: now,
      lastSeenAt: now,
    });

    return {
      registered: true,
      reused: false,
    };
  },
});

export const unregisterPushToken = mutation({
  args: {
    sessionToken: v.string(),
    apnsToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const normalizedToken = normalizeToken(args.apnsToken);
    console.log(`${PUSH_LOG_PREFIX} unregister token request`, {
      stackUserId: sessionContext.identity.subject,
      token: maskToken(normalizedToken),
    });
    const existingForToken = await ctx.db
      .query("pushTokens")
      .withIndex("by_apnsToken", (q: any) => q.eq("apnsToken", normalizedToken))
      .collect();

    for (const record of existingForToken) {
      if (record.stackUserId === sessionContext.identity.subject) {
        await ctx.db.delete(record._id);
      }
    }

    return { removed: true };
  },
});

export const deletePushTokenByApnsToken = internalMutation({
  args: {
    apnsToken: v.string(),
  },
  handler: async (ctx, args) => {
    const normalizedToken = normalizeToken(args.apnsToken);
    const records = await ctx.db
      .query("pushTokens")
      .withIndex("by_apnsToken", (q: any) => q.eq("apnsToken", normalizedToken))
      .collect();

    for (const record of records) {
      await ctx.db.delete(record._id);
    }

    return { deleted: records.length };
  },
});

export const sendMessagePush = internalAction({
  args: {
    recipientStackUserIds: v.array(v.string()),
    senderStackUserId: v.string(),
    senderName: v.string(),
    type: v.union(v.literal("direct_message"), v.literal("channel_message")),
    conversationId: v.optional(v.id("conversations")),
    channelId: v.optional(v.id("channels")),
    body: v.string(),
  },
  handler: async (ctx, args) => {
    console.log(`${PUSH_LOG_PREFIX} sendMessagePush start`, {
      type: args.type,
      senderStackUserId: args.senderStackUserId,
      recipientCount: args.recipientStackUserIds.length,
      recipients: args.recipientStackUserIds,
      conversationId: args.conversationId ?? null,
      channelId: args.channelId ?? null,
    });
    if (args.recipientStackUserIds.length === 0) {
      console.log(`${PUSH_LOG_PREFIX} sendMessagePush skipped: no recipients`);
      return { sent: 0, skipped: 0 };
    }

    const config = readApnsConfig();
    if (!config) {
      console.warn(
        `${PUSH_LOG_PREFIX} skipped: missing APNS_* environment variables`,
        {
          hasTeamId: Boolean(process.env.APNS_TEAM_ID),
          hasKeyId: Boolean(process.env.APNS_KEY_ID),
          hasBundleId: Boolean(process.env.APNS_BUNDLE_ID),
          hasPrivateKey: Boolean(process.env.APNS_PRIVATE_KEY),
          useSandbox: process.env.APNS_USE_SANDBOX ?? "true",
        }
      );
      return { sent: 0, skipped: args.recipientStackUserIds.length };
    }

    console.log(`${PUSH_LOG_PREFIX} APNs config loaded`, {
      bundleId: config.bundleId,
      useSandbox: config.useSandbox,
      teamId: config.teamId,
      keyId: config.keyId,
    });

    const tokens = await ctx.runQuery(internal.notifications.listPushTokensForUsers, {
      stackUserIds: args.recipientStackUserIds,
    });
    console.log(`${PUSH_LOG_PREFIX} tokens loaded for send`, {
      uniqueTokenCount: tokens.length,
      tokens: tokens.map(maskToken),
    });
    if (tokens.length === 0) {
      console.warn(`${PUSH_LOG_PREFIX} sendMessagePush skipped: no tokens registered`);
      return { sent: 0, skipped: args.recipientStackUserIds.length };
    }

    const bearerToken = await getApnsBearerToken(ctx, config);
    const notificationBody = truncateForAlert(args.body);
    const title =
      args.type === "channel_message"
        ? truncateForAlert(args.senderName, 60)
        : truncateForAlert(args.senderName, 60);

    const payload: PreparedPushPayload = {
      aps: {
        alert: {
          title,
          body: notificationBody,
        },
        sound: "default",
      },
      type: args.type,
      senderStackUserId: args.senderStackUserId,
      conversationId: args.conversationId as string | undefined,
      channelId: args.channelId as string | undefined,
    };

    let sent = 0;
    let skipped = 0;
    for (const token of tokens) {
      const result = await sendWithEnvironmentFallback(ctx, token, payload, config, bearerToken);
      if (result.ok) {
        sent += 1;
        console.log(`${PUSH_LOG_PREFIX} APNs sent`, {
          token: maskToken(token),
          type: args.type,
        });
        continue;
      }

      skipped += 1;
      console.warn(`${PUSH_LOG_PREFIX} APNs failed`, {
        token: maskToken(token),
        status: result.status,
        reason: result.reason,
      });
      if (isTokenInvalidReason(result.reason)) {
        await ctx.runMutation(internal.notifications.deletePushTokenByApnsToken, {
          apnsToken: token,
        });
        console.warn(`${PUSH_LOG_PREFIX} removed invalid token`, {
          token: maskToken(token),
          reason: result.reason,
        });
      } else {
        console.warn(`${PUSH_LOG_PREFIX} token kept (transient or config issue)`, {
          token: maskToken(token),
        });
      }
    }

    console.log(`${PUSH_LOG_PREFIX} sendMessagePush complete`, {
      sent,
      skipped,
      totalTokens: tokens.length,
    });
    return { sent, skipped };
  },
});
