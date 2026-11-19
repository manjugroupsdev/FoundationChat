import Foundation

nonisolated struct ChatPollingBackoffPolicy: Sendable {
    private(set) var notBefore: TimeInterval = 0
    private var failures = 0

    static func isBackgroundRead(_ path: String) -> Bool {
        guard let route = URLComponents(string: path)?.path else { return false }
        return ["/api/chat/typing", "/api/chat/presence", "/api/chat/messages/poll"].contains(route)
    }

    func isLimited(at uptime: TimeInterval) -> Bool { uptime < notBefore }

    mutating func record(status: Int, retryAfter: TimeInterval?, at uptime: TimeInterval) {
        if status == 429 || status == 503 {
            failures = min(failures + 1, 4)
            let delay = min(10 * pow(2, Double(failures - 1)), 60)
            let serverDelay = retryAfter.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
            notBefore = max(notBefore, uptime + max(delay, serverDelay))
        } else if (200..<300).contains(status), uptime >= notBefore {
            failures = 0
            notBefore = 0
        }
    }
}

/// Shared local cooldown for optional chat polling, not user writes or tracking.
actor ChatPollingBackoff {
    static let shared = ChatPollingBackoff()
    private var policies: [String: ChatPollingBackoffPolicy] = [:]

    func isLimited(token: String) -> Bool {
        policies[token]?.isLimited(at: ProcessInfo.processInfo.systemUptime) == true
    }

    func record(token: String, status: Int, retryAfter: TimeInterval?) {
        let now = ProcessInfo.processInfo.systemUptime
        guard status == 429 || status == 503 || policies[token] != nil else { return }
        if policies[token] == nil, policies.count >= 4,
           let oldest = policies.min(by: { $0.value.notBefore < $1.value.notBefore })?.key {
            policies.removeValue(forKey: oldest)
        }
        var policy = policies[token] ?? ChatPollingBackoffPolicy()
        policy.record(status: status, retryAfter: retryAfter, at: now)
        policies[token] = policy.notBefore == 0 ? nil : policy
    }
}
