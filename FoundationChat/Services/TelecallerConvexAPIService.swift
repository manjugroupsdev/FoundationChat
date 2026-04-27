import Foundation

/// HTTP client for Convex-backed telecaller endpoints.
enum TelecallerConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    struct LeadsPage: Sendable, Equatable {
        let leads: [ConvexLead]
        let nextCursor: String?
        let total: Int?
        let hasMore: Bool
    }

    private struct LeadsResponse: Decodable {
        let success: Bool
        let leads: [ConvexLead]?
        let total: Int?
        let nextCursor: String?
        let hasMore: Bool?
        let error: String?
    }

    /// Fetch leads assigned to the current user.
    /// - Parameters:
    ///   - status: optional server-side status filter (e.g. `"new"`, `"contacted"`).
    ///   - cursor: opaque cursor returned from a previous page.
    ///   - limit: page size hint.
    static func getMyLeads(
        token: String,
        status: String? = nil,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> LeadsPage {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let status, !status.isEmpty { items.append(URLQueryItem(name: "status", value: status)) }
        if let cursor, !cursor.isEmpty { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        let query = items.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        let path = "/api/telecaller/leads/my?\(query)"
        let data = try await get(path: path, token: token)
        let wrapper = try JSONDecoder().decode(LeadsResponse.self, from: data)
        if let error = wrapper.error, wrapper.success == false {
            throw TelecallerAPIError.server(error)
        }
        let leads = wrapper.leads ?? []
        let hasMore = wrapper.hasMore ?? (wrapper.nextCursor != nil)
        return LeadsPage(leads: leads, nextCursor: wrapper.nextCursor, total: wrapper.total, hasMore: hasMore)
    }

    // MARK: - HTTP

    private static func get(path: String, token: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw TelecallerAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw TelecallerAPIError.unauthorized }
            if http.statusCode >= 400 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    throw TelecallerAPIError.server(error)
                }
                throw TelecallerAPIError.server("Request failed (\(http.statusCode))")
            }
        }
        return data
    }
}

enum TelecallerAPIError: LocalizedError {
    case badURL
    case unauthorized
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL"
        case .unauthorized: return "Session expired. Please sign in again."
        case .server(let msg): return msg
        }
    }
}
