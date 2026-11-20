# MMS-250: iOS Request And Polling Load

## Confirmed Client Findings

- Home could reload from both its lifecycle task and warm `onAppear` callback.
  Its minute timer did not check selected tab, actual visibility or scene state.
- The Chat list started both `subscribeConversations` (a one-shot HTTP Future,
  not a stream) and the immediate iteration of its refresh loop. Channel search
  also loaded from both `onAppear` and a task.
- HR and chat polling did not consistently pause when the app became inactive.
  Presence polling ignored a cancelled sleep and could make one final request.
- Concurrent monthly attendance reads were not coalesced. Existing today and
  day-session read sharing had no post-punch generation boundary.

## Scoped Changes

- Home has one lifecycle-owned reload; minute attendance refreshes are visible,
  selected, foreground and completion-scheduled. Returning refreshes again.
- HR refreshes only on the visible foreground root screen. Its existing 180s
  periodic interval is unchanged, pauses for attendance forms and skips an
  already-running refresh. Slow responses cannot stack timer-fired requests.
- Chat list, DM and channel read loops pause when hidden/backgrounded. Visible
  intervals remain 30s for the list, 3s for messages, 2s for typing and 15s for
  presence. The duplicate one-shot list request is removed. Cancellation does
  not fall through into another presence request or a message fallback request.
- The existing MMS-250 local cooldown suppresses optional chat polls after
  429/503 (10/20/40/60s, or a longer numeric Retry-After). It neither retries a
  failed request nor gates sends, uploads, presence writes or tracking.
- Exact attendance GETs share only while in flight, including monthly reads.
  Keys isolate auth, host, query filters/ranges and timeout. No completed result
  is cached here. A cancelled screen consumer cannot cancel the shared read for
  another caller or fan out replacement requests. Punch responses invalidate
  earlier reads so they cannot overwrite the post-punch refresh.

GeoTrack collection/service lifecycle, heartbeats, point batching, visit/trip
writes, offline punch storage/replay, session-invalidation rules, PostHog bounds
and all backend code/settings remain unchanged. No new probes or retries.

## Verification And Release Gate

Verified 20 November 2026: all 15 standalone helper harnesses pass, including
20 surviving attendance readers after owner cancellation, cancelled-waiter
isolation, fresh reads after 429/503, UI polling cancellation/no-overlap, real
session-invalidation and PostHog-host boundaries. The full 229-source SDK build
passed (205.06s), followed by a final-source incremental SDK pass (88.56s).
The HR application/shift harnesses depend on app-only types and are not run by
the standalone runner; their source is included in the SDK build instead.

Run `bash tests/run-mobile-helper-tests.sh` for the pure Swift harnesses. These
exercise actual read-sharing/polling helpers, cancellation, overload/freshness,
account isolation, transport and real session-invalidation boundaries without
production requests. Full app sources are also checked against the arm64 iOS
SDK on the available WSL toolchain.

The SDK check substitutes a staging-only SwiftData macro shim. It is not a
native Xcode archive, actual SwiftData/runtime validation, physical-iPhone test,
TestFlight upload, active-trip continuity test or battery-day measurement.
Manoj must run those native build/device checks before rollout. In particular,
verify Home/HR/chat hide, return, foreground and background transitions; a
post-punch refresh; offline punch recovery; and a controlled active trip.

This reduces proven mobile load amplifiers. It does not prove that every
production 429/503, upstream capacity condition or network-path timeout is
resolved. Server logs/metrics and deployment verification remain operator work.
