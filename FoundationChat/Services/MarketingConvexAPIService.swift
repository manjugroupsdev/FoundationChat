import Foundation

struct StaffDigitalSign: Decodable, Sendable {
    let success: Bool
    let hasSignature: Bool
    let storageId: String?
    let url: String?
    let fileName: String?
    let error: String?
}

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

    private struct MarketingProjectResponse: Decodable {
        let success: Bool
        let project: MarketingProject?
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

    private struct ClientByPhoneResponse: Decodable {
        let success: Bool
        let client: BookingClientProfile?
        let error: String?
    }

    private struct BookingConversionPrefillResponse: Decodable {
        let success: Bool
        let prefill: BookingConversionPrefill?
        let error: String?
    }

    private struct BookingExchangeSourcesResponse: Decodable {
        let success: Bool
        let bookings: [BookingExchangeSource]?
        let error: String?
    }

    private struct PincodeResponse: Decodable {
        let postOffices: [PincodeOffice]?

        enum CodingKeys: String, CodingKey {
            case postOffices = "PostOffice"
        }
    }

    private struct PincodeOffice: Decodable {
        let name: String?
        let district: String?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case district = "District"
            case state = "State"
        }
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

    private struct RejectLoanRequest: Encodable {
        let id: String
        let reason: String
    }

    private struct ApproveLoanRequest: Encodable {
        let id: String
        let eSignatureId: String?
    }

    private struct DigitalSignRequest: Encodable {
        let storageId: String
        let fileName: String?
    }

    private struct RejectBookingRequest: Encodable {
        let reason: String
    }

    private struct CpGeofenceRemarkRequest: Encodable {
        let id: String
        let remark: String
    }

    private struct CpApprovalRejectRequest: Encodable {
        let id: String
        let remark: String
    }

    private struct CancelCpVisitRequest: Encodable {
        let id: String
        let reason: String?
    }

    private struct CpApprovalsResponse: Decodable {
        let success: Bool
        let items: [CpApprovalItem]?
        let error: String?
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

    static func getPendingLoanApprovals(token: String) async throws -> [AppLoan] {
        let data = try await get(path: "/api/hr/loans/pending-approvals", token: token)
        let wrapper = try decode(MyLoansResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load pending approvals") }
        return AppLoanMapper.mapLoanList(wrapper.pending ?? [], status: .pending)
            + AppLoanMapper.mapLoanList(wrapper.active ?? [], status: .pending)
            + AppLoanMapper.mapLoanList(wrapper.previous ?? [], status: .repaid)
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

    static func cancelLoan(token: String, id: String) async throws {
        let data = try await post(path: "/api/hr/loans/cancel", token: token, body: IdRequest(id: id))
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to cancel loan") }
    }

    static func approveLoan(token: String, id: String, eSignatureId: String? = nil) async throws {
        let data = try await post(
            path: "/api/hr/loans/approve",
            token: token,
            body: ApproveLoanRequest(id: id, eSignatureId: eSignatureId)
        )
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to approve loan") }
    }

    static func getDigitalSign(token: String) async throws -> StaffDigitalSign {
        let data = try await get(path: "/api/hr/staff/digital-sign", token: token)
        let wrapper = try decode(StaffDigitalSign.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Failed to load digital signature")
        }
        return wrapper
    }

    static func saveDigitalSign(token: String, storageId: String, fileName: String) async throws {
        let data = try await post(
            path: "/api/hr/staff/digital-sign",
            token: token,
            body: DigitalSignRequest(storageId: storageId, fileName: fileName)
        )
        let wrapper = try decode(StaffDigitalSign.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Failed to save digital signature")
        }
    }

    static func digitalSignPreviewURL(_ signature: StaffDigitalSign) -> URL? {
        if let storageId = signature.storageId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !storageId.isEmpty,
           var components = URLComponents(string: "\(baseURL)/api/storage/serve") {
            components.queryItems = [URLQueryItem(name: "storageId", value: storageId)]
            return components.url
        }
        guard let rawURL = signature.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty else { return nil }
        return URL(string: rawURL)
    }

    static func rejectLoan(token: String, id: String, reason: String = "Rejected by approver") async throws {
        let data = try await post(path: "/api/hr/loans/reject", token: token, body: RejectLoanRequest(id: id, reason: reason))
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to reject loan") }
    }

    // MARK: - Projects / Inventory

    static func getMarketingProjects(token: String) async throws -> [MarketingProject] {
        let data = try await get(path: "/api/marketing/projects", token: token)
        let wrapper: MarketingProjectsResponse
        do {
            wrapper = try await BackgroundJSONDecoder.decode(
                MarketingProjectsResponse.self,
                from: data
            )
        } catch {
            throw MarketingAPIError.decoding(error)
        }
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load projects") }
        return wrapper.projects ?? []
    }

    static func getMarketingProject(token: String, id: String) async throws -> MarketingProject {
        let data = try await get(
            path: "/api/projects/get",
            token: token,
            queryItems: [URLQueryItem(name: "id", value: id)],
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let wrapper = try decode(MarketingProjectResponse.self, from: data)
        guard wrapper.success, let project = wrapper.project else {
            throw MarketingAPIError.server(wrapper.error ?? "Failed to load project details")
        }
        return project
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
        let data = try await get(
            path: "/api/marketing/inventory-units",
            token: token,
            queryItems: items,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
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

    static func searchClientByPhone(token: String, phone: String) async throws -> BookingClientProfile? {
        let data = try await get(
            path: "/api/clients/search-by-phone",
            token: token,
            queryItems: [URLQueryItem(name: "phone", value: phone)]
        )
        let wrapper = try decode(ClientByPhoneResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Client search failed") }
        return wrapper.client
    }

    static func getBookingPlotPrefill(
        token: String,
        plotId: String,
        bookingDate: String?
    ) async throws -> BookingPlotPrefill {
        var queryItems = [URLQueryItem(name: "plotId", value: plotId)]
        if let bookingDate, !bookingDate.isEmpty {
            queryItems.append(URLQueryItem(name: "bookingDate", value: bookingDate))
        }
        let data = try await get(
            path: "/api/bookings/plot-prefill",
            token: token,
            queryItems: queryItems
        )
        let prefill = try decode(BookingPlotPrefill.self, from: data)
        guard prefill.success else {
            throw MarketingAPIError.server(prefill.error ?? "Plot pricing lookup failed")
        }
        return prefill
    }

    static func getBookingConversionPrefill(
        token: String,
        mobileNumber: String
    ) async throws -> BookingConversionPrefill? {
        let data = try await get(
            path: "/api/bookings/conversion-prefill",
            token: token,
            queryItems: [URLQueryItem(name: "mobileNumber", value: mobileNumber)],
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let wrapper = try decode(BookingConversionPrefillResponse.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Previous booking lookup failed")
        }
        return wrapper.prefill
    }

    static func listBookingExchangeSourceCandidates(
        token: String,
        mobileNumber: String
    ) async throws -> [BookingExchangeSource] {
        let data = try await get(
            path: "/api/bookings/exchange-source-candidates",
            token: token,
            queryItems: [URLQueryItem(name: "mobileNumber", value: mobileNumber)],
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let wrapper = try decode(BookingExchangeSourcesResponse.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Exchanged property lookup failed")
        }
        return wrapper.bookings ?? []
    }

    static func lookupPincode(token: String, pincode: String) async throws -> BookingPincodePrefill? {
        guard pincode.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else { return nil }
        let data = try await get(
            path: "/api/pincode",
            token: token,
            queryItems: [URLQueryItem(name: "pin", value: pincode)],
            cachePolicy: .returnCacheDataElseLoad
        )
        let responses = try decode([PincodeResponse].self, from: data)
        guard let offices = responses.first?.postOffices, !offices.isEmpty else { return nil }

        func firstValue(_ keyPath: KeyPath<PincodeOffice, String?>, excludingNA: Bool = false) -> String? {
            offices.lazy.compactMap { office -> String? in
                guard let value = office[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty,
                      !(excludingNA && value.caseInsensitiveCompare("NA") == .orderedSame) else { return nil }
                return value
            }.first
        }

        let locality = firstValue(\.name, excludingNA: true)?
            .replacingOccurrences(
                of: #"\s+(S\.O\.|B\.O\.|H\.O\.|GPO|HPO|SO|BO|HO)\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return BookingPincodePrefill(
            locality: locality,
            district: firstValue(\.district),
            state: firstValue(\.state)
        )
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

    /// GET /api/bookings/draft/get — resume an in-progress booking form.
    /// Returns nil when the caller has no saved draft for `sourceKey`.
    static func getBookingDraft(token: String, sourceKey: String) async throws -> BookingDraftPayload? {
        let data = try await get(
            path: "/api/bookings/draft/get",
            token: token,
            queryItems: [URLQueryItem(name: "sourceKey", value: sourceKey)],
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let wrapper = try decode(BookingDraftGetResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load draft") }
        return wrapper.draft
    }

    static func clearBookingDraft(token: String, sourceKey: String = "walk_in") async throws {
        struct ClearDraftRequest: Encodable {
            let sourceKey: String
        }
        _ = try await post(path: "/api/bookings/draft/clear", token: token, body: ClearDraftRequest(sourceKey: sourceKey))
    }

    static func listBookings(token: String, status: String? = nil, query: String? = nil) async throws -> [AppBooking] {
        var items: [URLQueryItem] = []
        if let status, !status.isEmpty, status != "all" {
            items.append(URLQueryItem(name: "status", value: status))
        }
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        let data = try await get(path: "/api/marketing/bookings/my", token: token, queryItems: items)
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

    static func parseAddress(token: String, raw: String) async throws -> ParsedAddressFields {
        let data = try await post(
            path: "/api/address/parse",
            token: token,
            body: AddressParseRequest(raw: raw)
        )
        let wrapper = try decode(AddressParseResponse.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Could not split address")
        }
        guard let fields = wrapper.fields else {
            throw MarketingAPIError.server("Address fields missing")
        }
        return fields
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

    /// Cancels a CP visit outright (separate endpoint from setOutcome). Used by
    /// the SV-cum-CP "Cancel" outcome. Mirrors setCpVisitOutcome's request/decode.
    static func cancelCpVisit(token: String, id: String, reason: String?) async throws {
        let data = try await post(
            path: "/api/marketing/clientPlaceVisits/cancel",
            token: token,
            body: CancelCpVisitRequest(id: id, reason: reason)
        )
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to cancel CP visit") }
    }

    // MARK: - Out-of-geofence CP completion (GM approval)

    /// Stashes the staff's out-of-geofence reason on the visit (shown to the approving GM).
    static func setCpGeofenceRemark(token: String, id: String, remark: String) async throws {
        let data = try await post(
            path: "/api/marketing/cp-visits/geofence-remark",
            token: token,
            body: CpGeofenceRemarkRequest(id: id, remark: remark)
        )
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to save geofence remark") }
    }

    static func getPendingCpApprovals(token: String) async throws -> [CpApprovalItem] {
        let data = try await get(path: "/api/marketing/cp-visits/pending-approvals", token: token)
        let wrapper = try decode(CpApprovalsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load pending approvals") }
        return wrapper.items ?? []
    }

    static func approveCpCompletion(token: String, id: String) async throws {
        let data = try await post(path: "/api/marketing/cp-visits/approve", token: token, body: IdRequest(id: id))
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to approve completion") }
    }

    static func rejectCpCompletion(token: String, id: String, remark: String) async throws {
        let data = try await post(
            path: "/api/marketing/cp-visits/reject",
            token: token,
            body: CpApprovalRejectRequest(id: id, remark: remark)
        )
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to reject completion") }
    }

    static func setSiteVisitOutcome(token: String, request: SetSiteVisitOutcomeRequest) async throws {
        let data = try await post(path: "/api/marketing/siteVisits/setOutcome", token: token, body: request)
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to set site visit outcome") }
    }

    static func scanSiteVisitQR(token: String, qrData: String) async throws -> ScannedSiteVisit {
        let data = try await post(
            path: "/api/marketing/siteVisits/scanQr",
            token: token,
            body: SiteVisitQRScanRequest(qrData: qrData)
        )
        let wrapper = try decode(SiteVisitQRScanResponse.self, from: data)
        guard wrapper.success, let visit = wrapper.visit else {
            throw MarketingAPIError.server(wrapper.error ?? "Unable to validate this SV QR")
        }
        return visit
    }

    /// Best-effort unlock before a manual outcome close. `setOutcome` only accepts a
    /// visit in on_counselling|picked_from_site|dropped, so advance on-site visits first.
    static func markSiteVisitOnCounselling(token: String, id: String) async throws {
        let data = try await post(
            path: "/api/marketing/siteVisits/markOnCounselling",
            token: token,
            body: SiteVisitIDRequest(id: id)
        )
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Couldn't start counselling")
        }
    }

    static func postponeSiteVisit(token: String, request: PostponeSiteVisitRequest) async throws {
        let data = try await post(
            path: "/api/marketing/siteVisits/postpone",
            token: token,
            body: request
        )
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Unable to postpone site visit")
        }
    }

    static func cancelSiteVisit(token: String, request: CancelSiteVisitRequest) async throws {
        let data = try await post(
            path: "/api/marketing/siteVisits/cancel",
            token: token,
            body: request
        )
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Unable to cancel site visit")
        }
    }

    static func markSiteVisitPickedUp(token: String, id: String) async throws {
        try await runSiteVisitLifecycle(path: "/api/marketing/siteVisits/markPickedUp", token: token, id: id)
    }

    static func markSiteVisitClientStarted(token: String, id: String) async throws {
        try await runSiteVisitLifecycle(path: "/api/marketing/siteVisits/markClientStarted", token: token, id: id)
    }

    static func markSiteVisitArrivedSite(token: String, id: String) async throws {
        try await runSiteVisitLifecycle(path: "/api/marketing/siteVisits/markArrivedSite", token: token, id: id)
    }

    static func markSiteVisitPickedFromSite(token: String, id: String) async throws {
        try await runSiteVisitLifecycle(path: "/api/marketing/siteVisits/markPickedFromSite", token: token, id: id)
    }

    static func markSiteVisitDropped(token: String, id: String) async throws {
        try await runSiteVisitLifecycle(path: "/api/marketing/siteVisits/markDropped", token: token, id: id)
    }

    private static func runSiteVisitLifecycle(path: String, token: String, id: String) async throws {
        let data = try await post(path: path, token: token, body: IdRequest(id: id))
        let wrapper = try decode(BaseMutationResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to update site visit status") }
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

    static func convertSiteVisitToBooking(
        token: String,
        request: ConvertSiteVisitToBookingRequest
    ) async throws -> ConvertSiteVisitToBookingResponse {
        let data = try await post(
            path: "/api/marketing/siteVisits/convertToBooking",
            token: token,
            body: request
        )
        let wrapper = try decode(ConvertSiteVisitToBookingResponse.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Failed to convert site visit to booking")
        }
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
        toDate: String? = nil,
        scope: String = "all",
        limit: Int? = nil,
        search: String? = nil
    ) async throws -> [CpVisitDetail] {
        var items = [URLQueryItem(name: "scope", value: scope)]
        if let fromDate, !fromDate.isEmpty {
            items.append(URLQueryItem(name: "fromDate", value: fromDate))
        }
        if let toDate, !toDate.isEmpty {
            items.append(URLQueryItem(name: "toDate", value: toDate))
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        let data = try await get(path: "/api/marketing/clientPlaceVisits/my", token: token, queryItems: items)
        let wrapper = try decode(MyMarketingCpVisitsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load CP visits") }
        return wrapper.visits
    }

    // MARK: - HTTP

    private static func get(
        path: String,
        token: String,
        queryItems: [URLQueryItem] = [],
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> Data {
        var components = URLComponents(string: "\(baseURL)\(path)")
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw MarketingAPIError.badURL }
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
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

/// One out-of-geofence CP completion awaiting GM approval. Mirrors Android
/// `GeoTrackApi.CpApprovalItem`. Powers the GM approval queue (UI is a later slice).
struct CpApprovalItem: Codable, Identifiable, Sendable {
    let id: String
    let outcome: String?
    let notes: String?
    let cpType: String?
    let clientName: String?
    let staffName: String?
    let staffId: String?
    let placeName: String?
    let placeAddress: String?
    let distanceMeters: Double?
    let completionLat: Double?
    let completionLng: Double?
    let staffRemark: String?
    let photoUrl: String?
    let requestedAt: Double?
    let scheduledDate: String?
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
