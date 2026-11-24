import Foundation

/// What the CP Visits list does when the MMS server is too busy to answer
/// (Android parity: CpListBusyPolicy).
///
/// The production backend runs at most 16 requests at once for every user
/// together. Under load it refuses with 429 ("TooManyConcurrentRequests") or a
/// 502/503/504. That is not a bad request: the same call works a little later.
/// So the list keeps what it has (or its saved copy), says the server is busy,
/// and asks again on its own after a growing pause instead of a dead-end error.
enum CpListBusyRules {
    /// Quiet automatic retries per busy spell; after that, pull to refresh.
    static let maxAutoRetries = 5
    static let firstRetrySeconds: Double = 10
    static let maxRetrySeconds: Double = 60
    static let minRetryAfterSeconds: Double = 5
    static let maxRetryAfterSeconds: Double = 120
    /// Filter options rarely change; re-read them at most this often per scope/dates.
    static let filterOptionsTTLSeconds: Double = 600

    static func isServerBusy(httpStatus: Int?) -> Bool {
        guard let httpStatus else { return false }
        return [429, 502, 503, 504].contains(httpStatus)
    }

    /// Wait before automatic retry number `attempt` (0-based), or nil when no
    /// more automatic retries should run. A server Retry-After wins, clamped.
    static func retryDelaySeconds(attempt: Int, retryAfterSeconds: Double?) -> Double? {
        guard attempt >= 0, attempt < maxAutoRetries else { return nil }
        if let retryAfterSeconds, retryAfterSeconds > 0 {
            return min(max(retryAfterSeconds, minRetryAfterSeconds), maxRetryAfterSeconds)
        }
        var delay = firstRetrySeconds
        for _ in 0..<attempt { delay = min(delay * 2, maxRetrySeconds) }
        return delay
    }

    static func filterOptionsKey(scope: String, fromDate: String?, toDate: String?) -> String {
        "\(scope)|\(fromDate ?? "")|\(toDate ?? "")"
    }

    static func filterOptionsStale(loadedKey: String?, loadedAt: Date?, wantedKey: String, now: Date) -> Bool {
        guard let loadedKey, let loadedAt, loadedKey == wantedKey else { return true }
        return now.timeIntervalSince(loadedAt) >= filterOptionsTTLSeconds
    }

    static func busyMessage(retryInSeconds: Double?) -> String {
        guard let retryInSeconds else {
            return "The server is busy right now. Pull down to try again."
        }
        return "The server is busy right now. Retrying in \(Int(retryInSeconds.rounded(.up)))s…"
    }
}
