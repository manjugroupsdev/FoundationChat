import CoreLocation
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

/// Wraps MMS business endpoints and direct Airix GeoTrack transport endpoints.
/// Auth: Bearer token from the active OTP session (same as Android GeoTrackApi.kt).
/// GPS writes bypass MMS and go directly to `AppConfig.geoTrackBaseURL`.
@MainActor
@Observable
final class GeoTrackAPIService {
    static let shared = GeoTrackAPIService()

    // Injected for testing
    var tokenProvider: (() -> String?)?
    var urlSession: any GeoTrackHTTPSession

    private let baseURL: String
    private let trackingBaseURL: String
    private let pendingControlKey = "geotrack.pendingDirectControl"
    private let slowBusinessPaths: Set<String> = [
        "/api/geotrack/visit/arrival-otp/request",
        "/api/geotrack/visit/arrival-otp/verify",
        "/api/geotrack/visit/complete"
    ]

    private struct PendingControl: Codable {
        let action: String
        let requestId: String
        let start: GeoTrackSessionStartRequest?
        let end: GeoTrackSessionEndRequest?
    }

    private struct ErrorEnvelope: Decodable {
        let error: String?
        let message: String?
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    init(
        baseURL: String? = nil,
        trackingBaseURL: String? = nil,
        tokenProvider: (() -> String?)? = nil,
        urlSession: (any GeoTrackHTTPSession) = URLSession.shared
    ) {
        self.baseURL = baseURL ?? AppConfig.baseURL
        self.trackingBaseURL = trackingBaseURL ?? (baseURL ?? AppConfig.geoTrackBaseURL)
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
    }

    // MARK: - Request builder

    private func makeRequest(
        path: String,
        method: String,
        body: (any Encodable)? = nil,
        directGeoTrack: Bool = false,
        idempotencyKey: String? = nil
    ) throws -> URLRequest {
        let host = directGeoTrack ? trackingBaseURL : baseURL
        guard let url = URL(string: host + path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        if slowBusinessPaths.contains(path) {
            request.timeoutInterval = 90
        }
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        let token = tokenProvider?()
        if directGeoTrack && token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw GeoTrackAPIError.noToken
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func makeGETRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        directGeoTrack: Bool = false
    ) throws -> URLRequest {
        let host = directGeoTrack ? trackingBaseURL : baseURL
        var components = URLComponents(string: host + path)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let token = tokenProvider?()
        if directGeoTrack && token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw GeoTrackAPIError.noToken
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeoTrackAPIError.badStatus(0)
        }
        // The MMS host owns the app session. A direct GeoTrack 401 is an
        // operation failure, not proof that the MMS token should be erased.
        let authorityHost = URL(string: baseURL)?.host
        let isAuthenticatedMMSRequest = request.value(forHTTPHeaderField: "Authorization") != nil
            && request.url?.host?.caseInsensitiveCompare(authorityHost ?? "") == .orderedSame
        if http.statusCode == 401 && isAuthenticatedMMSRequest {
            SessionInvalidationBus.emit(for: request, responseData: data)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
               let message = envelope.error ?? envelope.message,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw GeoTrackAPIError.serverError(message)
            }
            throw GeoTrackAPIError.badStatus(http.statusCode)
        }
        do {
            let decoded = try await BackgroundJSONDecoder.decode(T.self, from: data)
            return decoded
        } catch {
            throw GeoTrackAPIError.decodingFailed(error)
        }
    }

    // MARK: - Location Tracking

    /// POST /api/tracking/location/batch. The session is captured with each
    /// point so an offline backlog is never attributed to a later shift.
    func pushBatch(
        sessionId: String,
        deviceId: String,
        requestId: String,
        points: [GeoTrackLocationPoint]
    ) async throws -> GeoTrackPushBatchResponse {
        await retryPendingTrackingControl()
        let body = GeoTrackPushBatchRequest(
            sessionId: sessionId,
            deviceId: deviceId,
            requestId: requestId,
            points: points
        )
        let request = try makeRequest(
            path: "/api/tracking/location/batch",
            method: "POST",
            body: body,
            directGeoTrack: true,
            idempotencyKey: requestId
        )
        let result: GeoTrackPushBatchResponse = try await perform(request)
        guard result.success else {
            throw GeoTrackAPIError.serverError(result.error ?? "GeoTrack rejected the location batch")
        }
        return result
    }

    /// POST /api/tracking/sessions/start
    func startTracking(
        contextId: String? = nil,
        startedAt: Int64? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        batteryPct: Int? = nil
    ) async throws -> GeoTrackDirectSessionData {
        let coordinator = GeoTrackBootstrapCoordinator.shared
        let timestamp = startedAt ?? Int64(Date().timeIntervalSince1970 * 1_000)
        let body = GeoTrackSessionStartRequest(
            deviceId: coordinator.deviceId,
            contextType: "attendance",
            contextId: contextId,
            source: "mconnect",
            trigger: "attendance_punch_in",
            startedAt: timestamp,
            lat: lat,
            lng: lng,
            batteryPct: batteryPct
        )
        let requestId = "tracking-start-\(coordinator.deviceId)-\(contextId ?? String(timestamp))"
        savePendingControl(PendingControl(action: "start", requestId: requestId, start: body, end: nil))
        let request = try makeRequest(
            path: "/api/tracking/sessions/start",
            method: "POST",
            body: body,
            directGeoTrack: true,
            idempotencyKey: requestId
        )
        let result: GeoTrackDirectSessionResponse = try await perform(request)
        guard result.success, let session = result.data, !session.sessionId.isEmpty else {
            throw GeoTrackAPIError.serverError(result.error ?? "GeoTrack start failed")
        }
        clearPendingControl(requestId: requestId)
        return session
    }

    /// GET /api/tracking/sessions/current
    func currentTrackingSession() async throws -> GeoTrackDirectSessionData? {
        let request = try makeGETRequest(
            path: "/api/tracking/sessions/current",
            directGeoTrack: true
        )
        let result: GeoTrackDirectSessionResponse = try await perform(request)
        guard result.success else {
            throw GeoTrackAPIError.serverError(result.error ?? "GeoTrack session recovery failed")
        }
        return result.data
    }

    /// POST /api/tracking/sessions/end
    func stopTracking(
        sessionId: String,
        endedAt: Int64? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        reason: String = "attendance_punch_out"
    ) async throws -> GeoTrackDirectSessionData? {
        let body = GeoTrackSessionEndRequest(
            sessionId: sessionId,
            endedAt: endedAt ?? Int64(Date().timeIntervalSince1970 * 1_000),
            lat: lat,
            lng: lng,
            reason: reason
        )
        let requestId = "tracking-end-\(sessionId)"
        savePendingControl(PendingControl(action: "end", requestId: requestId, start: nil, end: body))
        let request = try makeRequest(
            path: "/api/tracking/sessions/end",
            method: "POST",
            body: body,
            directGeoTrack: true,
            idempotencyKey: requestId
        )
        let result: GeoTrackDirectSessionResponse = try await perform(request)
        guard result.success else {
            throw GeoTrackAPIError.serverError(result.error ?? "GeoTrack stop failed")
        }
        clearPendingControl(requestId: requestId)
        return result.data
    }

    /// Replays a failed start/stop with its original body and idempotency key.
    func retryPendingTrackingControl(
        allowStart: Bool = false,
        discardStart: Bool = false
    ) async {
        guard let data = UserDefaults.standard.data(forKey: pendingControlKey),
              let pending = try? JSONDecoder().decode(PendingControl.self, from: data) else { return }
        if let startedAt = pending.start?.startedAt,
           Self.indiaDayKey(milliseconds: startedAt) != Self.indiaDayKey() {
            clearPendingControl(requestId: pending.requestId)
            return
        }
        if pending.action != "end" && !allowStart {
            if discardStart {
                clearPendingControl(requestId: pending.requestId)
            }
            return
        }
        do {
            let body: any Encodable
            let path: String
            if pending.action == "end", let end = pending.end {
                path = "/api/tracking/sessions/end"
                body = end
            } else if let start = pending.start {
                path = "/api/tracking/sessions/start"
                body = start
            } else {
                return
            }
            let request = try makeRequest(
                path: path,
                method: "POST",
                body: body,
                directGeoTrack: true,
                idempotencyKey: pending.requestId
            )
            let result: GeoTrackDirectSessionResponse = try await perform(request)
            guard result.success, result.error == nil else { return }
            if pending.action == "end" {
                GeoTrackBootstrapCoordinator.shared.clearActiveSessionIfMatching(pending.end?.sessionId)
            } else if let sessionId = result.data?.sessionId {
                GeoTrackBootstrapCoordinator.shared.applyRecoveredSessionId(sessionId)
            }
            clearPendingControl(requestId: pending.requestId)
        } catch {
            // Keep the exact command for the next direct-session recovery.
        }
    }

    private func savePendingControl(_ command: PendingControl) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        UserDefaults.standard.set(data, forKey: pendingControlKey)
    }

    private func clearPendingControl(requestId: String) {
        guard let data = UserDefaults.standard.data(forKey: pendingControlKey),
              let pending = try? JSONDecoder().decode(PendingControl.self, from: data),
              pending.requestId == requestId else { return }
        UserDefaults.standard.removeObject(forKey: pendingControlKey)
    }

    var hasPendingTrackingStart: Bool {
        guard let data = UserDefaults.standard.data(forKey: pendingControlKey),
              let pending = try? JSONDecoder().decode(PendingControl.self, from: data) else {
            return false
        }
        return pending.action == "start"
    }

    func clearPendingTrackingStart() {
        guard hasPendingTrackingStart else { return }
        UserDefaults.standard.removeObject(forKey: pendingControlKey)
    }

    private static func indiaDayKey(
        milliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1_000))
    }

    // MARK: - Heartbeat

    /// POST /api/tracking/heartbeat
    /// Whether the app can currently get a location at all. Uses the
    /// authorization status rather than `locationServicesEnabled()`, which
    /// blocks the calling thread and is deprecated on the main actor.
    private static func locationServicesUsable() -> Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    func heartbeat(
        batteryPct: Int,
        appVersion: String,
        recordedAt: Int64? = nil,
        sessionId: String? = nil,
        deviceId: String? = nil
    ) async throws {
        await retryPendingTrackingControl()
        let coordinator = GeoTrackBootstrapCoordinator.shared
        let timestamp = recordedAt ?? Int64(Date().timeIntervalSince1970 * 1_000)
        let resolvedDeviceId = deviceId ?? coordinator.deviceId
        let requestId = "heartbeat-\(resolvedDeviceId)-\(timestamp)"
        let body = GeoTrackHeartbeatRequest(
            sessionId: sessionId ?? coordinator.activeSessionId,
            deviceId: resolvedDeviceId,
            requestId: requestId,
            deviceSequence: timestamp,
            batteryPct: batteryPct,
            appVersion: appVersion,
            recordedAt: timestamp,
            // iOS exposes NO public API for flight mode, so this stays nil
            // rather than guessing: inferring it from "no interfaces" would
            // mislabel a phone that is merely out of signal. Flight mode is
            // still reported on iOS — GeoTrackTamperMonitor infers it from
            // NWPathMonitor and raises AIRPLANE_MODE_ON, which the backend
            // prefers over these fallback flags anyway.
            airplaneMode: nil,
            // This one IS knowable, and was being sent as nil — so every gap on
            // an iPhone reached the backend with no device state to explain it.
            locationEnabled: Self.locationServicesUsable(),
            lat: nil,
            lng: nil,
            networkAvailable: nil,
            permissionState: Self.locationServicesUsable() ? "granted" : "location_missing",
            movementMode: nil,
            trackingActive: (sessionId ?? coordinator.activeSessionId) != nil,
            backgroundRestricted: nil
        )
        let request = try makeRequest(
            path: "/api/tracking/heartbeat",
            method: "POST",
            body: body,
            directGeoTrack: true,
            idempotencyKey: requestId
        )
        let result: GeoTrackBaseResponse = try await perform(request)
        guard result.success else {
            throw GeoTrackAPIError.serverError(result.error ?? "GeoTrack heartbeat failed")
        }
    }

    // MARK: - Tamper

    /// Every tracking/tamper event goes to the direct GeoTrack service.
    func reportTamper(
        eventType: GeoTrackTamperEventType,
        metadata: [String: String] = [:],
        detectedAt: Int64? = nil
    ) async throws {
        let timestamp = metadata["_detectedAt"].flatMap { Int64($0) }
            ?? detectedAt
            ?? Int64(Date().timeIntervalSince1970 * 1_000)
        let requestId = metadata["_requestId"]
            ?? "tamper-\(GeoTrackBootstrapCoordinator.shared.deviceId)-\(eventType.rawValue)-\(timestamp)"
        let publicMetadata = metadata.filter { !$0.key.hasPrefix("_") }
        let directEventType: String
        switch eventType {
        case .permissionDowngrade:
            directEventType = "PERMISSION_MISSING"
        default:
            directEventType = eventType.rawValue
        }
        let body = GeoTrackTamperReportRequest(
            sessionId: metadata["_sessionId"] ?? GeoTrackBootstrapCoordinator.shared.activeSessionId,
            eventType: directEventType,
            metadata: publicMetadata,
            detectedAt: timestamp,
            requestId: requestId
        )
        let request = try makeRequest(
            path: "/api/tracking/tamper-events",
            method: "POST",
            body: body,
            directGeoTrack: true,
            idempotencyKey: requestId
        )
        let result: GeoTrackBaseResponse = try await perform(request)
        guard result.success else {
            throw GeoTrackAPIError.serverError(result.error ?? "GeoTrack tamper report failed")
        }
    }

    /// GET /api/tracking/tamper-events?limit=...
    func tamperFeed(limit: Int = 50) async throws -> [GeoTrackTamperEvent] {
        let request = try makeGETRequest(
            path: "/api/tracking/tamper-events",
            queryItems: [URLQueryItem(name: "limit", value: "\(limit)")],
            directGeoTrack: true
        )
        let result: GeoTrackTamperFeedResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
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
        let request = try makeGETRequest(
            path: "/api/geotrack/timeline",
            queryItems: items,
            directGeoTrack: true
        )
        let result: GeoTrackTimelineResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
    }

    /// GET /api/geotrack/session-route?staffId=...&dayStart=...&dayEnd=...
    func sessionRoute(
        staffId: String? = nil,
        dayStart: Int64,
        dayEnd: Int64,
        minStopMinutes: Int? = nil
    ) async throws -> GeoTrackSessionRouteData? {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "dayStart", value: "\(dayStart)"),
            URLQueryItem(name: "dayEnd", value: "\(dayEnd)"),
        ]
        if let staffId { items.append(URLQueryItem(name: "staffId", value: staffId)) }
        if let minStopMinutes { items.append(URLQueryItem(name: "minStopMinutes", value: "\(minStopMinutes)")) }
        let request = try makeGETRequest(
            path: "/api/geotrack/session-route",
            queryItems: items,
            directGeoTrack: true
        )
        let result: GeoTrackSessionRouteResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data
    }

    /// GET /api/tracking/live
    func liveStatus() async throws -> [GeoTrackLiveStatusEntry] {
        let request = try makeGETRequest(path: "/api/tracking/live", directGeoTrack: true)
        let result: GeoTrackLiveStatusResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data ?? []
    }

    /// GET /api/geotrack/employee-detail?staffId=...
    func employeeDetail(staffId: String? = nil) async throws -> GeoTrackEmployeeDetail? {
        var items: [URLQueryItem] = []
        if let staffId { items.append(URLQueryItem(name: "staffId", value: staffId)) }
        let request = try makeGETRequest(
            path: "/api/geotrack/employee-detail",
            queryItems: items,
            directGeoTrack: true
        )
        let result: GeoTrackEmployeeDetailResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data
    }

    // MARK: - Trips & Stats

    /// GET /api/tracking/trips?staffId=...&from=...&to=...
    func trips(
        staffId: String? = nil,
        startDate: Int64,
        endDate: Int64
    ) async throws -> [GeoTrackTrip] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "from", value: "\(startDate)"),
            URLQueryItem(name: "to", value: "\(endDate)"),
        ]
        if let staffId { items.append(URLQueryItem(name: "staffId", value: staffId)) }
        let request = try makeGETRequest(
            path: "/api/tracking/trips",
            queryItems: items,
            directGeoTrack: true
        )
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
        let request = try makeGETRequest(
            path: "/api/geotrack/stats",
            queryItems: items,
            directGeoTrack: true
        )
        let result: GeoTrackStatsResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        return result.data
    }

    /// GET /api/mms-fleet/driver/trips
    func mmsFleetDriverTrips() async throws -> [FleetDriverTrip] {
        let request = try makeGETRequest(path: "/api/mms-fleet/driver/trips")
        let result: MmsFleetDriverTripsResponse = try await perform(request)
        if !result.success {
            throw GeoTrackAPIError.serverError(result.error ?? "Failed to load driver trips")
        }
        return result.trips
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

    /// GET /api/marketing/clientPlaceVisits/my
    func marketingCPVisits(fromDate: String? = nil, toDate: String? = nil, scope: String = "all") async throws -> [GeoTrackCPVisitDetail] {
        var items = [URLQueryItem(name: "scope", value: scope)]
        if let fromDate { items.append(URLQueryItem(name: "fromDate", value: fromDate)) }
        if let toDate { items.append(URLQueryItem(name: "toDate", value: toDate)) }
        let request = try makeGETRequest(path: "/api/marketing/clientPlaceVisits/my", queryItems: items)
        let result: GeoTrackMarketingCPVisitsResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        guard result.success else { throw GeoTrackAPIError.serverError("Failed to load CP visits.") }
        return result.visits
    }

    /// GET /api/tracking/places/search?q=...
    func searchPlaces(query: String) async throws -> [GeoTrackPlaceSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = try makeGETRequest(
            path: "/api/tracking/places/search",
            queryItems: [URLQueryItem(name: "q", value: trimmed)],
            directGeoTrack: true
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
        let request = try makeRequest(
            path: "/api/geotrack/route",
            method: "POST",
            body: body,
            directGeoTrack: true
        )
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
        let request = try makeRequest(
            path: "/api/geotrack/geocode-address",
            method: "POST",
            body: body,
            directGeoTrack: true
        )
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

    /// POST /api/mms-fleet/driver/arrive
    func markMmsFleetDriverArrived(siteVisitId: String) async throws {
        let body = MmsFleetDriverSiteVisitRequest(siteVisitId: siteVisitId)
        let request = try makeRequest(path: "/api/mms-fleet/driver/arrive", method: "POST", body: body)
        let result: MmsFleetDriverActionResponse = try await perform(request)
        if !result.success, let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    /// POST /api/mms-fleet/driver/start
    func startMmsFleetDriverTrip(siteVisitId: String, photoIds: [String], startKm: Double) async throws {
        let body = MmsFleetDriverStartRequest(siteVisitId: siteVisitId, photoIds: photoIds, startKm: startKm)
        let request = try makeRequest(path: "/api/mms-fleet/driver/start", method: "POST", body: body)
        let result: MmsFleetDriverActionResponse = try await perform(request)
        if !result.success, let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    /// POST /api/mms-fleet/driver/on-site
    func markMmsFleetDriverOnSite(siteVisitId: String) async throws {
        let body = MmsFleetDriverSiteVisitRequest(siteVisitId: siteVisitId)
        let request = try makeRequest(path: "/api/mms-fleet/driver/on-site", method: "POST", body: body)
        let result: MmsFleetDriverActionResponse = try await perform(request)
        if !result.success, let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    /// POST /api/mms-fleet/driver/picked-from-site
    func markMmsFleetDriverPickedFromSite(siteVisitId: String) async throws {
        let body = MmsFleetDriverSiteVisitRequest(siteVisitId: siteVisitId)
        let request = try makeRequest(path: "/api/mms-fleet/driver/picked-from-site", method: "POST", body: body)
        let result: MmsFleetDriverActionResponse = try await perform(request)
        if !result.success, let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    /// POST /api/mms-fleet/driver/end
    func endMmsFleetDriverTrip(siteVisitId: String, photoIds: [String], endKm: Double) async throws {
        let body = MmsFleetDriverEndRequest(siteVisitId: siteVisitId, photoIds: photoIds, endKm: endKm)
        let request = try makeRequest(path: "/api/mms-fleet/driver/end", method: "POST", body: body)
        let result: MmsFleetDriverActionResponse = try await perform(request)
        if !result.success, let err = result.error { throw GeoTrackAPIError.serverError(err) }
    }

    /// POST /api/geotrack/visit/complete
    @discardableResult
    func completeVisit(
        visitId: String,
        lat: Double? = nil,
        lng: Double? = nil,
        remarks: String? = nil,
        arrivalPhotoStorageId: String? = nil,
        clientMet: Bool? = nil,
        outcome: String? = nil,
        outcomeNotes: String? = nil,
        postponeReasons: [String]? = nil,
        followUpDate: String? = nil,
        followUpTime: String? = nil
    ) async throws -> GeoTrackBaseResponse {
        let body = GeoTrackCompleteVisitRequest(
            visitId: visitId,
            lat: lat,
            lng: lng,
            remarks: remarks,
            arrivalPhotoStorageId: arrivalPhotoStorageId,
            clientMet: clientMet,
            outcome: outcome,
            outcomeNotes: outcomeNotes,
            postponeReasons: postponeReasons,
            followUpDate: followUpDate,
            followUpTime: followUpTime
        )
        let request = try makeRequest(path: "/api/geotrack/visit/complete", method: "POST", body: body)
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        guard result.success else {
            throw GeoTrackAPIError.serverError("The server did not complete this visit. Refresh its status before retrying.")
        }
        return result
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
        if !result.success {
            throw GeoTrackAPIError.serverError(result.error ?? "The server could not send the arrival OTP.")
        }
        return result
    }

    /// POST /api/marketing/cp-visits/otp-assist
    /// Asks the assigned GM for help when a client will not share the arrival
    /// OTP. The backend sends the visit context and code to that GM over chat.
    func requestCpOtpAssist(
        clientPlaceVisitId: String,
        lat: Double? = nil,
        lng: Double? = nil,
        remark: String? = nil
    ) async throws -> CpOtpAssistResponse {
        let body = CpOtpAssistRequest(
            clientPlaceVisitId: clientPlaceVisitId,
            lat: lat,
            lng: lng,
            remark: remark
        )
        let request = try makeRequest(
            path: "/api/marketing/cp-visits/otp-assist",
            method: "POST",
            body: body
        )
        let result: CpOtpAssistResponse = try await perform(request)
        if !result.success, let error = result.error {
            throw GeoTrackAPIError.serverError(error)
        }
        return result
    }

    /// POST /api/geotrack/visit/arrival-otp/verify
    func verifyArrivalOtp(
        visitId: String,
        fallbackClientPlaceVisitId: String? = nil,
        otp: String,
        lat: Double? = nil,
        lng: Double? = nil,
        arrivalPhotoStorageId: String? = nil
    ) async throws -> GeoTrackArrivalOtpVerifyResponse {
        let body = GeoTrackArrivalOtpVerifyBody(
            visitId: visitId,
            otp: otp,
            lat: lat,
            lng: lng,
            arrivalPhotoStorageId: arrivalPhotoStorageId
        )
        let request = try makeRequest(path: "/api/geotrack/visit/arrival-otp/verify", method: "POST", body: body)
        do {
            let result: GeoTrackArrivalOtpVerifyResponse = try await perform(request)
            return result
        } catch GeoTrackAPIError.badStatus(400) {
            let fallbackId = fallbackClientPlaceVisitId?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !fallbackId.isEmpty, fallbackId != visitId else { throw GeoTrackAPIError.badStatus(400) }

            // Older compatibility layers can require the CP id instead of the
            // linked field-visit id. Their 400 happens before OTP verification,
            // so retrying once with the alternate id cannot consume an attempt.
            let fallbackBody = GeoTrackArrivalOtpVerifyBody(
                visitId: fallbackId,
                otp: otp,
                lat: lat,
                lng: lng,
                arrivalPhotoStorageId: arrivalPhotoStorageId
            )
            let fallbackRequest = try makeRequest(
                path: "/api/geotrack/visit/arrival-otp/verify",
                method: "POST",
                body: fallbackBody
            )
            let result: GeoTrackArrivalOtpVerifyResponse = try await perform(fallbackRequest)
            return result
        }
    }

    /// POST /api/geotrack/visit/arrival-otp/cancel
    func cancelArrivalOtp(visitId: String) async throws {
        let body = GeoTrackArrivalOtpCancelBody(visitId: visitId)
        let request = try makeRequest(path: "/api/geotrack/visit/arrival-otp/cancel", method: "POST", body: body)
        let result: GeoTrackBaseResponse = try await perform(request)
        if let err = result.error { throw GeoTrackAPIError.serverError(err) }
        guard result.success else {
            throw GeoTrackAPIError.serverError("The server could not cancel the arrival OTP.")
        }
    }

}
