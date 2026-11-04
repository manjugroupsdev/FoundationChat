import Foundation

@main
struct AttendanceSessionRulesTests {
    static func main() {
        typealias R = AttendanceSessionRules
        // The midnight job's close (16 Oct report): 23:59:59 IST = 18:29:59Z.
        precondition(R.isSyntheticClose(punchOutTime: "2026-10-16T18:29:59.000Z", autoClosed: nil, date: "2026-10-16"))
        precondition(R.realPunchOut(punchOutTime: "2026-10-16T18:29:59.000Z", autoClosed: nil, date: "2026-10-16") == nil)
        // Flagged rows, whatever the time.
        precondition(R.isSyntheticClose(punchOutTime: "2026-10-16T18:29:00.000Z", autoClosed: true, date: nil))
        // Real punch-outs are kept.
        precondition(!R.isSyntheticClose(punchOutTime: "2026-10-16T05:12:00.000Z", autoClosed: nil, date: "2026-10-16"))
        precondition(R.realPunchOut(punchOutTime: "2026-10-16T05:12:00.000Z", autoClosed: false, date: "2026-10-16") == "2026-10-16T05:12:00.000Z")
        // Another day's 23:59:59 is not this day's close; open sessions have nothing to hide.
        precondition(!R.isSyntheticClose(punchOutTime: "2026-10-17T18:29:59.000Z", autoClosed: nil, date: "2026-10-16"))
        precondition(!R.isSyntheticClose(punchOutTime: nil, autoClosed: nil, date: "2026-10-16"))
        precondition(!R.isSyntheticClose(punchOutTime: "", autoClosed: true, date: "2026-10-16"))
        print("AttendanceSessionRules: 8 assertions passed")
    }
}
