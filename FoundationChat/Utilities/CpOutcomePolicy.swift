import Foundation

/// CP categories allowed to close through the free-text `other` outcome.
/// Ported from Android `ui/marketing/CpOutcomePolicy.kt`.
private let cpTypesWithOtherOutcome: Set<String> = [
    "booking_cp",
    "gift_distribution",
    "old_client",
    "other_cp",
]

func cpTypeSupportsOtherOutcome(_ cpType: String?) -> Bool {
    guard let t = cpType?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
    return cpTypesWithOtherOutcome.contains(t)
}

func confirmedCpOutcome(
    status: String?, outcome: String?,
    convertedSiteVisitId: String? = nil, convertedBookingId: String? = nil
) -> String? {
    guard isCpDecisionCommitted(status) else { return nil }
    let value = outcome?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let value, !value.isEmpty { return value }
    // The server prelinks pending SV confirmations. Linkage is only a legacy
    // outcome fallback after the parent CP has actually completed.
    guard completedCpStatuses.contains(normalizedCpDecisionStatus(status)) else { return nil }
    if let id = convertedSiteVisitId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
        return "converted_to_site_visit"
    }
    if let id = convertedBookingId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
        return "converted_to_booking"
    }
    return nil
}

private let completedCpStatuses: Set<String> = ["completed", "complete", "done", "closed"]

private func normalizedCpDecisionStatus(_ status: String?) -> String {
    (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        .replacingOccurrences(of: "-", with: "_")
}

func isCpDecisionCommitted(_ status: String?) -> Bool {
    completedCpStatuses.union(["postponed", "pending_gm_approval", "cancelled", "canceled", "rejected"])
        .contains(normalizedCpDecisionStatus(status))
}

func cpOutcomeCaptureStatus(parentStatus: String?, effectiveStatus: String) -> String {
    if !isCpDecisionCommitted(parentStatus), completedCpStatuses.contains(normalizedCpDecisionStatus(effectiveStatus)) {
        return "arrived"
    }
    return effectiveStatus
}

func preferredCpCompletionStatus(_ candidates: [String?]) -> String? {
    let values = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return values.first { normalizedCpDecisionStatus($0) == "pending_gm_approval" } ?? values.first
}
