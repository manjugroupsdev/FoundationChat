/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as auth from "../auth.js";
import type * as authHelpers from "../authHelpers.js";
import type * as channels from "../channels.js";
import type * as conversations from "../conversations.js";
import type * as http from "../http.js";
import type * as locations from "../locations.js";
import type * as messages from "../messages.js";
import type * as notificationPrefs from "../notificationPrefs.js";
import type * as notifications from "../notifications.js";
import type * as posts from "../posts.js";
import type * as presence from "../presence.js";
import type * as reactions from "../reactions.js";
import type * as storageFolders from "../storageFolders.js";
import type * as typing from "../typing.js";
import type * as users from "../users.js";
import type * as viewer from "../viewer.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  auth: typeof auth;
  authHelpers: typeof authHelpers;
  channels: typeof channels;
  conversations: typeof conversations;
  http: typeof http;
  locations: typeof locations;
  messages: typeof messages;
  notificationPrefs: typeof notificationPrefs;
  notifications: typeof notifications;
  posts: typeof posts;
  presence: typeof presence;
  reactions: typeof reactions;
  storageFolders: typeof storageFolders;
  typing: typeof typing;
  users: typeof users;
  viewer: typeof viewer;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
