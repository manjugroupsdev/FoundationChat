import Foundation

// MARK: - Leaves

struct ConvexLeave: Codable, Identifiable, Equatable, Sendable {
    let _id: String
    let leaveId: String?
    let staffId: String?
    let staffName: String?
    let reportingToId: String?
    let pendingWithStaffId: String?
    let currentApproverId: String?
    let leaveType: String?
    let fromDate: String?
    let toDate: String?
    let days: Double?
    let reason: String?
    let status: String?
    let appliedOn: String?
    let approvedBy: String?
    let rejectedReason: String?
    // Half-day metadata. The backend books a half-day against a base leave type
    // (unpaid, casual, …) and flags it with these fields on /my + approvals, so
    // the list card can render "0.5 Day" and the "Half-day (Morning)" label the
    // same way Android does. Optional so older/absent keys decode cleanly.
    let isHalfDay: Bool?
    let halfDaySession: String?
    let halfDayType: String?

    var id: String { _id }

    /// Mirrors Android's `isHalfDay == true || leaveType contains "half_day"`.
    var isHalfDayLeave: Bool {
        if isHalfDay == true { return true }
        return leaveType?.lowercased().contains("half_day") == true
    }

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

struct ConvexLeaveBalance: Codable, Equatable, Sendable {
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

struct ConvexCompOffCredit: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let earnedDate: String?
    let expiresAt: String?
    let source: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case earnedDate, expiresAt, source, status
    }
}

// MARK: - Permissions

struct ConvexPermission: Codable, Identifiable, Equatable, Sendable {
    let _id: String
    let permissionId: String?
    let staffId: String?
    let staffName: String?
    let reportingToId: String?
    let pendingWithStaffId: String?
    let currentApproverId: String?
    let date: String?
    let fromTime: String?
    let toTime: String?
    let reason: String?
    let status: String?
    let appliedOn: String?
    let approvedBy: String?
    let rejectedReason: String?
    // The backend returns the slip length as `hours` (a Double, e.g. 1.5),
    // which is what Android's permission card renders. `durationMinutes` is
    // kept only as a legacy fallback — reading it alone left the iOS card
    // stuck on "--" because the real payload key is `hours`.
    let hours: Double?
    let durationMinutes: Int?

    var id: String { _id }

    /// Slip length in hours, preferring the backend `hours` field (Android
    /// parity) and falling back to `durationMinutes` when only that is present.
    var durationHours: Double? {
        if let hours { return hours }
        if let durationMinutes { return Double(durationMinutes) / 60 }
        return nil
    }

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

struct ConvexPermissionUsage: Codable, Equatable, Sendable {
    let usedHours: Double?
    let limitHours: Double?
    let remainingHours: Double?
}

// MARK: - Fines & Deductions

struct ConvexFineDeduction: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let staffName: String?
    let employeeId: String?
    let department: String?
    let typeName: String?
    let amount: Double?
    let month: Int?
    let year: Int?
    let monthName: String?
    let status: String?
    let notes: String?
    let photoUrl: String?
    let staffPhotoUrl: String?
    let createdAt: String?

    var id: String { _id }

    var displayName: String {
        staffName?.nonBlank ?? employeeId?.nonBlank ?? "Staff"
    }

    var displayDepartment: String {
        department?.nonBlank?.capitalized ?? "-"
    }

    var displayType: String {
        typeName?.nonBlank ?? "Fine"
    }

    var displayStatus: String {
        (status?.nonBlank ?? "active").capitalized
    }

    var displayDate: String {
        let parts = [monthName?.nonBlank, year.map(String.init)]
            .compactMap { $0 }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return createdAt?.nonBlank ?? ""
    }

    var initials: String {
        let pieces = displayName
            .split(separator: " ")
            .compactMap(\.first)
        let text = String(pieces.prefix(2)).uppercased()
        return text.isEmpty ? "S" : text
    }
}

// MARK: - Attendance

struct ConvexAttendanceSession: Codable, Equatable, Sendable {
    let punchInTime: String?
    let punchOutTime: String?
    let punchOutSource: String?
    let punchInLatitude: Double?
    let punchInLongitude: Double?
    let punchInPhoto: String?
    let punchOutLatitude: Double?
    let punchOutLongitude: Double?
    let punchOutPhoto: String?
    let source: String?
}

struct ConvexAttendanceFine: Codable, Equatable, Sendable, Identifiable {
    let typeName: String?
    let amount: Double?
    let reason: String?

    var id: String {
        "\(typeName ?? "fine")-\(amount ?? 0)-\(reason ?? "")"
    }
}

struct ConvexAttendanceRecord: Codable, Identifiable, Equatable, Sendable {
    let _id: String?
    let _creationTime: Double?
    let attendanceId: String?
    let date: String?
    let firstPunchIn: String?
    let lastPunchOut: String?
    let punchInTime: String?
    let punchOutTime: String?
    let hasOpenSession: Bool?
    let sessionCount: Int?
    let sessions: [ConvexAttendanceSession]?
    let totalMinutes: Int?
    let cumulativeMinutes: Int?
    let attendanceValue: Double?
    let staffId: String?
    let staffName: String?
    let designation: String?
    let employeeId: String?
    let staffPhotoUrl: String?
    let requestType: String?
    let requestedPunchIn: String?
    let requestedPunchOut: String?
    let requestReason: String?
    let requestStage: String?
    let source: String?
    let status: String?
    let approvedAttendance: String?
    let approvedBy: String?
    let approvedByName: String?
    let approvedOn: String?
    let penaltyKind: String?
    let penaltyReason: String?
    let penaltyTaskId: String?
    let penaltyTaskUrl: String?
    let lateMinutes: Int?
    let fineAmount: Double?
    let lateFineDeduction: Double?
    let otherFines: [ConvexAttendanceFine]?

    var id: String {
        if let _id = _id?.trimmingCharacters(in: .whitespacesAndNewlines), !_id.isEmpty {
            return _id
        }
        if let attendanceId = attendanceId?.trimmingCharacters(in: .whitespacesAndNewlines), !attendanceId.isEmpty {
            return attendanceId
        }
        let staffDateKey = [staffId, date]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        if !staffDateKey.isEmpty {
            return staffDateKey
        }
        if let date = date?.trimmingCharacters(in: .whitespacesAndNewlines), !date.isEmpty {
            return date
        }
        return "attendance-unknown"
    }

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
        guard let t = resolvedPunchOut else { return "--" }
        return Self.formatTime(t)
    }

    var resolvedPunchOut: String? {
        let firstIn = firstPunchIn ?? sessions?.first?.punchInTime
        guard hasOpenSession != true else { return nil }
        let candidate = lastPunchOut ?? sessions?.last?.punchOutTime
        guard let candidate, candidate != firstIn else { return nil }
        return candidate
    }

    /// Mirrors the web attendance badge rule. A regular absence must remain a
    /// plain "Absent"; only a system deadline/task penalty is called out.
    var hasAbsentPenalty: Bool {
        guard approvedAttendance?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "absent" else {
            return false
        }
        let approver = approvedByName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = penaltyKind?.trimmingCharacters(in: .whitespacesAndNewlines)
        return approver == "System (RO deadline)"
            || approver == "System (HR deadline)"
            || kind?.isEmpty == false
    }

    var resolvedPenaltyReason: String? {
        guard hasAbsentPenalty else { return nil }
        if let reason = penaltyReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            return reason
        }

        switch penaltyKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "task_block":
            return "Overdue task blocked attendance."
        case "hr_deadline":
            return "HR Attendance Review deadline missed."
        case "ro_deadline":
            return "Team approval deadline missed."
        default:
            if approvedByName?.trimmingCharacters(in: .whitespacesAndNewlines) == "System (HR deadline)" {
                return "HR Attendance Review deadline missed."
            }
            if approvedByName?.trimmingCharacters(in: .whitespacesAndNewlines) == "System (RO deadline)" {
                return "Team approval deadline missed."
            }
            return "Marked Absent because of an attendance penalty."
        }
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

    static func placeholder(date: String) -> ConvexAttendanceRecord {
        ConvexAttendanceRecord(
            _id: nil,
            _creationTime: nil,
            attendanceId: nil,
            date: date,
            firstPunchIn: nil,
            lastPunchOut: nil,
            punchInTime: nil,
            punchOutTime: nil,
            hasOpenSession: nil,
            sessionCount: nil,
            sessions: [],
            totalMinutes: 0,
            cumulativeMinutes: 0,
            attendanceValue: nil,
            staffId: nil,
            staffName: nil,
            designation: nil,
            employeeId: nil,
            staffPhotoUrl: nil,
            requestType: nil,
            requestedPunchIn: nil,
            requestedPunchOut: nil,
            requestReason: nil,
            requestStage: nil,
            source: nil,
            status: nil,
            approvedAttendance: nil,
            approvedBy: nil,
            approvedByName: nil,
            approvedOn: nil,
            penaltyKind: nil,
            penaltyReason: nil,
            penaltyTaskId: nil,
            penaltyTaskUrl: nil,
            lateMinutes: nil,
            fineAmount: nil,
            lateFineDeduction: nil,
            otherFines: nil
        )
    }
}

struct ConvexHomeFence: Decodable, Equatable, Sendable {
    let enabled: Bool
    let lat: Double?
    let lng: Double?
    let radiusMeters: Int
    let enforceable: Bool?
}

struct ConvexTodayAttendance: Codable, Equatable, Sendable {
    let _id: String?
    let attendanceId: String?
    let date: String?
    let firstPunchIn: String?
    let lastPunchOut: String?
    let hasOpenSession: Bool?
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
    let sessions: [ConvexAttendanceSession]?
    let source: String?
    let status: String?
    let remarks: String?

    var hasPunchedIn: Bool { (firstPunchIn ?? punchInTime) != nil }
    var hasPunchedOut: Bool { (lastPunchOut ?? punchOutTime) != nil }
    var isOpen: Bool { hasOpenSession == true || (hasPunchedIn && !hasPunchedOut) }

    var punchInDate: Date? {
        guard let t = firstPunchIn ?? punchInTime else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: t)
    }

    var punchOutDate: Date? {
        guard let t = lastPunchOut ?? punchOutTime else { return nil }
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
    let punchInAddress: String?
    let punchInPhoto: String?
    let punchOutLatitude: Double?
    let punchOutLongitude: Double?
    let punchOutAddress: String?
    let punchOutPhoto: String?
    let source: String?
    let punchOutSource: String?

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
    let reportingTo: String?

    var id: String { _id }

    private enum CodingKeys: String, CodingKey {
        case _id
        case id
        case name
        case phone
        case role
        case designation
        case status
        case employeeId
        case department
        case reportingTo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decodeIfPresent(String.self, forKey: ._id)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        designation = try container.decodeIfPresent(String.self, forKey: .designation)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        employeeId = try container.decodeIfPresent(String.self, forKey: .employeeId)
        department = try container.decodeIfPresent(String.self, forKey: .department)
        reportingTo = try container.decodeIfPresent(String.self, forKey: .reportingTo)
    }

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
