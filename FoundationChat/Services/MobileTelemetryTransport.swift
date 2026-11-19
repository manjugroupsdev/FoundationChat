import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated enum MobileTelemetryTransport {
    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 1
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        return config
    }
    static func session() -> URLSession {
        URLSession(configuration: configuration(), delegate: MobileTelemetryRedirectGuard(), delegateQueue: nil)
    }
    static func request(events: [[String: Any]]) throws -> URLRequest {
        var request = URLRequest(url: MobilePostHogConfig.batchURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["api_key": MobilePostHogConfig.projectToken, "batch": events])
        return request
    }
}

nonisolated private final class MobileTelemetryRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
