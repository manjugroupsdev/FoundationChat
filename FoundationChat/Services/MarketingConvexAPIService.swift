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

    private struct BookingsResponse: Decodable {
        let success: Bool
        let total: Int?
        let bookings: [AppBooking]?
        let error: String?
    }

    private struct BookingResponse: Decodable {
        let success: Bool
        let booking: AppBooking?
        let error: String?
    }

    private struct BaseMutationResponse: Decodable {
        let success: Bool
        let error: String?
    }

    private struct InventoryUnitIdRequest: Encodable {
        let id: String
    }

    private struct IdRequest: Encodable {
        let id: String
    }

    private struct RejectBookingRequest: Encodable {
        let reason: String
    }

    private struct EmptyRequest: Encodable {}

    private struct CreateLoanRequest: Encodable {
        let staffId: String?
        let nomineeStaffId: String?
        let nominee1Id: String?
        let nominee1Name: String?
        let nominee2Id: String?
        let nominee2Name: String?
        let loanAmount: Double?
        let interestType: String?
        let disbursedDate: String?
        let repaymentStartMonth: String?
        let tenureMonths: Double?
        let submittedDocument: String?
        let originalDocument: String?
        let purpose: String?
        let notes: String?
    }

    private struct CreateSalaryAdvanceRequest: Encodable {
        let amount: Double
        let purpose: String?
    }

    private struct LoanMutationResponse: Decodable {
        let success: Bool
        let id: String?
        let loanId: String?
        let error: String?
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

    @discardableResult
    static func createLoanRequest(
        token: String,
        staffId: String?,
        nomineeStaffId: String?,
        nominee1Id: String? = nil,
        nominee1Name: String? = nil,
        nominee2Id: String? = nil,
        nominee2Name: String? = nil,
        loanAmount: Double,
        interestType: String? = nil,
        disbursedDate: String,
        repaymentStartMonth: String,
        tenureMonths: Int,
        submittedDocument: String,
        purpose: String,
        notes: String? = nil
    ) async throws -> String {
        let request = CreateLoanRequest(
            staffId: staffId,
            nomineeStaffId: nomineeStaffId,
            nominee1Id: nominee1Id,
            nominee1Name: nominee1Name,
            nominee2Id: nominee2Id,
            nominee2Name: nominee2Name,
            loanAmount: loanAmount,
            interestType: interestType,
            disbursedDate: disbursedDate,
            repaymentStartMonth: repaymentStartMonth,
            tenureMonths: Double(tenureMonths),
            submittedDocument: submittedDocument,
            originalDocument: submittedDocument,
            purpose: purpose,
            notes: notes
        )
        let data = try await post(path: "/api/hr/loans/apply", token: token, body: request)
        let wrapper = try decode(LoanMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to submit loan request") }
        return wrapper.id ?? wrapper.loanId ?? ""
    }

    @discardableResult
    static func createSalaryAdvanceRequest(
        token: String,
        amount: Double,
        purpose: String?
    ) async throws -> String {
        let request = CreateLoanRequest(
            staffId: nil,
            nomineeStaffId: nil,
            nominee1Id: nil,
            nominee1Name: nil,
            nominee2Id: nil,
            nominee2Name: nil,
            loanAmount: amount,
            interestType: "Salary Advance",
            disbursedDate: nil,
            repaymentStartMonth: nil,
            tenureMonths: nil,
            submittedDocument: nil,
            originalDocument: nil,
            purpose: purpose?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? purpose : "Salary Advance",
            notes: nil
        )
        let data = try await post(path: "/api/hr/loans/apply", token: token, body: request)
        let wrapper = try decode(LoanMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to submit salary advance") }
        return wrapper.id ?? wrapper.loanId ?? ""
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

    static func saveBookingDraft<T: Encodable>(token: String, payload: T) async throws {
        _ = try await post(path: "/api/bookings/draft/save", token: token, body: payload)
    }

    static func clearBookingDraft(token: String, source: String = "walk_in") async throws {
        struct ClearDraftRequest: Encodable {
            let source: String
        }
        _ = try await post(path: "/api/bookings/draft/clear", token: token, body: ClearDraftRequest(source: source))
    }

    static func listBookings(token: String, status: String? = nil, query: String? = nil) async throws -> [AppBooking] {
        var items: [URLQueryItem] = []
        if let status, !status.isEmpty, status != "all" {
            items.append(URLQueryItem(name: "status", value: status))
        }
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        let data = try await get(path: "/api/bookings", token: token, queryItems: items)
        let wrapper = try decode(BookingsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load bookings") }
        return wrapper.bookings ?? []
    }

    static func getBooking(token: String, id: String) async throws -> AppBooking {
        let data = try await get(path: "/api/bookings/\(pathComponent(id))", token: token)
        let wrapper = try decode(BookingResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load booking") }
        guard let booking = wrapper.booking else { throw MarketingAPIError.server("Booking not found") }
        return booking
    }

    static func updateBooking(token: String, request: UpdateBookingRequest) async throws {
        let data = try await patch(path: "/api/bookings/\(pathComponent(request.id))", token: token, body: request)
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to update booking") }
    }

    static func approveBooking(token: String, id: String) async throws {
        let data = try await post(path: "/api/bookings/\(pathComponent(id))/approve", token: token, body: EmptyRequest())
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to approve booking") }
    }

    static func rejectBooking(token: String, id: String, reason: String) async throws {
        let data = try await post(path: "/api/bookings/\(pathComponent(id))/reject", token: token, body: RejectBookingRequest(reason: reason))
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to reject booking") }
    }

    static func createCpVisit(token: String, request: CreateCpVisitRequest) async throws -> CreateCpVisitResponse {
        let data = try await post(path: "/api/marketing/clientPlaceVisits/create", token: token, body: request)
        let wrapper = try decode(CreateCpVisitResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to create CP visit") }
        return wrapper
    }

    static func markClientMet(token: String, request: MarkClientMetRequest) async throws {
        let data = try await post(path: "/api/marketing/clientPlaceVisits/markClientMet", token: token, body: request)
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to record client met") }
    }

    static func setCpVisitOutcome(token: String, request: SetCpVisitOutcomeRequest) async throws {
        let data = try await post(path: "/api/marketing/clientPlaceVisits/setOutcome", token: token, body: request)
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to set outcome") }
    }

    static func setSiteVisitOutcome(token: String, request: SetSiteVisitOutcomeRequest) async throws {
        let data = try await post(path: "/api/marketing/siteVisits/setOutcome", token: token, body: request)
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to set site visit outcome") }
    }

    static func convertCpVisitToSiteVisit(
        token: String,
        request: ConvertCpVisitToSiteVisitRequest
    ) async throws -> ConvertCpVisitToSiteVisitResponse {
        let data = try await post(path: "/api/marketing/clientPlaceVisits/convertToSiteVisit", token: token, body: request)
        let wrapper = try decode(ConvertCpVisitToSiteVisitResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to create site visit") }
        return wrapper
    }

    static func getCpVisitDetail(token: String, id: String) async throws -> CpVisitDetail {
        let data = try await get(
            path: "/api/marketing/clientPlaceVisits/get",
            token: token,
            queryItems: [URLQueryItem(name: "id", value: id)]
        )
        let wrapper = try decode(CpVisitDetailResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load visit detail") }
        guard let visit = wrapper.visit else { throw MarketingAPIError.server("Visit detail missing") }
        return visit
    }

    static func getMyMarketingCpVisits(
        token: String,
        fromDate: String? = nil,
        toDate: String? = nil
    ) async throws -> [CpVisitDetail] {
        var items: [URLQueryItem] = []
        if let fromDate, !fromDate.isEmpty {
            items.append(URLQueryItem(name: "fromDate", value: fromDate))
        }
        if let toDate, !toDate.isEmpty {
            items.append(URLQueryItem(name: "toDate", value: toDate))
        }
        let data = try await get(path: "/api/marketing/clientPlaceVisits/my", token: token, queryItems: items)
        let wrapper = try decode(MyMarketingCpVisitsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load CP visits") }
        return wrapper.visits
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

    private static func patch<T: Encodable>(path: String, token: String, body: T) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw MarketingAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
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
