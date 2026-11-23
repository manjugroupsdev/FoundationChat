#!/bin/bash
# Pure Swift regressions only. No app launch, real network or production data.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swiftc >/dev/null && [ -f "$HOME/.local/share/swiftly/env.sh" ]; then
    . "$HOME/.local/share/swiftly/env.sh"
fi
OUT=$(mktemp -d)
trap 'rm -f "$OUT"/*; rmdir "$OUT"' EXIT
run() {
    local test="$1"
    shift
    swiftc -parse-as-library "$@" "tests/$test.swift" -o "$OUT/$test"
    if command -v timeout >/dev/null; then
        timeout 60 "$OUT/$test"
    else
        "$OUT/$test"
    fi
}
run HRAttendanceReadSharingTests FoundationChat/Services/HRAttendanceReadSharing.swift
run ScreenReadRefreshTests FoundationChat/Services/ScreenReadRefreshPolicy.swift
run ChatPollingBackoffTests FoundationChat/Services/ChatPollingBackoff.swift
run SessionInvalidationBoundaryTests FoundationChat/Auth/SessionInvalidationBus.swift
run MobileTelemetryBoundaryTests FoundationChat/Auth/SessionInvalidationBus.swift
run MMSRequestTransportTests FoundationChat/Services/MMSRequestTransport.swift tests/NetworkTestSupport.swift
run MobileTelemetryPolicyTests FoundationChat/Services/MobileTelemetryPolicy.swift FoundationChat/Services/MobilePostHogConfig.swift
run MobileTelemetryTransportTests FoundationChat/Services/MobileTelemetryTransport.swift FoundationChat/Services/MobileTelemetryPolicy.swift FoundationChat/Services/MobilePostHogConfig.swift
run AttendanceFailureTests FoundationChat/Services/AttendanceFailure.swift
run AttendanceSessionRulesTests FoundationChat/Services/AttendanceSessionRules.swift
# HRApplicationSupport/shift tests depend on app-only HR/Floater types; those
# sources are checked in the full SDK build, not replaced with test stubs here.
run LoanDocumentUploadPolicyTests FoundationChat/Services/LoanDocumentUploadPolicy.swift
run SiteVisitStaffRulesTests FoundationChat/Services/SiteVisitStaffRules.swift
run CachedDateFormattersTests FoundationChat/Utilities/CachedDateFormatters.swift
run AdaptiveColorRulesTests FoundationChat/Utilities/AdaptiveColorRules.swift
run OtpCodeInputTests FoundationChat/Views/Auth/OtpCodeInput.swift
run CpSavedDecisionTests FoundationChat/Utilities/CpOutcomePolicy.swift
run SiteVisitDraftPolicyTests FoundationChat/Services/SiteVisitDraftPolicy.swift FoundationChat/Services/SiteVisitStaffRules.swift
run RequiredReasonTests FoundationChat/Services/RequiredReason.swift
run SvCpFlowRulesTests FoundationChat/Utilities/SvCpFlowRules.swift
echo "All 19 standalone mobile helper harnesses passed. Not a native archive or iPhone UI test."
