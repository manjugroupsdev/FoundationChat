import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum IssueReporter {
    enum TestError: Error { case unexpectedNetworkRequest }
    static func data(for request: URLRequest, session: URLSession = .shared) async throws -> (Data, URLResponse) {
        throw TestError.unexpectedNetworkRequest
    }
}
