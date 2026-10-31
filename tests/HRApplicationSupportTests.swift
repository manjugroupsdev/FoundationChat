import Foundation

@main
struct HRApplicationSupportTests {
    static func main() {
        let zone = TimeZone(secondsFromGMT: 19800)!
        let date = ISO8601DateFormatter().date(from: "2026-10-28T04:00:00Z")!
        precondition(HRApplicationSupport.apiDate(date, timeZone: zone) == "2026-10-28")
        precondition(HRApplicationSupport.apiTime(date, timeZone: zone) == "09:30")
        precondition(HRApplicationSupport.apiTime(date, timeZone: TimeZone(secondsFromGMT: 0)!) == "04:00")
        let cases = [
            (#"{"error":"Permission must start at 09:30"}"#, "Permission must start at 09:30"),
            (#"{"error":{"message":"Insufficient balance"}}"#, "Insufficient balance"),
            (#"{"message":"Enter a reason"}"#, "Enter a reason"),
        ]
        for (body, expected) in cases {
            precondition(HRApplicationSupport.responseMessage(Data(body.utf8)) == expected)
        }
        precondition(HRApplicationSupport.responseMessage(Data("<html>Gateway error</html>".utf8)) == nil)
        precondition(HRApplicationSupport.submissionMessage(URLError(.timedOut)).contains("history before submitting"))
        print("HRApplicationSupport: 8 assertions passed")
    }
}
