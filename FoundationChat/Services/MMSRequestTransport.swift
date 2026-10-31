import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum MMSRequestTransport {
    // A single reusable write session prevents background reads from occupying
    // every connection slot used by an interactive submission.
    private static let writes = URLSession(configuration: .default)

    static func session(for method: String?, path: String? = nil) -> URLSession {
        if path == "/api/hr/shifts/today" { return writes }
        switch (method ?? "GET").uppercased() {
        case "GET", "HEAD", "OPTIONS": return .shared
        default: return writes
        }
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session(for: request.httpMethod, path: request.url?.path).data(for: request)
    }
}
