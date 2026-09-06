import Foundation
import UniformTypeIdentifiers

struct PostSalesUploadedFile: Codable, Sendable, Equatable {
    let storageId: String
    let fileName: String
    let mimeType: String
    let fileSize: Int
}

enum PostSalesStorageService {
    private struct GenerateUploadURLResponse: Decodable {
        let success: Bool
        let uploadUrl: String?
        let error: String?
    }

    private struct UploadFileResponse: Decodable {
        let storageId: String
    }

    private struct GetFileURLResponse: Decodable {
        let success: Bool
        let url: String?
        let error: String?
    }

    static func uploadFile(token: String, fileURL: URL) async throws -> PostSalesUploadedFile {
        let access = fileURL.startAccessingSecurityScopedResource()
        defer {
            if access { fileURL.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: fileURL)
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let storageId = try await uploadData(token: token, data: data, mimeType: mimeType)
        return PostSalesUploadedFile(
            storageId: storageId,
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType,
            fileSize: data.count
        )
    }

    static func uploadData(token: String, data: Data, mimeType: String = "image/jpeg") async throws -> String {
        let uploadURL = try await generateUploadURL(token: token)
        guard let url = URL(string: uploadURL) else { throw MarketingAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketingAPIError.server("File upload failed")
        }
        let wrapper = try JSONDecoder().decode(UploadFileResponse.self, from: responseData)
        return wrapper.storageId
    }

    static func getFileURL(token: String, storageId: String) async throws -> URL {
        let data = try await get(
            path: "/api/storage/get-url",
            token: token,
            queryItems: [URLQueryItem(name: "storageId", value: storageId)]
        )
        let wrapper = try JSONDecoder().decode(GetFileURLResponse.self, from: data)
        guard wrapper.success, let urlString = wrapper.url, let url = URL(string: urlString) else {
            throw MarketingAPIError.server(wrapper.error ?? "Failed to load file preview")
        }
        return url
    }

    private static func generateUploadURL(token: String) async throws -> String {
        let data = try await post(path: "/api/storage/generate-upload-url", token: token, body: EmptyBody())
        let wrapper = try JSONDecoder().decode(GenerateUploadURLResponse.self, from: data)
        guard wrapper.success, let uploadUrl = wrapper.uploadUrl else {
            throw MarketingAPIError.server(wrapper.error ?? "Failed to prepare upload")
        }
        return uploadUrl
    }

    private static func get(path: String, token: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: "\(AppConfig.baseURL)\(path)")
        components?.queryItems = queryItems
        guard let url = components?.url else { throw MarketingAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private static func post<T: Encodable>(path: String, token: String, body: T) async throws -> Data {
        guard let url = URL(string: "\(AppConfig.baseURL)\(path)") else { throw MarketingAPIError.badURL }
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
                SessionInvalidationBus.emit(for: request, responseData: data)
                throw MarketingAPIError.unauthorized
            }
            guard (200..<300).contains(http.statusCode) else {
                // The error body is {success: false, error: "..."} — a MIXED-type
                // object (bool + string), so decoding it as [String: String] fails
                // and the real reason was lost behind a generic "Request failed
                // (500)". Parse loosely and pull just the string `error`, matching
                // MarketingConvexAPIService. This surfaces the backend's real
                // message (e.g. a collection "no outstanding balance" / scope /
                // workflow error) instead of an opaque 500.
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String, !error.isEmpty {
                    throw MarketingAPIError.server(error)
                }
                throw MarketingAPIError.server("Request failed (\(http.statusCode))")
            }
        }
        return data
    }

    private struct EmptyBody: Encodable {}
}

enum PostSalesConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    private struct CasesByMobileResponse: Decodable {
        let success: Bool
        let cases: [PostSaleCaseSummary]?
        let error: String?
    }

    private struct CollectionsResponse: Decodable {
        let success: Bool
        let collections: [CustomerCollectionRow]?
        let error: String?
    }

    private struct SubmitCollectionResponse: Decodable {
        let success: Bool
        let collectionId: String?
        let collectionRefNo: String?
        let alreadySubmitted: Bool?
        let error: String?
    }

    struct SubmittedCollection: Sendable {
        let reference: String
        let alreadySubmitted: Bool
    }

    private struct VerifyCollectionResponse: Decodable {
        let success: Bool
        let collection: CustomerCollectionRow?
        let error: String?
    }

    private struct LoanDeskCasesResponse: Decodable {
        let success: Bool
        let cases: [LoanCaseRow]?
        let error: String?
    }

    private struct LegalStaffListResponse: Decodable {
        let success: Bool
        let staff: [LegalStaffRow]?
        let error: String?
    }

    private struct LoanCaseEnvelope: Decodable {
        let success: Bool
        let loanCase: LoanCaseRow?
        let error: String?
    }

    private struct ApproveCollectionRequest: Encodable {
        let collectionId: String
        let notes: String?
    }

    private struct RejectCollectionRequest: Encodable {
        let collectionId: String
        let remarks: String
    }

    private struct LoanCaseIdBody: Encodable {
        let loanCaseId: String
    }

    private struct LegalRejectLoanRequest: Encodable {
        let loanCaseId: String
        let remarks: String
    }

    static func getCasesByMobile(token: String, mobile: String) async throws -> [PostSaleCaseSummary] {
        let data = try await get(
            path: "/api/postsales/cases/byMobile",
            token: token,
            queryItems: [URLQueryItem(name: "mobile", value: mobile)]
        )
        let wrapper = try await decode(CasesByMobileResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load cases") }
        return wrapper.cases ?? []
    }

    static func listOpenBookings(token: String) async throws -> [PostSaleCaseSummary] {
        let data = try await get(path: "/api/postsales/cases/list", token: token)
        let wrapper = try await decode(CasesByMobileResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load open cases") }
        return wrapper.cases ?? []
    }

    static func listMyCollections(token: String) async throws -> [CustomerCollectionRow] {
        let data = try await get(path: "/api/postsales/collections/my", token: token)
        let wrapper = try await decode(CollectionsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load collections") }
        return wrapper.collections ?? []
    }

    static func listCollectionsForAccounts(token: String) async throws -> [CustomerCollectionRow] {
        let data = try await get(path: "/api/postsales/collections/for-accounts", token: token)
        let wrapper = try await decode(CollectionsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load account collections") }
        return wrapper.collections ?? []
    }

    @discardableResult
    static func submitCollection(token: String, request: SubmitCollectionRequest) async throws -> SubmittedCollection {
        let data = try await post(path: "/api/postsales/collections/submit", token: token, body: request)
        let wrapper = try await decode(SubmitCollectionResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to submit collection") }
        return SubmittedCollection(
            reference: wrapper.collectionRefNo ?? wrapper.collectionId ?? "",
            alreadySubmitted: wrapper.alreadySubmitted == true
        )
    }

    /// POST /api/postsales/collections/correct — collector edits their own
    /// still-pending collection before Accounts acts on it. Only the changed
    /// fields are sent; the server rejects a correction once verified.
    @discardableResult
    static func correctCollection(token: String, request: CorrectCollectionRequest) async throws -> CustomerCollectionRow? {
        let data = try await post(path: "/api/postsales/collections/correct", token: token, body: request)
        let wrapper = try await decode(VerifyCollectionResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to correct collection") }
        return wrapper.collection
    }

    static func approveCollection(token: String, collectionId: String, notes: String? = nil) async throws -> CustomerCollectionRow? {
        let data = try await post(
            path: "/api/postsales/collections/approve",
            token: token,
            body: ApproveCollectionRequest(collectionId: collectionId, notes: notes)
        )
        let wrapper = try await decode(VerifyCollectionResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to approve collection") }
        return wrapper.collection
    }

    static func rejectCollection(token: String, collectionId: String, remarks: String) async throws -> CustomerCollectionRow? {
        let data = try await post(
            path: "/api/postsales/collections/reject",
            token: token,
            body: RejectCollectionRequest(collectionId: collectionId, remarks: remarks)
        )
        let wrapper = try await decode(VerifyCollectionResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to reject collection") }
        return wrapper.collection
    }

    static func listLoanDeskForSales(token: String) async throws -> [LoanCaseRow] {
        try await listLoanDesk(path: "/api/postsales/loans/forSales", token: token)
    }

    static func listLoanDeskForLegalManager(token: String) async throws -> [LoanCaseRow] {
        try await listLoanDesk(path: "/api/postsales/loans/forLegalManager", token: token)
    }

    static func listLoanDeskForLegalTeam(token: String) async throws -> [LoanCaseRow] {
        try await listLoanDesk(path: "/api/postsales/loans/forLegalTeam", token: token)
    }

    static func listLegalStaff(token: String) async throws -> [LegalStaffRow] {
        let data = try await get(path: "/api/postsales/loans/legalStaff", token: token)
        let wrapper = try await decode(LegalStaffListResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load legal staff") }
        return wrapper.staff ?? []
    }

    @discardableResult
    static func submitLoanRequest(token: String, request: SubmitLoanDeskRequest) async throws -> LoanCaseRow? {
        let data = try await post(path: "/api/postsales/loans/submit", token: token, body: request)
        let wrapper = try await decode(LoanCaseEnvelope.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to submit loan case") }
        return wrapper.loanCase
    }

    static func uploadLoanDocument(
        token: String,
        loanCaseId: String,
        label: String,
        fileURL: URL,
        requestId: String
    ) async throws -> UploadLoanDocumentResponse {
        let access = fileURL.startAccessingSecurityScopedResource()
        defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
        let fileData = try Data(contentsOf: fileURL)
        guard !fileData.isEmpty else { throw MarketingAPIError.server("The selected document is empty.") }
        guard fileData.count <= 20 * 1024 * 1024 else { throw MarketingAPIError.server("Documents must be 20 MB or smaller.") }

        let boundary = "MConnect-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        func appendField(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        appendField("loanCaseId", loanCaseId)
        appendField("label", label)
        appendField("requestId", requestId)
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        guard let url = URL(string: "\(baseURL)/api/postsales/loans/upload-document") else {
            throw MarketingAPIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(requestId, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = body
        let data = try await perform(request)
        let wrapper = try await decode(UploadLoanDocumentResponse.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Failed to attach document to loan case")
        }
        return wrapper
    }

    static func deleteLoanDocument(
        token: String,
        request: DeleteLoanDocumentRequest
    ) async throws -> DeleteLoanDocumentResponse {
        let data = try await post(path: "/api/postsales/loans/delete-document", token: token, body: request)
        let wrapper = try await decode(DeleteLoanDocumentResponse.self, from: data)
        guard wrapper.success else {
            throw MarketingAPIError.server(wrapper.error ?? "Failed to delete document")
        }
        return wrapper
    }

    @discardableResult
    static func assignLoan(token: String, request: AssignLoanRequest) async throws -> LoanCaseRow? {
        let data = try await post(path: "/api/postsales/loans/assign", token: token, body: request)
        let wrapper = try await decode(LoanCaseEnvelope.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to assign loan") }
        return wrapper.loanCase
    }

    @discardableResult
    static func legalAcceptLoan(token: String, loanCaseId: String) async throws -> LoanCaseRow? {
        let data = try await post(path: "/api/postsales/loans/accept", token: token, body: LoanCaseIdBody(loanCaseId: loanCaseId))
        let wrapper = try await decode(LoanCaseEnvelope.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to accept loan") }
        return wrapper.loanCase
    }

    @discardableResult
    static func legalRejectLoan(token: String, loanCaseId: String, remarks: String) async throws -> LoanCaseRow? {
        let data = try await post(
            path: "/api/postsales/loans/reject",
            token: token,
            body: LegalRejectLoanRequest(loanCaseId: loanCaseId, remarks: remarks)
        )
        let wrapper = try await decode(LoanCaseEnvelope.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to reject loan") }
        return wrapper.loanCase
    }

    private static func listLoanDesk(path: String, token: String) async throws -> [LoanCaseRow] {
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(LoanDeskCasesResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load loan cases") }
        return wrapper.cases ?? []
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
                SessionInvalidationBus.emit(for: request, responseData: data)
                throw MarketingAPIError.unauthorized
            }
            guard (200..<300).contains(http.statusCode) else {
                // The error body is {success: false, error: "..."} — a MIXED-type
                // object (bool + string), so decoding it as [String: String] fails
                // and the real reason was lost behind a generic "Request failed
                // (500)". Parse loosely and pull just the string `error`, matching
                // MarketingConvexAPIService. This surfaces the backend's real
                // message (e.g. a collection "no outstanding balance" / scope /
                // workflow error) instead of an opaque 500.
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String, !error.isEmpty {
                    throw MarketingAPIError.server(error)
                }
                throw MarketingAPIError.server("Request failed (\(http.statusCode))")
            }
        }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        do {
            return try await BackgroundJSONDecoder.decode(type, from: data)
        } catch {
            throw MarketingAPIError.decoding(error)
        }
    }
}

enum FleetConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    private struct TripsResponse: Decodable {
        let success: Bool
        let trips: [FleetDriverTrip]?
        let error: String?
    }

    private struct ActionResponse: Decodable {
        let success: Bool
        let trip: FleetDriverTrip?
        let error: String?
    }

    private struct SiteVisitRequest: Encodable {
        let siteVisitId: String
    }

    private struct StartRequest: Encodable {
        let siteVisitId: String
        let photoIds: [String]
        let startKm: Double?
    }

    private struct AgencyStartRequest: Encodable {
        let siteVisitId: String
        let otp: String
        let photoIds: [String]
        let startKm: Double?
    }

    private struct EndRequest: Encodable {
        let siteVisitId: String
        let photoIds: [String]
        let endKm: Double?
    }

    static func listDriverTrips(token: String, scope: FleetDispatchScope = .mms) async throws -> [FleetDriverTrip] {
        let path = scope == .agency ? "/api/travel-desk/trips/driver" : "/api/mms-fleet/driver/trips"
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(TripsResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Failed to load trips") }
        return wrapper.trips ?? []
    }

    static func markArrived(token: String, scope: FleetDispatchScope, siteVisitId: String) async throws -> FleetDriverTrip? {
        let path = scope == .agency ? "/api/travel-desk/trips/arrive" : "/api/mms-fleet/driver/arrive"
        return try await action(path: path, token: token, body: SiteVisitRequest(siteVisitId: siteVisitId))
    }

    static func startTrip(token: String, scope: FleetDispatchScope, siteVisitId: String, startKm: Double?, photoIds: [String]) async throws -> FleetDriverTrip? {
        if scope == .agency {
            return try await action(
                path: "/api/travel-desk/trips/start",
                token: token,
                body: AgencyStartRequest(siteVisitId: siteVisitId, otp: "0000", photoIds: photoIds, startKm: startKm)
            )
        }
        return try await startTrip(token: token, siteVisitId: siteVisitId, startKm: startKm, photoIds: photoIds)
    }

    static func markOnSite(token: String, scope: FleetDispatchScope, siteVisitId: String) async throws -> FleetDriverTrip? {
        let path = scope == .agency ? "/api/travel-desk/trips/on-site" : "/api/mms-fleet/driver/on-site"
        return try await action(path: path, token: token, body: SiteVisitRequest(siteVisitId: siteVisitId))
    }

    static func markPickedFromSite(token: String, scope: FleetDispatchScope, siteVisitId: String) async throws -> FleetDriverTrip? {
        let path = scope == .agency ? "/api/travel-desk/trips/picked-from-site" : "/api/mms-fleet/driver/picked-from-site"
        return try await action(path: path, token: token, body: SiteVisitRequest(siteVisitId: siteVisitId))
    }

    static func endTrip(token: String, scope: FleetDispatchScope, siteVisitId: String, endKm: Double?, photoIds: [String]) async throws -> FleetDriverTrip? {
        let path = scope == .agency ? "/api/travel-desk/trips/end" : "/api/mms-fleet/driver/end"
        return try await action(path: path, token: token, body: EndRequest(siteVisitId: siteVisitId, photoIds: photoIds, endKm: endKm))
    }

    static func markArrived(token: String, siteVisitId: String) async throws -> FleetDriverTrip? {
        try await action(path: "/api/mms-fleet/driver/arrive", token: token, body: SiteVisitRequest(siteVisitId: siteVisitId))
    }

    static func startTrip(token: String, siteVisitId: String, startKm: Double?, photoIds: [String] = []) async throws -> FleetDriverTrip? {
        try await action(path: "/api/mms-fleet/driver/start", token: token, body: StartRequest(siteVisitId: siteVisitId, photoIds: photoIds, startKm: startKm))
    }

    static func markOnSite(token: String, siteVisitId: String) async throws -> FleetDriverTrip? {
        try await action(path: "/api/mms-fleet/driver/on-site", token: token, body: SiteVisitRequest(siteVisitId: siteVisitId))
    }

    static func markPickedFromSite(token: String, siteVisitId: String) async throws -> FleetDriverTrip? {
        try await action(path: "/api/mms-fleet/driver/picked-from-site", token: token, body: SiteVisitRequest(siteVisitId: siteVisitId))
    }

    static func endTrip(token: String, siteVisitId: String, endKm: Double?, photoIds: [String] = []) async throws -> FleetDriverTrip? {
        try await action(path: "/api/mms-fleet/driver/end", token: token, body: EndRequest(siteVisitId: siteVisitId, photoIds: photoIds, endKm: endKm))
    }

    private static func action<T: Encodable>(path: String, token: String, body: T) async throws -> FleetDriverTrip? {
        let data = try await post(path: path, token: token, body: body)
        let wrapper = try await decode(ActionResponse.self, from: data)
        guard wrapper.success else { throw MarketingAPIError.server(wrapper.error ?? "Trip action failed") }
        return wrapper.trip
    }

    private static func get(path: String, token: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw MarketingAPIError.badURL }
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
                SessionInvalidationBus.emit(for: request, responseData: data)
                throw MarketingAPIError.unauthorized
            }
            guard (200..<300).contains(http.statusCode) else {
                // The error body is {success: false, error: "..."} — a MIXED-type
                // object (bool + string), so decoding it as [String: String] fails
                // and the real reason was lost behind a generic "Request failed
                // (500)". Parse loosely and pull just the string `error`, matching
                // MarketingConvexAPIService. This surfaces the backend's real
                // message (e.g. a collection "no outstanding balance" / scope /
                // workflow error) instead of an opaque 500.
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String, !error.isEmpty {
                    throw MarketingAPIError.server(error)
                }
                throw MarketingAPIError.server("Request failed (\(http.statusCode))")
            }
        }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        do {
            return try await BackgroundJSONDecoder.decode(type, from: data)
        } catch {
            throw MarketingAPIError.decoding(error)
        }
    }
}
