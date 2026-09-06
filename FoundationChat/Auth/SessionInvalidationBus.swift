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

    static func emit(for request: URLRequest, responseData: Data?) {
        guard let requestHost = request.url?.host,
              let authorityHost = URL(string: AppConfig.baseURL)?.host,
              requestHost.caseInsensitiveCompare(authorityHost) == .orderedSame else { return }
        guard let header = request.value(forHTTPHeaderField: "Authorization"),
              let token = bearerToken(from: header) else { return }
        guard isTerminalSessionRejection(path: request.url?.path, responseData: responseData) else { return }
        emit(failedToken: token)
    }

    private static func isTerminalSessionRejection(path: String?, responseData: Data?) -> Bool {
        if let normalizedPath = path?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
           normalizedPath.caseInsensitiveCompare("api/auth/validate-session") == .orderedSame {
            return true
        }

        guard let responseData, !responseData.isEmpty else { return false }
        let values: [String]
        if let object = try? JSONSerialization.jsonObject(with: responseData) {
            values = relevantStrings(in: object)
        } else if let text = String(data: responseData, encoding: .utf8) {
            values = [text]
        } else {
            values = []
        }

        let terminalCodes: Set<String> = [
            "invalid_session",
            "session_invalid",
            "session_expired",
            "session_revoked",
            "session_inactive",
            "authentication_required",
        ]
        let terminalPhrases = [
            "invalid or expired session",
            "session expired",
            "invalid session",
            "session is invalid",
            "session revoked",
            "session has been revoked",
            "session inactive",
            "session is inactive",
            "signed in on another device",
            "authorization header with bearer token is required",
            "not authenticated",
        ]

        return values.contains { raw in
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let code = normalized.replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            return terminalCodes.contains(code) || terminalPhrases.contains { normalized.contains($0) }
        }
    }

    private static func relevantStrings(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, nestedValue in
                if ["error", "message", "reason", "code"].contains(key.lowercased()),
                   let string = nestedValue as? String {
                    return [string]
                }
                if nestedValue is [String: Any] || nestedValue is [Any] {
                    return relevantStrings(in: nestedValue)
                }
                return []
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(relevantStrings)
        }
        if let string = value as? String {
            return [string]
        }
        return []
    }

    private static func bearerToken(from header: String) -> String? {
        let parts = header.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard parts.count == 2,
              parts[0].caseInsensitiveCompare("Bearer") == .orderedSame else { return nil }
        let token = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
