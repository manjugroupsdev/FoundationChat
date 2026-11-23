import Foundation

/// Pure SV / CP flow rules shared by Home, the CP list, the CP outcome sheet and
/// SV Approvals. Standalone (Foundation only) so tests/SvCpFlowRulesTests.swift
/// can check them without the app.
enum SvCpFlowRules {
    /// CP statuses Home's Today list never offers as a trip. A postponed CP is
    /// closed until its follow-up, so it must not show Start Trip.
    static func homeHidesCpStatus(_ status: String?) -> Bool {
        homeHiddenCpStatuses.contains(normalized(status))
    }

    private static let homeHiddenCpStatuses: Set<String> = [
        "completed", "complete", "done", "closed", "cancelled", "canceled", "postponed"
    ]

    /// `/api/dailyTasks/listForTaskManager` defaults to 200 rows and caps at 500.
    /// SV Approvals filters that list on the phone, so it reads the cap.
    static let svApprovalTaskListLimit = 500

    /// Server rule for approving an out-of-station handoff
    /// (dailyTasks.updateStatus): the handoff's assigned GM, an admin, or a
    /// holder of `marketing.siteVisits.confirm`. Reject has a wider rule.
    static func canApproveSvHandoff(assignedTo: String?, me: String, canApproveAny: Bool) -> Bool {
        if canApproveAny { return true }
        guard let assignedTo = assignedTo?.trimmingCharacters(in: .whitespacesAndNewlines),
              !assignedTo.isEmpty, !me.isEmpty else { return false }
        return assignedTo == me
    }

    /// The CP's purpose: a Joint CP takes its category (server effectiveCpPurpose).
    static func effectiveCpPurpose(cpType: String?, jointCpCategory: String?) -> String {
        let type = normalized(cpType)
        return type == "joint_cp" ? normalized(jointCpCategory) : type
    }

    /// Follow-up / postpone date cap in days, matching the setOutcome check:
    /// collection 5, booking 7, otherwise none.
    static func cpFollowUpCapDays(cpType: String?, jointCpCategory: String?) -> Int? {
        switch effectiveCpPurpose(cpType: cpType, jointCpCategory: jointCpCategory) {
        case "collection_cp": return 5
        case "booking_cp": return 7
        default: return nil
        }
    }

    /// The server's CP `effectiveStatus` folds a field visit's `arrived` into
    /// `in_progress`, so an arrived CP read "Enroute" and never "Complete CP
    /// details". Keep the field visit's arrival when the server only says
    /// in_progress; every other server status wins as before.
    static func cpServerStatusKeepingArrival(server: String, fieldVisitStatus: String?) -> String {
        guard normalized(server) == "in_progress" else { return server }
        let fieldVisit = fieldVisitStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return arrivalStatuses.contains(normalized(fieldVisit)) ? fieldVisit : server
    }

    private static let arrivalStatuses: Set<String> = ["arrived", "arrival_verified"]

    private static func normalized(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }
}
