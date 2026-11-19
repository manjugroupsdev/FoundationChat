import Foundation

@main
struct ChatPollingBackoffTests {
    static func main() async {
        for path in ["/api/chat/typing?conversationId=test", "/api/chat/presence?staffIds=test", "/api/chat/messages/poll?after=1"] {
            precondition(ChatPollingBackoffPolicy.isBackgroundRead(path))
        }
        for path in ["/api/chat/messages/conversation", "/api/chat/presence/heartbeat", "/api/chat/typing-extra",
                     "/api/hr/attendance/today", "/api/tracking/heartbeat", "/api/chat/messages/send"] {
            precondition(!ChatPollingBackoffPolicy.isBackgroundRead(path))
        }
        var policy = ChatPollingBackoffPolicy()
        precondition(!policy.isLimited(at: 100))
        policy.record(status: 429, retryAfter: nil, at: 100)
        precondition(policy.notBefore == 110)
        precondition(policy.isLimited(at: 109.9) && !policy.isLimited(at: 110))
        policy.record(status: 200, retryAfter: nil, at: 101)
        precondition(policy.notBefore == 110, "Older in-flight success must not remove cooldown")
        policy.record(status: 429, retryAfter: nil, at: 110)
        precondition(policy.notBefore == 130)
        policy.record(status: 503, retryAfter: nil, at: 130)
        precondition(policy.notBefore == 170)
        policy.record(status: 429, retryAfter: nil, at: 170)
        precondition(policy.notBefore == 230)
        policy.record(status: 429, retryAfter: 120, at: 230)
        precondition(policy.notBefore == 350)
        policy.record(status: 200, retryAfter: nil, at: 350)
        precondition(policy.notBefore == 0)
        policy.record(status: 401, retryAfter: nil, at: 351)
        precondition(policy.notBefore == 0)
        policy.record(status: 400, retryAfter: nil, at: 351)
        precondition(policy.notBefore == 0)
        policy.record(status: 429, retryAfter: .infinity, at: 400)
        precondition(policy.notBefore == 410)
        let backoff = ChatPollingBackoff()
        await backoff.record(token: "first", status: 429, retryAfter: nil)
        let firstLimited = await backoff.isLimited(token: "first")
        let secondLimited = await backoff.isLimited(token: "second")
        precondition(firstLimited && !secondLimited)
        print("Chat polling backoff: all policy and account-isolation checks passed")
    }
}
