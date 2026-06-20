import Foundation

struct PostSaleCaseSummary: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let bookingId: String?
    let bookingRefNo: String?
    let clientName: String?
    let mobileNumber: String?
    let projectName: String?
    let plotNo: String?
    let totalAmount: Double?
    let approvedCollectedAmount: Double?
    let pendingCollectedAmount: Double?
    let balanceAmount: Double?
    let tenPercentAmount: Double?
    let currentStage: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case bookingId, bookingRefNo, clientName, mobileNumber, projectName, plotNo
        case totalAmount, approvedCollectedAmount, pendingCollectedAmount
        case balanceAmount, tenPercentAmount, currentStage
    }

    var title: String { clientName?.nonBlank ?? bookingRefNo?.nonBlank ?? "Post-sale Case" }
    var subtitle: String {
        [projectName, plotNo, mobileNumber].compactMap { $0?.nonBlank }.joined(separator: " · ")
    }
}

struct CustomerCollectionRow: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let collectionRefNo: String?
    let caseId: String?
    let bookingId: String?
    let amount: Double?
    let collectionDate: String?
    let paymentMode: String?
    let transactionReference: String?
    let bankName: String?
    let notes: String?
    let collectedByName: String?
    let collectedByStaffId: String?
    let proofStorageId: String?
    let proofFileName: String?
    let verificationStatus: String?
    let verificationNotes: String?
    let verifiedByName: String?
    let verifiedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let customerName: String?
    let bookingRefNo: String?
    let projectName: String?
    let plotNo: String?
    let customerPaymentCategory: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case collectionRefNo, caseId, bookingId, amount, collectionDate, paymentMode
        case transactionReference, bankName, notes, collectedByName, collectedByStaffId
        case proofStorageId, proofFileName, verificationStatus, verificationNotes
        case verifiedByName, verifiedAt, createdAt, updatedAt, customerName
        case bookingRefNo, projectName, plotNo, customerPaymentCategory
    }

    var displayTitle: String { customerName?.nonBlank ?? bookingRefNo?.nonBlank ?? collectionRefNo?.nonBlank ?? "Collection" }
    var displayStatus: String { (verificationStatus ?? "pending").replacingOccurrences(of: "_", with: " ").capitalized }
}

struct SubmitCollectionRequest: Encodable, Sendable {
    let caseId: String
    let amount: Double
    let paymentMode: String
    let transactionReference: String?
    let bankName: String?
    let proofStorageId: String?
    let proofFileName: String?
    let notes: String?
}

struct LoanCaseDocument: Codable, Identifiable, Equatable, Sendable {
    var id: String { label }
    let label: String
    let storageId: String?
    let fileName: String?
    let approved: Bool?
}

struct LoanCaseRow: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let caseId: String?
    let bookingId: String?
    let name: String?
    let phone: String?
    let amount: Double?
    let location: String?
    let date: String?
    let statusLabel: String?
    let status: String?
    let applicantType: String?
    let requestedAmount: Double?
    let sanctionedAmount: Double?
    let documentsChecklist: [LoanCaseDocument]?
    let documentLabels: [String]?
    let documentCount: Int?
    let legalAssignedStaffId: String?
    let legalAssignedName: String?
    let legalAssignedAt: String?
    let legalRejectionRemarks: String?
    let legalClearedAt: String?
    let legalClearedByName: String?
    let submittedByStaffId: String?
    let submittedByName: String?
    let bookingRefNo: String?
    let projectName: String?
    let plotNo: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case caseId, bookingId, name, phone, amount, location, date, statusLabel
        case status, applicantType, requestedAmount, sanctionedAmount
        case documentsChecklist, documentLabels, documentCount, legalAssignedStaffId
        case legalAssignedName, legalAssignedAt, legalRejectionRemarks, legalClearedAt
        case legalClearedByName, submittedByStaffId, submittedByName, bookingRefNo
        case projectName, plotNo
    }

    var displayTitle: String { name?.nonBlank ?? bookingRefNo?.nonBlank ?? caseId?.nonBlank ?? "Loan Case" }
    var displayAmount: Double { requestedAmount ?? sanctionedAmount ?? amount ?? 0 }
    var displayStatus: String { statusLabel?.nonBlank ?? status?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Pending" }
}

struct LegalStaffRow: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String?
    let designation: String?
    let department: String?
    let employeeId: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, designation, department, employeeId
    }

    var displayName: String { name?.nonBlank ?? employeeId?.nonBlank ?? id }
}

struct SubmitLoanDocument: Encodable, Sendable {
    let label: String
    let storageId: String
    let fileName: String?
}

struct SubmitLoanDeskRequest: Encodable, Sendable {
    let caseId: String
    let applicantType: String
    let requestedAmount: Double?
    let documents: [SubmitLoanDocument]
}

struct AssignLoanRequest: Encodable, Sendable {
    let loanCaseId: String
    let legalStaffId: String
    let legalStaffName: String
}

struct FleetDriverTrip: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let scheduledDate: String?
    let scheduledTime: String?
    let pickupAddress: String?
    let pickupTime: String?
    let driverName: String?
    let driverPhone: String?
    let travelDeskArrivedAt: Int64?
    let travelDeskStartedAt: Int64?
    let travelDeskOnSiteAt: Int64?
    let travelDeskEndedAt: Int64?
    let travelDeskStartKm: Double?
    let travelDeskEndKm: Double?
    let travelDeskStartPhotoIds: [String]?
    let travelDeskEndPhotoIds: [String]?
    let phase: String?
    let canOperateToday: Bool?
    let km: Double?
    let project: FleetDriverProject?
    let vehicle: FleetDriverVehicle?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case scheduledDate, scheduledTime, pickupAddress, pickupTime, driverName
        case driverPhone, travelDeskArrivedAt, travelDeskStartedAt, travelDeskOnSiteAt
        case travelDeskEndedAt, travelDeskStartKm, travelDeskEndKm
        case travelDeskStartPhotoIds, travelDeskEndPhotoIds, phase, canOperateToday
        case km, project, vehicle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        scheduledDate = try container.decodeIfPresent(String.self, forKey: .scheduledDate)
        scheduledTime = try container.decodeIfPresent(String.self, forKey: .scheduledTime)
        pickupAddress = try container.decodeIfPresent(String.self, forKey: .pickupAddress)
        pickupTime = try container.decodeIfPresent(String.self, forKey: .pickupTime)
        driverName = try container.decodeIfPresent(String.self, forKey: .driverName)
        driverPhone = try container.decodeIfPresent(String.self, forKey: .driverPhone)
        travelDeskArrivedAt = try container.decodeLossyInt64IfPresent(forKey: .travelDeskArrivedAt)
        travelDeskStartedAt = try container.decodeLossyInt64IfPresent(forKey: .travelDeskStartedAt)
        travelDeskOnSiteAt = try container.decodeLossyInt64IfPresent(forKey: .travelDeskOnSiteAt)
        travelDeskEndedAt = try container.decodeLossyInt64IfPresent(forKey: .travelDeskEndedAt)
        travelDeskStartKm = try container.decodeLossyDoubleIfPresent(forKey: .travelDeskStartKm)
        travelDeskEndKm = try container.decodeLossyDoubleIfPresent(forKey: .travelDeskEndKm)
        travelDeskStartPhotoIds = try container.decodeIfPresent([String].self, forKey: .travelDeskStartPhotoIds)
        travelDeskEndPhotoIds = try container.decodeIfPresent([String].self, forKey: .travelDeskEndPhotoIds)
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
        canOperateToday = try container.decodeIfPresent(Bool.self, forKey: .canOperateToday)
        km = try container.decodeLossyDoubleIfPresent(forKey: .km)
        project = try container.decodeIfPresent(FleetDriverProject.self, forKey: .project)
        vehicle = try container.decodeIfPresent(FleetDriverVehicle.self, forKey: .vehicle)
    }

    var title: String { project?.name?.nonBlank ?? pickupAddress?.nonBlank ?? "Driver Trip" }
    var displayPhase: String { (phase ?? "scheduled").replacingOccurrences(of: "_", with: " ").capitalized }
}

struct FleetDriverProject: Decodable, Equatable, Sendable {
    let id: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

struct FleetDriverVehicle: Decodable, Equatable, Sendable {
    let id: String?
    let vehicleNumber: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case vehicleNumber, type
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try decodeIfPresent(String.self, forKey: key)?.nonBlank { return Double(value) }
        return nil
    }

    func decodeLossyInt64IfPresent(forKey key: Key) throws -> Int64? {
        if let value = try decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
        if let value = try decodeIfPresent(Double.self, forKey: key) { return Int64(value) }
        if let value = try decodeIfPresent(String.self, forKey: key)?.nonBlank { return Int64(value) }
        return nil
    }
}
