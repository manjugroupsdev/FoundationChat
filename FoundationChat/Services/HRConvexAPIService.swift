import Foundation

/// HTTP client for Convex-based HR endpoints (leaves, permissions, attendance).
enum HRConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    // MARK: - Leaves

    private struct LeavesListResponse: Decodable, Sendable {
        let success: Bool; let total: Int?; let leaves: [ConvexLeave]?; let error: String?
    }

    private struct LeaveBalanceResponse: Decodable, Sendable {
        let success: Bool; let balance: ConvexLeaveBalance?; let error: String?
    }

    private struct LeaveActionResponse: Decodable, Sendable {
        let success: Bool; let leaveId: String?; let error: String?
    }

    private struct CompOffCreditsResponse: Decodable, Sendable {
        let success: Bool
        let credits: [ConvexCompOffCredit]?
        let error: String?
    }

    private struct ApplyCompOffRequest: Encodable {
        let creditId: String
        let date: String
    }

    private struct PolicyResponse: Decodable, Sendable {
        let success: Bool
        let policy: PolicyData?
    }

    private struct PolicyData: Decodable, Sendable {
        let leave: LeavePolicy?
    }

    struct LeavePolicy: Decodable, Sendable {
        let casualPerYear: Int?
        let sickPerYear: Int?
        let earnedPerYear: Int?
        let types: [String]?
    }

    static func getMyLeaves(token: String) async throws -> [ConvexLeave] {
        let data = try await get(path: "/api/hr/leaves/my", token: token)
        let wrapper = try await decode(LeavesListResponse.self, from: data)
        return wrapper.leaves ?? []
    }

    static func getLeaveBalance(token: String, year: Int, staffId: String? = nil) async throws -> ConvexLeaveBalance {
        var path = "/api/hr/leaves/balance?year=\(year)"
        if let staffId { path += "&staffId=\(staffId)" }
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(LeaveBalanceResponse.self, from: data)
        guard let balance = wrapper.balance else {
            throw HRConvexAPIError.unexpected("No balance data")
        }
        return balance
    }

    static func getPendingLeaveApprovals(
        token: String,
        teamOnly: Bool = false,
        scope: String? = nil,
        viewerStaffId: String? = nil
    ) async throws -> [ConvexLeave] {
        var queryItems: [URLQueryItem] = []
        if teamOnly {
            queryItems.append(URLQueryItem(name: "teamOnly", value: "true"))
        }
        if let scope {
            queryItems.append(URLQueryItem(name: "scope", value: scope))
        }
        var components = URLComponents()
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        let suffix = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        async let dataRequest = get(path: "/api/hr/leaves/pending-approvals\(suffix)", token: token)
        async let directTeamRequest: Set<String>? = scope == "direct"
            ? getDirectTeamIds(token: token)
            : nil
        let data = try await dataRequest
        let wrapper = try await decode(LeavesListResponse.self, from: data)
        let leaves = wrapper.leaves ?? []
        guard let directTeamIds = try await directTeamRequest else { return leaves }
        return leaves.filter {
            isVisibleInDirectApprovalScope(
                status: $0.status,
                staffId: $0.staffId,
                reportingToId: $0.reportingToId,
                pendingWithStaffId: $0.pendingWithStaffId,
                currentApproverId: $0.currentApproverId,
                directTeamIds: directTeamIds,
                viewerStaffId: viewerStaffId
            )
        }
    }

    static func getLeavePolicy(token: String) async throws -> LeavePolicy? {
        let data = try await get(path: "/api/hr/policy", token: token)
        let wrapper = try await decode(PolicyResponse.self, from: data)
        return wrapper.policy?.leave
    }

    static func applyLeave(
        token: String, leaveType: String, fromDate: String, toDate: String,
        reason: String, duration: String? = nil,
        reportingToId: String? = nil, reportingToName: String? = nil,
        isHalfDay: Bool? = nil, halfDaySession: String? = nil, halfDayType: String? = nil
    ) async throws -> String {
        var body: [String: Any] = [
            "leaveType": leaveType, "fromDate": fromDate,
            "toDate": toDate, "reason": reason
        ]
        if let duration { body["duration"] = duration }
        if let reportingToId { body["reportingToId"] = reportingToId }
        if let reportingToName { body["reportingToName"] = reportingToName }
        if let isHalfDay { body["isHalfDay"] = isHalfDay }
        if let halfDaySession { body["halfDaySession"] = halfDaySession }
        if let halfDayType { body["halfDayType"] = halfDayType }
        let data = try await post(path: "/api/hr/leaves/apply", token: token, jsonBody: body)
        let wrapper = try await decode(LeaveActionResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to apply leave") }
        return wrapper.leaveId ?? ""
    }

    static func approveLeave(token: String, id: String) async throws {
        let body: [String: Any] = ["id": id]
        let data = try await post(path: "/api/hr/leaves/approve", token: token, jsonBody: body)
        let wrapper = try await decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to approve leave") }
    }

    static func rejectLeave(token: String, id: String, reason: String) async throws {
        let body: [String: Any] = ["id": id, "reason": reason]
        let data = try await post(path: "/api/hr/leaves/reject", token: token, jsonBody: body)
        let wrapper = try await decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to reject leave") }
    }

    static func cancelLeave(token: String, id: String) async throws {
        let body: [String: Any] = ["id": id]
        let data = try await post(path: "/api/hr/leaves/cancel", token: token, jsonBody: body)
        let wrapper = try await decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to cancel leave") }
    }

    static func getCompOffCredits(token: String) async throws -> [ConvexCompOffCredit] {
        let data = try await get(path: "/api/hr/compoff/credits", token: token)
        let wrapper = try await decode(CompOffCreditsResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to load comp-off credits") }
        return wrapper.credits ?? []
    }

    static func applyCompOff(token: String, creditId: String, date: String) async throws -> String {
        let data = try await post(
            path: "/api/hr/compoff/apply",
            token: token,
            jsonBody: [
                "creditId": creditId,
                "date": date
            ]
        )
        let wrapper = try await decode(LeaveActionResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to apply comp off") }
        return wrapper.leaveId ?? ""
    }

    // MARK: - Permissions

    private struct PermissionsListResponse: Decodable, Sendable {
        let success: Bool; let total: Int?; let permissions: [ConvexPermission]?; let error: String?
    }

    private struct PermissionUsageResponse: Decodable, Sendable {
        let success: Bool
        let usedHours: Double?; let limitHours: Double?; let remainingHours: Double?
        let error: String?
    }

    private struct PermissionActionResponse: Decodable, Sendable {
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
        let wrapper = try await decode(PermissionsListResponse.self, from: data)
        return wrapper.permissions ?? []
    }

    static func getPendingPermissionApprovals(
        token: String,
        all: Bool = false,
        scope: String? = nil,
        viewerStaffId: String? = nil
    ) async throws -> [ConvexPermission] {
        var queryItems: [URLQueryItem] = []
        if all {
            queryItems.append(URLQueryItem(name: "all", value: "true"))
        }
        if let scope {
            queryItems.append(URLQueryItem(name: "scope", value: scope))
        }
        var components = URLComponents()
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        let suffix = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        async let dataRequest = get(path: "/api/hr/permissions/pending-approvals\(suffix)", token: token)
        async let directTeamRequest: Set<String>? = scope == "direct"
            ? getDirectTeamIds(token: token)
            : nil
        let data = try await dataRequest
        let wrapper = try await decode(PermissionsListResponse.self, from: data)
        let permissions = wrapper.permissions ?? []
        guard let directTeamIds = try await directTeamRequest else { return permissions }
        return permissions.filter {
            isVisibleInDirectApprovalScope(
                status: $0.status,
                staffId: $0.staffId,
                reportingToId: $0.reportingToId,
                pendingWithStaffId: $0.pendingWithStaffId,
                currentApproverId: $0.currentApproverId,
                directTeamIds: directTeamIds,
                viewerStaffId: viewerStaffId
            )
        }
    }

    static func getMonthlyPermissionUsage(
        token: String, year: Int, month: Int, staffId: String? = nil
    ) async throws -> ConvexPermissionUsage {
        var path = "/api/hr/permissions/monthly-usage?year=\(year)&month=\(month)"
        if let staffId { path += "&staffId=\(staffId)" }
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(PermissionUsageResponse.self, from: data)
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
        let wrapper = try await decode(PermissionActionResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to apply permission") }
        return wrapper.permissionId ?? ""
    }

    static func approvePermission(token: String, id: String) async throws {
        let body: [String: Any] = ["id": id]
        let data = try await post(path: "/api/hr/permissions/approve", token: token, jsonBody: body)
        let wrapper = try await decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to approve") }
    }

    static func rejectPermission(token: String, id: String, reason: String) async throws {
        let body: [String: Any] = ["id": id, "reason": reason]
        let data = try await post(path: "/api/hr/permissions/reject", token: token, jsonBody: body)
        let wrapper = try await decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to reject") }
    }

    static func cancelPermission(token: String, id: String) async throws {
        let body: [String: Any] = ["id": id]
        let data = try await post(path: "/api/hr/permissions/cancel", token: token, jsonBody: body)
        let wrapper = try await decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to cancel") }
    }

    // MARK: - Fines & Deductions

    private struct FinesListResponse: Decodable, Sendable {
        let success: Bool
        let fines: [ConvexFineDeduction]?
        let error: String?
    }

    private struct CreateFineResponse: Decodable, Sendable {
        let success: Bool
        let fineId: String?
        let error: String?
    }

    static func listFines(token: String, status: String? = nil) async throws -> [ConvexFineDeduction] {
        var path = "/api/hr/fines/list"
        if let status = status?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?status=\(status)"
        }
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(FinesListResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to load fines") }
        return wrapper.fines ?? []
    }

    static func listMyFines(token: String) async throws -> [ConvexFineDeduction] {
        let data = try await get(path: "/api/hr/fines/my", token: token)
        let wrapper = try await decode(FinesListResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to load fines") }
        return wrapper.fines ?? []
    }

    static func createFine(
        token: String,
        employeeId: String,
        amount: Double,
        month: Int,
        year: Int,
        customTypeName: String,
        notes: String? = nil,
        photoStorageId: String? = nil,
        photoFileName: String? = nil
    ) async throws -> String {
        var body: [String: Any] = [
            "employeeId": employeeId,
            "amount": amount,
            "month": month,
            "year": year,
            "customTypeName": customTypeName
        ]
        if let notes, !notes.isEmpty { body["notes"] = notes }
        if let photoStorageId, !photoStorageId.isEmpty { body["photoStorageId"] = photoStorageId }
        if let photoFileName, !photoFileName.isEmpty { body["photoFileName"] = photoFileName }

        let data = try await post(path: "/api/hr/fines/create", token: token, jsonBody: body)
        let wrapper = try await decode(CreateFineResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to create fine") }
        return wrapper.fineId ?? ""
    }

    // MARK: - Attendance

    private struct AttendanceListResponse: Decodable, Sendable {
        let success: Bool
        let total: Int?
        let records: [ConvexAttendanceRecord]?
        let requests: [ConvexAttendanceRecord]?
        let error: String?
    }

    private struct AttendanceTeamScopeResponse: Decodable, Sendable {
        let success: Bool
        let teamCount: Int?
        let hasTeam: Bool?
        let error: String?
    }

    private struct TodayAttendanceResponse: Decodable, Sendable {
        let success: Bool; let attendance: ConvexTodayAttendance?; let error: String?
    }

    private struct DaySessionsResponse: Decodable, Sendable {
        let success: Bool
        let sessions: [ConvexDaySession]?
        let cumulativeMinutes: Int?
        let sessionCount: Int?
        let hasOpenSession: Bool?
        let firstPunchIn: String?
        let lastPunchOut: String?
        let error: String?
    }

    private struct PunchResponse: Decodable, Sendable {
        let success: Bool; let attendanceId: String?; let error: String?
    }

    private struct HomeFenceResponse: Decodable, Sendable {
        let success: Bool
        let fence: ConvexHomeFence?
        let error: String?
    }

    private struct AttendanceRequestResponse: Decodable, Sendable {
        let success: Bool
        let requestId: String?
        let error: String?
    }

    private struct OnDutyTripResponse: Decodable, Sendable {
        let success: Bool
        let tripId: String?
        let alreadyActive: Bool?
        let distanceMeters: Int?
        let alreadyCompleted: Bool?
        let error: String?
    }

    private struct VendorsResponse: Decodable, Sendable {
        let success: Bool
        let vendors: [OnDutyVendor]?
        let error: String?
    }

    static func getMyAttendance(token: String, fromDate: String, toDate: String) async throws -> [ConvexAttendanceRecord] {
        let path = "/api/hr/attendance/my?fromDate=\(fromDate)&toDate=\(toDate)"
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(AttendanceListResponse.self, from: data)
        return wrapper.records ?? []
    }

    static func hasReportingTeam(token: String) async throws -> Bool {
        let data = try await get(path: "/api/hr/attendance/team-scope", token: token)
        let wrapper = try await decode(AttendanceTeamScopeResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load reporting team scope")
        }
        return wrapper.hasTeam ?? ((wrapper.teamCount ?? 0) > 0)
    }

    static func hasAttendanceTeamScope(token: String) async throws -> Bool {
        try await hasReportingTeam(token: token)
    }

    static func getTodayAttendance(token: String) async throws -> ConvexTodayAttendance? {
        let data = try await get(path: "/api/hr/attendance/today", token: token)
        let wrapper = try await decode(TodayAttendanceResponse.self, from: data)
        return wrapper.attendance
    }

    static func getDaySessions(token: String, date: String, staffId: String? = nil) async throws -> ConvexDaySessionsResponse {
        var path = "/api/hr/attendance/day-sessions?date=\(date)"
        if let staffId { path += "&staffId=\(staffId)" }
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(DaySessionsResponse.self, from: data)
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
        photo: String? = nil, remarks: String? = nil,
        deviceId: String? = nil
    ) async throws -> String {
        var body: [String: Any] = ["source": source]
        if let latitude { body["latitude"] = latitude }
        if let longitude { body["longitude"] = longitude }
        if let address { body["address"] = address }
        if let photo { body["photo"] = photo }
        if let remarks { body["remarks"] = remarks }
        if let deviceId { body["deviceId"] = deviceId }
        let data = try await post(path: "/api/hr/attendance/punch-in", token: token, jsonBody: body)
        let wrapper = try await decode(PunchResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Punch in failed") }
        return wrapper.attendanceId ?? ""
    }

    /// Punch out the current open session. Server auto-finds the open session from the auth token.
    static func punchOut(
        token: String,
        latitude: Double? = nil, longitude: Double? = nil,
        address: String? = nil, source: String = "mobile",
        photo: String? = nil, remarks: String? = nil,
        deviceId: String? = nil
    ) async throws {
        var body: [String: Any] = ["source": source]
        if let latitude { body["latitude"] = latitude }
        if let longitude { body["longitude"] = longitude }
        if let address { body["address"] = address }
        if let photo { body["photo"] = photo }
        if let remarks { body["remarks"] = remarks }
        if let deviceId { body["deviceId"] = deviceId }
        let data = try await post(path: "/api/hr/attendance/punch-out", token: token, jsonBody: body)
        let wrapper = try await decode(PunchResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Punch out failed") }
    }

    static func getPendingAttendanceApprovals(
        token: String,
        all: Bool = false,
        scope: String? = nil,
        includeRequests: Bool = false
    ) async throws -> [ConvexAttendanceRecord] {
        var queryItems: [URLQueryItem] = []
        if all {
            queryItems.append(URLQueryItem(name: "all", value: "true"))
        }
        if let scope {
            queryItems.append(URLQueryItem(name: "scope", value: scope))
        }
        if includeRequests {
            queryItems.append(URLQueryItem(name: "requests", value: "true"))
        }

        var components = URLComponents()
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        let path = "/api/hr/attendance/pending-approvals\(components.percentEncodedQuery.map { "?\($0)" } ?? "")"
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(AttendanceListResponse.self, from: data)
        return (wrapper.records ?? []) + (includeRequests ? wrapper.requests ?? [] : [])
    }

    static func getTeamAttendance(token: String, fromDate: String, toDate: String) async throws -> [ConvexAttendanceRecord] {
        let path = "/api/hr/attendance/team-attendance?fromDate=\(fromDate)&toDate=\(toDate)"
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(AttendanceListResponse.self, from: data)
        return wrapper.records ?? []
    }

    static func getAllAttendance(
        token: String,
        fromDate: String,
        toDate: String,
        search: String? = nil
    ) async throws -> [ConvexAttendanceRecord] {
        var queryItems = [
            URLQueryItem(name: "fromDate", value: fromDate),
            URLQueryItem(name: "toDate", value: toDate)
        ]
        if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }

        var components = URLComponents()
        components.queryItems = queryItems
        let path = "/api/hr/attendance/all?\(components.percentEncodedQuery ?? "")"
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(AttendanceListResponse.self, from: data)
        return wrapper.records ?? []
    }

    static func getHrReview(token: String, fromDate: String, toDate: String) async throws -> [ConvexAttendanceRecord] {
        let path = "/api/hr/attendance/hr-review?fromDate=\(fromDate)&toDate=\(toDate)"
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(AttendanceListResponse.self, from: data)
        return wrapper.records ?? []
    }

    static func approveAttendance(token: String, id: String, approvedAttendance: String, isRequest: Bool? = nil) async throws {
        var body: [String: Any] = ["id": id, "approvedAttendance": approvedAttendance]
        if let isRequest { body["isRequest"] = isRequest }
        let data = try await post(path: "/api/hr/attendance/approve", token: token, jsonBody: body)
        let wrapper = try await decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to approve") }
    }

    static func rejectAttendance(token: String, id: String, reason: String, isRequest: Bool? = nil) async throws {
        var body: [String: Any] = ["id": id, "reason": reason]
        if let isRequest { body["isRequest"] = isRequest }
        let data = try await post(path: "/api/hr/attendance/reject", token: token, jsonBody: body)
        let wrapper = try await decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to reject") }
    }

    static func cancelMyAttendance(token: String, date: String) async throws {
        let body: [String: Any] = ["date": date]
        let data = try await post(path: "/api/hr/attendance/cancel", token: token, jsonBody: body)
        let wrapper = try await decode(GenericSuccessResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to withdraw attendance") }
    }

    static func getHomeFence(token: String) async throws -> ConvexHomeFence? {
        let data = try await get(path: "/api/hr/attendance/home-fence", token: token)
        let wrapper = try await decode(HomeFenceResponse.self, from: data)
        guard wrapper.success else { throw HRConvexAPIError.server(wrapper.error ?? "Failed to load home fence") }
        return wrapper.fence
    }

    static func submitAttendanceRequest(
        token: String,
        attendanceId: String,
        date: String,
        type: String,
        remark: String? = nil,
        correctedPunchIn: String? = nil,
        correctedPunchOut: String? = nil,
        correctionReason: String? = nil
    ) async throws -> String {
        var body: [String: Any] = [
            "attendanceId": attendanceId,
            "date": date,
            "type": type
        ]
        if let remark { body["remark"] = remark }
        if let correctedPunchIn { body["correctedPunchIn"] = correctedPunchIn }
        if let correctedPunchOut { body["correctedPunchOut"] = correctedPunchOut }
        if let correctionReason { body["correctionReason"] = correctionReason }
        let data = try await post(path: "/api/hr/attendance/request", token: token, jsonBody: body)
        let wrapper = try await decode(AttendanceRequestResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to submit attendance request")
        }
        return wrapper.requestId ?? ""
    }

    static func startOnDutyTrip(
        token: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String? = nil,
        category: String? = nil,
        targetId: String? = nil,
        targetName: String? = nil,
        targetAddress: String? = nil,
        vehicleOwnership: String? = nil,
        vehicleType: String? = nil
    ) async throws -> String {
        var body: [String: Any] = [:]
        if let latitude { body["lat"] = latitude }
        if let longitude { body["lng"] = longitude }
        if let address { body["address"] = address }
        if let category { body["category"] = category }
        if let targetId { body["targetId"] = targetId }
        if let targetName { body["targetName"] = targetName }
        if let targetAddress { body["targetAddress"] = targetAddress }
        if let vehicleOwnership { body["vehicleOwnership"] = vehicleOwnership }
        if let vehicleType { body["vehicleType"] = vehicleType }
        let data = try await post(path: "/api/geotrack/on-duty/start", token: token, jsonBody: body)
        let wrapper = try await decode(OnDutyTripResponse.self, from: data)
        guard wrapper.success || wrapper.alreadyActive == true else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to start on duty")
        }
        return wrapper.tripId ?? ""
    }

    static func getVendors(token: String) async throws -> [OnDutyVendor] {
        let data = try await get(path: "/api/library/vendors", token: token)
        let wrapper = try await decode(VendorsResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load vendors")
        }
        return (wrapper.vendors ?? []).filter { $0.status?.localizedCaseInsensitiveContains("inactive") != true }
    }

    static func completeOnDutyTrip(
        token: String,
        tripId: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String? = nil
    ) async throws {
        var body: [String: Any] = [:]
        if let tripId { body["tripId"] = tripId }
        if let latitude { body["lat"] = latitude }
        if let longitude { body["lng"] = longitude }
        if let address { body["address"] = address }
        let data = try await post(path: "/api/geotrack/on-duty/complete", token: token, jsonBody: body)
        let wrapper = try await decode(OnDutyTripResponse.self, from: data)
        guard wrapper.success || wrapper.alreadyCompleted == true else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to complete on duty")
        }
    }

    // MARK: - Marketing / Site Visits

    private struct MySiteVisitsResponse: Decodable, Sendable {
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
        let wrapper = try await decode(MySiteVisitsResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        return wrapper.visits ?? []
    }

    // MARK: - Staff Directory

    private struct StaffPaginatedResponse: Decodable, Sendable {
        let success: Bool
        let page: [ConvexStaffListItem]?
        let isDone: Bool?
        let continueCursor: String?
        let error: String?
    }

    private struct StaffListResponse: Decodable, Sendable {
        let success: Bool
        let staff: [ConvexStaffListItem]?
        let results: [ConvexStaffListItem]?
        let error: String?
    }

    private struct StaffDetailResponse: Decodable, Sendable {
        let success: Bool
        let staff: ConvexStaffDetail?
        let error: String?
    }

    private static func getDirectTeamIds(token: String) async throws -> Set<String> {
        let data = try await get(path: "/api/hr/staff/my-team", token: token)
        let wrapper = try await decode(StaffListResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load direct reports")
        }
        return Set((wrapper.staff ?? wrapper.results ?? []).map(\._id))
    }

    private static func isVisibleInDirectApprovalScope(
        status: String?,
        staffId: String?,
        reportingToId: String?,
        pendingWithStaffId: String?,
        currentApproverId: String?,
        directTeamIds: Set<String>,
        viewerStaffId: String?
    ) -> Bool {
        guard status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "pending" else {
            return true
        }
        if let staffId, directTeamIds.contains(staffId) {
            return true
        }
        guard let viewerStaffId else { return false }
        if pendingWithStaffId == viewerStaffId || currentApproverId == viewerStaffId {
            return true
        }
        return pendingWithStaffId == nil
            && currentApproverId == nil
            && reportingToId == viewerStaffId
    }

    private struct StaffCountResponse: Decodable, Sendable {
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
        let wrapper = try await decode(StaffPaginatedResponse.self, from: data)
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
        let wrapper = try await decode(StaffListResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        return wrapper.staff ?? wrapper.results ?? []
    }

    /// `GET /api/hr/staff` — full directory (unpaginated).
    static func listAllStaff(token: String, status: String? = nil) async throws -> [ConvexStaffListItem] {
        var path = "/api/hr/staff"
        if let status = status?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?status=\(status)"
        }
        let data = try await get(path: path, token: token)
        let wrapper = try await decode(StaffListResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        return wrapper.staff ?? wrapper.results ?? []
    }

    /// `GET /api/hr/staff/count` — total active staff count.
    static func getStaffCount(token: String) async throws -> Int {
        let data = try await get(path: "/api/hr/staff/count", token: token)
        let wrapper = try await decode(StaffCountResponse.self, from: data)
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
        let wrapper = try await decode(StaffDetailResponse.self, from: data)
        if !wrapper.success, let err = wrapper.error {
            throw HRConvexAPIError.server(err)
        }
        guard let staff = wrapper.staff else {
            throw HRConvexAPIError.unexpected("Staff not found")
        }
        return staff
    }

    // MARK: - Storage (file upload)

    private struct GenerateUploadURLResponse: Decodable, Sendable {
        let success: Bool; let uploadUrl: String?; let error: String?
    }

    private struct UploadFileResponse: Decodable, Sendable {
        let storageId: String
    }

    private struct GetFileURLResponse: Decodable, Sendable {
        let success: Bool; let url: String?; let error: String?
    }

    /// Generate a one-time upload URL for a file.
    static func generateUploadURL(token: String) async throws -> String {
        let data = try await post(path: "/api/storage/generate-upload-url", token: token, jsonBody: [:])
        let wrapper = try await decode(GenerateUploadURLResponse.self, from: data)
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
        request.setValue(String(fileData.count), forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 180
        request.httpBody = fileData
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HRConvexAPIError.server("File upload failed")
        }
        guard (200..<300).contains(http.statusCode) else {
            let responseText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(180)
            if let responseText, !responseText.isEmpty {
                throw HRConvexAPIError.server("File upload failed (\(http.statusCode)): \(responseText)")
            }
            throw HRConvexAPIError.server("File upload failed (\(http.statusCode))")
        }
        let wrapper = try JSONDecoder().decode(UploadFileResponse.self, from: data)
        return wrapper.storageId
    }

    /// Get a download URL for a stored file.
    static func getFileURL(token: String, storageId: String) async throws -> String {
        let data = try await get(path: "/api/storage/get-url?storageId=\(storageId)", token: token)
        let wrapper = try await decode(GetFileURLResponse.self, from: data)
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

    private struct UpdateMyProfileResponse: Decodable, Sendable {
        let success: Bool
        let staff: AuthUser?
        let user: AuthUser?
        let error: String?
    }

    private struct ProfilePhotoResponse: Decodable, Sendable {
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
        let wrapper = try await decode(UpdateMyProfileResponse.self, from: data)
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
        let wrapper = try await decode(ProfilePhotoResponse.self, from: data)
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
        let wrapper = try await decode(ProfilePhotoResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to remove profile photo")
        }
        return wrapper.staff ?? wrapper.user
    }

    // MARK: - Shared response types

    private struct GenericSuccessResponse: Decodable, Sendable {
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

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try await BackgroundJSONDecoder.decode(type, from: data)
    }

    private static func checkHTTPError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            SessionInvalidationBus.emit()
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

struct OnDutyVendor: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let nickname: String?
    let companyName: String?
    let type: String?
    let phone: String?
    let email: String?
    let address: String?
    let status: String?
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
