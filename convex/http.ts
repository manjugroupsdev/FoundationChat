import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";

const ADMIN_SECRET = process.env.ADMIN_API_SECRET ?? "";

function requireAdminSecret(request: Request) {
  const authHeader = request.headers.get("Authorization");
  const token = authHeader?.replace("Bearer ", "").trim() ?? "";

  if (!ADMIN_SECRET || !token || token !== ADMIN_SECRET) {
    throw new Error("Unauthorized");
  }
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

function jsonResponse(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  });
}

function errorResponse(message: string, status = 400) {
  return jsonResponse({ error: message }, status);
}

const optionsHandler = httpAction(async () => {
  return new Response(null, { status: 204, headers: corsHeaders() });
});

// ── Tracked Users ──────────────────────────────────────────────

const listTrackedUsers = httpAction(async (ctx, request) => {
  try {
    requireAdminSecret(request);
  } catch {
    return errorResponse("Unauthorized", 401);
  }
  const data = await ctx.runQuery(internal.locations.listTrackedUsersInternal);
  return jsonResponse(data);
});

// ── Location History ───────────────────────────────────────────

const listLocationHistory = httpAction(async (ctx, request) => {
  try {
    requireAdminSecret(request);
  } catch {
    return errorResponse("Unauthorized", 401);
  }
  const url = new URL(request.url);
  const targetStackUserId = url.searchParams.get("userId");
  const startDate = Number(url.searchParams.get("startDate"));
  const endDate = Number(url.searchParams.get("endDate"));

  if (!targetStackUserId || !startDate || !endDate) {
    return errorResponse("Missing userId, startDate, or endDate params");
  }
  const data = await ctx.runQuery(internal.locations.listForUserInternal, {
    targetStackUserId,
    startDate,
    endDate,
  });
  return jsonResponse(data);
});

// ── Delete Location History ────────────────────────────────────

const deleteLocationHistory = httpAction(async (ctx, request) => {
  try {
    requireAdminSecret(request);
  } catch {
    return errorResponse("Unauthorized", 401);
  }
  const body = await request.json();
  const { targetStackUserId, startDate, endDate } = body;

  if (!targetStackUserId || !startDate || !endDate) {
    return errorResponse("Missing targetStackUserId, startDate, or endDate");
  }
  const result = await ctx.runMutation(internal.locations.deleteForUserInternal, {
    targetStackUserId,
    startDate,
    endDate,
  });
  return jsonResponse(result);
});

// ── All Users ──────────────────────────────────────────────────

const listAllUsers = httpAction(async (ctx, request) => {
  try {
    requireAdminSecret(request);
  } catch {
    return errorResponse("Unauthorized", 401);
  }
  const data = await ctx.runQuery(internal.users.listAllInternal);
  return jsonResponse(data);
});

// ── All Conversations ──────────────────────────────────────────

const listAllConversations = httpAction(async (ctx, request) => {
  try {
    requireAdminSecret(request);
  } catch {
    return errorResponse("Unauthorized", 401);
  }
  const data = await ctx.runQuery(internal.conversations.listAllInternal);
  return jsonResponse(data);
});

// ── All Channels ───────────────────────────────────────────────

const listAllChannels = httpAction(async (ctx, request) => {
  try {
    requireAdminSecret(request);
  } catch {
    return errorResponse("Unauthorized", 401);
  }
  const data = await ctx.runQuery(internal.channels.listAllInternal);
  return jsonResponse(data);
});

// ── All Posts ───────────────────────────────────────────────────

const listAllPosts = httpAction(async (ctx, request) => {
  try {
    requireAdminSecret(request);
  } catch {
    return errorResponse("Unauthorized", 401);
  }
  const data = await ctx.runQuery(internal.posts.listAllInternal);
  return jsonResponse(data);
});

// ── Router ─────────────────────────────────────────────────────

const http = httpRouter();

http.route({ path: "/admin/tracked-users", method: "GET", handler: listTrackedUsers });
http.route({ path: "/admin/tracked-users", method: "OPTIONS", handler: optionsHandler });

http.route({ path: "/admin/locations", method: "GET", handler: listLocationHistory });
http.route({ path: "/admin/locations", method: "OPTIONS", handler: optionsHandler });
http.route({ path: "/admin/locations", method: "DELETE", handler: deleteLocationHistory });

http.route({ path: "/admin/users", method: "GET", handler: listAllUsers });
http.route({ path: "/admin/users", method: "OPTIONS", handler: optionsHandler });

http.route({ path: "/admin/conversations", method: "GET", handler: listAllConversations });
http.route({ path: "/admin/conversations", method: "OPTIONS", handler: optionsHandler });

http.route({ path: "/admin/channels", method: "GET", handler: listAllChannels });
http.route({ path: "/admin/channels", method: "OPTIONS", handler: optionsHandler });

http.route({ path: "/admin/posts", method: "GET", handler: listAllPosts });
http.route({ path: "/admin/posts", method: "OPTIONS", handler: optionsHandler });

export default http;
