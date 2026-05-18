import Foundation
import SwiftUI

/// Mirrors the Android `TodayVisit` payload returned by `GET /api/sitevisits/my`.
/// Field aliases handle the historical name variants the Convex backend has
/// emitted for the start/end times — see `Mconnect/network/GeoTrackApi.kt`.
struct ConvexSiteVisit: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let clientPlaceId: String?
    let scheduledDate: String?
    let status: String?
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

    var id: String { _id }

    enum CodingKeys: String, CodingKey {
        case _id, clientPlaceId, scheduledDate, status, placeName, placeAddress, placeType
        case placeLat, placeLng, tripType, clientPlaceVisitId, leadName, leadPhone, cpVisit
        case scheduledStartTime, scheduledEndTime
        case startTime, endTime, scheduledTime, scheduledFrom, scheduledTo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)
        clientPlaceId = try container.decodeIfPresent(String.self, forKey: .clientPlaceId)
        scheduledDate = try container.decodeIfPresent(String.self, forKey: .scheduledDate)
        status = try container.decodeIfPresent(String.self, forKey: .status)
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
        scheduledStartTime = try container.decodeFirstPresentString(for: [.scheduledStartTime, .startTime, .scheduledTime, .scheduledFrom])
        scheduledEndTime = try container.decodeFirstPresentString(for: [.scheduledEndTime, .endTime, .scheduledTo])
    }

    /// Canonical bucket (matches the Android `bindRow` mapping).
    var statusBucket: SiteVisitStatus {
        switch (status ?? "").lowercased() {
        case "completed": return .completed
        case "picked_up", "on_site", "dropped", "in-progress", "in_progress",
             "client_started", "ongoing", "started", "active", "arrived":
            return .inProgress
        case "cancelled", "canceled", "no_show": return .cancelled
        default: return .scheduled
        }
    }
}

struct CpVisitDetailResponse: Decodable, Sendable {
    let success: Bool
    let visit: CpVisitDetail?
    let error: String?
}

struct CpVisitDetail: Decodable, Identifiable, Sendable {
    let id: String
    let leadId: String?
    let clientId: String?
    let clientPlaceId: String?
    let origin: String?
    let telecallerStaffId: String?
    let assignedStaffId: String?
    let assignedAt: Int64?
    let scheduledDate: String?
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
    let cancelledAt: Int64?
    let expectedAttendeeCount: Int?
    let foodPreferences: String?
    let vehiclePreference: String?
    let isBookingCompleted: Bool?
    let createdAt: Int64?
    let updatedAt: Int64?
    let lead: CpVisitLead?
    let client: CpVisitClient?
    let telecaller: CpVisitStaff?
    let assignedStaff: CpVisitStaff?
    let clientPlace: CpVisitPlace?
    let fieldVisit: CpVisitFieldVisit?
    let arrivalProof: CpVisitArrivalProof?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case leadId, clientId, clientPlaceId, origin, telecallerStaffId, assignedStaffId
        case assignedAt, scheduledDate, scheduledTime, status, clientMet, clientMetAt
        case clientNoShowReason, outcome, postponeReasons, convertedSiteVisitId
        case convertedBookingId, fieldVisitId, notes, completedAt, cancelledAt
        case expectedAttendeeCount, foodPreferences, vehiclePreference, isBookingCompleted
        case createdAt, updatedAt, lead, client, telecaller, assignedStaff, clientPlace
        case fieldVisit, arrivalProof
    }
}

struct CpVisitLead: Decodable, Sendable {
    let id: String?
    let contactName: String?
    let mobileNumber: String?
    let city: String?
    let preferredArea: String?
    let followUpStatus: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case contactName, mobileNumber, city, preferredArea, followUpStatus
    }
}

struct CpVisitClient: Decodable, Sendable {
    let id: String?
    let clientName: String?
    let mobileNumber: String?
    let city: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case clientName, mobileNumber, city
    }
}

struct CpVisitStaff: Decodable, Sendable {
    let id: String?
    let staffName: String?
    let staffCode: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case staffName, staffCode
    }
}

struct CpVisitPlace: Decodable, Sendable {
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
    let contactPerson: String?
    let contactPhone: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, address, formattedAddress, landmark, city, state, pincode
        case lat, lng, contactPerson, contactPhone
    }
}

struct CpVisitFieldVisit: Decodable, Sendable {
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

struct CpVisitArrivalProof: Decodable, Sendable {
    let photoStorageId: String?
    let photoUrl: String?
    let otpVerifiedAt: Int64?
    let otpRequestedAt: Int64?
    let gpsLat: Double?
    let gpsLng: Double?
    let distanceFromPlaceMeters: Double?
}

struct ConvexCPVisitState: Decodable, Equatable, Sendable {
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

enum SiteVisitStatus: String, CaseIterable, Identifiable, Sendable {
    case all
    case scheduled
    case inProgress
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .secondary
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }
}
