import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
typealias URLRequest = FoundationNetworking.URLRequest
#endif

enum AppConfig { static let baseURL = "https://mms.example" }
final class TelemetryBoundaryEvents: @unchecked Sendable {
    let lock = NSLock()
    var count = 0
    func received() { lock.withLock { count += 1 } }
    var total: Int { lock.withLock { count } }
}
@main struct MobileTelemetryBoundaryTests {
    static func main() async {
        let events = TelemetryBoundaryEvents()
        let listener = NotificationCenter.default.addObserver(forName: .didInvalidateSession, object: nil, queue: nil) { _ in events.received() }
        defer { NotificationCenter.default.removeObserver(listener) }
        var request = URLRequest(url: URL(string: "https://us.i.posthog.com/batch/")!)
        // Even accidental future authentication must not turn PostHog into MMS authority.
        request.setValue("Bearer fake-session", forHTTPHeaderField: "Authorization")
        SessionInvalidationBus.emit(for: request, responseData: Data("{\"error\":\"session expired\"}".utf8))
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        precondition(events.total == 0)
        print("PostHog unauthorized response cannot clear the MMS session: passed")
    }
}
