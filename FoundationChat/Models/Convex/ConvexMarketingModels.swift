import Foundation
import SwiftUI

/// Mirrors the Android `TodayVisit` payload returned by `GET /api/sitevisits/my`.
/// Field aliases handle the historical name variants the Convex backend has
/// emitted for the start/end times — see `Mconnect/network/GeoTrackApi.kt`.
struct ConvexSiteVisit: Codable, Identifiable, Equatable, Sendable {
    let _id: String
    let clientPlaceId: String?
    let scheduledDate: String?
    let status: String?
    let rawStatus: String?
    let placeName: String?
    let placeAddress: String?
    let placeType: String?
    let placeLat: Double?
    let placeLng: Double?
    let scheduledStartTime: String?
    let scheduledEndTime: String?
    let tripType: String?
    let clientPlaceVisitId: String?
    let leadName: String?
    let leadPhone: String?
    let cpVisit: ConvexCPVisitState?
    let outcome: String?
    let convertedBookingId: String?
    let convertedSiteVisitId: String?
    let completedAt: Int64?
    let completedOffline: Bool?
    let creationTime: Double?
    let travelMode: String?
    let vehiclePreference: String?
    let vehicleAssigned: Bool?
    let confirmationStatus: String?
    let visitCategory: String?
    let lmoName: String?
    let lmoStaffId: String?
    // The visit's assigned BDO from the backend, never the signed-in viewer.
    let bdoName: String?
    let bdoStaffId: String?
    let staffName: String?
    let projectId: String?
    let projectName: String?

    var id: String { _id }

    enum CodingKeys: String, CodingKey {
        case _id, clientPlaceId, scheduledDate, status, rawStatus, placeName, placeAddress, placeType
        case placeLat, placeLng, tripType, clientPlaceVisitId, leadName, leadPhone, cpVisit
        case outcome, convertedBookingId, convertedSiteVisitId, completedAt, completedOffline
        case creationTime, travelMode, vehiclePreference, vehicleAssigned, confirmationStatus, visitCategory
        case lmoName, lmoStaffId, bdoName, bdoStaffId, staffName, projectId, projectName
        case scheduledStartTime, scheduledEndTime
        case startTime, endTime, scheduledTime, scheduledFrom, scheduledTo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)
        clientPlaceId = try container.decodeIfPresent(String.self, forKey: .clientPlaceId)
        scheduledDate = try container.decodeIfPresent(String.self, forKey: .scheduledDate)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        rawStatus = try container.decodeIfPresent(String.self, forKey: .rawStatus)
        placeName = try container.decodeIfPresent(String.self, forKey: .placeName)
        placeAddress = try container.decodeIfPresent(String.self, forKey: .placeAddress)
        placeType = try container.decodeIfPresent(String.self, forKey: .placeType)
        placeLat = try container.decodeIfPresent(Double.self, forKey: .placeLat)
        placeLng = try container.decodeIfPresent(Double.self, forKey: .placeLng)
        tripType = try container.decodeIfPresent(String.self, forKey: .tripType)
        clientPlaceVisitId = try container.decodeIfPresent(String.self, forKey: .clientPlaceVisitId)
        leadName = try container.decodeIfPresent(String.self, forKey: .leadName)
        leadPhone = try container.decodeIfPresent(String.self, forKey: .leadPhone)
        cpVisit = try container.decodeIfPresent(ConvexCPVisitState.self, forKey: .cpVisit)
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome)
        convertedBookingId = try container.decodeIfPresent(String.self, forKey: .convertedBookingId)
        convertedSiteVisitId = try container.decodeIfPresent(String.self, forKey: .convertedSiteVisitId)
        completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAt)
        completedOffline = try container.decodeIfPresent(Bool.self, forKey: .completedOffline)
        creationTime = try container.decodeIfPresent(Double.self, forKey: .creationTime)
        travelMode = try container.decodeIfPresent(String.self, forKey: .travelMode)
        vehiclePreference = try container.decodeIfPresent(String.self, forKey: .vehiclePreference)
        vehicleAssigned = try container.decodeIfPresent(Bool.self, forKey: .vehicleAssigned)
        confirmationStatus = try container.decodeIfPresent(String.self, forKey: .confirmationStatus)
        visitCategory = try container.decodeIfPresent(String.self, forKey: .visitCategory)
        lmoName = try container.decodeIfPresent(String.self, forKey: .lmoName)
        lmoStaffId = try container.decodeIfPresent(String.self, forKey: .lmoStaffId)
        bdoName = try container.decodeIfPresent(String.self, forKey: .bdoName)
        bdoStaffId = try container.decodeIfPresent(String.self, forKey: .bdoStaffId)
        staffName = try container.decodeIfPresent(String.self, forKey: .staffName)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        scheduledStartTime = try container.decodeFirstPresentString(for: [.scheduledStartTime, .startTime, .scheduledTime, .scheduledFrom])
        scheduledEndTime = try container.decodeFirstPresentString(for: [.scheduledEndTime, .endTime, .scheduledTo])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encodeIfPresent(clientPlaceId, forKey: .clientPlaceId)
        try container.encodeIfPresent(scheduledDate, forKey: .scheduledDate)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(rawStatus, forKey: .rawStatus)
        try container.encodeIfPresent(placeName, forKey: .placeName)
        try container.encodeIfPresent(placeAddress, forKey: .placeAddress)
        try container.encodeIfPresent(placeType, forKey: .placeType)
        try container.encodeIfPresent(placeLat, forKey: .placeLat)
        try container.encodeIfPresent(placeLng, forKey: .placeLng)
        try container.encodeIfPresent(scheduledStartTime, forKey: .scheduledStartTime)
        try container.encodeIfPresent(scheduledEndTime, forKey: .scheduledEndTime)
        try container.encodeIfPresent(tripType, forKey: .tripType)
        try container.encodeIfPresent(clientPlaceVisitId, forKey: .clientPlaceVisitId)
        try container.encodeIfPresent(leadName, forKey: .leadName)
        try container.encodeIfPresent(leadPhone, forKey: .leadPhone)
        try container.encodeIfPresent(cpVisit, forKey: .cpVisit)
        try container.encodeIfPresent(outcome, forKey: .outcome)
        try container.encodeIfPresent(convertedBookingId, forKey: .convertedBookingId)
        try container.encodeIfPresent(convertedSiteVisitId, forKey: .convertedSiteVisitId)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(completedOffline, forKey: .completedOffline)
        try container.encodeIfPresent(creationTime, forKey: .creationTime)
        try container.encodeIfPresent(travelMode, forKey: .travelMode)
        try container.encodeIfPresent(vehiclePreference, forKey: .vehiclePreference)
        try container.encodeIfPresent(vehicleAssigned, forKey: .vehicleAssigned)
        try container.encodeIfPresent(confirmationStatus, forKey: .confirmationStatus)
        try container.encodeIfPresent(visitCategory, forKey: .visitCategory)
        try container.encodeIfPresent(lmoName, forKey: .lmoName)
        try container.encodeIfPresent(lmoStaffId, forKey: .lmoStaffId)
        try container.encodeIfPresent(bdoName, forKey: .bdoName)
        try container.encodeIfPresent(bdoStaffId, forKey: .bdoStaffId)
        try container.encodeIfPresent(staffName, forKey: .staffName)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encodeIfPresent(projectName, forKey: .projectName)
    }

    /// Canonical bucket (matches the Android `bindRow` mapping).
    var statusBucket: SiteVisitStatus {
        switch (status ?? "").lowercased() {
        case "completed": return .completed
        case "client_started", "started":
            return .clientStarted
        case "picked_up":
            return .pickedUp
        case "on_site", "dropped", "in-progress", "in_progress",
             "ongoing", "active", "arrived", "consulting", "on_counselling",
             "picked_from_site":
            return .inProgress
        case "cancelled", "canceled", "no_show": return .cancelled
        default: return .scheduled
        }
    }

    var hasLockedOutcome: Bool {
        let ownOutcome = outcome?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cpOutcome = cpVisit?.outcome?.trimmingCharacters(in: .whitespacesAndNewlines)
        let booking = convertedBookingId?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ownOutcome?.isEmpty == false
            || cpOutcome?.isEmpty == false
            || booking?.isEmpty == false
            || completedAt != nil
    }
}

struct SiteVisitQRScanResponse: Decodable, Sendable {
    let success: Bool
    let visit: ScannedSiteVisit?
    let error: String?
}

struct ScannedSiteVisit: Decodable, Identifiable, Sendable {
    let _id: String
    let status: String?
    let outcome: String?
    let notes: String?
    let scheduledDate: String?
    let scheduledTime: String?
    let canStartCounselling: Bool?
    let canRecordOutcome: Bool?
    let expectedAttendeeCount: Int?
    let attendees: [ScannedSiteVisitAttendee]?
    let foodPreferences: String?
    let project: ScannedSiteVisitProject?
    let lead: ScannedSiteVisitLead?
    let client: ScannedSiteVisitClient?
    let bdoStaff: ScannedSiteVisitStaff?
    let telecallerStaff: ScannedSiteVisitStaff?
    let inchargeStaff: ScannedSiteVisitStaff?

    var id: String { _id }
}

struct ScannedSiteVisitProject: Decodable, Sendable {
    let name: String?
    let projectName: String?
}

struct ScannedSiteVisitLead: Decodable, Sendable {
    let clientName: String?
    let contactName: String?
    let mobileNumber: String?
    let mobileNumberNormalized: String?
    let profession: String?
    let temperature: String?
}

struct ScannedSiteVisitClient: Decodable, Sendable {
    let clientName: String?
    let mobileNumber: String?
    let mobileNumberNormalized: String?
    let profession: String?
}

struct ScannedSiteVisitStaff: Decodable, Sendable {
    let id: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

struct ScannedSiteVisitAttendee: Decodable, Sendable {
    let name: String?
    let relation: String?
    let age: String?
    let isVeg: Bool?
    let notes: String?
}

struct CpVisitDetailResponse: Codable, Sendable {
    let success: Bool
    let visit: CpVisitDetail?
    let error: String?
}

struct MyMarketingCpVisitsResponse: Codable, Sendable {
    let success: Bool
    let total: Int?
    let visits: [CpVisitDetail]
    let scope: String?
    let directReportIds: [String]?
    let canViewTeam: Bool?
    let error: String?
}

struct CpVisitDetail: Codable, Identifiable, Sendable {
    let id: String
    let leadId: String?
    let clientId: String?
    let clientPlaceId: String?
    let origin: String?
    let telecallerStaffId: String?
    let assignedStaffId: String?
    let assignedAt: Int64?
    let scheduledDate: String?
    let activityDate: String?
    let scheduledTime: String?
    let status: String?
    let clientMet: Bool?
    let clientMetAt: Int64?
    let clientNoShowReason: String?
    let outcome: String?
    let postponeReasons: [String]?
    let convertedSiteVisitId: String?
    let convertedBookingId: String?
    let fieldVisitId: String?
    let notes: String?
    let completedAt: Int64?
    let completedOffline: Bool?
    let cancelledAt: Int64?
    let expectedAttendeeCount: Int?
    let foodPreferences: String?
    let vehiclePreference: String?
    let driverName: String?
    let driverPhone: String?
    let cpType: String?
    let jointCpCategory: String?
    let projectId: String?
    let isBookingCompleted: Bool?
    let createdAt: Int64?
    let updatedAt: Int64?
    let proposedSiteVisit: ProposedSiteVisit?
    let attendees: [CpVisitAttendee]?
    let lead: CpVisitLead?
    let client: CpVisitClient?
    let telecaller: CpVisitStaff?
    let assignedStaff: CpVisitStaff?
    let clientPlace: CpVisitPlace?
    let fieldVisit: CpVisitFieldVisit?
    let arrivalProof: CpVisitArrivalProof?
    let project: CpVisitProject?
    let inchargeStaff: CpVisitStaff?
    let joint: JointCpSummary?
    // Client-not-met auto-reschedule: how many times this visit has bounced on
    // "client not met", the last not-met date, and — once the client has been
    // not-met 3+ times in a row — a warning flag for the card.
    let rescheduleCount: Int?
    let lastNotMetDate: String?
    let clientUnavailableWarning: Bool?
    // Out-of-geofence GM approval: the GM the staff is waiting on (while
    // pending_gm_approval), and — after a GM reject — the remark + the flag that
    // this visit was reopened for the same staff.
    let approvalGmName: String?
    let rejectRemark: String?
    let reassignedFromRejection: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case leadId, clientId, clientPlaceId, origin, telecallerStaffId, assignedStaffId
        case assignedAt, scheduledDate, activityDate, scheduledTime, status, clientMet, clientMetAt
        case clientNoShowReason, outcome, postponeReasons, convertedSiteVisitId
        case convertedBookingId, fieldVisitId, notes, completedAt, completedOffline, cancelledAt
        case expectedAttendeeCount, foodPreferences, vehiclePreference, driverName, driverPhone
        case cpType, jointCpCategory, projectId, isBookingCompleted
        case createdAt, updatedAt, lead, client, telecaller, assignedStaff, clientPlace
        case proposedSiteVisit, attendees, fieldVisit, arrivalProof, project, inchargeStaff, joint
        case rescheduleCount, lastNotMetDate, clientUnavailableWarning
        case approvalGmName, rejectRemark, reassignedFromRejection
    }
}

struct JointCpParticipant: Codable, Sendable {
    let staffId: String?
    let staffName: String?
    let isPrimary: Bool?
    let status: String?
    let outcome: String?
    let notes: String?
    let clientMet: Bool?
    let startedAt: Int64?
    let completedAt: Int64?
    let distanceMeters: Double?
    let outOfGeofence: Bool?
}

struct JointCpSummary: Codable, Sendable {
    let participants: [JointCpParticipant]?
    let leadStaffName: String?
    let leadStaffId: String?
    let companionNames: [String]?
    let totalCount: Int?
}

struct CpVisitProject: Codable, Sendable {
    let id: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

struct ProposedSiteVisit: Codable, Sendable {
    let id: String?
    let projectId: String?
    let scheduledDate: String?
    let scheduledTime: String?
    let inchargeStaffId: String?
    let hodStaffId: String?
    let bdoStaffId: String?
    let avpStaffId: String?
    let gmStaffId: String?
    let seniorManagerStaffId: String?
    let status: String?
    let outcome: String?
    let convertedBookingId: String?
    let cancelledAt: Int64?
    let travelMode: String?
    let vehicleId: String?
    let travelAgencyId: String?
    let driverName: String?
    let driverPhone: String?
    let pickedUpAt: Int64?
    let arrivedSiteAt: Int64?
    let consultingAt: Int64?
    let consultingVerifiedByStaffId: String?
    let pickedFromSiteAt: Int64?
    let droppedAt: Int64?
    let completedAt: Int64?
    let travelDeskStartedAt: Int64?
    let travelDeskArrivedAt: Int64?
    let travelDeskOnSiteAt: Int64?
    let travelDeskPickedFromSiteAt: Int64?
    let travelDeskEndedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case projectId, scheduledDate, scheduledTime, inchargeStaffId, hodStaffId
        case bdoStaffId, avpStaffId, gmStaffId, seniorManagerStaffId
        case status, outcome, convertedBookingId, cancelledAt, travelMode, vehicleId, travelAgencyId
        case driverName, driverPhone, pickedUpAt, arrivedSiteAt, consultingAt
        case consultingVerifiedByStaffId, pickedFromSiteAt, droppedAt, completedAt
        case travelDeskStartedAt, travelDeskArrivedAt, travelDeskOnSiteAt
        case travelDeskPickedFromSiteAt, travelDeskEndedAt
    }

    var isMeaningful: Bool {
        [
            projectId, scheduledDate, scheduledTime, inchargeStaffId, hodStaffId,
            bdoStaffId, avpStaffId, gmStaffId, seniorManagerStaffId
        ]
        .contains { $0?.nilIfBlank != nil }
    }
}

struct CpVisitAttendee: Codable, Sendable {
    let name: String?
    let relation: String?
    let age: String?
    let isVeg: Bool?
    let notes: String?
}

struct CpVisitLead: Codable, Sendable {
    let id: String?
    let contactName: String?
    let mobileNumber: String?
    let city: String?
    let preferredArea: String?
    let followUpStatus: String?
    let manualProfile: CpVisitLeadManualProfile?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case contactName, mobileNumber, city, preferredArea, followUpStatus, manualProfile
    }
}

struct CpVisitLeadManualProfile: Codable, Sendable {
    let clientName: String?
}

struct CpVisitClient: Codable, Sendable {
    let id: String?
    let clientName: String?
    let mobileNumber: String?
    let city: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case clientName, mobileNumber, city
    }
}

struct CpVisitStaff: Codable, Sendable {
    let id: String?
    let name: String?
    let staffName: String?
    let staffCode: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, staffName, staffCode
    }
}

struct CpVisitPlace: Codable, Sendable {
    let id: String?
    let name: String?
    let address: String?
    let formattedAddress: String?
    let landmark: String?
    let city: String?
    let state: String?
    let pincode: String?
    let lat: Double?
    let lng: Double?
    let googleMapsLink: String?
    let contactPerson: String?
    let contactPhone: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, address, formattedAddress, landmark, city, state, pincode
        case lat, lng, googleMapsLink, contactPerson, contactPhone
    }
}

struct CpVisitFieldVisit: Codable, Sendable {
    let id: String?
    let status: String?
    let startedAt: Int64?
    let completedAt: Int64?
    let distanceMeters: Double?
    let durationMinutes: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, startedAt, completedAt, distanceMeters, durationMinutes
    }
}

struct CpVisitArrivalProof: Codable, Sendable {
    let photoStorageId: String?
    let photoUrl: String?
    let otpVerifiedAt: Int64?
    let otpRequestedAt: Int64?
    let gpsLat: Double?
    let gpsLng: Double?
    let distanceFromPlaceMeters: Double?
}

struct AddressParseRequest: Encodable, Sendable {
    let raw: String
}

struct AddressParseResponse: Decodable, Sendable {
    let success: Bool
    let fields: ParsedAddressFields?
    let error: String?
}

struct ParsedAddressFields: Decodable, Equatable, Sendable {
    let doorNo: String?
    let street: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let pincode: String?
}

struct ConvexCPVisitState: Codable, Equatable, Sendable {
    let clientMet: Bool?
    let clientMetAt: Double?
    let clientNoShowReason: String?
    let outcome: String?
    let postponeReasons: [String]?
}

private extension KeyedDecodingContainer {
    func decodeFirstPresentString(for keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Booking draft (auto-save / resume / clear)
//
// Mirrors Android `BookingDraftManager` + `ApiService` bookings/draft/{save,get,clear}.
// The mobile owns the opaque `draftJson` blob shape; the backend stores it as a
// plain string keyed on `sourceKey` (e.g. "cp:<cpVisitId>"). `updatedAt` lets the
// client prefer whichever of the local/cloud copies is newer on resume.

struct BookingDraftSaveRequest: Encodable, Sendable {
    let sourceKey: String
    let sourceCpVisitId: String?
    let sourceSiteVisitId: String?
    let draftJson: String
}

struct BookingDraftPayload: Decodable, Sendable {
    let sourceKey: String?
    let draftJson: String?
    let updatedAt: Double?
}

struct BookingDraftGetResponse: Decodable, Sendable {
    let success: Bool
    let draft: BookingDraftPayload?
    let error: String?
}

struct BookingPincodePrefill: Sendable {
    let locality: String?
    let district: String?
    let state: String?
}

enum SiteVisitStatus: String, CaseIterable, Identifiable, Sendable {
    case all
    case scheduled
    case clientStarted
    case pickedUp
    case inProgress
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .scheduled: return "Scheduled"
        case .clientStarted: return "Client Started"
        case .pickedUp: return "Picked Up"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .secondary
        case .scheduled: return .blue
        case .clientStarted: return .cyan
        case .pickedUp: return .indigo
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }
}
