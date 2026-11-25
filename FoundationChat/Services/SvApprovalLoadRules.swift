import Foundation

/// How SV Approvals reads its task list without tripping the server's busy
/// limit (Android parity: SvApprovalLoadPolicy).
///
/// The queue is filtered from the 500-row task-manager list, a heavy read.
/// The App Library already reads it for the SV Approvals badge; opening the
/// screen straight after fired a second identical read, which the server
/// refused with 429 under load until a manual "Try again". The screen now
/// shares the badge's read (in flight, or finished moments ago) and retries a
/// busy answer quietly with a short backoff while the skeleton stays up.
nonisolated enum SvApprovalLoadRules {
    /// A task list read this recently is reused instead of read again.
    static let shareSeconds: Double = 30
    /// Quiet automatic retries on a busy server before "Couldn't load" shows.
    static let maxAutoRetries = 4
    private static let retryDelays: [Double] = [1.5, 4, 10, 20]

    static func isFresh(fetchedAt: Date?, now: Date) -> Bool {
        guard let fetchedAt else { return false }
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age <= shareSeconds
    }

    /// Wait before automatic retry `attempt` (0-based), or nil when used up.
    static func retryDelaySeconds(attempt: Int) -> Double? {
        guard attempt >= 0, attempt < maxAutoRetries else { return nil }
        return retryDelays[attempt]
    }

    static func isServerBusy(httpStatus: Int?) -> Bool {
        guard let httpStatus else { return false }
        return [429, 502, 503, 504].contains(httpStatus)
    }
}
