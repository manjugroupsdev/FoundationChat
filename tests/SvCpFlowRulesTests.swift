import Foundation

/// SV / CP flow rules: Home hiding, SV approval gate, follow-up caps and the
/// arrived-vs-in_progress CP status.
@main
struct SvCpFlowRulesTests {
    static func main() {
        // Home never offers Start Trip for a closed or postponed CP.
        for status in ["postponed", "Postponed", "completed", "cancelled", "canceled", " done "] {
            precondition(SvCpFlowRules.homeHidesCpStatus(status), status)
        }
        for status in ["scheduled", "in_progress", "arrived", "pending_gm_approval", nil] {
            precondition(!SvCpFlowRules.homeHidesCpStatus(status))
        }

        // Approve: assigned GM, or admin / marketing.siteVisits.confirm.
        precondition(SvCpFlowRules.canApproveSvHandoff(assignedTo: "gm1", me: "gm1", canApproveAny: false))
        precondition(!SvCpFlowRules.canApproveSvHandoff(assignedTo: "gm1", me: "avp1", canApproveAny: false))
        precondition(SvCpFlowRules.canApproveSvHandoff(assignedTo: "gm1", me: "avp1", canApproveAny: true))
        precondition(!SvCpFlowRules.canApproveSvHandoff(assignedTo: nil, me: "gm1", canApproveAny: false))
        precondition(!SvCpFlowRules.canApproveSvHandoff(assignedTo: " ", me: "", canApproveAny: false))
        precondition(SvCpFlowRules.svApprovalTaskListLimit == 500)

        // Follow-up caps follow the effective purpose (Joint CP -> category).
        precondition(SvCpFlowRules.cpFollowUpCapDays(cpType: "collection_cp", jointCpCategory: nil) == 5)
        precondition(SvCpFlowRules.cpFollowUpCapDays(cpType: "booking_cp", jointCpCategory: nil) == 7)
        precondition(SvCpFlowRules.cpFollowUpCapDays(cpType: "joint_cp", jointCpCategory: "collection_cp") == 5)
        precondition(SvCpFlowRules.cpFollowUpCapDays(cpType: "joint_cp", jointCpCategory: "booking_cp") == 7)
        precondition(SvCpFlowRules.cpFollowUpCapDays(cpType: "joint_cp", jointCpCategory: nil) == nil)
        precondition(SvCpFlowRules.cpFollowUpCapDays(cpType: "new_client_cp", jointCpCategory: "booking_cp") == nil)
        precondition(SvCpFlowRules.cpFollowUpCapDays(cpType: nil, jointCpCategory: nil) == nil)

        // Server in_progress + arrived field visit keeps "arrived"; others unchanged.
        precondition(SvCpFlowRules.cpServerStatusKeepingArrival(server: "in_progress", fieldVisitStatus: "arrived") == "arrived")
        precondition(SvCpFlowRules.cpServerStatusKeepingArrival(server: "in_progress", fieldVisitStatus: "in-progress") == "in_progress")
        precondition(SvCpFlowRules.cpServerStatusKeepingArrival(server: "in_progress", fieldVisitStatus: nil) == "in_progress")
        precondition(SvCpFlowRules.cpServerStatusKeepingArrival(server: "completed", fieldVisitStatus: "arrived") == "completed")
        precondition(SvCpFlowRules.cpServerStatusKeepingArrival(server: "postponed", fieldVisitStatus: "arrived") == "postponed")
        precondition(SvCpFlowRules.cpServerStatusKeepingArrival(server: "scheduled", fieldVisitStatus: "arrived") == "scheduled")

        print("SvCpFlowRulesTests passed")
    }
}
