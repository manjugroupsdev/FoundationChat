import Foundation

// MARK: - HTTP session protocol (enables lightweight mocking without URLProtocol)

protocol GeoTrackHTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: GeoTrackHTTPSession {}

// MARK: - GeoTrack API Error

enum GeoTrackAPIError: LocalizedError {
    case noToken
    case badStatus(Int)
    case serverError(String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No authentication token available."
        case .badStatus(let code):
            return "Server returned HTTP \(code)."
        case .serverError(let msg):
            return "Server error: \(msg)"
        case .decodingFailed(let err):
            return "Failed to decode response: \(err.localizedDescription)"
        }
    }
}

// MARK: - GeoTrack API Service

/// Wraps all 18 Convex HTTP geotrack endpoints.
/// Auth: Bearer token from the active OTP session (same as Android GeoTrackApi.kt).
/// Base URL: AppConfig.baseURL  (e.g. https://opulent-cricket-895.convex.site)
@MainActor
@Observable
final class GeoTrackAPIService {
    static let shared = GeoTrackAPIService()

    // Injected for testing
    var tokenProvider: (() -> String?)?
    var urlSession: any GeoTrackHTTPSession

    private let baseURL: String

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(
        baseURL: String = AppConfig.baseURL,
        tokenProvider: (() -> String?)? = nil,
        urlSession: (any GeoTrackHTTPSession) = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
    }

    // MARK: - Request builder

    private func makeRequest(
        path: String,
        method: String,
        body: (any Encodable)? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func makeGETRequest(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        var components = URLComponents(string: baseURL + path)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeoTrackAPIError.badStatus(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GeoTrackAPIError.badStatus(http.statusCode)
        }
        do {
            let decoded = try decoder.decode(T.self, from: data)
            return decoded
        } catch {
            throw GeoTrackAPIError.decodingFailed(error)
        }
    }

    // MARK: - Tracking Bootstrap / Device Sync

    /// GET /api/tracking/bootstrap?deviceId=...
    func trackingBootstrap(deviceId: String? = nil) async throws -> TrackingBootstrapData? {
        var query: [URLQueryItem] = []
        if let deviceId, !deviceId.isEmpty {
            query.append(URLQueryItem(name: "deviceId", value: deviceId))
        }
        let request = try makeGETRequest(path: "/api/tracking/bootstrap", queryItems: query)
        let result: TrackingBootstrapResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data
    }

    /// POST /api/tracking/device/sync
    func syncTrackingDevice(_ body: TrackingDeviceSyncRequest) async throws -> TrackingDeviceSyncResponse {
        let request = try makeRequest(path: "/api/tracking/device/sync", method: "POST", body: body)
        let result: TrackingDeviceSyncResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result
    }

    // MARK: - Location Tracking

    /// POST /api/geotrack/push-batch
    func pushBatch(points: [GeoTrackLocationPoint]) async throws -> GeoTrackPushBatchResponse {
        let body = GeoTrackPushBatchRequest(points: points)
        let request = try makeRequest(path: "/api/geotrack/push-batch", method: "POST", body: body)
        let result: GeoTrackPushBatchResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result
    }

    /// POST /api/geotrack/start
    func startTracking(lat: Double? = nil, lng: Double? = nil) async throws {
        let body = GeoTrackStartRequest(lat: lat, lng: lng)
        let request = try makeRequest(path: "/api/geotrack/start", method: "POST", body: body)
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    /// POST /api/geotrack/stop
    func stopTracking() async throws {
        let request = try makeRequest(path: "/api/geotrack/stop", method: "POST")
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    // MARK: - Heartbeat

    /// POST /api/geotrack/heartbeat
    func heartbeat(batteryPct: Int, appVersion: String) async throws {
        let body = GeoTrackHeartbeatRequest(batteryPct: batteryPct, appVersion: appVersion)
        let request = try makeRequest(path: "/api/geotrack/heartbeat", method: "POST", body: body)
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    // MARK: - Tamper

    /// POST /api/geotrack/tamper/report
    func reportTamper(
        eventType: GeoTrackTamperEventType,
        metadata: [String: String] = [:]
    ) async throws {
        let body = GeoTrackTamperReportRequest(eventType: eventType, metadata: metadata)
        let request = try makeRequest(path: "/api/geotrack/tamper/report", method: "POST", body: body)
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    /// GET /api/geotrack/tamper/feed?limit=...
    func tamperFeed(limit: Int = 50) async throws -> [GeoTrackTamperEvent] {
        let request = try makeGETRequest(
            path: "/api/geotrack/tamper/feed",
            queryItems: [URLQueryItem(name: "limit", value: "\(limit)")]
        )
        let result: GeoTrackTamperFeedResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
    }

    // MARK: - Consent

    /// POST /api/geotrack/consent
    func recordConsent(consented: Bool = true, appVersion: String) async throws {
        let body = GeoTrackConsentRequest(consented: consented, appVersion: appVersion)
        let request = try makeRequest(path: "/api/geotrack/consent", method: "POST", body: body)
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    /// GET /api/geotrack/consent/status
    func consentStatus() async throws -> GeoTrackConsentRecord? {
        let request = try makeGETRequest(path: "/api/geotrack/consent/status")
        let result: GeoTrackConsentStatusResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data
    }

    // MARK: - Timeline & Live Status

    /// GET /api/geotrack/timeline?staffId=...&dayStart=...&dayEnd=...
    func timeline(
        staffId: String? = nil,
        dayStart: Int64,
        dayEnd: Int64
    ) async throws -> [GeoTrackTimelinePoint] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "dayStart", value: "\(dayStart)"),
            URLQueryItem(name: "dayEnd", value: "\(dayEnd)"),
        ]
        if let staffId { items.append(URLQueryItem(name: "staffId", value: staffId)) }
        let request = try makeGETRequest(path: "/api/geotrack/timeline", queryItems: items)
        let result: GeoTrackTimelineResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
    }

    /// GET /api/geotrack/live-status
    func liveStatus() async throws -> [GeoTrackLiveStatusEntry] {
        let request = try makeGETRequest(path: "/api/geotrack/live-status")
        let result: GeoTrackLiveStatusResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
    }

    /// GET /api/geotrack/employee-detail?staffId=...
    func employeeDetail(staffId: String? = nil) async throws -> GeoTrackEmployeeDetail? {
        var items: [URLQueryItem] = []
        if let staffId { items.append(URLQueryItem(name: "staffId", value: staffId)) }
        let request = try makeGETRequest(path: "/api/geotrack/employee-detail", queryItems: items)
        let result: GeoTrackEmployeeDetailResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data
    }

    // MARK: - Trips & Stats

    /// GET /api/geotrack/trips?staffId=...&startDate=...&endDate=...
    func trips(
        staffId: String? = nil,
        startDate: Int64,
        endDate: Int64
    ) async throws -> [GeoTrackTrip] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "startDate", value: "\(startDate)"),
            URLQueryItem(name: "endDate", value: "\(endDate)"),
        ]
        if let staffId { items.append(URLQueryItem(name: "staffId", value: staffId)) }
        let request = try makeGETRequest(path: "/api/geotrack/trips", queryItems: items)
        let result: GeoTrackTripsResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
    }

    /// GET /api/geotrack/stats?staffId=...&startDate=...&endDate=...
    func stats(
        staffId: String? = nil,
        startDate: Int64,
        endDate: Int64
    ) async throws -> GeoTrackStats? {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "startDate", value: "\(startDate)"),
            URLQueryItem(name: "endDate", value: "\(endDate)"),
        ]
        if let staffId { items.append(URLQueryItem(name: "staffId", value: staffId)) }
        let request = try makeGETRequest(path: "/api/geotrack/stats", queryItems: items)
        let result: GeoTrackStatsResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data
    }

    // MARK: - Assigned Places & Today Visits

    /// GET /api/geotrack/assigned-places
    func assignedPlaces() async throws -> [GeoTrackAssignedPlace] {
        let request = try makeGETRequest(path: "/api/geotrack/assigned-places")
        let result: GeoTrackAssignedPlacesResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
    }

    /// GET /api/geotrack/today-visits?date=YYYY-MM-DD
    func todayVisits(date: String? = nil) async throws -> [GeoTrackTodayVisit] {
        var items: [URLQueryItem] = []
        if let date { items.append(URLQueryItem(name: "date", value: date)) }
        let request = try makeGETRequest(path: "/api/geotrack/today-visits", queryItems: items)
        let result: GeoTrackTodayVisitsResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
    }

    /// GET /api/tracking/places/search?q=...
    func searchPlaces(query: String) async throws -> [GeoTrackPlaceSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = try makeGETRequest(
            path: "/api/tracking/places/search",
            queryItems: [URLQueryItem(name: "q", value: trimmed)]
        )
        let result: GeoTrackPlaceSearchResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
    }

    /// POST /api/geotrack/route
    func route(
        originLat: Double,
        originLng: Double,
        destLat: Double,
        destLng: Double
    ) async throws -> GeoTrackRouteResponse {
        let body = GeoTrackRouteRequest(
            originLat: originLat,
            originLng: originLng,
            destLat: destLat,
            destLng: destLng
        )
        let request = try makeRequest(path: "/api/geotrack/route", method: "POST", body: body)
        let result: GeoTrackRouteResponse = try await perform(request)
        if !result.success, let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result
    }

    /// POST /api/geotrack/geocode-address
    func geocodeAddress(_ address: String) async throws -> GeoTrackGeocodeAddressResponse {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GeoTrackAPIError.serverError("Address is empty")
        }
        let body = GeoTrackGeocodeAddressRequest(address: trimmed)
        let request = try makeRequest(path: "/api/geotrack/geocode-address", method: "POST", body: body)
        let result: GeoTrackGeocodeAddressResponse = try await perform(request)
        if !result.success, let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result
    }

    // MARK: - Visit Lifecycle

    /// POST /api/geotrack/visit/create
    func createVisit(
        clientPlaceId: String,
        scheduledDate: String,
        notes: String? = nil
    ) async throws -> String {
        let body = GeoTrackCreateVisitRequest(
            clientPlaceId: clientPlaceId,
            scheduledDate: scheduledDate,
            notes: notes
        )
        let request = try makeRequest(path: "/api/geotrack/visit/create", method: "POST", body: body)
        let result: GeoTrackCreateVisitResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        guard let visitId = result.visitId else {
            throw GeoTrackAPIError.serverError("visitId missing from response")
        }
        return visitId
    }

    /// POST /api/geotrack/visit/start
    func startVisit(visitId: String, lat: Double? = nil, lng: Double? = nil) async throws {
        let body = GeoTrackStartVisitRequest(visitId: visitId, lat: lat, lng: lng)
        let request = try makeRequest(path: "/api/geotrack/visit/start", method: "POST", body: body)
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    /// POST /api/geotrack/visit/complete
    func completeVisit(
        visitId: String,
        lat: Double? = nil,
        lng: Double? = nil,
        remarks: String? = nil,
        arrivalPhotoStorageId: String? = nil
    ) async throws {
        let body = GeoTrackCompleteVisitRequest(
            visitId: visitId,
            lat: lat,
            lng: lng,
            remarks: remarks,
            arrivalPhotoStorageId: arrivalPhotoStorageId
        )
        let request = try makeRequest(path: "/api/geotrack/visit/complete", method: "POST", body: body)
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    // MARK: - Arrival OTP

    /// POST /api/geotrack/visit/arrival-otp/request
    func requestArrivalOtp(
        visitId: String,
        lat: Double,
        lng: Double
    ) async throws -> GeoTrackArrivalOtpRequestResponse {
        let body = GeoTrackArrivalOtpRequestBody(visitId: visitId, lat: lat, lng: lng)
        let request = try makeRequest(path: "/api/geotrack/visit/arrival-otp/request", method: "POST", body: body)
        let result: GeoTrackArrivalOtpRequestResponse = try await perform(request)
        if !result.success, let err = result.error {
            throw GeoTrackAPIError.serverError(err)
        }
        return result
    }

    /// POST /api/geotrack/visit/arrival-otp/verify
    func verifyArrivalOtp(
        visitId: String,
        otp: String,
        lat: Double? = nil,
        lng: Double? = nil
    ) async throws -> GeoTrackArrivalOtpVerifyResponse {
        let body = GeoTrackArrivalOtpVerifyBody(visitId: visitId, otp: otp, lat: lat, lng: lng)
        let request = try makeRequest(path: "/api/geotrack/visit/arrival-otp/verify", method: "POST", body: body)
        let result: GeoTrackArrivalOtpVerifyResponse = try await perform(request)
        return result
    }

    /// POST /api/geotrack/visit/arrival-otp/cancel
    func cancelArrivalOtp(visitId: String) async throws {
        let body = GeoTrackArrivalOtpCancelBody(visitId: visitId)
        let request = try makeRequest(path: "/api/geotrack/visit/arrival-otp/cancel", method: "POST", body: body)
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }
}
