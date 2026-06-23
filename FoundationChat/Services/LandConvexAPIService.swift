import Foundation

enum LandConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    private struct InspectionsResponse: Decodable {
        let success: Bool
        let inspections: [LandInspection]?
        let properties: [LandInspection]?
        let items: [LandInspection]?
        let error: String?
    }

    private struct InspectionResponse: Decodable {
        let success: Bool
        let inspection: LandInspection?
        let error: String?
    }

    private struct QueriesResponse: Decodable {
        let success: Bool
        let queries: [LandQueryLog]?
        let logs: [LandQueryLog]?
        let items: [LandQueryLog]?
        let error: String?
    }

    private struct MutationResponse: Decodable {
        let success: Bool
        let id: String?
        let error: String?
    }

    static func listInspections(
        token: String,
        fromDate: String? = nil,
        toDate: String? = nil
    ) async throws -> [LandInspection] {
        var queryItems: [URLQueryItem] = []
        if let fromDate, !fromDate.isEmpty { queryItems.append(URLQueryItem(name: "fromDate", value: fromDate)) }
        if let toDate, !toDate.isEmpty { queryItems.append(URLQueryItem(name: "toDate", value: toDate)) }
        let data = try await get(path: "/api/land/inspections/my", token: token, queryItems: queryItems)
        let wrapper = try decode(InspectionsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load inspections") }
        return wrapper.items ?? wrapper.inspections ?? wrapper.properties ?? []
    }

    static func saveInspection(token: String, request: SaveLandInspectionRequest) async throws -> String {
        let data = try await post(path: "/api/land/inspections/save", token: token, body: request)
        let wrapper = try decode(MutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to save inspection") }
        return wrapper.id ?? ""
    }

    static func rescheduleInspection(token: String, request: RescheduleLandInspectionRequest) async throws {
        let data = try await post(path: "/api/land/inspections/reschedule", token: token, body: request)
        let wrapper = try decode(MutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to reschedule inspection") }
    }

    static func acceptInspection(token: String, request: AcceptLandInspectionRequest) async throws {
        let data = try await post(path: "/api/land/inspections/accept", token: token, body: request)
        let wrapper = try decode(MutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to accept inspection") }
    }

    static func listQueries(token: String) async throws -> [LandQueryLog] {
        let data = try await get(path: "/api/land/queries/my", token: token)
        let wrapper = try decode(QueriesResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load queries") }
        return wrapper.items ?? wrapper.queries ?? wrapper.logs ?? []
    }

    static func updateQuery(token: String, request: LandQueryUpdateRequest) async throws {
        let data = try await post(path: "/api/land/queries/update", token: token, body: request)
        let wrapper = try decode(MutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to update query") }
    }

    private static func get(path: String, token: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(string: "\(baseURL)\(path)")
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw MarketingAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private static func post<T: Encodable>(path: String, token: String, body: T) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw MarketingAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private static func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                SessionInvalidationBus.emit()
                throw MarketingAPIError.unauthorized
            }
            if http.statusCode >= 400 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    throw MarketingAPIError.server(error)
                }
                throw MarketingAPIError.server("Request failed (\(http.statusCode))")
            }
        }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MarketingAPIError.decoding(error)
        }
    }
}
