import Foundation

@main
struct SvApprovalLoadRulesTests {
    static func main() {
        typealias R = SvApprovalLoadRules
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        // Reuse a read from moments ago; never an old, future or missing one.
        check(R.isFresh(fetchedAt: now.addingTimeInterval(-2), now: now), "2 s old is shared")
        check(R.isFresh(fetchedAt: now.addingTimeInterval(-R.shareSeconds), now: now), "edge is shared")
        check(!R.isFresh(fetchedAt: now.addingTimeInterval(-R.shareSeconds - 1), now: now), "too old")
        check(!R.isFresh(fetchedAt: now.addingTimeInterval(5), now: now), "clock went back")
        check(!R.isFresh(fetchedAt: nil, now: now), "never read")

        // Busy retries: quick first, then back off, then stop.
        check(R.retryDelaySeconds(attempt: 0) == 1.5, "first retry 1.5 s")
        check(R.retryDelaySeconds(attempt: 1) == 4, "second retry 4 s")
        check(R.retryDelaySeconds(attempt: 3) == 20, "last retry 20 s")
        check(R.retryDelaySeconds(attempt: R.maxAutoRetries) == nil, "stop after max")
        check(R.retryDelaySeconds(attempt: -1) == nil, "no negative attempt")

        // Only busy codes are retried quietly.
        for code in [429, 502, 503, 504] { check(R.isServerBusy(httpStatus: code), "\(code) busy") }
        for code in [400, 401, 403, 404, 500] { check(!R.isServerBusy(httpStatus: code), "\(code) not busy") }
        check(!R.isServerBusy(httpStatus: nil), "nil not busy")

        print("SvApprovalLoadRules: \(count) assertions passed")
    }
}
