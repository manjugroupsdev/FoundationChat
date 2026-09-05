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

    private struct UpdateLeadRequest: Encodable {
        let id: String
        let contactName: String?
        let emailId: String?
        let alternateNumber: String?
        let locationPreferred: String?
        let manualProfile: ManualProfilePatch
    }

    private struct ManualProfilePatch: Encodable {
        let clientName: String?
        let pincode: String?
        let address: String?
        let state: String?
        let district: String?
        let alternateMobileNumber: String?
        let doorNo: String?
        let landmark: String?
    }

    private struct MutationResponse: Decodable {
        let success: Bool
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
        let wrapper = try await BackgroundJSONDecoder.decode(LeadsResponse.self, from: data)
        if let error = wrapper.error, wrapper.success == false {
            throw TelecallerAPIError.server(error)
        }
        let leads = wrapper.leads ?? []
        let hasMore = wrapper.hasMore ?? (wrapper.nextCursor != nil)
        return LeadsPage(leads: leads, nextCursor: wrapper.nextCursor, total: wrapper.total, hasMore: hasMore)
    }

    /// Mirrors Android's best-effort lead write-back after a booking form that
    /// was prefilled from a telecaller lead is successfully saved.
    static func updateLeadFromBooking(
        token: String,
        leadId: String,
        contactName: String?,
        emailId: String?,
        alternateNumber: String?,
        locationPreferred: String?,
        pincode: String?,
        address: String?,
        state: String?,
        district: String?,
        doorNo: String?,
        landmark: String?
    ) async throws {
        let request = UpdateLeadRequest(
            id: leadId,
            contactName: contactName,
            emailId: emailId,
            alternateNumber: alternateNumber,
            locationPreferred: locationPreferred,
            manualProfile: ManualProfilePatch(
                clientName: contactName,
                pincode: pincode,
                address: address,
                state: state,
                district: district,
                alternateMobileNumber: alternateNumber,
                doorNo: doorNo,
                landmark: landmark
            )
        )
        let data = try await post(path: "/api/telecaller/leads/update", token: token, body: request)
        let response = try await BackgroundJSONDecoder.decode(MutationResponse.self, from: data)
        guard response.success else {
            throw TelecallerAPIError.server(response.error ?? "Lead update failed")
        }
    }

    /// Fetch the authenticated Modern Dialer mapping (WebRTC token + extension).
    /// Mirrors the Android `ApiService.getMobileDialerConfig`, which hits
    /// `GET api/mobile/dialer/config` with the bearer token. Used to decide
    /// whether the authenticated user can use the Modern Dialer softphone.
    static func getMobileDialerConfig(token: String) async throws -> MobileDialerConfig {
        let data = try await get(path: "/api/mobile/dialer/config", token: token)
        return try await BackgroundJSONDecoder.decode(MobileDialerConfig.self, from: data)
    }

    static func getMobileDialerCurrentCall(token: String, callId: String? = nil) async throws -> MobileDialerCurrentCall? {
        var path = "/api/mobile/dialer/calls/current"
        if let callId = callId?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?callId=\(callId)"
        }
        let data = try await get(path: path, token: token)
        return try await BackgroundJSONDecoder.decode(MobileDialerCurrentCallResponse.self, from: data).call
    }

    static func performMobileDialerAction(
        token: String,
        callId: String,
        action: String,
        deviceId: String,
        eventId: String?,
        idempotencyKey: UUID
    ) async throws -> MobileDialerActionResponse {
        let body = MobileDialerActionRequest(
            action: action,
            platform: "ios",
            deviceId: deviceId,
            eventId: eventId
        )
        let data = try await post(
            path: "/api/mobile/dialer/calls/\(callId.urlPathComponent)/action",
            token: token,
            body: body,
            headers: ["Idempotency-Key": idempotencyKey.uuidString]
        )
        return try await BackgroundJSONDecoder.decode(MobileDialerActionResponse.self, from: data)
    }

    static func restartMobileDialerMedia(
        token: String,
        callId: String,
        deviceId: String,
        idempotencyKey: UUID
    ) async throws -> MobileDialerMediaRestartResponse {
        let data = try await post(
            path: "/api/mobile/dialer/calls/\(callId.urlPathComponent)/media/restart",
            token: token,
            body: MobileDialerMediaRestartRequest(
                reason: "ice_failed",
                platform: "ios",
                deviceId: deviceId
            ),
            headers: ["Idempotency-Key": idempotencyKey.uuidString]
        )
        return try await BackgroundJSONDecoder.decode(MobileDialerMediaRestartResponse.self, from: data)
    }

    static func getMobileDialerMedia(token: String, callId: String) async throws -> MobileDialerMediaResponse {
        let data = try await get(
            path: "/api/mobile/dialer/calls/\(callId.urlPathComponent)/media",
            token: token
        )
        return try await BackgroundJSONDecoder.decode(MobileDialerMediaResponse.self, from: data)
    }

    // MARK: - HTTP

    private static func get(path: String, token: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw TelecallerAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                SessionInvalidationBus.emit()
                throw TelecallerAPIError.unauthorized
            }
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

    private static func post<T: Encodable>(
        path: String,
        token: String,
        body: T,
        headers: [String: String] = [:]
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw TelecallerAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                SessionInvalidationBus.emit()
                throw TelecallerAPIError.unauthorized
            }
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

// MARK: - Modern Dialer config
//
// Mirrors the Android `MobileDialerConfigResponse` shape
// (app/.../network/ApiService.kt). Decoded defensively — every field optional —
// so one renamed/absent field never aborts the parse.

struct MobileDialerConfig: Decodable, Sendable, Equatable {
    let success: Bool?
    let configured: Bool?
    let provider: String?
    let mode: String?
    let apiUrl: String?
    let staff: MobileDialerStaff?
    let mapping: MobileDialerMapping?
    let features: MobileDialerFeatures?
    let error: String?
}

struct MobileDialerStaff: Decodable, Sendable, Equatable {
    let id: String?
    let name: String?
    let employeeId: String?
}

struct MobileDialerMapping: Decodable, Sendable, Equatable {
    let staffName: String?
    let `extension`: String?
    let token: String?
    let tokenExpiresAt: String?
    let active: Bool?
}

struct MobileDialerFeatures: Decodable, Sendable, Equatable {
    let outbound: Bool?
    let incomingPush: Bool?
    let pickup: Bool?
    let hangup: Bool?
    let mute: Bool?
    let hold: Bool?
    let pushProvider: String?
    let pushProviders: [String]?
    let pushConfigSource: String?
}

struct MobileDialerCurrentCallResponse: Decodable, Sendable {
    let success: Bool
    let call: MobileDialerCurrentCall?
}

struct MobileDialerCurrentCall: Decodable, Sendable {
    let callId: String
    let direction: String
    let stage: String
    let fromNumber: String?
    let toNumber: String?
    let displayName: String?
    let `extension`: String?
    let requiresPickup: Bool?
    let muted: Bool?
    let held: Bool?
    let startedAt: String?
    let expiresAt: String?
}

private struct MobileDialerActionRequest: Encodable {
    let action: String
    let platform: String
    let deviceId: String
    let eventId: String?
}

struct MobileDialerActionResponse: Decodable, Sendable {
    let success: Bool
    let callId: String
    let stage: String
    let alreadyApplied: Bool?
}

private struct MobileDialerMediaRestartRequest: Encodable {
    let reason: String
    let platform: String
    let deviceId: String
}

struct MobileDialerMediaRestartResponse: Decodable, Sendable {
    let success: Bool
    let callId: String
    let stage: String
    let iceRestarted: Bool?
}

struct MobileDialerMediaResponse: Decodable, Sendable {
    let success: Bool
    let callId: String
    let `extension`: String?
    let media: MobileDialerMediaDiagnostics?
}

struct MobileDialerMediaDiagnostics: Decodable, Sendable {
    let iceConnectionState: String?
    let iceGatheringState: String?
    let signalingState: String?
    let candidateType: String?
    let lastRtpAt: String?
}

private extension String {
    var urlPathComponent: String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return addingPercentEncoding(withAllowedCharacters: safe) ?? self
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
