import Foundation

@main
struct CpListBusyRulesTests {
    static func main() {
        typealias R = CpListBusyRules
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }

        // Only "retry later" answers count as busy.
        for code in [429, 502, 503, 504] { check(R.isServerBusy(httpStatus: code), "\(code) is busy") }
        for code in [nil, 200, 400, 401, 403, 404, 500] as [Int?] {
            check(!R.isServerBusy(httpStatus: code), "\(String(describing: code)) is not busy")
        }

        // Back-off 10, 20, 40, 60, 60 then stop.
        check(R.retryDelaySeconds(attempt: 0, retryAfterSeconds: nil) == 10, "first retry 10 s")
        check(R.retryDelaySeconds(attempt: 1, retryAfterSeconds: nil) == 20, "second retry 20 s")
        check(R.retryDelaySeconds(attempt: 2, retryAfterSeconds: nil) == 40, "third retry 40 s")
        check(R.retryDelaySeconds(attempt: 3, retryAfterSeconds: nil) == 60, "capped at 60 s")
        check(R.retryDelaySeconds(attempt: 4, retryAfterSeconds: nil) == 60, "still 60 s")
        check(R.retryDelaySeconds(attempt: R.maxAutoRetries, retryAfterSeconds: nil) == nil, "budget spent")
        check(R.retryDelaySeconds(attempt: -1, retryAfterSeconds: nil) == nil, "negative attempt")

        // Retry-After honoured within bounds.
        check(R.retryDelaySeconds(attempt: 0, retryAfterSeconds: 30) == 30, "retry-after 30")
        check(R.retryDelaySeconds(attempt: 0, retryAfterSeconds: 1) == 5, "retry-after floor")
        check(R.retryDelaySeconds(attempt: 0, retryAfterSeconds: 3600) == 120, "retry-after ceiling")
        check(R.retryDelaySeconds(attempt: 0, retryAfterSeconds: 0) == 10, "zero header ignored")
        check(R.retryDelaySeconds(attempt: R.maxAutoRetries, retryAfterSeconds: 30) == nil, "header can't extend budget")

        // Filter options re-read only when scope/dates change or they age.
        let key = R.filterOptionsKey(scope: "all", fromDate: nil, toDate: nil)
        let t0 = Date(timeIntervalSince1970: 1_000)
        check(R.filterOptionsStale(loadedKey: nil, loadedAt: nil, wantedKey: key, now: t0), "never loaded")
        check(!R.filterOptionsStale(loadedKey: key, loadedAt: t0, wantedKey: key, now: t0.addingTimeInterval(60)), "fresh")
        check(R.filterOptionsStale(loadedKey: key, loadedAt: t0, wantedKey: key,
                                   now: t0.addingTimeInterval(R.filterOptionsTTLSeconds)), "aged")
        check(R.filterOptionsStale(loadedKey: key, loadedAt: t0,
                                   wantedKey: R.filterOptionsKey(scope: "mine", fromDate: nil, toDate: nil),
                                   now: t0.addingTimeInterval(1)), "scope changed")

        check(R.busyMessage(retryInSeconds: 10) == "The server is busy right now. Retrying in 10s…", "retry message")
        check(R.busyMessage(retryInSeconds: nil) == "The server is busy right now. Pull down to try again.", "final message")

        print("CpListBusyRulesTests: \(count) assertions passed")
    }
}
