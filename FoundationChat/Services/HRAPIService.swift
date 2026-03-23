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

            // Handle null
            if container.decodeNil() {
                throw DecodingError.valueNotFound(Date.self, .init(codingPath: container.codingPath, debugDescription: "null date"))
            }

            let string = try container.decode(String.self)
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw DecodingError.valueNotFound(Date.self, .init(codingPath: container.codingPath, debugDescription: "empty date"))
            }

            // Try ISO 8601 with timezone
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: trimmed) { return date }

            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: trimmed) { return date }

            // Try date-only and other formats
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            for format in ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "HH:mm:ss"] {
                df.dateFormat = format
                if let date = df.date(from: trimmed) { return date }
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

    // MARK: - GPS Tracking

    func fetchGPSTrips(limit: Int = 50, search: String = "", userId: Int = 0, mode: String = "all") async throws -> [APIGPSTrip] {
        try await fetchItems(namespace: "marketing", apiName: "siteVisitGPSList", data: [
            "limit": limit, "search": search, "userId": userId, "mode": mode,
        ])
    }

    func fetchGPSTripDetail(siteVisitGPSId: Int) async throws -> APIGPSTripDetail {
        let body: [String: Any] = [
            "namespace": "marketing",
            "apiName": "siteVisitGPSDetail",
            "data": ["siteVisitGPSId": siteVisitGPSId],
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

        let decoded = try decoder.decode(APIResponse<APIGPSTripDetail>.self, from: responseData)
        guard decoded.status == "ok" else { throw URLError(.badServerResponse) }
        return decoded.data
    }

    func fetchGPSDayMap(date: String, userId: Int = 0) async throws -> APIGPSDayMap {
        let body: [String: Any] = [
            "namespace": "marketing",
            "apiName": "siteVisitGPSDayMap",
            "data": ["date": date, "userId": userId],
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

        let decoded = try decoder.decode(APIResponse<APIGPSDayMap>.self, from: responseData)
        guard decoded.status == "ok" else { throw URLError(.badServerResponse) }
        return decoded.data
    }

    func approveGPSTrip(siteVisitGPSId: Int, actorUserId: Int, isApproved: Bool, reason: String = "") async throws -> [String: Any] {
        try await callMutation(namespace: "marketing", apiName: "odApprovalSave", data: [
            "siteVisitGPSId": siteVisitGPSId,
            "actorUserId": actorUserId,
            "isApproved": isApproved,
            "reason": reason,
        ])
    }

    // MARK: - Travel Log

    func fetchTravelLog(limit: Int = 50, search: String = "", fromDate: String = "", toDate: String = "") async throws -> [APITravelLog] {
        try await fetchItems(namespace: "marketing", apiName: "svTravelList", data: [
            "limit": limit, "search": search, "fromDate": fromDate, "toDate": toDate,
            "projectName": "", "driverName": "", "vehicleNumber": "",
        ])
    }

    // MARK: - GPS Session Management (Write)

    func startGPSSession(userId: Int, purpose: String, remarks: String = "", startingLatitude: Double, startingLongitude: Double, callLogId: Int = 0) async throws -> GPSSessionStartResult {
        let body: [String: Any] = [
            "namespace": "marketing",
            "apiName": "gpsSessionStart",
            "data": [
                "userId": userId,
                "purpose": purpose,
                "remarks": remarks,
                "startingLatitude": startingLatitude,
                "startingLongitude": startingLongitude,
                "callLogId": callLogId,
            ] as [String: Any],
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
        let decoded = try decoder.decode(APIResponse<GPSSessionStartResult>.self, from: responseData)
        guard decoded.status == "ok" else { throw URLError(.badServerResponse) }
        return decoded.data
    }

    func postGPSWaypoints(siteVisitGPSId: Int, userId: Int, waypoints: [[String: Any]]) async throws -> GPSWaypointPostResult {
        let body: [String: Any] = [
            "namespace": "marketing",
            "apiName": "gpsWaypointPost",
            "data": [
                "siteVisitGPSId": siteVisitGPSId,
                "userId": userId,
                "waypoints": waypoints,
            ] as [String: Any],
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
        let decoded = try decoder.decode(APIResponse<GPSWaypointPostResult>.self, from: responseData)
        guard decoded.status == "ok" else { throw URLError(.badServerResponse) }
        return decoded.data
    }

    func endGPSSession(siteVisitGPSId: Int, userId: Int, endingLatitude: Double, endingLongitude: Double, closingRemarks: String = "") async throws -> GPSSessionEndResult {
        let body: [String: Any] = [
            "namespace": "marketing",
            "apiName": "gpsSessionEnd",
            "data": [
                "siteVisitGPSId": siteVisitGPSId,
                "userId": userId,
                "endingLatitude": endingLatitude,
                "endingLongitude": endingLongitude,
                "closingRemarks": closingRemarks,
            ] as [String: Any],
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
        let decoded = try decoder.decode(APIResponse<GPSSessionEndResult>.self, from: responseData)
        guard decoded.status == "ok" else { throw URLError(.badServerResponse) }
        return decoded.data
    }

    func uploadGPSPhoto(siteVisitGPSId: Int, imageBase64: String, siteVisitGPSDetailId: Int = 0) async throws -> GPSPhotoUploadResult {
        let body: [String: Any] = [
            "namespace": "marketing",
            "apiName": "gpsPhotoUpload",
            "data": [
                "siteVisitGPSId": siteVisitGPSId,
                "siteVisitGPSDetailId": siteVisitGPSDetailId,
                "imageBase64": imageBase64,
                "imagePath": "",
            ] as [String: Any],
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
        let decoded = try decoder.decode(APIResponse<GPSPhotoUploadResult>.self, from: responseData)
        guard decoded.status == "ok" else { throw URLError(.badServerResponse) }
        return decoded.data
    }

    // MARK: - MMS Auth

    func mmsOtpSend(mobileNumber: String) async throws -> MMSOtpSendResult {
        let body: [String: Any] = [
            "namespace": "auth",
            "apiName": "otpSend",
            "data": ["mobileNumber": mobileNumber],
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

        // Use plain JSONDecoder (no custom date decoder needed for auth)
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let status = json["status"] as? String
        else {
            throw URLError(.badServerResponse)
        }

        if status == "error" {
            let message = json["message"] as? String ?? "Failed to send OTP"
            throw AuthStoreError.smsDeliveryFailed(message)
        }

        guard let data = json["data"] as? [String: Any] else {
            throw URLError(.badServerResponse)
        }

        return MMSOtpSendResult(
            sent: data["sent"] as? Bool,
            message: data["message"] as? String
        )
    }

    func mmsOtpVerify(mobileNumber: String, otp: String) async throws -> MMSOtpVerifyResult {
        let body: [String: Any] = [
            "namespace": "auth",
            "apiName": "otpVerify",
            "data": ["mobileNumber": mobileNumber, "otp": otp],
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

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let status = json["status"] as? String
        else {
            throw URLError(.badServerResponse)
        }

        if status == "error" {
            let message = json["message"] as? String ?? "Verification failed"
            throw AuthStoreError.smsDeliveryFailed(message)
        }

        guard let data = json["data"] as? [String: Any] else {
            throw URLError(.badServerResponse)
        }

        return MMSOtpVerifyResult(
            verified: data["verified"] as? Bool,
            userId: data["userId"] as? Int,
            userName: data["userName"] as? String,
            fullName: data["fullName"] as? String,
            roleId: data["roleId"] as? Int,
            roleName: data["roleName"] as? String,
            isAdmin: data["isAdmin"] as? Bool,
            branchId: data["branchId"] as? Int,
            message: data["message"] as? String
        )
    }

    // MARK: - MMS Session Storage

    private(set) var mmsSession: MMSUserSession? {
        didSet {
            if let session = mmsSession {
                if let data = try? JSONEncoder().encode(session) {
                    UserDefaults.standard.set(data, forKey: "mmsUserSession")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "mmsUserSession")
            }
        }
    }

    var mmsUserId: Int { mmsSession?.userId ?? 0 }
    var isMmsLoggedIn: Bool { mmsSession != nil && mmsSession!.userId > 0 }

    func loadStoredMMSSession() {
        guard let data = UserDefaults.standard.data(forKey: "mmsUserSession"),
              let session = try? JSONDecoder().decode(MMSUserSession.self, from: data)
        else { return }
        mmsSession = session
    }

    func setMMSSession(from result: MMSOtpVerifyResult) {
        guard let userId = result.userId, userId > 0 else { return }
        mmsSession = MMSUserSession(
            userId: userId,
            userName: result.userName ?? "",
            fullName: result.fullName ?? "",
            roleId: result.roleId ?? 0,
            roleName: result.roleName ?? "",
            isAdmin: result.isAdmin ?? false,
            branchId: result.branchId ?? 0
        )
    }

    func clearMMSSession() {
        mmsSession = nil
    }
}
