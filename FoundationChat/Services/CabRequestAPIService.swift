import Foundation

/// A cab request (web Fleet > Cab Requests). Optional fields everywhere but
/// the id, so one unexpected value can't fail the whole list.
struct CabRequest: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let staffId: String?
    let staffName: String?
    let employeeId: String?
    let purpose: String?
    let fromLocation: String?
    let toLocation: String?
    /// YYYY-MM-DD
    let requestedDate: String?
    /// HH:mm
    let requestedTime: String?
    let passengerCount: Double?
    let vehiclePreference: String?
    let notes: String?
    /// pending | approved | rejected | assigned | completed | cancelled
    let status: String?
    let reportingToId: String?
    let reportingToName: String?
    let approvedByName: String?
    let rejectionReason: String?
    let vehicleNumber: String?
    let driverName: String?
    let driverPhone: String?
    let createdAt: Double?

    var id: String { _id }
}

struct CabRequestVehicle: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let vehicleNumber: String?
    let make: String?
    let model: String?
    let defaultDriverName: String?
    let defaultDriverPhone: String?
    let status: String?

    var id: String { _id }
}

struct NewCabRequest: Encodable, Sendable {
    let purpose: String
    let fromLocation: String
    let toLocation: String
    let requestedDate: String
    let requestedTime: String?
    let passengerCount: Int?
    let notes: String?
}

enum CabRequestAPIError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }
}

/// The /api/cab-requests/* routes: the same Convex functions and IAM keys as
/// the web tab (marketing.fleet.cabRequest.create / approve / viewAll / assign).
enum CabRequestAPIService {
    private struct ListResponse: Decodable {
        let success: Bool
        let requests: [CabRequest]?
        let error: String?
    }

    private struct ActionResponse: Decodable {
        let success: Bool
        let error: String?
    }

    private struct VehiclesResponse: Decodable {
        let success: Bool
        let vehicles: [CabRequestVehicle]?
        let error: String?
    }

    private struct IdBody: Encodable { let id: String }
    private struct RejectBody: Encodable { let id: String; let reason: String }
    private struct AssignBody: Encodable {
        let id: String
        let vehicleId: String
        let driverName: String?
        let driverPhone: String?
    }

    static func mine(token: String) async throws -> [CabRequest] {
        try await list("/api/cab-requests/mine", token: token)
    }

    static func approvals(token: String) async throws -> [CabRequest] {
        try await list("/api/cab-requests/approvals", token: token)
    }

    static func all(token: String) async throws -> [CabRequest] {
        try await list("/api/cab-requests/all", token: token)
    }

    static func create(token: String, request: NewCabRequest) async throws {
        try await action("/api/cab-requests/create", token: token, body: request)
    }

    static func approve(token: String, id: String) async throws {
        try await action("/api/cab-requests/approve", token: token, body: IdBody(id: id))
    }

    static func reject(token: String, id: String, reason: String) async throws {
        try await action("/api/cab-requests/reject", token: token, body: RejectBody(id: id, reason: reason))
    }

    static func cancel(token: String, id: String) async throws {
        try await action("/api/cab-requests/cancel", token: token, body: IdBody(id: id))
    }

    static func complete(token: String, id: String) async throws {
        try await action("/api/cab-requests/complete", token: token, body: IdBody(id: id))
    }

    static func assign(
        token: String,
        id: String,
        vehicleId: String,
        driverName: String?,
        driverPhone: String?
    ) async throws {
        try await action(
            "/api/cab-requests/assign",
            token: token,
            body: AssignBody(id: id, vehicleId: vehicleId, driverName: driverName, driverPhone: driverPhone)
        )
    }

    /// Active fleet vehicles for assignment (same list the web dialog uses).
    static func activeVehicles(token: String) async throws -> [CabRequestVehicle] {
        let data = try await send(path: "/api/mms-fleet/dispatch/vehicles", token: token, body: Optional<IdBody>.none)
        let response = try JSONDecoder().decode(VehiclesResponse.self, from: data)
        guard response.success else { throw CabRequestAPIError.server(response.error ?? "Couldn't load vehicles") }
        return (response.vehicles ?? []).filter {
            ($0.status ?? "active").caseInsensitiveCompare("active") == .orderedSame
        }
    }

    // MARK: - HTTP

    private static func list(_ path: String, token: String) async throws -> [CabRequest] {
        let data = try await send(path: path, token: token, body: Optional<IdBody>.none)
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        guard response.success else { throw CabRequestAPIError.server(response.error ?? "Couldn't load cab requests") }
        return response.requests ?? []
    }

    private static func action<T: Encodable>(_ path: String, token: String, body: T) async throws {
        let data = try await send(path: path, token: token, body: body)
        let response = try JSONDecoder().decode(ActionResponse.self, from: data)
        guard response.success else { throw CabRequestAPIError.server(response.error ?? "Something went wrong") }
    }

    /// GET when `body` is nil, else POST. Error bodies carry `{ error }`.
    private static func send<T: Encodable>(path: String, token: String, body: T?) async throws -> Data {
        guard let url = URL(string: "\(AppConfig.baseURL)\(path)") else {
            throw CabRequestAPIError.server("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        } else {
            request.httpMethod = "GET"
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                SessionInvalidationBus.emit(for: request, responseData: data)
            }
            if http.statusCode >= 400 {
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                if let message { throw CabRequestAPIError.server(message) }
                // The routes are missing on a server that hasn't been updated yet.
                if http.statusCode == 404 {
                    throw CabRequestAPIError.server("Cab requests aren't available on the server yet.")
                }
                throw CabRequestAPIError.server("Request failed (\(http.statusCode))")
            }
        }
        return data
    }
}
