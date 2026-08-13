# Android → iOS Parity Roadmap (backend/logic focus)

_Owner: DARX. Generated 2026-08-13 from a fresh dual-repo audit. Supersedes the stale
`ANDROID_IOS_LATEST_UPDATE_GAP.md` (2026-07-17)._

## Ground rules

- **Goal:** bring the iOS SwiftUI app (this repo, `darx` branch) to **backend/logic parity**
  with the Android app (`Mconnect`). Keep the iOS **UI native** — do not clone Android XML.
- **Backend:** both apps target the **same prod backend**. iOS base URL is hardcoded
  `https://api-mfpl.theairix.com` (`FoundationChat/Config/AppConfig.swift`); Android uses the
  same host in prod via `BuildConfig.BASE_URL`. ⚠️ Confirm once: Android's gradle *default*
  string still reads `next-spaniel-814.convex.site` (a reverted test DB) — prod is overridden
  to mfpl. Treat mfpl as the source of truth.
- **Build/verify:** this work is authored on **Windows (no Xcode)**. Claude ports logic in
  reviewable slices; **safeer/teammate builds on macOS** and returns compile/runtime errors;
  Claude fixes. iOS edits ship un-compiled from Claude's side.
- **Priority:** biggest **logic** gaps first (not bug-fix-first, not UI).

## Reframe from the audit

The iOS **service/endpoint layer is ~80% present** and on the right backend. The gap is
**business-logic flows** (the non-trivial behavior beyond a plain API call) and a few
genuinely incomplete modules — NOT missing endpoints.

## Prioritized logic gaps

1. **GeoTrack lifecycle correctness** (XL, device-only QA)
   - Android ref: `geotrack/service/GeoTrackService.kt`, `AttendanceTrackingGate.kt`, `geotrack/data/*`.
   - Must match: clock-in→out bounding; Room/Core-Data **store-and-forward** (batch sync w/ backoff,
     sent-purge 7d, unsent-purge 30d); **motion-adaptive GPS** (10s moving / 150s idle, sticky
     recent-motion window, stationary dedup); heartbeat 120s; **tamper events stamped at true
     `detectedAt`** so replayed offline events surface at the real time.
   - iOS today: `GeoTrackAPIService.swift` + `LocationManager`/`GeoTrackPersistence`/`Heartbeat`/
     `TamperMonitor`/`BootstrapCoordinator` exist and are the best-architected area. Lifecycle
     *rules* unverified; `GeoTrackPersistence.swift:92` has a `fatalError` crash path.

2. **Punch / attendance flow** (XL)
   - Android ref: `ui/home/HomeViewModel.kt` `punch()` (~L214), `enqueueOfflinePunch()` (~L311),
     `geotrack/AttendanceTrackingGate.kt`.
   - Must match: capture **device tap time** as punch timestamp; **offline enqueue+replay** of
     punches (photo + tap time) flushed when Home opens; **two clocked-in notions** (lenient
     day-gate vs strict open-session-now); **biometric/manual/csv punch enables trips+tracking
     identically to in-app punch** (source-agnostic gate).
   - iOS today: `HRConvexAPIService.swift` covers punch endpoints (SOLID); offline queue + tap-time
     + dual-gate logic likely absent.

3. **CP ↔ SV outcome + confirmation flip** (L, pure logic — good first slice)
   - Android ref: `ui/home/CompleteCpVisitBottomSheet.kt` (outcome policy), `ui/marketing/*`.
   - Must match: 4-tab outcome chooser with **none pre-selected**; convert path distinguishes a
     **pre-existing pending SV** (`setOutcome` flips confirmationStatus pending→confirmed) vs
     **materialize new** (`convertToSiteVisit`) via `convertedSiteVisitId` — unconditional convert
     strands the SV pending; out-of-geofence CP → GM approval (`geofence-remark` → approve/reject).
   - iOS today: `MarketingConvexAPIService.swift` has the endpoints; branch logic unverified.

4. **Fleet / TravelDesk admin** (L — genuinely incomplete)
   - Android ref: `network/TravelDeskApi.kt`.
   - iOS `FleetDispatchAPIService.swift` is missing **vehicle update + vehicle status-change** and
     the billing/extra-km/evidence/complete-offline/resend-WhatsApp surface; uses a brittle dual
     REST + raw-Convex-mutation transport across two hosts.

5. **Trip / arrival-OTP + booking-draft + collection-payment flows** (L)
   - Arrival OTP: masked contact, expiry/resend cooldown/max-resends, arrival photo sent inline
     on verify (`ui/home/ArrivalOtpBottomSheet.kt`).
   - Booking draft auto-save/resume/clear keyed on `sourceKey` (`bookings/draft/*`).
   - Collection-CP gate requires a completed booking; payment-mode union + proof upload + accounts
     approve/reject.

6. **Cache-first loading** (M) — mirror Android `ui/common/LocalCache.kt` (per-key JSON snapshots,
   paint-then-refresh) on dashboard/home/chat. iOS is network-only today.

7. **Chat forwarding + offline send queue** (M) — iOS `AuthStore.savePrivateFile` /
   `sharePrivateFileToConversation` throw `notImplemented`; no forward endpoint; offline retry lives
   in the View, not a service. Compare to Android chat forward + Room pending queue.

## Cross-cutting hardening (do alongside, not as a phase)

- Replace the ~15 duplicated `get/post/checkHTTPError/decode` helpers with **one shared client**
  (model on `GeoTrackAPIService`'s injectable `URLSessionProtocol`); centralize Bearer header +
  401→`SessionInvalidationBus` logout. Removes config drift across the 3 hosts.
- Kill the `GeoTrackPersistence.swift:92` `fatalError` (graceful store-recreate).
- Triage the `AuthStore` `notImplemented` cluster (Posts feed / private files / location history):
  confirm each is truly out-of-scope vs a silent parity gap before shipping UI that calls it.
- Relocate mislocated logic (Loans in Marketing service; Driver-trips in PostSales service).

## Suggested phasing (each phase = a Mac-buildable slice)

- **Phase 1 (start):** deep flow-diff + port of ONE high-value module's logic to establish the
  pattern. Recommended: **Marketing CP/SV outcome + trip/arrival flow** (pure logic, high value,
  DARX's crown-jewel area, no device-background dependency to verify).
- **Phase 2:** Punch/attendance flow logic (offline enqueue, tap-time, dual-gate, biometric independence).
- **Phase 3:** GeoTrack lifecycle correctness (needs real-device QA on macOS).
- **Phase 4:** Fleet/TravelDesk admin completion.
- **Phase 5:** Cache-first loading + Chat forwarding/offline queue.
- **Ongoing:** shared-client refactor + crash/debt hardening.

## Verify (macOS)

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FoundationChat.xcodeproj -scheme FoundationChat \
  -destination 'generic/platform=iOS Simulator' build
```
