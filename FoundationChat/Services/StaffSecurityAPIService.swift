import Foundation

struct StaffBoundDevice: Decodable, Sendable {
    let bound: Bool
    let deviceId: String?
    let platform: String?
    let deviceModel: String?
    let batteryPct: Double?
    let ip: String?
    let boundAt: Double?
    let lastSeenAt: Double?
}

struct StaffPasswordStatus: Decodable, Sendable {
    let hasPassword: Bool
    let mustChangePassword: Bool
    let passwordExpiryExempt: Bool
    let passwordUpdatedAt: Double?
}

struct StaffLoginSession: Decodable, Sendable {
    let createdAt: Double?
    let expiresAt: Double?
}

struct ActiveStaffLogin: Decodable, Identifiable, Sendable {
    let staffId: String?
    let employeeId: String?
    let name: String?
    let phone: String?
    let photo: String?
    let designation: String?
    let department: String?
    let webSession: StaffLoginSession?
    let mobileSession: StaffLoginSession?
    let deviceCount: Int

    var id: String {
        staffId ?? employeeId ?? phone
            ?? [name, designation, department].compactMap { $0 }.joined(separator: "|")
    }
}

struct ActiveStaffSession: Decodable, Identifiable, Sendable {
    let deviceKey: String
    let sessionId: String?
    let sessionIds: [String]
    let deviceType: String
    let browser: String
    let os: String
    let device: String
    let model: String
    let ip: String
    let createdAt: Double?
    let expiresAt: Double?
    let isCurrent: Bool

    var id: String { deviceKey }
}

struct BulkDeviceResetResult: Decodable, Sendable {
    let selectedStaffCount: Int
    let staffWithBindings: Int
    let bindingsCleared: Int
    let mobileSessionsSignedOut: Int
}

enum StaffSecurityAPIService {
    private static let baseURL = AppConfig.baseURL

    private struct SecurityResponse: Decodable {
        let success: Bool
        let binding: StaffBoundDevice?
        let error: String?
    }

    private struct PasswordStatusResponse: Decodable {
        let success: Bool
        let status: StaffPasswordStatus?
        let error: String?
    }

    private struct ActiveLoginsResponse: Decodable {
        let success: Bool
        let rows: [ActiveStaffLogin]?
        let error: String?
    }

    private struct ActiveSessionsResponse: Decodable {
        let success: Bool
        let sessions: [ActiveStaffSession]?
        let error: String?
    }

    private struct ActionResponse: Decodable {
        let success: Bool
        let error: String?
    }

    private struct SelectableStaffIDsResponse: Decodable {
        let success: Bool
        let total: Int
        let staffIds: [String]
        let error: String?
    }

    private struct BulkDeviceResetResponse: Decodable {
        let success: Bool
        let selectedStaffCount: Int?
        let staffWithBindings: Int?
        let bindingsCleared: Int?
        let mobileSessionsSignedOut: Int?
        let error: String?
    }

    static func deviceBinding(token: String, staffId: String) async throws -> StaffBoundDevice? {
        let id = try encoded(staffId)
        let response: SecurityResponse = try await request(
            path: "/api/hr/staff/security?staffId=\(id)",
            token: token
        )
        guard response.success else { throw StaffSecurityAPIError.server(response.error ?? "Unable to load device status") }
        return response.binding
    }

    static func passwordStatus(token: String, staffId: String) async throws -> StaffPasswordStatus? {
        let id = try encoded(staffId)
        let response: PasswordStatusResponse = try await request(
            path: "/api/hr/staff/password-status?staffId=\(id)",
            token: token
        )
        guard response.success else { throw StaffSecurityAPIError.server(response.error ?? "Unable to load password status") }
        return response.status
    }

    static func activeLogins(token: String) async throws -> [ActiveStaffLogin] {
        let response: ActiveLoginsResponse = try await request(
            path: "/api/hr/staff/active-logins",
            token: token
        )
        guard response.success else { throw StaffSecurityAPIError.server(response.error ?? "Unable to load staff logins") }
        return response.rows ?? []
    }

    static func activeSessions(token: String, staffId: String) async throws -> [ActiveStaffSession] {
        let id = try encoded(staffId)
        let response: ActiveSessionsResponse = try await request(
            path: "/api/hr/staff/active-sessions?staffId=\(id)",
            token: token
        )
        guard response.success else { throw StaffSecurityAPIError.server(response.error ?? "Unable to load active devices") }
        return response.sessions ?? []
    }

    static func resetDevice(token: String, staffId: String) async throws {
        try await action(path: "/api/hr/staff/device-reset", token: token, body: ["staffId": staffId])
    }

    static func selectableStaffIDs(
        token: String,
        designation: String? = nil,
        department: String? = nil,
        query: String? = nil
    ) async throws -> (ids: [String], total: Int) {
        let response: SelectableStaffIDsResponse = try await request(
            path: "/api/hr/staff/selectable-ids",
            token: token,
            queryItems: [
                URLQueryItem(name: "designation", value: designation?.staffSecurityNonBlank),
                URLQueryItem(name: "department", value: department?.staffSecurityNonBlank),
                URLQueryItem(name: "query", value: query?.staffSecurityNonBlank)
            ]
        )
        guard response.success else {
            throw StaffSecurityAPIError.server(response.error ?? "Unable to select matching staff")
        }
        return (response.staffIds, response.total)
    }

    static func resetDevicesBulk(token: String, staffIds: [String]) async throws -> BulkDeviceResetResult {
        let response: BulkDeviceResetResponse = try await request(
            path: "/api/hr/staff/device-reset/bulk",
            token: token,
            method: "POST",
            body: ["staffIds": staffIds]
        )
        guard response.success else {
            throw StaffSecurityAPIError.server(response.error ?? "Unable to reset selected devices")
        }
        return BulkDeviceResetResult(
            selectedStaffCount: response.selectedStaffCount ?? staffIds.count,
            staffWithBindings: response.staffWithBindings ?? 0,
            bindingsCleared: response.bindingsCleared ?? 0,
            mobileSessionsSignedOut: response.mobileSessionsSignedOut ?? 0
        )
    }

    static func forceMobileLogout(token: String, staffId: String) async throws {
        try await action(path: "/api/hr/staff/force-logout", token: token, body: ["staffId": staffId])
    }

    static func logoutEverywhere(token: String, staffId: String) async throws {
        try await action(path: "/api/hr/staff/logout-everywhere", token: token, body: ["staffId": staffId])
    }

    static func logoutDevice(token: String, staffId: String, sessionIds: [String]) async throws {
        try await action(
            path: "/api/hr/staff/logout-device",
            token: token,
            body: ["staffId": staffId, "sessionIds": sessionIds]
        )
    }

    static func setPassword(
        token: String,
        staffId: String,
        newPassword: String,
        mustChangePassword: Bool
    ) async throws {
        try await action(
            path: "/api/hr/staff/set-password",
            token: token,
            body: [
                "staffId": staffId,
                "newPassword": newPassword,
                "mustChangePassword": mustChangePassword
            ]
        )
    }

    static func setPasswordExpiryExempt(token: String, staffId: String, exempt: Bool) async throws {
        try await action(
            path: "/api/hr/staff/password-expiry-exempt",
            token: token,
            body: ["staffId": staffId, "exempt": exempt]
        )
    }

    private static func action(path: String, token: String, body: [String: Any]) async throws {
        let response: ActionResponse = try await request(path: path, token: token, method: "POST", body: body)
        guard response.success else { throw StaffSecurityAPIError.server(response.error ?? "Security action failed") }
    }

    private static func request<T: Decodable>(
        path: String,
        token: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw StaffSecurityAPIError.badURL
        }
        let populatedQueryItems = queryItems.filter { $0.value != nil }
        if !populatedQueryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + populatedQueryItems
        }
        guard let url = components.url else { throw StaffSecurityAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 401 { SessionInvalidationBus.emit(for: request, responseData: data) }
        guard (200..<300).contains(statusCode) else {
            let message = (try? JSONDecoder().decode(ActionResponse.self, from: data).error)
            throw StaffSecurityAPIError.server(message ?? "Request failed (\(statusCode))")
        }
        return try await BackgroundJSONDecoder.decode(T.self, from: data)
    }

    private static func encoded(_ value: String) throws -> String {
        guard let result = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw StaffSecurityAPIError.badURL
        }
        return result
    }
}

enum StaffSecurityAPIError: LocalizedError {
    case badURL
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid security request."
        case .server(let message): return message
        }
    }
}

private extension String {
    var staffSecurityNonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
