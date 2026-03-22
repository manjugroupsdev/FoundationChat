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
