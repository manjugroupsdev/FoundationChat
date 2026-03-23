import Foundation

// MARK: - Permission Models

struct APIPermission: Decodable, Identifiable, Equatable {
    let mobilePermissionId: Int
    let employeeId: Int
    let employeeName: String?
    let employeeCode: String?
    let departmentName: String?
    let permissionDate: Date?
    let reason: String?
    let expectedDurationInMins: Int?
    let beginningDateTime: Date?
    let endingDateTime: Date?
    let totalDurationInMins: Int?
    let closingRemarks: String?
    let approvalStatus: String?
    let approvalByText: String?
    let approvalDateTime: Date?

    var id: Int { mobilePermissionId }

    var durationFormatted: String {
        let mins = totalDurationInMins ?? expectedDurationInMins ?? 0
        let h = mins / 60
        let m = mins % 60
        return String(format: "%02d:%02d", h, m)
    }

    var permissionStatus: PermissionStatus {
        switch approvalStatus?.lowercased() {
        case "approved": return .approved
        case "rejected": return .rejected
        default: return .pending
        }
    }
}

enum PermissionStatus: String, CaseIterable {
    case pending = "Pending"
    case approved = "Approved"
    case rejected = "Rejected"
}

// MARK: - Attendance Models

struct APIMobileAttendance: Decodable, Identifiable, Equatable {
    let mobileAttendanceId: Int
    let employeeId: Int
    let employeeName: String?
    let empUserName: String?
    let empUserId: Int?
    let departmentName: String?
    let inDateAndTime: Date?
    let outDateAndTime: Date?
    let totalDurationInMins: Int?
    let lateEntryDurationInMins: Int?
    let earlyExitDurationInMins: Int?
    let approvedAttendance: String?
    let approvalRemarks: String?
    let needApproval: Bool?
    let startingLocation: String?
    let endingLocation: String?
    let empUserMobileNo: String?

    var id: Int { mobileAttendanceId }

    var isOpen: Bool {
        outDateAndTime == nil
    }

    var totalHours: Double? {
        guard let mins = totalDurationInMins, mins > 0 else {
            guard let inTime = inDateAndTime, let outTime = outDateAndTime else { return nil }
            return outTime.timeIntervalSince(inTime) / 3600
        }
        return Double(mins) / 60
    }

    var totalHoursFormatted: String? {
        guard let hours = totalHours, hours > 0 else { return nil }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%02d:%02d", h, m)
    }
}

struct APIDailyAttendance: Decodable, Identifiable, Equatable {
    let dailyAttendanceId: Int
    let employeeId: Int
    let employeeName: String?
    let employeeCode: String?
    let departmentName: String?
    let designationName: String?
    let dateAndTime: String?
    let morningSession: String?
    let eveningSession: String?
    let inTime: String?
    let outTime: String?
    let totalHours: String?
    let workingDurationInMins: Int?
    let attendanceValue: Double?
    let morningRemarks: String?
    let eveningRemarks: String?
    let isVerified: Bool?

    var id: Int { dailyAttendanceId }

    var workingHoursFormatted: String? {
        if let total = totalHours, !total.isEmpty {
            // Format is "HH:mm:ss" — strip seconds
            let parts = total.split(separator: ":")
            if parts.count >= 2 {
                return "\(parts[0]):\(parts[1])"
            }
            return total
        }
        guard let mins = workingDurationInMins, mins > 0 else { return nil }
        let h = mins / 60
        let m = mins % 60
        return String(format: "%02d:%02d", h, m)
    }
}

struct APIMonthlyAttendance: Decodable, Identifiable, Equatable {
    let employeeId: Int
    let employeeName: String?
    let employeeCode: String?
    let departmentName: String?
    let designationName: String?
    let totalPresent: Double?
    let totalAbsent: Double?
    let totalLeave: Double?
    let totalHolidays: Double?
    let totalWeekOffs: Double?
    let totalWorkingDays: Double?
    let totalOtMins: Int?
    let lateEntries: Int?
    let earlyExits: Int?
    let dayWise: [APIDayWise]?

    var id: Int { employeeId }
}

struct APIDayWise: Decodable, Equatable, Identifiable {
    let day: Int
    let attendanceValue: Double?
    let attendanceType: String?
    let inTime: String?
    let outTime: String?
    let remarks: String?

    var id: Int { day }
}

// MARK: - Call Followup Models

struct APICallLog: Decodable, Identifiable, Equatable {
    let callLogId: Int
    let callStatusId: Int?
    let clientId: Int?
    let callRefNo: String?
    let createdDateAndTime: Date?
    let clientName: String?
    let mobileNumber: String?
    let location: String?
    let nameOfProject: String?
    let callSource: String?
    let callStatus: String?
    let callType: String?
    let assignedTo: String?
    let reason: String?
    let remarks: String?
    let reviewDateTime: Date?
    let clientVisited: Bool?

    var id: Int { callLogId }

    var displayName: String { clientName ?? "Unknown" }
    var displayPhone: String { mobileNumber ?? "" }
}

// MARK: - Site Visit Models

struct APISiteVisit: Decodable, Identifiable, Equatable {
    let siteVisitId: Int
    let siteVisitRefNo: String?
    let siteVisitDate: Date?
    let clientName: String?
    let mobileNumber: String?
    let projectName: String?
    let currentStatusId: Int?
    let currentStatusText: String?
    let siteIncharge: String?
    let confirmedByName: String?
    let pickupLocation: String?
    let pickupTime: String?
    let bookingStatusId: Int?
    let bookingStatusText: String?

    var id: Int { siteVisitId }
    var displayClient: String { clientName ?? "Unknown" }
    var displayProject: String { projectName ?? "" }
    var displayStatus: String { currentStatusText ?? "Unknown" }
}

// MARK: - Dashboard Summary

struct DayAttendanceSummary: Identifiable {
    let id = UUID()
    let day: String
    let hours: Double?
    let date: Date
}

// MARK: - GPS Tracking Models

struct APIGPSTrip: Decodable, Identifiable, Equatable {
    let siteVisitGPSId: Int
    let refNo: String?
    let purpose: String?
    let remarks: String?
    let startingDateAndTime: Date?
    let endingDateAndTime: Date?
    let isApproved: Bool?
    let userId: Int?
    let userName: String?
    let roleId: Int?
    let startingLocation: String?
    let endingLocation: String?
    let noOfLocation: Int?
    let noOfImages: Int?
    let totalDuration: String?
    let createdDateAndTime: Date?

    var id: Int { siteVisitGPSId }
    var displayName: String { userName ?? "Unknown" }

    var startCoordinate: (lat: Double, lng: Double)? {
        parseCoordinate(startingLocation)
    }

    var endCoordinate: (lat: Double, lng: Double)? {
        parseCoordinate(endingLocation)
    }

    private func parseCoordinate(_ str: String?) -> (lat: Double, lng: Double)? {
        guard let str, !str.isEmpty else { return nil }
        let parts = str.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) else { return nil }
        return (lat, lng)
    }
}

struct APIGPSTripDetail: Decodable {
    let siteVisitGPSId: Int
    let refNo: String?
    let userName: String?
    let purpose: String?
    let startingDateAndTime: Date?
    let endingDateAndTime: Date?
    let totalDuration: String?
    let waypoints: [APIWaypoint]
}

struct APIWaypoint: Decodable, Identifiable, Equatable {
    let latitude: Double
    let longitude: Double
    let isManuallyCaptured: Bool?
    let description: String?

    var id: String { "\(latitude),\(longitude)" }
}

struct APIGPSDayMap: Decodable {
    let date: String?
    let users: [APIGPSDayUser]
    let waypoints: [APIGPSDayWaypoint]
    let segments: [APIGPSSegment]
}

struct APIGPSDayUser: Decodable, Identifiable, Equatable {
    let userId: Int
    let userName: String?
    let recordCount: Int?
    let totalPoints: Int?
    let totalDuration: String?
    let firstStart: Date?
    let lastEnd: Date?
    let purposes: String?

    var id: Int { userId }
    var displayName: String { userName ?? "User \(userId)" }
}

struct APIGPSDayWaypoint: Decodable, Identifiable, Equatable {
    let lat: Double
    let lng: Double
    let manual: Bool?
    let time: Date?
    let gpsId: Int?

    var id: String { "\(lat),\(lng),\(gpsId ?? 0)" }
}

struct APIGPSSegment: Decodable, Identifiable, Equatable {
    let gpsId: Int
    let purpose: String?
    let startTime: Date?
    let endTime: Date?

    var id: Int { gpsId }
}

struct APITravelLog: Decodable, Identifiable, Equatable {
    let siteVisitDate: Date?
    let nameOfProject: String?
    let clientName: String?
    let pickupLocation: String?
    let pickupTime: String?
    let driverName: String?
    let driverContactNumber: String?
    let vehicleNumber: String?
    let openingKM: Double?
    let closingKM: Double?
    let totalKM: Double?
    let siteIncharge: String?
    let hodName: String?

    var id: String {
        "\(siteVisitDate?.timeIntervalSince1970 ?? 0)_\(clientName ?? "")_\(nameOfProject ?? "")"
    }
}

// MARK: - GPS Write Models

struct GPSSessionStartResult: Decodable {
    let siteVisitGPSId: Int
    let refNo: String?
}

struct GPSWaypointPostResult: Decodable {
    let savedCount: Int
}

struct GPSSessionEndResult: Decodable {
    let totalWaypoints: Int?
    let totalDistanceKm: Double?
    let totalDuration: String?
}

struct GPSPhotoUploadResult: Decodable {
    let imageId: Int?
    let imagePath: String?
}

// MARK: - MMS Auth Models

struct MMSOtpSendResult: Decodable {
    let sent: Bool?
    let message: String?
}

struct MMSOtpVerifyResult: Decodable {
    let verified: Bool?
    let userId: Int?
    let userName: String?
    let fullName: String?
    let roleId: Int?
    let roleName: String?
    let isAdmin: Bool?
    let branchId: Int?
    let message: String?
}

// MARK: - MMS User Session

struct MMSUserSession: Codable {
    let userId: Int
    let userName: String
    let fullName: String
    let roleId: Int
    let roleName: String
    let isAdmin: Bool
    let branchId: Int
}
