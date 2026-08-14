# iOS Parity Sync — Build & Verify Checklist

_Generated 2026-08-13. Companion to `PARITY_ROADMAP.md`. Covers the Android→iOS
backend/logic parity sync ported into the `darx` working tree. Updated 2026-08-14
after pulling `origin/darx` to `9c5bd20`: the Debug simulator build now succeeds
on macOS/Xcode, so remaining items below are runtime, device, or backend-contract
checks rather than first-compile blockers._

## Build status

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FoundationChat.xcodeproj -scheme FoundationChat \
  -destination 'generic/platform=iOS Simulator' build
```

Verified locally on 2026-08-14 with:

```sh
xcodebuild -project FoundationChat.xcodeproj -scheme FoundationChat \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build
```

Result: **BUILD SUCCEEDED**. The pulled `darx` head also closes two previously
large parity gaps: Inventory/Dialer/My Leads are no longer App-Library
Coming-soon rows, and Site Visits now include completed-visit arrival proof plus
journey timeline detail.

Original change surface: **24 files modified, 3 new** (`PendingPunchStore.swift`,
`CpOutcomePolicy.swift`, `CpApprovalQueueView.swift`), ~1,466 insertions, plus
later parity commits through `9c5bd20`.

## Highest-risk items to check first
1. **Backend field/enum contracts** — the shared `api-mfpl` validator is strict. New/renamed
   request fields and outcome literals must match exactly (see per-module VERIFY).
2. **Fleet MMS driver create/update/set-status** was moved from raw-Convex to REST
   (`api/mms-fleet/dispatch/drivers/*`) — live-check the staff token is accepted.
3. **Punch `clientPunchTime`** — confirm the endpoint reads it as an ISO string and overrides
   server-receive time; otherwise offline/tap-time accuracy silently degrades.
4. **GeoTrack** — clock-out must stop tracking promptly while backgrounded (device QA).

---

## Functional verify — by module

### CP/SV outcome (CompleteCpVisitSheet, SiteVisitOutcomeSheet, TripNavigationView, CpVisitsView, SiteVisitsListView, MarketingConvexAPIService, ConvexAppModuleModels, CpOutcomePolicy.swift)
- **Preserved (do not regress):** the pending-SV FLIP vs materialize branch (`isLockedSvMode && convertedSiteVisitId != nil` → `setCpVisitOutcome outcome:"interested"`, else `convertCpVisitToSiteVisit`), and `hasFixedSiteVisitSignal` detection.
- P0-1 geofence: out-of-fence CP completion now warns + captures reason → `setCpGeofenceRemark` → proceeds (held for GM approval), no longer hard-blocked. Uses `.alert` TextField (iOS16+); **empty reason is allowed through** (best-effort, like Android).
- P0-2: SV "postponed" → `follow_up` (backend rejects "postponed" for SV). Verify SV setOutcome accepts `follow_up` + `followupDueDate`.
- P1-3: neither sheet pre-selects an outcome tab now.
- P1-4: best-effort `markSiteVisitOnCounselling` before SV `setOutcome` (fixes on_site 500).
- P1-5: "Others" outcome gated by `cpTypeSupportsOtherOutcome({booking_cp,gift_distribution,follow_up})`; `cpType` threaded into `CompleteCpVisitSheet` (new **required** param — watch for other instantiations/previews).
- **VERIFY:** (a) `SetSiteVisitOutcomeRequest` still sends `reasons`/`bookingId` that Android omits — confirm validator tolerates. (b) `followupDueTime` sent nil (date-only UI). (c) `SetCpVisitOutcomeRequest` converted to explicit init. (d) `svStyle = isLockedSvMode || sv_cum_cp`; did NOT also hide the Site Visit tab for SV-cum-CP — flag if it should.

### Marketing flows (CompleteCpVisitSheet, PostSales/Marketing services + models)
- Booking-draft autosave/get/clear (2s debounce, `sourceKey="cp:<id>"`, resume prefers newer of local/cloud, clear after createBooking).
- Collection self-correction added (`collections/correct`); gate/union/proof were already parity.
- **VERIFY:** `bookings/draft/get` response shape + `updatedAt` unit (assumed **ms**); cross-platform draft blob shape differs (graceful-empty fallback, Android↔iOS won't cross-resume same CP); `collections/correct` returns updated row; `collectorEditedAt` key.

### Arrival-OTP + GM approval (ArrivalOtpSheet, TripNavigationView, GeoTrack models/service, CpApprovalQueueView, CpVisitsView)
- Arrival photo now sent **inline at OTP-verify** (Android parity); also still sent at completeVisit (idempotent belt-and-braces).
- New **CpApprovalQueueView** (approve/reject out-of-geofence CP completions), reached from CpVisitsView toolbar — pairs with P0-1 above.
- **VERIFY:** dual-send idempotency (remove from completeVisit if backend overwrites); `CpApprovalItem` **camelCase** JSON keys against live `/cp-visits/pending-approvals`; `photoUrl` assumed a resolved URL (not a bare storage id); no client permission gate (shown to all, server scopes the feed) — add `hasPermission` gate if desired.

### Fleet / TravelDesk (FleetDispatchAPIService, FleetDispatchModels, FleetPortalExperienceView)
- Added: `updateVehicle` (+Active/Inactive status field), driver `category` (new/old), agencies list/allot, `unassign`, `resendDriverWhatsapp`, `finalizeBilling`, `cancellationBilling`, `extraKm`, `evidence`, `statusUpdate`, `completeOffline`. Vehicle edit UI added.
- **VERIFY:** MMS driver create/update/set-status **convexMutate→REST swap** (behavioral — confirm token accepted); MMS vehicle create left on Convex (no REST route in Android); driver `category` lowercase accepted both scopes; nil-omit vs explicit-null encoding; billing/status/offline **service methods NOT yet wired to buttons** (need photo/km/reason UIs — build on Mac); settings/staff routes skipped (iOS settings still local `@AppStorage`); `FleetVehicleDetailSheet` edit-button placement (custom header, no NavigationStack).

### Punch / attendance (AttendanceTrackingGate, HRConvexAPIService, PunchFlowView, HomeView, PendingPunchStore.swift)
- Dual gates: lenient source-agnostic day-gate (status/ticker) vs strict `hasOpenSessionNow()->Bool?` (new-trip start); **nil = retain last state, never stop**. Biometric/manual/csv punches enable trips+tracking identically.
- Device **tap-time** captured → `clientPunchTime` (ISO local offset).
- **Offline punch queue** (`PendingPunchStore`, new isolated Core Data store): enqueue on network failure, flush on Home open, replay with original tap time + selfie (uploaded at flush), delete on server-reject / keep on network-fail.
- **VERIFY:** `clientPunchTime` field name/unit + server override; second `NSPersistentContainer` ("PendingPunch") loads cleanly alongside GeoTrack; Application Support selfie read/write + cleanup; `HRConvexAPIError`(reject/don't-retry) vs `URLError`(queue) classification matches your 4xx/5xx surfacing; server rejects duplicate replayed punch; tap time = selfie moment (change to Confirm-tap if preferred).

### Chat forwarding (ConversationDetailView)
- Channels added as forward targets (conversation-forward already existed).
- **VERIFY:** channel-forward attachment payload (`storageId/fileName/fileType/fileSize`); picker shows my+public channels (Android = member-only — filter by `joined` if backend populates it). Private-file stubs left `notImplemented` (dead sample, no Android feature/route — confirm no `/api/files/*` exists). Offline send queue already durable (SwiftData) — untouched.

### GeoTrack lifecycle (GeoTrackPersistence, GeoTrackBootstrapCoordinator, LocationManager, GeoTrackAPIService, GeoTrackModels)
- **Fixed:** `fatalError` on Core Data load → recovery ladder (destroy+recreate → in-memory fallback); bootstrap clock-in gate now `hasOpenSessionNow()->Bool?` with nil=retain (won't stop tracking on a blip); batch drain up to 25×200/cycle + 30-day age-purge of unsent points/tamper events; tamper events replay with true `detectedAt`.

---

## Device QA (GeoTrack — can't be validated without a real device)
- **Clock-out cadence:** iOS re-evaluates the gate on app lifecycle/foreground, not a guaranteed 30s background wake. Confirm clock-out stops tracking promptly while backgrounded and no out-of-window points are captured after punch-out.
- **Motion-adaptive GPS (NOT ported — device tuning):** iOS only switches accuracy on fg/bg. Android targets to tune against: 10s moving / 150s+40m idle; sticky recent-motion 120s; motion ≥1.5 m/s; stationary dedup skip <50m within 5min; moving store >15m; drift guards (>100m@<1m/s, >500m@<15m/s).
- **Heartbeat (NOT ported — structural):** cadence matches (120s) but iOS sends only `batteryPct`+`appVersion` and does **not** buffer/replay failed heartbeats. Android also sends `recordedAt`/`airplaneMode`/`locationEnabled` and replays. Add if the web battery/uptime history needs no gaps.

---

## Deferred / known-remaining parity items (by design)
- **Cache-first `LocalCache`** (dashboard/home/chat stale-while-refresh) — perf polish, not a logic gap; iOS stays network-only for now. Do after the first build settles.
- **Fleet billing/status/offline UIs** — service methods are ready; the input UIs (photo/km/reason) are better built + run on Mac.
- **Fleet settings/staff server-backing** — iOS "Rate System" is local `@AppStorage`; port `travel-desk/settings|staff` routes when made server-backed.
- **Motion-adaptive GPS + heartbeat buffer/replay** — device-tuned / structural (above).
- **AuthStore `notImplemented` stubs** (Posts feed, location history, private-file share) — no Android counterpart / no backend route; left honest rather than faked. Leave unless a real feature+endpoint appears.

---

# Wave 2 — full module audit (logic + functional UI/UX)

Every remaining module was diffed Android-vs-iOS and fixed. **Real functional bugs the audit
caught** (not polish — these were broken):

| Bug | Module | Effect |
|---|---|---|
| `ConvexLead` decoded a fabricated JSON shape (`name/phone/status`) | Telecaller | **every lead rendered blank**; search/filter never matched |
| Permission model decoded `durationMinutes` (fake) vs real `hours` | HR Permissions | **every permission showed "--"** |
| Half-day leave mapped to `"casual"` instead of `"unpaid"` | HR Leaves | **wrong balance drained** (data bug); half-days showed "0 Days" |
| Reschedule sent `{id,scheduledDate}` vs `{propertyId,requestedDate}` | Land | **reschedule always silently failed** |
| Inspection form never called `/get` | Land | **saved report never loaded** — all tabs opened blank |
| Loan Desk role→action mapping wrong; Sales submit unreachable | Post-Sales | wrong actions per role; **Sales could never submit docs** |
| `correctCollection` API had no UI | Post-Sales | collectors **couldn't edit** a pending amount |
| Fleet "My Trips" tile never listed in any section | App Library | **tile invisible** to drivers/admins |
| Dashboard hardcoded fake trend `%` + dropped `prev*` decode | Dashboard | **fake numbers shown as data** |
| Expense posted `paid:true` | Projects | new expenses showed "Paid" not "Pending" |
| `AppNotification._id` required, no `id` fallback | Notifications | list decode could throw → **notifications vanish** (fixed) |
| Missing `dailyTasks/updateStatus`; handoff actions; non-tappable cards | Tasks | task-manager actions unreachable |
| Self-Finance tab excluded blank-category rows | Post-Sales | rows hidden from tab |

**Also fixed:** missing IAM gates (`canViewFleetMyTrips`, `canCompleteOfflineFleet`), Front-Desk
scanner gate widened to `marketing.siteVisits.*`, "Delayed" task status selector wired, Land
yes/no unions + phases field, loan-desk View-Documents + rejection remarks + name-based role
detection.

**At parity, no change needed:** Daily Log/DPR, Issues, Front Desk (local history store + state
machine), Accounts verification, comp-off, fines, staff, arrival-OTP, collection gate/union/proof,
offline chat outbox, OTP/emp-id/change-pw/validate/logout, 401→logout bus, most App-Library gates.

## Wave-2 VERIFY ON MAC (add to the list above)
- **Tasks:** `POST /api/dailyTasks/updateStatus` route on prod; web origin `mg.theairix.com`.
- **HR:** permission payload key is `hours`; half-day books against **unpaid** + renders "0.5 Day";
  loan repayments are embedded in `/get` (else history empty).
- **Land:** reschedule `{propertyId,requestedDate}` accepted; form hydrates from `/get`; server
  accepts `eConnectionToLand`/`telecom` as `yes`/`no` + `eConnectionPhases`.
- **Post-Sales:** loan-desk `statusLabel` exact strings (`Docs Pending`/`App Received`/`Approved`/
  `Rejected`); `LabeledContent` iOS16+.
- **Dashboard:** trend pills show real deltas when backend sends `prev*`, hidden otherwise.
- **App Library:** Fleet "My Trips" shows for driver/super-admin, hidden otherwise.

## Remaining follow-ups (flagged, need a small targeted pass or backend confirmation)
- **Telecaller softphone/dashboard depth** — App Library now opens real My Leads
  and Dialer screens, but iOS still does not have Android's full in-app WebRTC
  call service/incoming-call stack or Calls Report/Registrations dashboards.
- **Site Visit depth** — completed-visit arrival proof and timeline are now
  present. Remaining depth is the Android-style overview funnel/KPI screen and
  any live-detail deltas discovered during device testing.
- **Loan approval e-signature** — Android requires a digital signature (`ApproveLoanRequest{id,
  eSignatureId}` via `/api/hr/staff/digital-sign`); iOS sends only `{id}`. **Confirm whether the
  backend REJECTS loan approval without `eSignatureId`** — if so this blocks iOS loan approval and
  needs the digital-sign endpoints + a signature-capture sheet. (Lives in `MarketingConvexAPIService`.)
- **Loan workflow tracker** (`/api/hr/loans/workflow`) + dedicated **repayments** endpoint — absent
  on iOS (uses embedded data). Marketing-service additions.
- **`approvals` push route** — no iOS handler; wire `PushNavigationRoute` → the new
  `CpApprovalQueueView`.
- **Push-register payload** — send `provider:"apns"` + `deviceId` (iOS sends only token/platform/
  bundleId); confirm real bundle id.
- **Profile edit** — `updateMyProfile` posts to `/api/staff/me/update` vs Android `/api/hr/staff/
  update`, and has no caller; wire the iOS profile-edit screen to the correct path.
- **reporting-officer fields** on leave/permission apply (backend resolves server-side; low impact).
- Fleet driver-designation exact-vs-prefix match + external-fleet routing breadth — regression-guarded,
  leave until deliberately migrated.

---

# Wave 3 — cache-first loading + offline + white-layer fix

New reusable `FoundationChat/Utilities/LocalCache.swift` (Swift mirror of Android
`ui/common/LocalCache`: per-key JSON under Application Support/`response_cache/`, timestamped,
failure-swallowing, `clearAll()` on logout).

**Cache-first ("stale-while-refresh") + offline-keep wired into:**
- **Home attendance** — `paintCachedHomeState()` repaints today/month attendance from cache before
  the network round-trip → clocked-in status/times paint instantly. Punch/gate/PendingPunch logic
  untouched. Offline: keeps cached snapshot on fetch failure.
- **Dashboard (VP tiles)** — paints cached `ConvexMobileDashboard` on entry; caches on success.
  Skeleton already gated on `managementDashboard == nil`, so with cache it never flashes.
- **Logout** — `LocalCache.clearAll()` in `AuthStore.logout()` and `expireSession()`.
- **Lists (best-effort):** Tasks, My Leads, Leaves (.my), Permissions (.my) — paint-if-empty,
  keep-on-error.

**White-layer fix (user-reported "white layer blocking the view very often"):** root cause was the
full-screen white loading skeleton re-showing on every `reload()` (which runs on every return to
Home). Dashboard path is fixed by the cache paint + its existing `== nil` gate; the trip section
(`HomeView.swift:658`) was ungated and now uses `if isLoading && visibleVisits.isEmpty` so refresh
never covers existing content.

## Wave-3 compile status
- Types changed Decodable→**Codable** and compile successfully: `ConvexAttendanceSession/
  Fine/Record`, `ConvexTodayAttendance`, `ConvexLeave`, `ConvexLeaveBalance`, `ConvexPermission`,
  `ConvexPermissionUsage`, `ConvexMobileDashboard`, `DailyTask`, `ConvexLead` (the 3 with custom
  `init(from:)` + explicit CodingKeys are the ones to watch; `ConvexLead` has one extra unused `id`
  CodingKey).
- `LocalCache.get(_:as:)`/`put` generic inference on the new snapshot types + `[ConvexLead]`
  compiles.
- staffId source `authStore.currentSession?.user.staffId ?? _id ?? "anon"`.
- **Device:** confirm `homeOverviewSection` (personal attendance card) is actually rendered in
  `contentArea` on this branch — the cache plumbing is correct but only *visible* if that section is
  in the view tree (dashboard users are unaffected).

## Wave-3 not-wired (follow-up: needs a Mac build to add `encode(to:)`/projection snapshots)
- Cache-first for **chat list, CP visits, site visits, collections** — their models have custom
  lossy `init(from:)` with renamed keys, so Encodable synthesis is unsafe to add blind.
- **Trip-list** cache-first (would remove the cold-recreate skeleton for driver/normal users too).
