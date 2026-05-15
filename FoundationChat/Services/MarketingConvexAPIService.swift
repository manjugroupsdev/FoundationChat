import Foundation

enum MarketingConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    // MARK: - Response wrappers

    private struct MyLoansResponse: Decodable {
        let success: Bool
        let active: [ConvexLoanData]?
        let previous: [ConvexLoanData]?
        let pending: [ConvexLoanData]?
        let error: String?
    }

    private struct LoanDetailResponse: Decodable {
        let success: Bool
        let loan: ConvexLoanData?
        let error: String?
    }

    private struct MarketingProjectsResponse: Decodable {
        let success: Bool
        let projects: [MarketingProject]?
        let error: String?
    }

    private struct InventoryUnitsResponse: Decodable {
        let success: Bool
        let units: [InventoryUnit]?
        let error: String?
    }

    private struct InventoryUnitResponse: Decodable {
        let success: Bool
        let unit: InventoryUnit?
        let error: String?
    }

    private struct InventoryLayoutResponse: Decodable {
        let success: Bool
        let units: [InventoryUnit]?
        let error: String?
    }

    private struct TelecallerLeadSearchResponse: Decodable {
        let success: Bool
        let total: Int?
        let leads: [TelecallerLeadSearchData]?
        let error: String?
    }

    private struct CreateBookingResponse: Decodable {
        let success: Bool
        let id: String?
        let error: String?
    }

    private struct InventoryUnitIdRequest: Encodable {
        let id: String
    }

    struct LoansPage: Sendable {
        let active: [AppLoan]
        let previous: [AppLoan]
    }

    // MARK: - Loans

    static func getMyLoans(token: String, staffId: String? = nil) async throws -> LoansPage {
        var items: [URLQueryItem] = []
        if let staffId, !staffId.isEmpty {
            items.append(URLQueryItem(name: "staffId", value: staffId))
        }
        let data = try await get(path: "/api/hr/loans/my", token: token, queryItems: items)
        let wrapper = try decode(MyLoansResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load loans") }
        let active = AppLoanMapper.mapLoanList(wrapper.pending ?? [], status: .pending)
            + AppLoanMapper.mapLoanList(wrapper.active ?? [], status: .active)
        let previous = AppLoanMapper.mapLoanList(wrapper.previous ?? [], status: .repaid)
        return LoansPage(active: active, previous: previous)
    }

    static func getLoanDetail(token: String, id: String, mappedStatus: AppLoanStatus) async throws -> AppLoan {
        let data = try await get(
            path: "/api/hr/loans/get",
            token: token,
            queryItems: [URLQueryItem(name: "id", value: id)]
        )
        let wrapper = try decode(LoanDetailResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load loan") }
        guard let loan = wrapper.loan else { throw MarketingAPIError.server("Loan not found") }
        return AppLoanMapper.fromRemote(loan, mappedStatus: mappedStatus)
    }

    // MARK: - Projects / Inventory

    static func getMarketingProjects(token: String) async throws -> [MarketingProject] {
        let data = try await get(path: "/api/marketing/projects", token: token)
        let wrapper = try decode(MarketingProjectsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load projects") }
        return wrapper.projects ?? []
    }

    static func listInventoryUnits(
        token: String,
        projectId: String,
        unitType: String? = nil,
        facing: String? = nil,
        status: String? = nil
    ) async throws -> [InventoryUnit] {
        var items = [URLQueryItem(name: "projectId", value: projectId)]
        if let unitType, !unitType.isEmpty { items.append(URLQueryItem(name: "unitType", value: unitType)) }
        if let facing, !facing.isEmpty { items.append(URLQueryItem(name: "facing", value: facing)) }
        if let status, !status.isEmpty { items.append(URLQueryItem(name: "status", value: status)) }
        let data = try await get(path: "/api/marketing/inventory-units", token: token, queryItems: items)
        let wrapper = try decode(InventoryUnitsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load units") }
        return wrapper.units ?? []
    }

    static func getInventoryUnit(token: String, id: String) async throws -> InventoryUnit {
        let data = try await get(
            path: "/api/marketing/inventory-units/get",
            token: token,
            queryItems: [URLQueryItem(name: "id", value: id)]
        )
        let wrapper = try decode(InventoryUnitResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load unit") }
        guard let unit = wrapper.unit else { throw MarketingAPIError.server("Unit not found") }
        return unit
    }

    static func holdInventoryUnit(token: String, id: String) async throws -> InventoryUnit {
        let data = try await post(
            path: "/api/marketing/inventory-units/hold",
            token: token,
            body: InventoryUnitIdRequest(id: id)
        )
        let wrapper = try decode(InventoryUnitResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to hold unit") }
        guard let unit = wrapper.unit else { throw MarketingAPIError.server("Updated unit missing") }
        return unit
    }

    static func releaseInventoryUnit(token: String, id: String) async throws -> InventoryUnit {
        let data = try await post(
            path: "/api/marketing/inventory-units/release",
            token: token,
            body: InventoryUnitIdRequest(id: id)
        )
        let wrapper = try decode(InventoryUnitResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to release unit") }
        guard let unit = wrapper.unit else { throw MarketingAPIError.server("Updated unit missing") }
        return unit
    }

    static func getInventoryLayout(token: String, projectId: String) async throws -> [InventoryUnit] {
        let data = try await get(
            path: "/api/marketing/inventory-units/layout",
            token: token,
            queryItems: [URLQueryItem(name: "projectId", value: projectId)]
        )
        let wrapper = try decode(InventoryLayoutResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load layout") }
        return wrapper.units ?? []
    }

    // MARK: - Booking / Leads

    static func searchTelecallerLeadsByPhone(token: String, phone: String) async throws -> [TelecallerLeadSearchData] {
        let data = try await get(
            path: "/api/telecaller/leads/search-by-phone",
            token: token,
            queryItems: [URLQueryItem(name: "phone", value: phone)]
        )
        let wrapper = try decode(TelecallerLeadSearchResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Lead search failed") }
        return wrapper.leads ?? []
    }

    static func createBooking(token: String, request: CreateBookingRequest) async throws -> String {
        let data = try await post(path: "/api/bookings", token: token, body: request)
        let wrapper = try decode(CreateBookingResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to create booking") }
        return wrapper.id ?? ""
    }

    static func createCpVisit(token: String, request: CreateCpVisitRequest) async throws -> CreateCpVisitResponse {
        let data = try await post(path: "/api/marketing/clientPlaceVisits/create", token: token, body: request)
        let wrapper = try decode(CreateCpVisitResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to create CP visit") }
        return wrapper
    }

    // MARK: - HTTP

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
            if http.statusCode == 401 { throw MarketingAPIError.unauthorized }
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

enum MarketingAPIError: LocalizedError {
    case badURL
    case unauthorized
    case server(String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL"
        case .unauthorized: return "Session expired. Please sign in again."
        case .server(let message): return message
        case .decoding(let error): return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
