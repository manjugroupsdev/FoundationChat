import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
typealias URLRequest = FoundationNetworking.URLRequest
#endif

enum AppConfig {
    static let baseURL = "https://mms.example"
}

final class BoundaryEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.withLock { values.append(value) } }
    var tokens: [String] { lock.withLock { values } }
}

@main
struct SessionInvalidationBoundaryTests {
    static func request(_ path: String, host: String = "mms.example", authenticated: Bool = true) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://" + host + path)!)
        if authenticated { request.setValue("Bearer test-session", forHTTPHeaderField: "Authorization") }
        return request
    }

    static func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    static func main() async {
        let events = BoundaryEvents()
        let observer = NotificationCenter.default.addObserver(forName: .didInvalidateSession, object: nil, queue: nil) { note in
            if let event = note.object as? SessionInvalidationBus.Event { events.append(event.failedToken) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let expired = Data("{\"error\":\"session expired\"}".utf8)
        for path in ["/api/chat/typing", "/api/push/register", "/api/notifications/unread-count"] {
            SessionInvalidationBus.emit(for: request(path), responseData: expired)
        }
        SessionInvalidationBus.emit(for: request("/api/auth/validate-session", host: "geo.example"), responseData: expired)
        SessionInvalidationBus.emit(for: request("/api/auth/validate-session", authenticated: false), responseData: expired)
        SessionInvalidationBus.emit(for: request("/api/auth/send-otp", authenticated: false), responseData: expired)
        SessionInvalidationBus.emit(for: request("/api/hr/attendance/today"), responseData: Data("{\"error\":\"operation refused\"}".utf8))
        await drain()
        precondition(events.tokens.isEmpty, "Secondary/public/operation failures must not clear the session")
        SessionInvalidationBus.emit(for: request("/api/auth/validate-session"), responseData: nil)
        await drain()
        precondition(events.tokens == ["test-session"])
        let event = SessionInvalidationBus.Event(failedToken: "old", reason: "expired")
        precondition(!event.matches(currentToken: "fresh"))
        precondition(!event.matches(currentToken: nil))
        precondition(event.matches(currentToken: "old"))
        print("Session invalidation: authoritative-host and token boundaries passed")
    }
}
