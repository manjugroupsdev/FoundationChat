import Foundation

/// A mandatory alert sent from web (Settings > Mobile alerts) to this staff
/// member. Shown full screen until it has been on screen `minViewSeconds`.
nonisolated struct MobileAlert: Identifiable, Equatable, Sendable {
    let deliveryId: String
    let sendId: String
    let title: String
    let bodyHtml: String
    /// `/api/storage/files/<id>` (bearer-protected) or an absolute URL.
    let imageUrl: String?
    let sentAt: Date?
    let minViewSeconds: Int

    var id: String { deliveryId }

    static let defaultMinViewSeconds = 5
}

nonisolated enum MobileAlertAPIError: LocalizedError, Sendable {
    case invalidURL
    case rejected(status: Int?, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .rejected(_, let message): return message
        }
    }

    /// A rejection a retry can't fix (unknown delivery, another staff's alert,
    /// a missing route). Auth, timeout, rate-limit and 5xx failures are retried.
    var isPermanent: Bool {
        switch self {
        case .invalidURL:
            return true
        case .rejected(let status, _):
            guard let status else { return true }
            return (400..<500).contains(status) && ![401, 408, 429].contains(status)
        }
    }
}

/// The /api/mobile/alerts/* routes.
enum MobileAlertAPIService {
    static func fetchDetail(token: String, deliveryId: String) async throws -> MobileAlert {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "deliveryId", value: deliveryId)]
        let data = try await send(path: "/api/mobile/alerts/detail?\(components.percentEncodedQuery ?? "")",
                                  token: token, body: Optional<ViewedBody>.none)
        let response = try JSONDecoder().decode(DetailResponse.self, from: data)
        guard response.success, let alert = response.alert?.alert else {
            throw MobileAlertAPIError.rejected(status: nil, message: response.error ?? "Alert is no longer available")
        }
        return alert
    }

    /// Alerts this staff member hasn't viewed yet, oldest first.
    static func fetchPending(token: String) async throws -> [MobileAlert] {
        let data = try await send(path: "/api/mobile/alerts/pending", token: token, body: Optional<ViewedBody>.none)
        let response = try JSONDecoder().decode(PendingResponse.self, from: data)
        guard response.success else {
            throw MobileAlertAPIError.rejected(status: nil, message: response.error ?? "Couldn't load alerts")
        }
        return response.alerts
    }

    /// Idempotent: acknowledging an already-viewed delivery still succeeds.
    static func markViewed(token: String, deliveryId: String) async throws {
        let data = try await send(
            path: "/api/mobile/alerts/viewed",
            token: token,
            body: ViewedBody(deliveryId: deliveryId)
        )
        let response = try JSONDecoder().decode(ActionResponse.self, from: data)
        guard response.success else {
            throw MobileAlertAPIError.rejected(status: nil, message: response.error ?? "Couldn't mark the alert viewed")
        }
    }

    // MARK: - Decoding

    private nonisolated struct ViewedBody: Encodable {
        let deliveryId: String
    }

    private nonisolated struct DetailResponse: Decodable {
        let success: Bool
        let alert: RawAlert?
        let error: String?
    }

    private nonisolated struct ActionResponse: Decodable {
        let success: Bool
        let error: String?

        private nonisolated enum CodingKeys: String, CodingKey { case success, error }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            success = (try? container.decodeIfPresent(Bool.self, forKey: .success)) ?? false
            error = try? container.decodeIfPresent(String.self, forKey: .error)
        }
    }

    /// Lossy: an alert with a bad or missing field is skipped (or defaulted)
    /// instead of failing the whole list.
    private nonisolated struct PendingResponse: Decodable {
        let success: Bool
        let alerts: [MobileAlert]
        let error: String?

        private nonisolated enum CodingKeys: String, CodingKey { case success, alerts, error }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            success = (try? container.decodeIfPresent(Bool.self, forKey: .success)) ?? false
            error = try? container.decodeIfPresent(String.self, forKey: .error)

            var parsed: [MobileAlert] = []
            if var list = try? container.nestedUnkeyedContainer(forKey: .alerts) {
                while !list.isAtEnd {
                    let index = list.currentIndex
                    if (try? list.decodeNil()) == true { continue }
                    if let raw = try? list.decode(RawAlert.self), let alert = raw.alert {
                        parsed.append(alert)
                    }
                    // Never spin on an element the decoder couldn't step past.
                    if list.currentIndex == index { break }
                }
            }
            alerts = parsed
        }
    }

    /// Every field optional and read with `try?`, so decoding never throws.
    private nonisolated struct RawAlert: Decodable {
        let deliveryId: String?
        let sendId: String?
        let title: String?
        let bodyHtml: String?
        let imageUrl: String?
        let sentAt: Double?
        let minViewSeconds: Double?

        private nonisolated enum CodingKeys: String, CodingKey {
            case deliveryId, sendId, title, bodyHtml, imageUrl, sentAt, minViewSeconds
        }

        init(from decoder: Decoder) throws {
            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                deliveryId = nil
                sendId = nil
                title = nil
                bodyHtml = nil
                imageUrl = nil
                sentAt = nil
                minViewSeconds = nil
                return
            }
            deliveryId = Self.string(container, .deliveryId)
            sendId = Self.string(container, .sendId)
            title = Self.string(container, .title)
            bodyHtml = Self.string(container, .bodyHtml)
            imageUrl = Self.string(container, .imageUrl)
            sentAt = Self.number(container, .sentAt)
            minViewSeconds = Self.number(container, .minViewSeconds)
        }

        var alert: MobileAlert? {
            guard let deliveryId = Self.trimmed(deliveryId) else { return nil }
            // Clamped before the Int conversion: a "inf"/"nan" string would trap.
            var seconds = MobileAlert.defaultMinViewSeconds
            if let minViewSeconds, minViewSeconds.isFinite {
                seconds = Int(min(max(minViewSeconds, 0), 3_600).rounded())
            }
            return MobileAlert(
                deliveryId: deliveryId,
                sendId: Self.trimmed(sendId) ?? "",
                title: Self.trimmed(title) ?? "Alert",
                bodyHtml: bodyHtml ?? "",
                imageUrl: Self.trimmed(imageUrl),
                sentAt: sentAt.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil },
                minViewSeconds: seconds
            )
        }

        private static func string(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return String(value) }
            return nil
        }

        private static func number(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Double(value) }
            return nil
        }

        private static func trimmed(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        }
    }

    // MARK: - HTTP

    /// GET when `body` is nil, else POST. Error bodies carry `{ error }`.
    private static func send<T: Encodable>(path: String, token: String, body: T?) async throws -> Data {
        guard let url = URL(string: "\(AppConfig.baseURL)\(path)") else {
            throw MobileAlertAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        } else {
            request.httpMethod = "GET"
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                SessionInvalidationBus.emit(for: request, responseData: data)
            }
            if http.statusCode >= 400 {
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw MobileAlertAPIError.rejected(
                    status: http.statusCode,
                    message: message ?? "Request failed (\(http.statusCode))"
                )
            }
        }
        return data
    }
}
