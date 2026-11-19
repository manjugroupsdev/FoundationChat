import Foundation

@main struct MobileTelemetryPolicyTests {
    static func main() {
        precondition(MobileTelemetryPolicy.route("/api/hr/staff/Surya/9884693351?otp=1234#secret") == "/api/hr/staff/:id/:id")
        precondition(MobileTelemetryPolicy.route("/api/user%40example.com/secretToken") == "/api/:id/:id")
        precondition(MobileTelemetryPolicy.route("/api/hr/attendance/punch-in") == "/api/hr/attendance/punch-in")
        precondition(MobileTelemetryPolicy.route(String(repeating: "/secret/", count: 100)).count < 80)
        precondition(MobileTelemetryPolicy.service("API-MFPL.THEAIRIX.COM", authority: "api-mfpl.theairix.com") == "mms")
        precondition(MobileTelemetryPolicy.service("api-geo.theairix.com", authority: "api-mfpl.theairix.com") == "geotrack")
        for host in ["us.i.posthog.com", "storage-private.example.com", "api-mfpl.theairix.com.attacker.test"] {
            precondition(MobileTelemetryPolicy.service(host, authority: "api-mfpl.theairix.com") == nil)
        }
        precondition(MobileTelemetryPolicy.method("private-data") == "OTHER")
        for value in ["Bearer token", "user@example.com", "/home/user/file", "55555555"] {
            precondition(MobileTelemetryPolicy.symbol(value) == "Unknown")
        }
        precondition(MobileTelemetryPolicy.symbol("NSRangeException") == "NSRangeException")
        var sampled = MobileTelemetryBudget()
        precondition((1...100).filter { sampled.accept("request-\($0)", timing: true, healthy: true, now: 10) }.count == 5)
        var limited = MobileTelemetryBudget()
        precondition((1...1000).filter { limited.accept("timing-\($0)", timing: true, healthy: false, now: 1) }.count == 20)
        precondition((1...1000).filter { limited.accept("error-\($0)", timing: false, healthy: false, now: 1) }.count == 40)
        var persisted = MobileTelemetryBudget(day: 0, errors: 40, timings: 20)
        precondition(!persisted.accept("new", timing: false, healthy: false, now: 1))
        precondition(!persisted.accept("new", timing: true, healthy: false, now: 1))
        precondition(persisted.accept("new", timing: false, healthy: false, now: 86_400))
        precondition(persisted.errors == 1 && persisted.timings == 0)
        var exceptions = MobileTelemetryBudget()
        precondition((1...100).filter { exceptions.accept("crash-\($0)", timing: false, healthy: false, now: 1, exception: true) }.count == 8)
        precondition((1...100).filter { exceptions.accept("http-\($0)", timing: false, healthy: false, now: 1) }.count == 32)
        var restarted = MobileTelemetryBudget(day: 0, exceptions: 8)
        precondition(!restarted.accept("new", timing: false, healthy: false, now: 1, exception: true))
        precondition(restarted.accept("new", timing: false, healthy: false, now: 86_400, exception: true))
        var repeated = MobileTelemetryBudget()
        precondition(repeated.accept("same", timing: false, healthy: false, now: 1))
        precondition(!repeated.accept("same", timing: false, healthy: false, now: 2))
        precondition(repeated.accept("same", timing: false, healthy: false, now: 601))
        precondition(MobileTelemetryPolicy.retryDelay(status: nil, failures: 1, retryAfter: nil) == 600)
        precondition(MobileTelemetryPolicy.retryDelay(status: 503, failures: 2, retryAfter: 1) == 1200)
        precondition(MobileTelemetryPolicy.retryDelay(status: 429, failures: 1, retryAfter: 3600) == 3600)
        precondition(MobileTelemetryPolicy.retryDelay(status: 401, failures: 1, retryAfter: nil) == 21_600)
        precondition(MobileTelemetryPolicy.retryDelay(status: 500, failures: 500, retryAfter: .greatestFiniteMagnitude) == 21_600)
        precondition(MobileTelemetryPolicy.maxQueue == 60 && MobileTelemetryPolicy.batchSize == 20)
        precondition(MobileTelemetryPolicy.flushInterval >= 60)
        precondition(MobilePostHogConfig.batchURL.absoluteString == "https://us.i.posthog.com/batch/")
        print("Mobile PostHog privacy, service isolation, sampling, persistent budgets, dedup and backoff: passed")
    }
}
