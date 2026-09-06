import Foundation

enum FrontDeskAPIService {
    private static let baseURL = AppConfig.baseURL

    private struct InvitationLookupResponse: Decodable, Sendable {
        let success: Bool
        let invitation: FrontDeskInvitation?
        let error: String?
    }

    private struct CheckInResponse: Decodable, Sendable {
        let success: Bool
        let passNumber: String?
        let error: String?
    }

    private struct CheckOutResponse: Decodable, Sendable {
        let success: Bool
        let checkoutAt: Int64?
        let error: String?
    }

    static func invitation(token: String, inviteToken: String) async throws -> FrontDeskInvitation {
        var components = URLComponents(string: "\(baseURL)/api/frontdesk/invitations/by-token")
        components?.queryItems = [URLQueryItem(name: "token", value: inviteToken)]
        guard let url = components?.url else { throw FrontDeskAPIError.badURL }

        let data = try await request(url: url, method: "GET", token: token)
        let response = try await BackgroundJSONDecoder.decode(InvitationLookupResponse.self, from: data)
        guard response.success, var invitation = response.invitation else {
            throw FrontDeskAPIError.server(response.error ?? "Invitation not found")
        }

        if invitation.checkinState == nil,
           invitation.status?.caseInsensitiveCompare("checked_in") == .orderedSame,
           let invitationID = invitation.invitationID,
           let isActive = try? await isInvitationActive(token: token, invitationID: invitationID) {
            invitation.checkinState = isActive ? "in" : "out"
        }
        return invitation
    }

    static func checkIn(token: String, invitationID: String) async throws -> FrontDeskCheckInResult {
        let data = try await post(
            path: "/api/frontdesk/invitations/checkin",
            token: token,
            body: ["invitationId": invitationID]
        )
        let response = try await BackgroundJSONDecoder.decode(CheckInResponse.self, from: data)
        guard response.success else {
            throw FrontDeskAPIError.server(response.error ?? "Check-in failed")
        }
        return FrontDeskCheckInResult(passNumber: response.passNumber)
    }

    static func checkOut(token: String, invitationID: String) async throws -> FrontDeskCheckOutResult {
        do {
            let data = try await post(
                path: "/api/frontdesk/invitations/checkout",
                token: token,
                body: ["invitationId": invitationID]
            )
            let response = try await BackgroundJSONDecoder.decode(CheckOutResponse.self, from: data)
            guard response.success else {
                throw FrontDeskAPIError.server(response.error ?? "Check-out failed")
            }
            return FrontDeskCheckOutResult(checkoutAt: response.checkoutAt)
        } catch FrontDeskAPIError.unauthorized {
            throw FrontDeskAPIError.unauthorized
        } catch {
            guard try await checkOutViaFunctionAPI(token: token, invitationID: invitationID) else {
                throw error
            }
            return FrontDeskCheckOutResult(
                checkoutAt: Int64(Date().timeIntervalSince1970 * 1_000)
            )
        }
    }

    private static func isInvitationActive(token: String, invitationID: String) async throws -> Bool {
        try await activeCheckInID(token: token, invitationID: invitationID) != nil
    }

    private static func checkOutViaFunctionAPI(token: String, invitationID: String) async throws -> Bool {
        guard let checkInID = try await activeCheckInID(token: token, invitationID: invitationID) else {
            return false
        }
        _ = try await functionCall(
            endpoint: "mutation",
            path: "frontdesk:checkout",
            arguments: [
                "sessionToken": rawSessionToken(token),
                "checkinId": checkInID
            ]
        )
        return true
    }

    private static func activeCheckInID(token: String, invitationID: String) async throws -> String? {
        let response = try await functionCall(
            endpoint: "query",
            path: "frontdesk:listActive",
            arguments: ["sessionToken": rawSessionToken(token)]
        )
        guard let rows = response["value"] as? [[String: Any]] else { return nil }
        return rows.first { ($0["invitationId"] as? String) == invitationID }?["_id"] as? String
    }

    private static func functionCall(
        endpoint: String,
        path: String,
        arguments: [String: Any]
    ) async throws -> [String: Any] {
        let cloudBaseURL = baseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: ".convex.site", with: ".convex.cloud")
        guard let url = URL(string: "\(cloudBaseURL)/api/\(endpoint)") else {
            throw FrontDeskAPIError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "path": path,
            "args": arguments,
            "format": "json"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["status"] as? String == "success" else {
            throw FrontDeskAPIError.server("Front Desk action failed")
        }
        return object
    }

    private static func rawSessionToken(_ token: String) -> String {
        token.replacingOccurrences(of: "Bearer ", with: "", options: [.anchored, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func post(path: String, token: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw FrontDeskAPIError.badURL }
        return try await request(
            url: url,
            method: "POST",
            token: token,
            body: try JSONSerialization.data(withJSONObject: body)
        )
    }

    private static func request(
        url: URL,
        method: String,
        token: String,
        body: Data? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        if http.statusCode == 401 {
            SessionInvalidationBus.emit(for: request)
            throw FrontDeskAPIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw FrontDeskAPIError.server(message ?? "Request failed (\(http.statusCode))")
        }
        return data
    }
}

enum FrontDeskAPIError: LocalizedError {
    case badURL
    case unauthorized
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid Front Desk URL."
        case .unauthorized:
            return "Your session has expired."
        case .server(let message):
            return message
        }
    }
}
