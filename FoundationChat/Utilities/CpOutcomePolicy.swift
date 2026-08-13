import Foundation

/// CP categories allowed to close through the free-text `other` outcome.
/// Ported from Android `ui/marketing/CpOutcomePolicy.kt`.
private let cpTypesWithOtherOutcome: Set<String> = [
    "booking_cp",
    "gift_distribution",
    "follow_up",
]

func cpTypeSupportsOtherOutcome(_ cpType: String?) -> Bool {
    guard let t = cpType?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
    return cpTypesWithOtherOutcome.contains(t)
}
