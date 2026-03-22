import { internal } from "./_generated/api";
import { action, internalMutation, mutation } from "./_generated/server";
import { v } from "convex/values";
import { OTP_IDENTITY_ISSUER, requireSession } from "./authHelpers";

const OTP_VALIDITY_MS = 10 * 60 * 1000;
const OTP_RESEND_COOLDOWN_MS = 60 * 1000;
const OTP_MAX_ATTEMPTS = 5;
const SESSION_VALIDITY_MS = 30 * 24 * 60 * 60 * 1000;
const ADMIN_PHONE_NUMBER = "+916369487527";
const ADMIN_STACK_USER_ID = `phone:${ADMIN_PHONE_NUMBER}`;
const ADMIN_FIXED_OTP = "123456";
const ADMIN_DISPLAY_NAME = "MMS Admin";

function normalizePhoneNumber(input: string) {
  const trimmed = input.trim();
  if (!trimmed) {
    throw new Error("Phone number is required");
  }

  if (trimmed.startsWith("+")) {
    const digits = trimmed.slice(1).replace(/\D/g, "");
    if (digits.length < 10 || digits.length > 15) {
      throw new Error("Enter a valid phone number");
    }
    return `+${digits}`;
  }

  const digitsOnly = trimmed.replace(/\D/g, "");
  if (digitsOnly.length == 10) {
    return `+91${digitsOnly}`;
  }
  if (digitsOnly.length >= 11 && digitsOnly.length <= 15) {
    return `+${digitsOnly}`;
  }

  throw new Error("Enter a valid phone number");
}

function generateOtpCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function generateSessionToken() {
  const segmentA = crypto.randomUUID();
  const segmentB = crypto.randomUUID().replace(/-/g, "");
  return `sess_${segmentA}${segmentB}`;
}

function resolvedOtpForPhone(phoneNumber: string, requestedOtp?: string) {
  if (phoneNumber === ADMIN_PHONE_NUMBER) {
    return ADMIN_FIXED_OTP;
  }

  const candidate = requestedOtp?.trim() ?? generateOtpCode();
  if (!/^\d{6}$/.test(candidate)) {
    throw new Error("Invalid OTP format");
  }
  return candidate;
}

async function upsertUserForPhone(ctx: any, phoneNumber: string, now: number) {
  const stackUserId = `phone:${phoneNumber}`;
  const existingUser = await ctx.db
    .query("users")
    .withIndex("by_stackUserId", (q: any) => q.eq("stackUserId", stackUserId))
    .first();

  const preferredName = phoneNumber === ADMIN_PHONE_NUMBER ? ADMIN_DISPLAY_NAME : phoneNumber;

  if (existingUser) {
    await ctx.db.patch(existingUser._id, {
      name: existingUser.name ?? preferredName,
      updatedAt: now,
    });
    return stackUserId;
  }

  await ctx.db.insert("users", {
    stackUserId,
    name: preferredName,
    email: undefined,
    imageUrl: undefined,
    createdAt: now,
    updatedAt: now,
  });

  return stackUserId;
}

function readAirtelConfig() {
  return {
    endpoint:
      process.env.AIRTEL_SMS_ENDPOINT ?? "https://iqsms.airtel.in/api/v1/send-prepaid-sms",
    customerId:
      process.env.AIRTEL_CUSTOMER_ID ?? "8dfa792b-7695-4054-ad5b-0ac872a05453",
    dltTemplateId:
      process.env.AIRTEL_DLT_TEMPLATE_ID ?? "1007495382194071124",
    entityId: process.env.AIRTEL_ENTITY_ID ?? "1001711943218436692",
    sourceAddress: process.env.AIRTEL_SOURCE_ADDRESS ?? "MNJWLL",
    messageType: process.env.AIRTEL_MESSAGE_TYPE ?? "SERVICE_IMPLICIT",
    otpMessageTemplate:
      process.env.AIRTEL_OTP_MESSAGE_TEMPLATE
      ?? "{{OTP}} is the OTP to signup on AIVIDA. Valid for 10 minutes. Do not share this with anyone.",
  };
}

function renderOtpMessage(template: string, otp: string) {
  if (template.includes("{{OTP}}")) {
    return template.replace(/\{\{OTP\}\}/g, otp);
  }
  return `${otp} ${template}`;
}

async function sendOtpThroughAirtel(phoneNumber: string, otp: string) {
  const config = readAirtelConfig();
  const message = renderOtpMessage(config.otpMessageTemplate, otp);

  const response = await fetch(config.endpoint, {
    method: "POST",
    headers: {
      accept: "application/json",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      customerId: config.customerId,
      destinationAddress: [phoneNumber],
      dltTemplateId: config.dltTemplateId,
      entityId: config.entityId,
      message,
      messageType: config.messageType,
      sourceAddress: config.sourceAddress,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Failed to send OTP (Airtel ${response.status}): ${errorText || "No error details"}`
    );
  }
}

export const createOtpChallenge = internalMutation({
  args: {
    phoneNumber: v.string(),
    code: v.string(),
    now: v.number(),
    expiresAt: v.number(),
  },
  handler: async (ctx, args) => {
    const latestChallenge = await ctx.db
      .query("otpChallenges")
      .withIndex("by_phoneNumber_createdAt", (q) => q.eq("phoneNumber", args.phoneNumber))
      .order("desc")
      .first();

    if (latestChallenge && args.now - latestChallenge.createdAt < OTP_RESEND_COOLDOWN_MS) {
      const retryAfterSeconds = Math.ceil(
        (OTP_RESEND_COOLDOWN_MS - (args.now - latestChallenge.createdAt)) / 1000
      );
      throw new Error(`Please wait ${retryAfterSeconds}s before requesting another OTP.`);
    }

    return await ctx.db.insert("otpChallenges", {
      phoneNumber: args.phoneNumber,
      code: args.code,
      attempts: 0,
      maxAttempts: OTP_MAX_ATTEMPTS,
      expiresAt: args.expiresAt,
      consumedAt: undefined,
      createdAt: args.now,
      updatedAt: args.now,
    });
  },
});

export const deleteOtpChallenge = internalMutation({
  args: {
    challengeId: v.id("otpChallenges"),
  },
  handler: async (ctx, args) => {
    await ctx.db.delete(args.challengeId);
    return { success: true };
  },
});

export const requestOtpFromClient = mutation({
  args: {
    phoneNumber: v.string(),
    otp: v.string(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const normalizedPhoneNumber = normalizePhoneNumber(args.phoneNumber);
    const normalizedOtp = resolvedOtpForPhone(normalizedPhoneNumber, args.otp);

    const latestChallenge = await ctx.db
      .query("otpChallenges")
      .withIndex("by_phoneNumber_createdAt", (q) => q.eq("phoneNumber", normalizedPhoneNumber))
      .order("desc")
      .first();

    if (latestChallenge && now - latestChallenge.createdAt < OTP_RESEND_COOLDOWN_MS) {
      const retryAfterSeconds = Math.ceil(
        (OTP_RESEND_COOLDOWN_MS - (now - latestChallenge.createdAt)) / 1000
      );
      throw new Error(`Please wait ${retryAfterSeconds}s before requesting another OTP.`);
    }

    const expiresAt = now + OTP_VALIDITY_MS;
    await upsertUserForPhone(ctx, normalizedPhoneNumber, now);
    const challengeId = await ctx.db.insert("otpChallenges", {
      phoneNumber: normalizedPhoneNumber,
      code: normalizedOtp,
      attempts: 0,
      maxAttempts: OTP_MAX_ATTEMPTS,
      expiresAt,
      consumedAt: undefined,
      createdAt: now,
      updatedAt: now,
    });

    return {
      challengeId,
      phoneNumber: normalizedPhoneNumber,
      expiresAt,
      expiresInSeconds: Math.floor((expiresAt - now) / 1000),
    };
  },
});

export const cancelOtpRequest = mutation({
  args: {
    challengeId: v.id("otpChallenges"),
  },
  handler: async (ctx, args) => {
    const challenge = await ctx.db.get(args.challengeId);
    if (challenge) {
      await ctx.db.delete(args.challengeId);
    }
    return { success: true };
  },
});

export const consumeOtpAndCreateSession = internalMutation({
  args: {
    phoneNumber: v.string(),
    code: v.string(),
    now: v.number(),
  },
  handler: async (ctx, args) => {
    const latestChallenge = await ctx.db
      .query("otpChallenges")
      .withIndex("by_phoneNumber_createdAt", (q) => q.eq("phoneNumber", args.phoneNumber))
      .order("desc")
      .first();

    if (!latestChallenge) {
      throw new Error("No OTP request found for this phone number.");
    }

    if (latestChallenge.consumedAt) {
      throw new Error("This OTP has already been used. Request a new OTP.");
    }

    if (latestChallenge.expiresAt <= args.now) {
      throw new Error("OTP has expired. Request a new OTP.");
    }

    if (latestChallenge.attempts >= latestChallenge.maxAttempts) {
      throw new Error("Too many invalid attempts. Request a new OTP.");
    }

    if (latestChallenge.code !== args.code.trim()) {
      await ctx.db.patch(latestChallenge._id, {
        attempts: latestChallenge.attempts + 1,
        updatedAt: args.now,
      });
      throw new Error("Invalid OTP. Please try again.");
    }

    await ctx.db.patch(latestChallenge._id, {
      consumedAt: args.now,
      updatedAt: args.now,
    });

    const stackUserId = await upsertUserForPhone(ctx, args.phoneNumber, args.now);
    const identityName = args.phoneNumber === ADMIN_PHONE_NUMBER ? ADMIN_DISPLAY_NAME : args.phoneNumber;

    const sessionToken = generateSessionToken();
    const expiresAt = args.now + SESSION_VALIDITY_MS;

    await ctx.db.insert("authSessions", {
      sessionToken,
      stackUserId,
      phoneNumber: args.phoneNumber,
      createdAt: args.now,
      updatedAt: args.now,
      expiresAt,
    });

    return {
      sessionToken,
      phoneNumber: args.phoneNumber,
      stackUserId,
      expiresAt,
      identity: {
        tokenIdentifier: `otp:${stackUserId}`,
        subject: stackUserId,
        issuer: OTP_IDENTITY_ISSUER,
        email: null,
        name: identityName,
      },
    };
  },
});

export const requestOtp = action({
  args: {
    phoneNumber: v.string(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const normalizedPhoneNumber = normalizePhoneNumber(args.phoneNumber);
    const otp = resolvedOtpForPhone(normalizedPhoneNumber);
    const expiresAt = now + OTP_VALIDITY_MS;

    await ctx.runMutation(internal.auth.ensureUserForPhone, {
      phoneNumber: normalizedPhoneNumber,
      now,
    });

    const challengeId = await ctx.runMutation(internal.auth.createOtpChallenge, {
      phoneNumber: normalizedPhoneNumber,
      code: otp,
      now,
      expiresAt,
    });

    try {
      await sendOtpThroughAirtel(normalizedPhoneNumber, otp);
    } catch (error) {
      await ctx.runMutation(internal.auth.deleteOtpChallenge, { challengeId });
      throw error;
    }

    return {
      phoneNumber: normalizedPhoneNumber,
      expiresAt,
      expiresInSeconds: Math.floor((expiresAt - now) / 1000),
    };
  },
});

export const ensureUserForPhone = internalMutation({
  args: {
    phoneNumber: v.string(),
    now: v.number(),
  },
  handler: async (ctx, args) => {
    await upsertUserForPhone(ctx, args.phoneNumber, args.now);
    return { success: true };
  },
});

export const verifyOtp = action({
  args: {
    phoneNumber: v.string(),
    otp: v.string(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const normalizedPhoneNumber = normalizePhoneNumber(args.phoneNumber);

    return await ctx.runMutation(internal.auth.consumeOtpAndCreateSession, {
      phoneNumber: normalizedPhoneNumber,
      code: args.otp,
      now,
    });
  },
});

export const restoreSession = mutation({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionContext = await requireSession(ctx, args.sessionToken);
    const now = Date.now();

    await ctx.db.patch(sessionContext.session._id, {
      updatedAt: now,
    });

    return {
      sessionToken: sessionContext.session.sessionToken,
      phoneNumber: sessionContext.session.phoneNumber,
      expiresAt: sessionContext.session.expiresAt,
      stackUserId: sessionContext.session.stackUserId,
      identity: sessionContext.identity,
    };
  },
});

export const logout = mutation({
  args: {
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const session = await ctx.db
      .query("authSessions")
      .withIndex("by_sessionToken", (q) => q.eq("sessionToken", args.sessionToken.trim()))
      .first();

    if (session) {
      await ctx.db.delete(session._id);
    }

    return {
      success: true,
    };
  },
});
