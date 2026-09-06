import Foundation

extension Notification.Name {
    static let didInvalidateSession = Notification.Name("didInvalidateSession")
}

enum SessionInvalidationBus {
    struct Event {
        let failedToken: String
        let reason: String

        func matches(currentToken: String?) -> Bool {
            guard let currentToken, !currentToken.isEmpty else { return false }
            return failedToken == currentToken
        }
    }

    private static func emit(
        failedToken: String,
        reason: String = "Session expired. Please sign in again."
    ) {
        guard !failedToken.isEmpty else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .didInvalidateSession,
                object: Event(failedToken: failedToken, reason: reason)
            )
        }
    }

    static func emit(for request: URLRequest) {
        guard let requestHost = request.url?.host,
              let authorityHost = URL(string: AppConfig.baseURL)?.host,
              requestHost.caseInsensitiveCompare(authorityHost) == .orderedSame else { return }
        guard let header = request.value(forHTTPHeaderField: "Authorization"),
              let token = bearerToken(from: header) else { return }
        emit(failedToken: token)
    }

    private static func bearerToken(from header: String) -> String? {
        let parts = header.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard parts.count == 2,
              parts[0].caseInsensitiveCompare("Bearer") == .orderedSame else { return nil }
        let token = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
