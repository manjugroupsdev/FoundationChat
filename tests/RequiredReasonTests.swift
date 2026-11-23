import Foundation

/// SV approval Reject needs a reason, like the web handoff dialog.
@main
struct RequiredReasonTests {
    static func main() {
        precondition(RequiredReason.normalized(nil) == nil)
        precondition(RequiredReason.normalized("") == nil)
        precondition(RequiredReason.normalized("  \n\t ") == nil)
        precondition(RequiredReason.normalized("  Client not ready \n") == "Client not ready")

        let reject = RequiredReason.dailyTaskStatusBody(id: "task-1", status: "cancelled", reason: " Client not ready ")
        precondition(reject["id"] as? String == "task-1")
        precondition(reject["status"] as? String == "cancelled")
        precondition(reject["reason"] as? String == "Client not ready")

        let approve = RequiredReason.dailyTaskStatusBody(id: "task-1", status: "completed", reason: "ignored")
        precondition(approve["status"] as? String == "completed")
        precondition(approve["reason"] == nil)

        let blank = RequiredReason.dailyTaskStatusBody(id: "task-1", status: "cancelled", reason: "   ")
        precondition(blank["reason"] == nil)

        print("RequiredReasonTests passed")
    }
}
