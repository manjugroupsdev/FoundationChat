# Android -> iOS Parity Audit

Android source: `/Users/safeermohamed/Desktop/MMS-Web/Mconnect`

Android reference commit: `375286c` (`Home: keep Today's Trip below the profile/notify header while scrolling`)

iOS source: `/Users/safeermohamed/Desktop/MMS-Web/FoundationChat`

Last checked: 2026-07-17

## Status Legend

- DONE: iOS has a native equivalent wired to the same backend behavior.
- PARTIAL: iOS has the core screen/flow, but some Android behavior is still missing.
- MISSING: Android feature exists and iOS does not yet have an equivalent.
- NATIVE-DIFFERENT: Platform behavior should stay different unless QA finds a real product gap.

## Latest Android Updates Reviewed

### `87e8d81..375286c`

- Android Home XML/scroll polish: Today's Trip/dashboard header stays below the profile/notification header while scrolling.
- Android Apply Leave: Compensatory Off flow uses `/api/hr/compoff/credits` and `/api/hr/compoff/apply`.
- Android Home task nudge: scoped task-manager tasks, pending banner, bottom sheet, and redirect into Tasks.

### Earlier Home dashboard commits in the current Android history

- Management dashboard is gated by `SessionManager.canViewVpDashboard()`, not broad `isAdmin`.
- Allowed users: role `super-admin`, IAM `vpDashboard.view`, or VP/GM/MD designation families including VP, AVP, GM, AGM, DGM.
- Management users see company KPI overview instead of Today's Trip.
- Dashboard uses `/api/mobile/dashboard` with HR and Marketing tabs plus date filtering.

## Implemented In iOS In This Pass

### Home management dashboard

Status: DONE

iOS files:

- `FoundationChat/Auth/StackSession.swift`
- `FoundationChat/Models/Convex/ConvexDashboardModels.swift`
- `FoundationChat/Services/DashboardConvexAPIService.swift`
- `FoundationChat/Views/Home/HomeView.swift`

Details:

- Added Android-equivalent gate `AuthUser.canViewManagementDashboard`.
- Gate matches Android: `super-admin`, `vpDashboard.view`, or VP/GM/MD designation family.
- Home now branches like Android:
  - Management users: personal attendance overview + pending tasks + company dashboard.
  - Normal users/drivers: personal attendance overview + pending tasks + Today's Trip.
- Added `/api/mobile/dashboard` client.
- Added resilient dashboard decoder for Android fields:
  - HR: `totalStaff`, `present`, `absent`, `leave`, optional `leaveApproved`, `weekOff`, `permissionCount`, `wfhApproved`, `notPunchedIn`.
  - Marketing: `totalCalls`, `incomingCalls`, `outboundCalls`, `hot`, `warm`, `cold`, `cpVisitsFixed`, `svVisitsFixed`, optional completed visit/bookings/registrations/collections fields.
- Added native SwiftUI HR/Marketing segmented control.
- Added native graphical date picker sheet.
- Date query uses India-local `yyyy-MM-dd`, matching Android's dashboard date handling.
- Pull to refresh reloads dashboard for management users.
- Dashboard cards navigate to nearest native iOS detail screens:
  - Attendance cards -> Attendance list.
  - Leave -> Leaves.
  - Permission -> Permissions.
  - Calls -> Dialer.
  - Hot/Warm/Cold -> My Leads.
  - CP -> CP Visits.
  - SV -> Site Visits.
  - Bookings/Registrations -> Bookings.
  - Collections -> Collections.

### Home task nudge

Status: DONE

iOS files:

- `FoundationChat/Views/Home/HomeView.swift`
- `FoundationChat/Models/Convex/ConvexTaskModels.swift`

Details:

- Loads `/api/dailyTasks/listForTaskManager`.
- Shows pending count.
- Shows due-today count.
- Shows native task preview bottom sheet.
- CTA opens native `TasksListView`.
- Decodes Android creator/role/designation fields for task cards.

### Compensatory Off leave flow

Status: DONE

iOS files:

- `FoundationChat/Models/Convex/ConvexHRModels.swift`
- `FoundationChat/Services/HRConvexAPIService.swift`
- `FoundationChat/Views/HR/Leaves/ApplyLeaveView.swift`

Details:

- Loads credits from `/api/hr/compoff/credits`.
- Submits through `/api/hr/compoff/apply`.
- Comp Off hides reason input like Android.
- Requires credit selection before submit.
- Locks Comp Off date selection to the credit month.
- Disables the earned day.
- Uses single-day native date selection for Comp Off.

## Module-by-Module Parity

### Auth and session

Status: DONE

Android:

- OTP login.
- Employee ID/password login.
- Force password change.
- Session validation/logout.
- IAM permission refresh.

iOS:

- Native login/root/session store exists.
- Force password change exists.
- Session invalidation bus exists.
- IAM refresh exists in `AuthStore`.
- Management dashboard gate now matches Android.

Remaining:

- Validate every Android auth edge case with real accounts, especially password-change and expired-session messaging.

### Home

Status: DONE for latest Android behavior, PARTIAL for cache polish

Android:

- Animated header.
- Notification badge/profile.
- QR scanner handle.
- Today's Trip for normal users.
- Driver trip filtering.
- Pending task nudge.
- Management HR/Marketing dashboard for VP/GM/super-admin.
- Dashboard date picker.
- XML sticky header/scroll safety.

iOS:

- Native animated header exists.
- Notification badge/profile exists.
- QR scanner handle exists.
- Today's Trip exists.
- Driver filtering exists.
- Pending tasks exists.
- Management dashboard exists after this pass.
- Date picker exists after this pass.

Remaining:

- Android cache-first `LocalCache` for dashboard numbers is not mirrored yet. iOS currently network-loads the dashboard.
- Android XML sticky header fix is NATIVE-DIFFERENT. SwiftUI Home uses native scrolling; only port if visual QA shows overlap.

### Notifications and push routing

Status: PARTIAL

Android:

- Firebase Messaging.
- Push token manager.
- Workflow notification routes.
- Chat/task notification helpers.

iOS:

- APNS delegate exists.
- Push route parser exists.
- Notifications list exists.
- HR permission/approval push route integration exists.

Remaining:

- Validate APNS category/thread grouping against Android grouped notification behavior.
- Confirm every Android workflow route has an iOS route mapping.

### Chat

Status: PARTIAL to DONE depending on subflow

Android:

- Chat list/messages.
- Media capture/preview/edit.
- Forward picker.
- Message actions/info.
- Group info/contact info.
- Search.
- Location share/map viewer.
- Offline pending queue/cache.
- Mentions/reply gestures.

iOS:

- Conversations, channels, detail, input, message views exist.
- Channel/member info exists.
- Media and search views exist.
- Location views exist.
- Push navigation exists.

Remaining:

- Compare Android forwarding, message info, custom camera/media edit, mentions, and pending queue behavior against iOS one-by-one.
- Validate offline send retry parity.

### HR attendance and geotrack

Status: PARTIAL to DONE

Android:

- HR dashboard.
- Clock-in/out.
- Attendance history/review.
- Selfie camera/detail.
- Punch logs.
- Home geofence warning.
- On-duty forms/proof.
- GeoTrack consent/live/today/assigned/stats.
- Background tracking services/workers/tamper/heartbeat.

iOS:

- HR dashboard exists.
- Attendance list/review exists.
- Punch flow/camera/logs exist.
- GeoTrack consent/live/today/assigned/stats/detail exists.
- Location manager, bootstrap, heartbeat, tamper monitor, persistence exist.

Remaining:

- Android background tracking uses foreground service/workers/boot receiver; iOS equivalent must be validated under iOS background location limits.
- Compare home geofence blocking dialogs and on-duty proof edge cases.

### HR leaves, permissions, staff, fines, loans

Status: DONE for latest leave update; PARTIAL overall

Android:

- Leaves list/apply/approve/reject/cancel.
- Comp Off credits/apply.
- Permissions apply/approve/reject/cancel.
- Staff list/detail.
- Fines create/list/my fines.
- Loans.

iOS:

- Leaves, approvals, Comp Off, permissions, permission approvals, staff, fines, loans exist.

Remaining:

- Validate half-day leave recording against Android's latest fix.
- Compare fine creation fields and month/year filtering.
- Compare loan approval/cancellation states against Android.

### Marketing, trips, and visits

Status: PARTIAL to DONE

Android:

- CP visits.
- Site visits.
- Visit overview.
- Trip navigation.
- Arrival OTP.
- CP/client seen sheets.
- Booking draft/complete visit.
- Collection payment entry.
- Driver start/end trip sheets.

iOS:

- CP Visits, Site Visits, Trip Navigation, Arrival OTP, Complete CP Visit, Site Visit Outcome, Bookings, Collections exist.

Remaining:

- Android has several specialized bottom sheets; iOS has native equivalents for the major ones but needs a screen-by-screen QA pass:
  - CP client seen/no-show.
  - Old client remarks.
  - Booking draft manager.
  - Driver start/end/completed trip sheets.
  - Collection payment entry inside trip completion.

### Telecaller

Status: DONE for core flows

Android:

- Dialer.
- My Leads.

iOS:

- Dialer exists.
- My Leads exists.

Remaining:

- Validate PBX call bridge responses and station persistence against Android defaults.

### App Library and fleet

Status: PARTIAL

Android:

- App Library gates.
- Admin Fleet portal.
- My Trips.
- Vehicles/drivers/create/update/status.
- Allocate vehicle.
- Manage rates/settings.

iOS:

- App Library exists.
- Fleet views exist.

Remaining:

- Compare Admin Fleet management depth:
  - Vehicle create/update/status.
  - Driver create/update/status.
  - Allocate vehicle.
  - Rate/settings management.
- Android TravelDesk API has `/api/travel-desk/*`; confirm every iOS Fleet view uses equivalent endpoints.

### Front Desk

Status: PARTIAL to DONE

Android:

- QR scan.
- Invitation by token.
- Check-in/check-out.
- QR history.

iOS:

- FrontDesk QR scanner exists.
- Check-in/check-out service paths exist through app module services.

Remaining:

- Confirm QR history view parity.
- Validate repeat scan checkout behavior.

### Post Sales, collections, loans

Status: PARTIAL

Android:

- Collections.
- Account verification.
- Loan/customer flows.
- Post-sales cases.

iOS:

- Collections view exists.
- Accounts review exists.
- Loan desk exists.
- Post-sales lookup exists.

Remaining:

- Compare account verification filters/actions.
- Compare proof upload/preview behavior.
- Validate dashboard collection totals route once backend sends aggregate fields.

### Land

Status: PARTIAL

Android:

- Land module exists under API/app library.

iOS:

- Land views and models exist.

Remaining:

- Needs dedicated Android-vs-iOS pass for land query/inspection/status fields.

### Projects, issues, expenses, tasks

Status: PARTIAL

Android:

- Issues.
- Project expenses.
- Daily Log.
- DPR reports/recipients/send.
- Project picker/date filters.
- Task Manager.
- Task detail/timeline/update.
- Web task link.

iOS:

- Issues exists.
- Project expenses exists.
- Tasks list/detail/update exists.

Remaining:

- Daily Log and DPR are the biggest missing project-side Android features in iOS:
  - `/api/projects/daily-log/create`
  - `/api/projects/daily-log/list`
  - `/api/projects/daily-log/mine`
  - `/api/projects/dpr/mine`
  - `/api/projects/dpr/recipients`
  - `/api/projects/dpr/reports`
  - `/api/projects/dpr/send`
- Web task link bottom sheet parity needs checking.
- Task timeline parity needs checking.

### Shared UI/platform helpers

Status: NATIVE-DIFFERENT / PARTIAL

Android:

- Common bottom sheets.
- Pull-to-refresh wrapper.
- Searchable selection dialog.
- Staff picker.
- Month/year picker.
- Image preview dialog.
- Map pin drop bottom sheet.
- Local cache.
- Skeleton helpers.

iOS:

- Native sheets, searchable selectors, camera picker, loading cards, and SwiftUI navigation exist.

Remaining:

- Missing or not fully validated:
  - Map pin drop / manual location picker.
  - Cache-first dashboard loading.
  - Shared image preview behavior where Android has full-screen dialogs.
  - Infinite scroll helper parity in long lists.

## Priority Next Work

1. Project Daily Log + DPR parity. This is a real module gap.
2. Admin Fleet parity audit and endpoint matching.
3. Chat forwarding/message-info/offline queue parity.
4. Background GeoTrack real-device QA under iOS background location constraints.
5. Dashboard cache-first loading if management users need instant stale-while-refresh numbers.

## Verification

- iOS build command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FoundationChat.xcodeproj -scheme FoundationChat -destination 'generic/platform=iOS Simulator' build
```

- Result: build succeeded.
- Note: build still shows a pre-existing warning in `FoundationChat/Services/LocationManager.swift` about `@preconcurrency` on `CLLocationManagerDelegate`.
