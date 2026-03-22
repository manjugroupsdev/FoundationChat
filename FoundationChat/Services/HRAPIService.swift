import Foundation

@MainActor
@Observable
final class HRAPIService {
    static let shared = HRAPIService()

    private let baseURL = "https://mms20-core-api.azurewebsites.net/api"

    // Generic API response envelope
    private struct APIResponse<T: Decodable>: Decodable {
        let status: String
        let data: T
    }

    private struct ItemsWrapper<T: Decodable>: Decodable {
        let items: [T]
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            // Try ISO 8601 with timezone
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: string) { return date }

            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: string) { return date }

            // Try date-only format
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            for format in ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd HH:mm:ss"] {
                df.dateFormat = format
                if let date = df.date(from: string) { return date }
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(string)")
        }
        return d
    }()

    func fetchItems<T: Decodable>(namespace: String, apiName: String, data: [String: Any]) async throws -> [T] {
        let body: [String: Any] = [
            "namespace": namespace,
            "apiName": apiName,
            "data": data,
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try decoder.decode(APIResponse<ItemsWrapper<T>>.self, from: responseData)
        guard decoded.status == "ok" else {
            throw URLError(.badServerResponse)
        }
        return decoded.data.items
    }

    func callMutation(namespace: String, apiName: String, data: [String: Any]) async throws -> [String: Any] {
        let body: [String: Any] = [
            "namespace": namespace,
            "apiName": apiName,
            "data": data,
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let result = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let status = result["status"] as? String, status == "ok",
              let data = result["data"] as? [String: Any]
        else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Permissions

    func fetchPermissions(limit: Int = 50, mode: String = "all", userId: Int = 0, search: String = "") async throws -> [APIPermission] {
        try await fetchItems(namespace: "hr", apiName: "mobilePermissionsList", data: [
            "limit": limit, "mode": mode, "userId": userId, "search": search,
        ])
    }

    func savePermission(mobilePermissionId: Int = 0, employeeId: Int, permissionDate: String, reason: String, expectedDurationInMins: Int, userId: Int) async throws -> [String: Any] {
        try await callMutation(namespace: "hr", apiName: "mobilePermissionSave", data: [
            "mobilePermissionId": mobilePermissionId,
            "employeeId": employeeId,
            "permissionDate": permissionDate,
            "reason": reason,
            "expectedDurationInMins": expectedDurationInMins,
            "userId": userId,
        ])
    }

    func approvePermission(mobilePermissionId: Int, approvalStatus: String, approvalRemarks: String, userId: Int) async throws -> [String: Any] {
        try await callMutation(namespace: "hr", apiName: "mobilePermissionApprovalSave", data: [
            "mobilePermissionId": mobilePermissionId,
            "approvalStatus": approvalStatus,
            "approvalRemarks": approvalRemarks,
            "userId": userId,
        ])
    }

    // MARK: - Attendance

    func fetchMobileAttendance(limit: Int = 50, mode: String = "all", userId: Int = 0, fromDate: String = "", toDate: String = "", search: String = "") async throws -> [APIMobileAttendance] {
        try await fetchItems(namespace: "hr", apiName: "mobileAttendanceList", data: [
            "limit": limit, "mode": mode, "userId": userId, "fromDate": fromDate, "toDate": toDate, "search": search,
        ])
    }

    func fetchDailyAttendance(date: String, departmentId: Int = 0, employeeId: Int = 0, search: String = "", limit: Int = 50) async throws -> [APIDailyAttendance] {
        try await fetchItems(namespace: "hr", apiName: "dailyAttendanceList", data: [
            "date": date, "departmentId": departmentId, "employeeId": employeeId, "search": search, "limit": limit,
        ])
    }

    func fetchMonthlyAttendance(month: Int, year: Int, departmentId: Int = 0, search: String = "", limit: Int = 100) async throws -> [APIMonthlyAttendance] {
        try await fetchItems(namespace: "hr", apiName: "monthlyAttendanceList", data: [
            "month": month, "year": year, "departmentId": departmentId, "search": search, "limit": limit,
        ])
    }

    func approveMobileAttendance(mobileAttendanceId: Int, approvedAttendance: String, approvalRemarks: String, userId: Int) async throws -> [String: Any] {
        try await callMutation(namespace: "hr", apiName: "mobileAttendanceApprovalSave", data: [
            "mobileAttendanceId": mobileAttendanceId,
            "approvedAttendance": approvedAttendance,
            "approvalRemarks": approvalRemarks,
            "userId": userId,
        ])
    }

    // MARK: - Call Followup

    func fetchCallLogs(limit: Int = 50, search: String = "") async throws -> [APICallLog] {
        try await fetchItems(namespace: "marketing", apiName: "callLogsList", data: [
            "limit": limit, "search": search,
        ])
    }

    func saveLeadFollowup(callLogId: Int, nextReviewDate: String, remarks: String, callStatusId: Int, userId: Int) async throws -> [String: Any] {
        try await callMutation(namespace: "marketing", apiName: "leadFollowupSave", data: [
            "callLogId": callLogId,
            "nextReviewDate": nextReviewDate,
            "remarks": remarks,
            "callStatusId": callStatusId,
            "userId": userId,
        ])
    }

    // MARK: - Site Visits

    func fetchSiteVisits(limit: Int = 50, search: String = "") async throws -> [APISiteVisit] {
        try await fetchItems(namespace: "marketing", apiName: "siteVisitsList", data: [
            "limit": limit, "search": search,
        ])
    }

    func updateSiteVisitStatus(siteVisitId: Int, statusId: Int, statusText: String, userId: Int) async throws -> [String: Any] {
        try await callMutation(namespace: "marketing", apiName: "siteVisitStatusSave", data: [
            "siteVisitId": siteVisitId,
            "statusId": statusId,
            "statusText": statusText,
            "userId": userId,
        ])
    }
}
