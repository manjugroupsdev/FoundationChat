import Foundation

// Lens staff face enrollment. The phone never talks to the Lens service and
// never sees its key: it sends the picked photos to our server, which checks
// `lens.enroll` (or super admin) and forwards them with the key.
//
//   GET  /api/lens/staff?search=&cursor=&limit=30
//   POST /api/lens/enroll   { staffId, replace, photos: [{ pose, mimeType, dataBase64 }] }

nonisolated struct LensStaffEnrollment: Decodable, Sendable, Equatable {
    let faceSamples: Int?
    let enrolledAt: Double?
    let enrolledByName: String?
    let lastAddedSamples: Int?
}

nonisolated struct LensStaff: Decodable, Identifiable, Sendable, Equatable {
    let staffId: String
    let employeeCode: String?
    let name: String?
    let department: String?
    let designation: String?
    let photoUrl: String?
    let enrollment: LensStaffEnrollment?

    var id: String { staffId }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unnamed staff" : trimmed
    }

    var code: String? {
        let trimmed = employeeCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var canEnroll: Bool { code != nil }
    var isEnrolled: Bool { (enrollment?.faceSamples ?? 0) > 0 }

    var initials: String {
        let parts = displayName.split(whereSeparator: { $0 == " " || $0 == "." }).prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

nonisolated struct LensStaffPage: Decodable, Sendable {
    let items: [LensStaff]
    let nextCursor: String?
}

nonisolated struct LensFailedPhoto: Decodable, Sendable, Identifiable, Equatable {
    let pose: String?
    let code: String?
    let message: String?

    var id: String { (pose ?? "") + (code ?? "") + (message ?? "") }
}

nonisolated struct LensEnrollResult: Decodable, Sendable, Equatable {
    let ok: Bool?
    let employeeCode: String?
    let addedSamples: Int
    let faceSamples: Int?
    let enrolledAt: Double?
    let failed: [LensFailedPhoto]?
    let needsRetake: Bool?

    var mustRetake: Bool { needsRetake ?? (addedSamples < 3) }
}

nonisolated struct LensPhotoUpload: Sendable {
    let pose: String
    let jpeg: Data
}

nonisolated enum LensEnrollError: LocalizedError, Sendable {
    case server(status: Int, code: String?, message: String, failed: [LensFailedPhoto])
    case badURL

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid Lens request."
        case .server(_, _, let message, _): return message
        }
    }

    var code: String? {
        if case .server(_, let code, _, _) = self { return code }
        return nil
    }

    var failed: [LensFailedPhoto] {
        if case .server(_, _, _, let failed) = self { return failed }
        return []
    }

    /// Failures the staff member fixes by recording again (vs. admin / retry).
    var asksForRetake: Bool {
        switch code {
        case "NO_USABLE_FACE", "PHOTOS_SHOW_DIFFERENT_PEOPLE", "INVALID_REQUEST": return true
        default: return false
        }
    }

    var isRetryable: Bool {
        switch self {
        case .server(let status, let code, _, _):
            return status == 503 || code == "LENS_NOT_READY" || status >= 500 && code != "LENS_NOT_CONFIGURED"
        case .badURL: return false
        }
    }
}

nonisolated enum LensEnrollmentAPIService {
    private nonisolated struct ErrorBody: Decodable {
        let error: String?
        let message: String?
        let code: String?
        let failed: [LensFailedPhoto]?
    }

    static func staff(token: String, search: String, cursor: String?, limit: Int = 30) async throws -> LensStaffPage {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { items.append(URLQueryItem(name: "search", value: query)) }
        if let cursor, !cursor.isEmpty { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        let data = try await send(path: "/api/lens/staff", token: token, queryItems: items)
        return try JSONDecoder().decode(LensStaffPage.self, from: data)
    }

    static func enroll(token: String, staffId: String, replace: Bool, photos: [LensPhotoUpload]) async throws -> LensEnrollResult {
        let body: [String: Any] = [
            "staffId": staffId,
            "replace": replace,
            "photos": photos.map {
                ["pose": $0.pose, "mimeType": "image/jpeg", "dataBase64": $0.jpeg.base64EncodedString()]
            }
        ]
        let json = try JSONSerialization.data(withJSONObject: body)
        // Lens builds an embedding per photo; give it time on a slow network.
        let data = try await send(path: "/api/lens/enroll", token: token, method: "POST", body: json, timeout: 120)
        return try JSONDecoder().decode(LensEnrollResult.self, from: data)
    }

    private static func send(
        path: String,
        token: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem] = [],
        timeout: TimeInterval = 30
    ) async throws -> Data {
        guard var components = URLComponents(string: AppConfig.baseURL + path) else { throw LensEnrollError.badURL }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw LensEnrollError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await MMSRequestTransport.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { await SessionInvalidationBus.emit(for: request, responseData: data) }
        guard (200..<300).contains(status) else {
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let code = parsed?.code
            let message = parsed?.error ?? parsed?.message
            throw LensEnrollError.server(
                status: status,
                code: code,
                message: LensMessages.sentence(code: code, status: status, server: message),
                failed: parsed?.failed ?? []
            )
        }
        return data
    }
}

/// Staff-facing sentences (contract). The server already sends these; the
/// local copy covers old servers / bodies without `error`.
nonisolated enum LensMessages {
    static func sentence(code: String?, status: Int, server: String?) -> String {
        if let local = byCode(code) { return local }
        if let server, !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return server }
        switch status {
        case 403: return "You don't have permission to enroll staff faces."
        case 404: return "This staff member was not found."
        case 429, 502, 503, 504: return "The face service is busy right now. Wait a moment and try again."
        default: return "Couldn't enroll the photos (\(status)). Try again."
        }
    }

    static func byCode(_ code: String?) -> String? {
        switch code {
        case "FACE_MATCHES_ANOTHER_PERSON":
            return "This face is already enrolled for another staff member. Contact admin."
        case "FACE_DOES_NOT_MATCH_EXISTING_ENROLLMENT":
            return "These photos don't match this staff member's existing enrollment. Contact admin, or re-enroll with Replace."
        case "NO_USABLE_FACE":
            return "None of the photos could be used. Record again in good light, facing the camera."
        case "PHOTOS_SHOW_DIFFERENT_PEOPLE":
            return "The photos don't match each other. Record again, alone in the frame, turning only slightly."
        case "NO_EMPLOYEE_CODE":
            return "This staff member has no employee code, so they can't be enrolled."
        case "STAFF_NOT_FOUND":
            return "This staff member was not found."
        case "FORBIDDEN":
            return "You don't have permission to enroll staff faces."
        case "LENS_NOT_CONFIGURED":
            return "Lens enrollment is not configured yet."
        case "LENS_REJECTED":
            return "The face service rejected the request. Contact admin."
        case "LENS_NOT_READY":
            return "The face service is starting up. Try again in a few seconds."
        default:
            return nil
        }
    }

    /// Per-photo reason → sentence (server message preferred).
    static func photoReason(_ failure: LensFailedPhoto) -> String {
        if let message = failure.message, !message.isEmpty { return message }
        switch failure.code {
        case "NO_FACE": return "No face found, or the head is turned too far."
        case "BLURRY_OR_POOR_QUALITY_FACE": return "Too blurred."
        case "FACE_TOO_SMALL": return "The face is too small. Move closer."
        case "NOT_SAME_PERSON": return "This photo doesn't match the others."
        case "TOO_SIMILAR_TO_ANOTHER_PERSON": return "Too similar to another enrolled person."
        case "INVALID_IMAGE": return "The photo couldn't be read."
        default: return "This photo couldn't be used."
        }
    }
}
