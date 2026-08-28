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
    let designation: String?
    let department: String?
    let webSession: StaffLoginSession?
    let mobileSession: StaffLoginSession?
    let deviceCount: Int

    var id: String { staffId ?? employeeId ?? phone ?? UUID().uuidString }
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
        body: [String: Any]? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw StaffSecurityAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 401 { SessionInvalidationBus.emit() }
        guard (200..<300).contains(statusCode) else {
            let message = (try? JSONDecoder().decode(ActionResponse.self, from: data).error)
            throw StaffSecurityAPIError.server(message ?? "Request failed (\(statusCode))")
        }
        return try JSONDecoder().decode(T.self, from: data)
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
