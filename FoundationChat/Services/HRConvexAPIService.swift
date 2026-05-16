import Foundation

/// HTTP client for Convex-based HR endpoints (leaves, permissions, attendance).
enum HRConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    // MARK: - Leaves

    private struct LeavesListResponse: Decodable {
        let success: Bool; let total: Int?; let leaves: [ConvexLeave]?; let error: String?
    }

    private struct LeaveBalanceResponse: Decodable {
        let success: Bool; let balance: ConvexLeaveBalance?; let error: String?
    }

    private struct LeaveActionResponse: Decodable {
        let success: Bool; let leaveId: String?; let error: String?
    }

    static func getMyLeaves(token: String) async throws -> [ConvexLeave] {
        let data = try await get(path: "/api/hr/leaves/my", token: token)
        let wrapper = try decode(LeavesListResponse.self, from: data)
        return wrapper.leaves ?? []
    }

    static func getLeaveBalance(token: String, year: Int, staffId: String? = nil) async throws -> ConvexLeaveBalance {
        var path = "/api/hr/leaves/balance?year=\(year)"
        if let staffId { path += "&staffId=\(staffId)" }
        let data = try await get(path: path, token: token)
        let wrapper = try decode(LeaveBalanceResponse.self, from: data)
        guard let balance = wrapper.balance else {
            throw HRConvexAPIError.unexpected("No balance data")
        }
        return balance
    }

    static func getPendingLeaveApprovals(token: String) async throws -> [ConvexLeave] {
        let data = try await get(path: "/api/hr/leaves/pending-approvals", token: token)
        let wrapper = try decode(LeavesListResponse.self, from: data)
        return wrapper.leaves ?? []
    }

    static func applyLeave(
        token: String, leaveType: String, fromDate: String, toDate: String,
        reason: String, reportingToId: String? = nil, reportingToName: String? = nil
    ) async throws -> String {
        var body: [String: Any] = [
            "leaveType": leaveType, "fromDate": fromDate,
            "toDate": toDate, "reason": reason
        ]
        if let reportingToId { body["reportingToId"] = reportingToId }
        if let reportingToName { body["reportingToName"] = reportingToName }
        let data = try await post(path: "/api/hr/leaves/apply", token: token, jsonBody: body)
        let wrapper = try decode(LeaveActionResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to apply leave") }
        return wrapper.leaveId ?? ""
    }

    static func approveLeave(token: String, id: String) async throws {
        let body: [String: Any] = ["id": id]
        let data = try await post(path: "/api/hr/leaves/approve", token: token, jsonBody: body)
        let wrapper = try decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to approve leave") }
    }

    static func rejectLeave(token: String, id: String, reason: String) async throws {
        let body: [String: Any] = ["id": id, "reason": reason]
        let data = try await post(path: "/api/hr/leaves/reject", token: token, jsonBody: body)
        let wrapper = try decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to reject leave") }
    }

    static func cancelLeave(token: String, id: String) async throws {
        let body: [String: Any] = ["id": id]
        let data = try await post(path: "/api/hr/leaves/cancel", token: token, jsonBody: body)
        let wrapper = try decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to cancel leave") }
    }

    // MARK: - Permissions

    private struct PermissionsListResponse: Decodable {
        let success: Bool; let total: Int?; let permissions: [ConvexPermission]?; let error: String?
    }

    private struct PermissionUsageResponse: Decodable {
        let success: Bool
        let usedHours: Double?; let limitHours: Double?; let remainingHours: Double?
        let error: String?
    }

    private struct PermissionActionResponse: Decodable {
        let success: Bool; let permissionId: String?; let error: String?
    }

    static func listPermissions(
        token: String, staffId: String? = nil, status: String? = nil, reportingToId: String? = nil
    ) async throws -> [ConvexPermission] {
        var path = "/api/hr/permissions?"
        var params: [String] = []
        if let staffId { params.append("staffId=\(staffId)") }
        if let status { params.append("status=\(status)") }
        if let reportingToId { params.append("reportingToId=\(reportingToId)") }
        path += params.joined(separator: "&")
        let data = try await get(path: path, token: token)
        let wrapper = try decode(PermissionsListResponse.self, from: data)
        return wrapper.permissions ?? []
    }

    static func getMonthlyPermissionUsage(
        token: String, year: Int, month: Int, staffId: String? = nil
    ) async throws -> ConvexPermissionUsage {
        var path = "/api/hr/permissions/monthly-usage?year=\(year)&month=\(month)"
        if let staffId { path += "&staffId=\(staffId)" }
        let data = try await get(path: path, token: token)
        let wrapper = try decode(PermissionUsageResponse.self, from: data)
        return ConvexPermissionUsage(
            usedHours: wrapper.usedHours,
            limitHours: wrapper.limitHours,
            remainingHours: wrapper.remainingHours
        )
    }

    static func applyPermission(
        token: String, date: String, fromTime: String, toTime: String,
        reason: String, reportingToId: String? = nil, reportingToName: String? = nil
    ) async throws -> String {
        var body: [String: Any] = [
            "date": date, "fromTime": fromTime,
            "toTime": toTime, "reason": reason
        ]
        if let reportingToId { body["reportingToId"] = reportingToId }
        if let reportingToName { body["reportingToName"] = reportingToName }
        let data = try await post(path: "/api/hr/permissions/apply", token: token, jsonBody: body)
        let wrapper = try decode(PermissionActionResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to apply permission") }
        return wrapper.permissionId ?? ""
    }

    static func approvePermission(token: String, id: String) async throws {
        let body: [String: Any] = ["id": id]
        let data = try await post(path: "/api/hr/permissions/approve", token: token, jsonBody: body)
        let wrapper = try decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to approve") }
    }

    static func rejectPermission(token: String, id: String, reason: String) async throws {
        let body: [String: Any] = ["id": id, "reason": reason]
        let data = try await post(path: "/api/hr/permissions/reject", token: token, jsonBody: body)
        let wrapper = try decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to reject") }
    }

    static func cancelPermission(token: String, id: String) async throws {
        let body: [String: Any] = ["id": id]
        let data = try await post(path: "/api/hr/permissions/cancel", token: token, jsonBody: body)
        let wrapper = try decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to cancel") }
    }

    // MARK: - Attendance

    private struct AttendanceListResponse: Decodable {
        let success: Bool; let total: Int?; let records: [ConvexAttendanceRecord]?; let error: String?
    }

    private struct TodayAttendanceResponse: Decodable {
        let success: Bool; let attendance: ConvexTodayAttendance?; let error: String?
    }

    private struct DaySessionsResponse: Decodable {
        let success: Bool
        let sessions: [ConvexDaySession]?
        let cumulativeMinutes: Int?
        let sessionCount: Int?
        let hasOpenSession: Bool?
        let firstPunchIn: String?
        let lastPunchOut: String?
        let error: String?
    }

    private struct PunchResponse: Decodable {
        let success: Bool; let attendanceId: String?; let error: String?
    }

    static func getMyAttendance(token: String, fromDate: String, toDate: String) async throws -> [ConvexAttendanceRecord] {
        let path = "/api/hr/attendance/my?fromDate=\(fromDate)&toDate=\(toDate)"
        let data = try await get(path: path, token: token)
        let wrapper = try decode(AttendanceListResponse.self, from: data)
        return wrapper.records ?? []
    }

    static func getTodayAttendance(token: String) async throws -> ConvexTodayAttendance? {
        let data = try await get(path: "/api/hr/attendance/today", token: token)
        let wrapper = try decode(TodayAttendanceResponse.self, from: data)
        return wrapper.attendance
    }

    static func getDaySessions(token: String, date: String, staffId: String? = nil) async throws -> ConvexDaySessionsResponse {
        var path = "/api/hr/attendance/day-sessions?date=\(date)"
        if let staffId { path += "&staffId=\(staffId)" }
        let data = try await get(path: path, token: token)
        let wrapper = try decode(DaySessionsResponse.self, from: data)
        return ConvexDaySessionsResponse(
            sessions: wrapper.sessions,
            cumulativeMinutes: wrapper.cumulativeMinutes,
            sessionCount: wrapper.sessionCount,
            hasOpenSession: wrapper.hasOpenSession,
            firstPunchIn: wrapper.firstPunchIn,
            lastPunchOut: wrapper.lastPunchOut
        )
    }

    static func punchIn(
        token: String,
        latitude: Double? = nil, longitude: Double? = nil,
        address: String? = nil, source: String = "mobile",
        photo: String? = nil, remarks: String? = nil
    ) async throws -> String {
        var body: [String: Any] = ["source": source]
        if let latitude { body["latitude"] = latitude }
        if let longitude { body["longitude"] = longitude }
        if let address { body["address"] = address }
        if let photo { body["photo"] = photo }
        if let remarks { body["remarks"] = remarks }
        let data = try await post(path: "/api/hr/attendance/punch-in", token: token, jsonBody: body)
        let wrapper = try decode(PunchResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Punch in failed") }
        return wrapper.attendanceId ?? ""
    }

    /// Punch out the current open session. Server auto-finds the open session from the auth token.
    static func punchOut(
        token: String,
        latitude: Double? = nil, longitude: Double? = nil,
        address: String? = nil, photo: String? = nil, remarks: String? = nil
    ) async throws {
        var body: [String: Any] = [:]
        if let latitude { body["latitude"] = latitude }
        if let longitude { body["longitude"] = longitude }
        if let address { body["address"] = address }
        if let photo { body["photo"] = photo }
        if let remarks { body["remarks"] = remarks }
        let data = try await post(path: "/api/hr/attendance/punch-out", token: token, jsonBody: body)
        let wrapper = try decode(PunchResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Punch out failed") }
    }

    static func getPendingAttendanceApprovals(token: String) async throws -> [ConvexAttendanceRecord] {
        let data = try await get(path: "/api/hr/attendance/pending-approvals", token: token)
        let wrapper = try decode(AttendanceListResponse.self, from: data)
        return wrapper.records ?? []
    }

    static func approveAttendance(token: String, id: String, approvedAttendance: String) async throws {
        let body: [String: Any] = ["id": id, "approvedAttendance": approvedAttendance]
        let data = try await post(path: "/api/hr/attendance/approve", token: token, jsonBody: body)
        let wrapper = try decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to approve") }
    }

    static func rejectAttendance(token: String, id: String, reason: String) async throws {
        let body: [String: Any] = ["id": id, "reason": reason]
        let data = try await post(path: "/api/hr/attendance/reject", token: token, jsonBody: body)
        let wrapper = try decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to reject") }
    }

    // MARK: - Marketing / Site Visits

    private struct MySiteVisitsResponse: Decodable {
        let success: Bool
        let total: Int?
        let visits: [ConvexSiteVisit]?
        let error: String?
    }

    /// `GET /api/sitevisits/my?fromDate&toDate` — returns the staff's scheduled
    /// site visits across the given date range. Mirrors Android `getMySiteVisits`.
    static func getMySiteVisits(
        token: String,
        fromDate: String? = nil,
        toDate: String? = nil
    ) async throws -> [ConvexSiteVisit] {
        var params: [String] = []
        if let fromDate { params.append("fromDate=\(fromDate)") }
        if let toDate { params.append("toDate=\(toDate)") }
        var path = "/api/sitevisits/my"
        if !params.isEmpty { path += "?" + params.joined(separator: "&") }
        let data = try await get(path: path, token: token)
        let wrapper = try decode(MySiteVisitsResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        return wrapper.visits ?? []
    }

    // MARK: - Staff Directory

    private struct StaffPaginatedResponse: Decodable {
        let success: Bool
        let page: [ConvexStaffListItem]?
        let isDone: Bool?
        let continueCursor: String?
        let error: String?
    }

    private struct StaffListResponse: Decodable {
        let success: Bool
        let staff: [ConvexStaffListItem]?
        let results: [ConvexStaffListItem]?
        let error: String?
    }

    private struct StaffDetailResponse: Decodable {
        let success: Bool
        let staff: ConvexStaffDetail?
        let error: String?
    }

    private struct StaffCountResponse: Decodable {
        let success: Bool
        let count: Int?
        let error: String?
    }

    /// `GET /api/hr/staff/paginated` — cursor-paginated directory.
    static func getStaffPaginated(
        token: String,
        numItems: Int = 25,
        cursor: String? = nil,
        status: String? = nil
    ) async throws -> ConvexStaffPaginatedPage {
        var params: [String] = ["numItems=\(numItems)"]
        if let cursor, !cursor.isEmpty {
            if let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                params.append("cursor=\(encoded)")
            }
        }
        if let status, !status.isEmpty {
            params.append("status=\(status)")
        }
        let path = "/api/hr/staff/paginated?" + params.joined(separator: "&")
        let data = try await get(path: path, token: token)
        let wrapper = try decode(StaffPaginatedResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        return ConvexStaffPaginatedPage(
            page: wrapper.page ?? [],
            isDone: wrapper.isDone ?? true,
            continueCursor: wrapper.continueCursor
        )
    }

    /// `GET /api/hr/staff/search?query=…` — server-side search.
    static func searchStaff(token: String, query: String) async throws -> [ConvexStaffListItem] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw HRConvexAPIError.badURL
        }
        let data = try await get(path: "/api/hr/staff/search?query=\(encoded)", token: token)
        let wrapper = try decode(StaffListResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        return wrapper.staff ?? wrapper.results ?? []
    }

    /// `GET /api/hr/staff` — full directory (unpaginated).
    static func listAllStaff(token: String) async throws -> [ConvexStaffListItem] {
        let data = try await get(path: "/api/hr/staff", token: token)
        let wrapper = try decode(StaffListResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        return wrapper.staff ?? wrapper.results ?? []
    }

    /// `GET /api/hr/staff/count` — total active staff count.
    static func getStaffCount(token: String) async throws -> Int {
        let data = try await get(path: "/api/hr/staff/count", token: token)
        let wrapper = try decode(StaffCountResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        return wrapper.count ?? 0
    }

    /// `GET /api/hr/staff/get?id=…` — single staff record with full profile.
    static func getStaffDetail(token: String, id: String) async throws -> ConvexStaffDetail {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw HRConvexAPIError.badURL
        }
        let data = try await get(path: "/api/hr/staff/get?id=\(encoded)", token: token)
        let wrapper = try decode(StaffDetailResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        guard let staff = wrapper.staff else {
            throw HRConvexAPIError.unexpected("Staff not found")
        }
        return staff
    }

    // MARK: - Storage (file upload)

    private struct GenerateUploadURLResponse: Decodable {
        let success: Bool; let uploadUrl: String?; let error: String?
    }

    private struct UploadFileResponse: Decodable {
        let storageId: String
    }

    private struct GetFileURLResponse: Decodable {
        let success: Bool; let url: String?; let error: String?
    }

    /// Generate a one-time upload URL for a file.
    static func generateUploadURL(token: String) async throws -> String {
        let data = try await post(path: "/api/storage/generate-upload-url", token: token, jsonBody: [:])
        let wrapper = try decode(GenerateUploadURLResponse.self, from: data)
        guard wrapper.success, let url = wrapper.uploadUrl else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to generate upload URL")
        }
        return url
    }

    /// Upload raw file data to the upload URL and return the storage ID.
    static func uploadFile(uploadURL: String, data fileData: Data, contentType: String = "image/jpeg") async throws -> String {
        guard let url = URL(string: uploadURL) else { throw HRConvexAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HRConvexAPIError.server("File upload failed")
        }
        let wrapper = try JSONDecoder().decode(UploadFileResponse.self, from: data)
        return wrapper.storageId
    }

    /// Get a download URL for a stored file.
    static func getFileURL(token: String, storageId: String) async throws -> String {
        let data = try await get(path: "/api/storage/get-url?storageId=\(storageId)", token: token)
        let wrapper = try decode(GetFileURLResponse.self, from: data)
        guard wrapper.success, let url = wrapper.url else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to get file URL")
        }
        return url
    }

    /// Convenience: upload a photo and return its storage ID.
    static func uploadPhoto(token: String, imageData: Data) async throws -> String {
        let uploadURL = try await generateUploadURL(token: token)
        return try await uploadFile(uploadURL: uploadURL, data: imageData)
    }

    // MARK: - Staff profile (self)

    private struct UpdateMyProfileResponse: Decodable {
        let success: Bool
        let staff: AuthUser?
        let user: AuthUser?
        let error: String?
    }

    private struct ProfilePhotoResponse: Decodable {
        let success: Bool
        let staff: AuthUser?
        let user: AuthUser?
        let error: String?
    }

    /// `POST /api/staff/me/update` — update own profile. Mirrors Android `updateMyProfile`.
    /// Returns the refreshed `AuthUser` snapshot when the server includes one.
    static func updateMyProfile(
        token: String,
        name: String?,
        email: String?,
        phone: String?,
        photoStorageId: String?
    ) async throws -> AuthUser? {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let email { body["email"] = email }
        if let phone { body["phone"] = phone }
        if let photoStorageId { body["photo"] = photoStorageId }
        let data = try await post(path: "/api/staff/me/update", token: token, jsonBody: body)
        let wrapper = try decode(UpdateMyProfileResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update profile")
        }
        return wrapper.staff ?? wrapper.user
    }

    /// `POST /api/hr/staff/me/profile-photo` — set own profile photo storage id.
    static func setMyProfilePhoto(token: String, storageId: String) async throws -> AuthUser? {
        let data = try await post(
            path: "/api/hr/staff/me/profile-photo",
            token: token,
            jsonBody: ["storageId": storageId]
        )
        let wrapper = try decode(ProfilePhotoResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update profile photo")
        }
        return wrapper.staff ?? wrapper.user
    }

    /// `DELETE /api/hr/staff/me/profile-photo` — remove own profile photo.
    static func deleteMyProfilePhoto(token: String) async throws -> AuthUser? {
        guard let url = URL(string: "\(baseURL)/api/hr/staff/me/profile-photo") else {
            throw HRConvexAPIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPError(data: data, response: response)
        let wrapper = try decode(ProfilePhotoResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to remove profile photo")
        }
        return wrapper.staff ?? wrapper.user
    }

    // MARK: - Shared response types

    private struct GenericSuccessResponse: Decodable {
        let success: Bool; let error: String?
    }

    // MARK: - HTTP helpers

    private static func get(path: String, token: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw HRConvexAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPError(data: data, response: response)
        return data
    }

    private static func post(path: String, token: String, jsonBody: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw HRConvexAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPError(data: data, response: response)
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    private static func checkHTTPError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw HRConvexAPIError.unauthorized(error)
            }
            throw HRConvexAPIError.unauthorized("Unauthorized")
        }
        if http.statusCode >= 400 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw HRConvexAPIError.server(error)
            }
            throw HRConvexAPIError.server("Request failed (\(http.statusCode))")
        }
    }
}

// MARK: - Errors

enum HRConvexAPIError: LocalizedError {
    case badURL
    case unauthorized(String)
    case server(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL"
        case .unauthorized(let msg): return msg
        case .server(let msg): return msg
        case .unexpected(let msg): return msg
        }
    }
}
