import Foundation

@main
struct AttendanceFailureTests {
    static func main() {
        // What the punch-in route returns (HTTP 500) when a session is already open.
        let wrapped = "Uncaught Error: Already punched in. Punch out first.\n    at handler (../convex/staffAttendance.ts:6612:12)"
        precondition(AttendanceAlreadyRecorded.from(wrapped) == .clockedIn)
        precondition(AttendanceFailureText.userFacing(wrapped) == AttendanceAlreadyRecorded.clockedIn.message)

        let noSession = "Uncaught Error: No active punch-in found for today"
        precondition(AttendanceAlreadyRecorded.from(noSession) == .clockedOut)
        precondition(AttendanceFailureText.userFacing(noSession) == AttendanceAlreadyRecorded.clockedOut.message)

        // Clean server wording passes through unchanged and is still recognised.
        precondition(AttendanceFailureText.userFacing("You have already clocked in today.") == "You have already clocked in today.")
        precondition(AttendanceAlreadyRecorded.from("You have already clocked in today.") == .clockedIn)
        precondition(AttendanceAlreadyRecorded.from("No active punch-in found for today") == .clockedOut)
        precondition(AttendanceAlreadyRecorded.from(AttendanceAlreadyRecorded.clockedIn.message) == .clockedIn)
        precondition(AttendanceAlreadyRecorded.from(AttendanceAlreadyRecorded.clockedOut.message) == .clockedOut)

        // Real failures are not mistaken for an already-recorded punch.
        for text in ["Outside the allowed attendance location.", "Failed to encode selfie",
                     AttendanceFailureText.unconfirmed, "", "Request failed (500)"] {
            precondition(AttendanceAlreadyRecorded.from(text) == nil, text)
        }
        precondition(AttendanceAlreadyRecorded.from(nil as String?) == nil)

        // Backend diagnostics never reach the staff; business messages do.
        for diagnostic in ["Uncaught ReferenceError: checkStaffEscalationPenalty is not defined",
                           "TypeError: Cannot read properties of undefined",
                           "Unexpected failure\n    at attendance.ts:42:9",
                           "<!doctype html><html>500</html>", "", "   "] {
            precondition(AttendanceFailureText.userFacing(diagnostic) == AttendanceFailureText.unconfirmed, diagnostic)
        }
        precondition(AttendanceFailureText.userFacing(nil) == AttendanceFailureText.unconfirmed)
        precondition(AttendanceFailureText.userFacing("Outside the allowed attendance location.") == "Outside the allowed attendance location.")
        print("AttendanceFailure: 21 assertions passed")
    }
}
