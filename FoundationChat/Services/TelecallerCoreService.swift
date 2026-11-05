import Foundation

/// Talks to Telecaller Core, the service behind the web "Insights" page, the
/// same way the web does:
///  1. exchange the MFPL session for a short-lived core JWT
///     (POST {baseURL}/api/internal/telecaller/session/exchange), cached until
///     a minute before it expires;
///  2. POST {core}/api with {namespace, apiName, auth, data}.
/// A core "unauthorized" drops the cached JWT and retries once.
actor TelecallerCoreService {
    static let shared = TelecallerCoreService()

    private let coreURL = URL(string: "https://api-telecaller.theairix.com/api")!
    private var cachedToken: (session: String, jwt: String, expiresAt: Date)?

    enum CoreError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }

    private struct ExchangeResponse: Decodable {
        let success: Bool?
        let accessToken: String?
        let expiresIn: Double?
        let error: String?
    }

    private func jwt(session: String, refresh: Bool) async throws -> String {
        if !refresh, let cached = cachedToken, cached.session == session,
           cached.expiresAt.timeIntervalSinceNow > 60 {
            return cached.jwt
        }
        guard let url = URL(string: "\(AppConfig.baseURL)/api/internal/telecaller/session/exchange") else {
            throw CoreError.message("Insights is unavailable")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try? JSONDecoder().decode(ExchangeResponse.self, from: data)
        guard decoded?.success == true, let token = decoded?.accessToken, !token.isEmpty else {
            throw CoreError.message(decoded?.error ?? "Couldn't sign in to Insights")
        }
        let ttl = max(decoded?.expiresIn ?? 300, 30)
        cachedToken = (session, token, Date().addingTimeInterval(ttl))
        return token
    }

    /// Calls a core API and returns the raw `data` JSON.
    func call(session: String, namespace: String, apiName: String, data: [String: Any]) async throws -> Data {
        try await attempt(session: session, namespace: namespace, apiName: apiName, data: data, refresh: false)
    }

    private func attempt(session: String, namespace: String, apiName: String, data: [String: Any], refresh: Bool) async throws -> Data {
        let auth = try await jwt(session: session, refresh: refresh)
        var request = URLRequest(url: coreURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "namespace": namespace, "apiName": apiName, "auth": auth, "data": data,
        ])
        let (body, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let message = envelope?["message"] as? String
        if (code == 401 || message == "unauthorized") && !refresh {
            return try await attempt(session: session, namespace: namespace, apiName: apiName, data: data, refresh: true)
        }
        guard (200..<300).contains(code), envelope?["status"] as? String != "error",
              let payload = envelope?["data"] else {
            throw CoreError.message(message ?? "Insights is unavailable (\(code))")
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    func reset() { cachedToken = nil }
}

/// One Team Performance metric: actual against target.
struct CockpitMetric: Codable, Equatable, Sendable {
    var actual: Double = 0
    var target: Double = 0
    var percentage: Double = 0
}

/// The cockpitPerformance answer, trimmed to what the dashboard shows.
struct CockpitPerformance: Codable, Equatable, Sendable {
    var metrics: [String: CockpitMetric] = [:]
    var dateFrom: String?
    var dateTo: String?
    var availableFrom: String?
    var canSeeAll: Bool?

    enum CodingKeys: String, CodingKey { case metrics, dateFrom, dateTo, availableFrom, canSeeAll }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decode metric by metric: one odd entry must not drop the whole card.
        var parsed: [String: CockpitMetric] = [:]
        if let raw = try? c.decode([String: LossyMetric].self, forKey: .metrics) {
            for (key, value) in raw { if let metric = value.metric { parsed[key] = metric } }
        }
        metrics = parsed
        dateFrom = try? c.decodeIfPresent(String.self, forKey: .dateFrom)
        dateTo = try? c.decodeIfPresent(String.self, forKey: .dateTo)
        availableFrom = try? c.decodeIfPresent(String.self, forKey: .availableFrom)
        canSeeAll = try? c.decodeIfPresent(Bool.self, forKey: .canSeeAll)
    }

    private struct LossyMetric: Decodable {
        let metric: CockpitMetric?
        init(from decoder: Decoder) throws {
            metric = try? CockpitMetric(from: decoder)
        }
    }
}
