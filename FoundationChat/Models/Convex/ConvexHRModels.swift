import Foundation

// MARK: - Leaves

struct ConvexLeave: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let leaveId: String?
    let staffName: String?
    let leaveType: String?
    let fromDate: String?
    let toDate: String?
    let days: Double?
    let reason: String?
    let status: String?
    let appliedOn: String?
    let approvedBy: String?
    let rejectedReason: String?

    var id: String { _id }

    var statusColor: String {
        switch status {
        case "approved": return "green"
        case "rejected": return "red"
        case "cancelled": return "gray"
        default: return "orange"
        }
    }

    var leaveTypeLabel: String {
        switch leaveType {
        case "casual": return "Casual Leave"
        case "sick": return "Sick Leave"
        case "earned": return "Earned Leave"
        case "unpaid": return "Unpaid Leave"
        case "compensatory": return "Compensatory Off"
        default: return leaveType?.capitalized ?? "Leave"
        }
    }
}

struct ConvexLeaveBalance: Decodable, Equatable, Sendable {
    let casual: Double?
    let casualUsed: Double?
    let sick: Double?
    let sickUsed: Double?
    let earned: Double?
    let earnedUsed: Double?
    let year: Int?

    var casualRemaining: Double { (casual ?? 0) - (casualUsed ?? 0) }
    var sickRemaining: Double { (sick ?? 0) - (sickUsed ?? 0) }
    var earnedRemaining: Double { (earned ?? 0) - (earnedUsed ?? 0) }
}

// MARK: - Permissions

struct ConvexPermission: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let permissionId: String?
    let staffName: String?
    let date: String?
    let fromTime: String?
    let toTime: String?
    let reason: String?
    let status: String?
    let appliedOn: String?
    let approvedBy: String?
    let rejectedReason: String?
    let durationMinutes: Int?

    var id: String { _id }

    var statusColor: String {
        switch status {
        case "approved": return "green"
        case "rejected": return "red"
        case "cancelled": return "gray"
        default: return "orange"
        }
    }

    var timeRange: String {
        guard let from = fromTime, let to = toTime else { return "--" }
        return "\(from) – \(to)"
    }
}

struct ConvexPermissionUsage: Decodable, Equatable, Sendable {
    let usedHours: Double?
    let limitHours: Double?
    let remainingHours: Double?
}

// MARK: - Attendance

struct ConvexAttendanceSession: Decodable, Equatable, Sendable {
    let punchInTime: String?
    let punchOutTime: String?
    let punchInLatitude: Double?
    let punchInLongitude: Double?
    let punchInPhoto: String?
    let punchOutLatitude: Double?
    let punchOutLongitude: Double?
    let punchOutPhoto: String?
    let source: String?
}

struct ConvexAttendanceRecord: Decodable, Identifiable, Equatable, Sendable {
    let _id: String?
    let _creationTime: Double?
    let attendanceId: String?
    let date: String?
    let firstPunchIn: String?
    let lastPunchOut: String?
    let sessionCount: Int?
    let sessions: [ConvexAttendanceSession]?
    let totalMinutes: Int?
    let cumulativeMinutes: Int?
    let attendanceValue: Double?
    let staffId: String?
    let staffName: String?
    let source: String?
    let status: String?
    let approvedAttendance: String?
    let approvedBy: String?
    let approvedByName: String?
    let approvedOn: String?

    var id: String { _id ?? attendanceId ?? UUID().uuidString }

    var totalHoursFormatted: String {
        let mins = totalMinutes ?? cumulativeMinutes ?? 0
        guard mins > 0 else { return "--" }
        let h = mins / 60
        let m = mins % 60
        return String(format: "%dh %02dm", h, m)
    }

    var punchInFormatted: String {
        guard let t = firstPunchIn ?? sessions?.first?.punchInTime else { return "--" }
        return Self.formatTime(t)
    }

    var punchOutFormatted: String {
        guard let t = lastPunchOut ?? sessions?.last?.punchOutTime else { return "--" }
        return Self.formatTime(t)
    }

    private static func formatTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let tf = DateFormatter()
            tf.dateFormat = "hh:mm a"
            return tf.string(from: date)
        }
        return iso
    }
}

struct ConvexTodayAttendance: Decodable, Equatable, Sendable {
    let _id: String?
    let attendanceId: String?
    let date: String?
    let punchInTime: String?
    let punchOutTime: String?
    let punchInLatitude: Double?
    let punchInLongitude: Double?
    let punchInAddress: String?
    let punchInPhoto: String?
    let punchOutLatitude: Double?
    let punchOutLongitude: Double?
    let punchOutAddress: String?
    let punchOutPhoto: String?
    let totalMinutes: Int?
    let cumulativeMinutes: Int?
    let sessionCount: Int?
    let source: String?
    let status: String?
    let remarks: String?

    var hasPunchedIn: Bool { punchInTime != nil }
    var hasPunchedOut: Bool { punchOutTime != nil }
    var isOpen: Bool { hasPunchedIn && !hasPunchedOut }

    var punchInDate: Date? {
        guard let t = punchInTime else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: t)
    }

    var punchOutDate: Date? {
        guard let t = punchOutTime else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: t)
    }
}

struct ConvexDaySession: Decodable, Identifiable, Equatable, Sendable {
    let _id: String?
    let punchInTime: String?
    let punchOutTime: String?
    let durationMinutes: Int?
    let punchInLatitude: Double?
    let punchInLongitude: Double?
    let punchOutLatitude: Double?
    let punchOutLongitude: Double?

    var id: String { _id ?? UUID().uuidString }
}

struct ConvexDaySessionsResponse: Decodable, Equatable, Sendable {
    let sessions: [ConvexDaySession]?
    let cumulativeMinutes: Int?
    let sessionCount: Int?
    let hasOpenSession: Bool?
    let firstPunchIn: String?
    let lastPunchOut: String?
}

// MARK: - Staff Directory

struct ConvexStaffListItem: Decodable, Identifiable, Equatable, Sendable, Hashable {
    let _id: String
    let name: String?
    let phone: String?
    let role: String?
    let designation: String?
    let status: String?
    let employeeId: String?
    let department: String?

    var id: String { _id }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed : nil) ?? "Unnamed"
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first.map(String.init) }
        return chars.joined().uppercased()
    }

    var subtitle: String {
        [designation, role]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var formattedPhone: String? {
        guard let phone, !phone.isEmpty else { return nil }
        let digits = phone.filter(\.isNumber)
        if digits.count == 10 { return "+91 \(digits)" }
        if digits.count == 12, digits.hasPrefix("91") {
            let rest = digits.dropFirst(2)
            return "+91 \(rest)"
        }
        return phone
    }

    var isActive: Bool {
        (status ?? "").lowercased() == "active"
    }
}

struct ConvexStaffEmergencyContact: Decodable, Equatable, Sendable {
    let name: String?
    let phone: String?
    let relation: String?
}

struct ConvexStaffDocument: Decodable, Equatable, Sendable, Identifiable {
    let docType: String?
    let name: String?
    let storageId: String?
    let uploadedOn: String?

    var id: String { storageId ?? "\(docType ?? "")-\(uploadedOn ?? UUID().uuidString)" }
}

struct ConvexStaffDetail: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let name: String?
    let phone: String?
    let email: String?
    let role: String?
    let designation: String?
    let department: String?
    let status: String?
    let employeeId: String?
    let company: String?
    let branch: String?
    let dateOfBirth: String?
    let joiningDate: String?
    let bloodGroup: String?
    let address: String?
    let city: String?
    let state: String?
    let pincode: String?
    let aadhaarNumber: String?
    let panNumber: String?
    let bankName: String?
    let accountNumber: String?
    let branchName: String?
    let ifscCode: String?
    let emergencyContact: ConvexStaffEmergencyContact?
    let gender: String?
    let maritalStatus: String?
    let fatherName: String?
    let motherName: String?
    let religion: String?
    let nationality: String?
    let qualification: String?
    let experienceYears: Int?
    let reportingToName: String?
    let roleLevel: Int?
    let documents: [ConvexStaffDocument]?
    let photo: String?

    var id: String { _id }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed : nil) ?? "Unnamed"
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first.map(String.init) }
        return chars.joined().uppercased()
    }

    var headerSubtitle: String {
        [designation, department]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var isActive: Bool {
        (status ?? "").lowercased() == "active"
    }
}

struct ConvexStaffPaginatedPage: Decodable, Equatable, Sendable {
    let page: [ConvexStaffListItem]
    let isDone: Bool
    let continueCursor: String?
}
