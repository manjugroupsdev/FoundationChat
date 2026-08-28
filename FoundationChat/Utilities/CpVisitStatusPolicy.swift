import Foundation

/// Resolves the display/action status shared by Home and the CP Visits list.
///
/// A CP and its spawned field visit are separate records. While travel is live,
/// the field visit owns states such as `arrived`. Once the CP itself reaches a
/// terminal state, however, that CP state must win even if a flaky follow-up
/// request left the field visit open.
enum CpVisitStatusPolicy {
    private static let terminalStatuses: Set<String> = [
        "completed",
        "complete",
        "done",
        "closed",
        "cancelled",
        "canceled",
        "postponed",
        "pending_gm_approval"
    ]

    static func resolve(cpStatus: String?, fieldVisitStatus: String?) -> String {
        let cp = cpStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if terminalStatuses.contains(cp.lowercased()) {
            return cp
        }

        let fieldVisit = fieldVisitStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fieldVisit.isEmpty {
            return fieldVisit
        }

        return cp.isEmpty ? "scheduled" : cp
    }
}
