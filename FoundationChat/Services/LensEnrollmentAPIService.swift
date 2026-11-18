import Foundation

// Lens staff face enrollment. The phone never talks to the Lens service and
// never sees its key: it sends the picked photos to our server, which checks
// `lens.enroll` (or super admin) and forwards them with the key.
//
//   GET  /api/lens/staff?search=&cursor=&limit=30
//   POST /api/lens/enroll   { staffId, replace, photos: [{ pose, mimeType, dataBase64 }] }
//   POST /api/lens/enroll/pending   { staffId }   (send photos saved while Lens was down)
//   GET  /api/lens/captures?staffId=   (saved photos)
//   POST /api/lens/captures/delete   { captureId } | { staffId, all: true }   (never Lens)
//   POST /api/lens/captures/retake   { staffId, photo: { pose, mimeType, dataBase64 } }

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
    /// Live photos saved on the profile, and how many still wait for Lens.
    let savedPhotos: Int?
    let pendingPhotos: Int?

    var id: String { staffId }
    var waitingPhotos: Int { pendingPhotos ?? 0 }

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
    /// Retake of one pose: the pose, "enrolled" / "lens_pending", and a sentence.
    let pose: String?
    let lensStatus: String?
    let message: String?

    var mustRetake: Bool { needsRetake ?? (addedSamples < 3) }
    var isWaitingForLens: Bool { lensStatus == "lens_pending" }
}

/// One saved photo on the staff profile.
nonisolated struct LensCapture: Decodable, Sendable, Identifiable, Equatable {
    let captureId: String
    let pose: String?
    let lensStatus: String?
    let capturedAt: Double?
    let capturedByName: String?
    let url: String?

    var id: String { captureId }
    var inLens: Bool { lensStatus == "enrolled" }
}

nonisolated struct LensCapturesPage: Decodable, Sendable {
    let enrollment: LensStaffEnrollment?
    let captures: [LensCapture]?
}

nonisolated struct LensDeleteResult: Decodable, Sendable {
    let deleted: Int?
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
        case "NO_USABLE_FACE", "PHOTOS_SHOW_DIFFERENT_PEOPLE", "INVALID_REQUEST", "PHOTO_NOT_USED": return true
        default: return false
        }
    }

    /// Lens wasn't configured / reachable, but the server kept the photos on
    /// the staff profile ("Photos saved…"): not lost, waiting for Lens.
    var savedForLater: Bool {
        guard case .server(_, let code, let message, _) = self,
              code == "LENS_NOT_CONFIGURED" || code == "LENS_NOT_READY" else { return false }
        return message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("photos saved")
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
        let data = try await retryingBusy { try await send(path: "/api/lens/staff", token: token, queryItems: items) }
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

    /// Sends the photos already saved on the staff profile to Lens (no re-recording).
    static func sendPending(token: String, staffId: String) async throws -> LensEnrollResult {
        let json = try JSONSerialization.data(withJSONObject: ["staffId": staffId])
        let data = try await send(path: "/api/lens/enroll/pending", token: token, method: "POST", body: json, timeout: 120)
        return try JSONDecoder().decode(LensEnrollResult.self, from: data)
    }

    /// The staff member's saved photos (newest first) with viewable URLs.
    static func captures(token: String, staffId: String) async throws -> LensCapturesPage {
        let data = try await retryingBusy {
            try await send(
                path: "/api/lens/captures", token: token, queryItems: [URLQueryItem(name: "staffId", value: staffId)]
            )
        }
        return try JSONDecoder().decode(LensCapturesPage.self, from: data)
    }

    /// Deletes our saved photo (or all of them when `captureId` is nil). Never calls Lens.
    static func deleteCaptures(token: String, staffId: String, captureId: String?) async throws -> Int {
        let body: [String: Any] = captureId.map { ["captureId": $0] } ?? ["staffId": staffId, "all": true]
        let json = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(path: "/api/lens/captures/delete", token: token, method: "POST", body: json)
        return (try? JSONDecoder().decode(LensDeleteResult.self, from: data))?.deleted ?? 0
    }

    /// Retake of one pose: added to Lens as a new sample (or kept waiting); the old photo of that pose goes.
    static func retake(token: String, staffId: String, photo: LensPhotoUpload) async throws -> LensEnrollResult {
        let body: [String: Any] = [
            "staffId": staffId,
            "photo": ["pose": photo.pose, "mimeType": "image/jpeg", "dataBase64": photo.jpeg.base64EncodedString()]
        ]
        let json = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(path: "/api/lens/captures/retake", token: token, method: "POST", body: json, timeout: 120)
        return try JSONDecoder().decode(LensEnrollResult.self, from: data)
    }

    /// The prod server sometimes answers 429 (too many requests at once) or a
    /// gateway error for a moment. Reads retry those, and network drops, twice
    /// (0.8 s, 2 s) before the staff sees "busy". Never used for uploads.
    static func retryingBusy<T>(
        delays: [UInt64] = [800_000_000, 2_000_000_000],
        _ block: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await block()
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                guard attempt < delays.count, isBusy(error) else { throw error }
                try await Task.sleep(nanoseconds: delays[attempt])
                attempt += 1
            }
        }
    }

    static func isBusy(_ error: Error) -> Bool {
        if case LensEnrollError.server(let status, _, _, _) = error {
            return [429, 502, 503, 504].contains(status)
        }
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        return false
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
        // Keep the server's "Photos saved…" wording: it tells the staff the photos weren't lost.
        if code == "LENS_NOT_CONFIGURED" || code == "LENS_NOT_READY",
           let server, server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("photos saved") {
            return server
        }
        if let local = byCode(code) { return local }
        if let server, !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return server }
        switch status {
        case 403: return "You don't have permission to enroll staff faces."
        // A 404 with no code means the Lens routes themselves are missing on the server
        // (Convex "No matching routes found"); STAFF_NOT_FOUND is matched by code above.
        case 404: return "Lens enrollment isn't set up on the server yet. Ask the admin to deploy it."
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
