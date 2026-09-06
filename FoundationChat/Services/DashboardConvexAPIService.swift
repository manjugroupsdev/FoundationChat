import Foundation

/// HTTP client for the Android-parity Home management dashboard endpoints.
enum DashboardConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    static func getMobileDashboard(token: String, date: String? = nil) async throws -> ConvexMobileDashboard {
        var path = "/api/mobile/dashboard"
        if let encodedDate = date?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           !encodedDate.isEmpty {
            path += "?date=\(encodedDate)"
        }

        let data = try await get(path: path, token: token)
        let dashboard = try await BackgroundJSONDecoder.decode(ConvexMobileDashboard.self, from: data)
        guard dashboard.success else {
            throw HRConvexAPIError.server(dashboard.error ?? "Failed to load dashboard")
        }
        return dashboard
    }

    /// Today's calls drill-down (optionally filtered to a direction). Mirrors
    /// Android `getDashboardCalls` → `GET /api/dashboard/calls?date=&direction=`.
    static func getDashboardCalls(
        token: String,
        date: String? = nil,
        direction: String? = nil
    ) async throws -> [DashboardCallRow] {
        var items: [URLQueryItem] = []
        if let date, !date.isEmpty { items.append(URLQueryItem(name: "date", value: date)) }
        if let direction, !direction.isEmpty {
            items.append(URLQueryItem(name: "direction", value: direction))
        }
        var comps = URLComponents()
        comps.queryItems = items.isEmpty ? nil : items
        let query = comps.percentEncodedQuery.map { "?\($0)" } ?? ""
        let data = try await get(path: "/api/dashboard/calls\(query)", token: token)
        let resp = try await BackgroundJSONDecoder.decode(DashboardCallsResponse.self, from: data)
        guard resp.success else {
            throw HRConvexAPIError.server(resp.error ?? "Failed to load calls")
        }
        return resp.calls ?? []
    }

    /// Today's completed registrations. Mirrors Android
    /// `getDashboardRegistrations` → `GET /api/dashboard/registrations?date=`.
    static func getDashboardRegistrations(
        token: String,
        date: String? = nil
    ) async throws -> [DashboardRegistrationRow] {
        var path = "/api/dashboard/registrations"
        if let encoded = date?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           !encoded.isEmpty {
            path += "?date=\(encoded)"
        }
        let data = try await get(path: path, token: token)
        let resp = try await BackgroundJSONDecoder.decode(DashboardRegistrationsResponse.self, from: data)
        guard resp.success else {
            throw HRConvexAPIError.server(resp.error ?? "Failed to load registrations")
        }
        return resp.registrations ?? []
    }

    private static func get(path: String, token: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw HRConvexAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPError(data: data, response: response, request: request)
        return data
    }

    private static func checkHTTPError(data: Data, response: URLResponse, request: URLRequest) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            SessionInvalidationBus.emit(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw HRConvexAPIError.unauthorized(error)
            }
            throw HRConvexAPIError.unauthorized("Unauthorized")
        }
        if http.statusCode >= 400 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw HRConvexAPIError.server(error)
            }
            throw HRConvexAPIError.server("Request failed (\(http.statusCode))")
        }
    }
}
