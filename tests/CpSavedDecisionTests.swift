import Foundation

@main
struct CpSavedDecisionTests {
    static func main() {
        precondition(cpOutcomeCaptureStatus(parentStatus: "in_progress", effectiveStatus: "completed") == "arrived")
        precondition(cpOutcomeCaptureStatus(parentStatus: "scheduled", effectiveStatus: "done") == "arrived")
        precondition(cpOutcomeCaptureStatus(parentStatus: "in_progress", effectiveStatus: "pending_review") == "pending_review")
        precondition(cpOutcomeCaptureStatus(parentStatus: "completed", effectiveStatus: "completed") == "completed")
        precondition(cpOutcomeCaptureStatus(parentStatus: "pending_gm_approval", effectiveStatus: "pending_gm_approval") == "pending_gm_approval")
        precondition(!isCpDecisionCommitted("in_progress"))
        precondition(isCpDecisionCommitted(" PENDING-GM-APPROVAL "))
        precondition(isCpDecisionCommitted("cancelled"))
        for status in [nil, "scheduled", "in_progress", "arrived", "on_site"] as [String?] {
            precondition(confirmedCpOutcome(status: status, outcome: nil, convertedSiteVisitId: "sv-precreated") == nil)
            precondition(confirmedCpOutcome(status: status, outcome: "interested", convertedSiteVisitId: "sv-precreated") == nil)
        }
        precondition(confirmedCpOutcome(status: "pending_review", outcome: "interested") == nil)
        for status in ["completed", "postponed", "pending_gm_approval", " PENDING-GM-APPROVAL "] {
            precondition(confirmedCpOutcome(status: status, outcome: " interested ") == "interested")
        }
        precondition(confirmedCpOutcome(status: "completed", outcome: nil, convertedSiteVisitId: "sv1") == "converted_to_site_visit")
        precondition(confirmedCpOutcome(status: "done", outcome: " ", convertedBookingId: "booking1") == "converted_to_booking")
        precondition(confirmedCpOutcome(status: "pending_gm_approval", outcome: nil, convertedSiteVisitId: "sv1") == nil)
        precondition(confirmedCpOutcome(status: "completed", outcome: nil, convertedSiteVisitId: " ") == nil)
        for outcome in ["old_client_visited", "gift_distributed", "collection_done", "not_collected", "rejected"] {
            precondition(confirmedCpOutcome(status: "completed", outcome: outcome) == outcome)
            precondition(confirmedCpOutcome(status: "in_progress", outcome: outcome) == nil)
        }
        precondition(preferredCpCompletionStatus([nil, "completed", nil, "pending_gm_approval"]) == "pending_gm_approval")
        precondition(preferredCpCompletionStatus(["completed", " Pending-GM-Approval "]) == "Pending-GM-Approval")
        precondition(preferredCpCompletionStatus([nil, " "]) == nil)
        precondition(preferredCpCompletionStatus(["completed", nil]) == "completed")
        print("CP pending-link, saved-decision resume, special outcomes and GM hold policies passed")
    }
}
