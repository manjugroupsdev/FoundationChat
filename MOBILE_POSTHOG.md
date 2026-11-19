# Mobile PostHog Diagnostics

MMS-254 replaces the existing automatic IssueReporter send path with direct
US PostHog batch ingestion, project 750346 / MMS Mobile. No web or Convex edits.
No full analytics SDK, autocapture, replay, flag/config polling or endpoint probes.

`mobile_endpoint` contains service, allowlisted/normalized route, method, status,
latency and outcome. Healthy requests are sampled one in twenty. `$exception`
contains generic failed-flow categories or crash type/signal. Existing MetricKit
reports remain delayed summaries, not a symbolicated crash SDK. No raw crash
reason, memory dump, response body, auth headers, URLs/query values, notice text,
staff identity/contact details, photos or location are sent. Random installation
UUID only; person profiles and GeoIP are disabled. Old unsent raw diagnostics are
discarded, never migrated. Attendance queues and user sessions remain intact.

Persisted UTC-day cap: 20 timings plus 40 errors, with at most 8 exceptions within
the latter. Ten-minute signature deduplication; 60 events on disk, 20 per batch,
three-day expiry, 64 bounded observation closures. Observe existing requests
only. Never synchronously flush in a request/UI/crash callback. Minimum one minute
between batches. Isolated ephemeral session, no cookies/credentials/cache,
single connection, redirects disabled and 15-second resource timeout. Failure
backoff 10 minutes to 6 hours (bounded numeric Retry-After); later real observations
or foreground/network resume trigger retry, not a recurring background poll.

These are sampled diagnostic signals, not a complete traffic/SLA counter. OS
suspension may defer batches. At 332 installations, maxima fit the current Free
allowances (617,520 total events and 82,336 exceptions over 31 days); review quotas
when installation counts grow. The capture token in MobilePostHogConfig.swift is
a public write-only token, never a personal/admin API key. `enabled` is a local
compile-time kill switch, not another configuration endpoint.

Existing build headers/web verification behavior is untouched. Updated apps stop
sending automatic diagnostics to Settings/Mobile/Issues; older builds still do.
Use PostHog Activity/Error Tracking and endpoint/platform/build analytics, excluding
`verification = true` synthetic validation data. No person-specific monitoring.

Validation on Windows/WSL is not a Mac archive, actual iPhone battery comparison,
or TestFlight check. Manoj must perform those before release and review app privacy
disclosures. No store version, push, merge, production or rollout is implicit.

API references: https://posthog.com/docs/api/capture and
https://posthog.com/docs/error-tracking/installation/manual
