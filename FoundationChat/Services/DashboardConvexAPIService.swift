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
        let dashboard = try JSONDecoder().decode(ConvexMobileDashboard.self, from: data)
        guard dashboard.success else {
            throw HRConvexAPIError.server(dashboard.error ?? "Failed to load dashboard")
        }
        return dashboard
    }

    private static func get(path: String, token: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw HRConvexAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPError(data: data, response: response)
        return data
    }

    private static func checkHTTPError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            SessionInvalidationBus.emit()
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
