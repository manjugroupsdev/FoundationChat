import Foundation

enum FleetDispatchScope: Equatable, Sendable {
    case agency
    case mms
}

struct FleetDispatchProject: Decodable, Hashable, Sendable {
    let id: String
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

struct FleetDispatchVehicleReference: Decodable, Hashable, Sendable {
    let id: String
    let vehicleNumber: String?
    let type: String?
    let capacity: Int?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case vehicleNumber, type, capacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        vehicleNumber = try container.decodeIfPresent(String.self, forKey: .vehicleNumber)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        capacity = try container.decodeIfPresent(Int.self, forKey: .capacity)
    }
}

struct FleetDispatchTrip: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let scheduledDate: String?
    let scheduledTime: String?
    let pickupAddress: String?
    let pickupTime: String?
    let expectedAttendeeCount: Int?
    let vehiclePreference: String?
    let driverName: String?
    let driverPhone: String?
    let status: String?
    let vehicleId: String?
    let project: FleetDispatchProject?
    let vehicle: FleetDispatchVehicleReference?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case scheduledDate, scheduledTime, pickupAddress, pickupTime
        case expectedAttendeeCount, vehiclePreference, driverName, driverPhone
        case status, vehicleId, project, vehicle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        scheduledDate = try container.decodeIfPresent(String.self, forKey: .scheduledDate)
        scheduledTime = try container.decodeIfPresent(String.self, forKey: .scheduledTime)
        pickupAddress = try container.decodeIfPresent(String.self, forKey: .pickupAddress)
        pickupTime = try container.decodeIfPresent(String.self, forKey: .pickupTime)
        expectedAttendeeCount = try container.decodeIfPresent(Int.self, forKey: .expectedAttendeeCount)
        vehiclePreference = try container.decodeIfPresent(String.self, forKey: .vehiclePreference)
        driverName = try container.decodeIfPresent(String.self, forKey: .driverName)
        driverPhone = try container.decodeIfPresent(String.self, forKey: .driverPhone)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        vehicleId = try container.decodeIfPresent(String.self, forKey: .vehicleId)
        project = try container.decodeIfPresent(FleetDispatchProject.self, forKey: .project)
        vehicle = try container.decodeIfPresent(FleetDispatchVehicleReference.self, forKey: .vehicle)
    }

    var isCompleted: Bool {
        status?.localizedCaseInsensitiveCompare("completed") == .orderedSame
    }
}

struct FleetDispatchVehicle: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let vehicleNumber: String?
    let type: String?
    let capacity: Int?
    let defaultDriverName: String?
    let defaultDriverPhone: String?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case vehicleNumber, type, capacity, defaultDriverName, defaultDriverPhone, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        vehicleNumber = try container.decodeIfPresent(String.self, forKey: .vehicleNumber)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        capacity = try container.decodeIfPresent(Int.self, forKey: .capacity)
        defaultDriverName = try container.decodeIfPresent(String.self, forKey: .defaultDriverName)
        defaultDriverPhone = try container.decodeIfPresent(String.self, forKey: .defaultDriverPhone)
        status = try container.decodeIfPresent(String.self, forKey: .status)
    }

    var isActive: Bool {
        status?.localizedCaseInsensitiveCompare("inactive") != .orderedSame
    }
}

struct FleetDispatchDriver: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let phone: String?
    let address: String?
    /// Lowercase MMS contract value: "old" or "new" (Android TravelDeskDriver).
    let category: String?
    let status: String

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case name, phone, address, category, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Driver"
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
    }

    var isActive: Bool { status.localizedCaseInsensitiveCompare("active") == .orderedSame }
}

struct FleetAllocationDraft: Sendable {
    let vehicleId: String
    let pickupTime: String
    let pricingMode: String
    let driverName: String
    let driverPhone: String
    let amount: Double
}

// MARK: - MMS dispatch: external agencies

/// An external travel agency an MMS dispatcher can allot a trip to.
/// Mirrors Android TravelDeskAgency (network/TravelDeskModels.kt).
struct FleetDispatchAgency: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let status: String?
    let mobileNumber: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case name, status, mobileNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        mobileNumber = try container.decodeIfPresent(String.self, forKey: .mobileNumber)
    }

    var isActive: Bool {
        status?.localizedCaseInsensitiveCompare("inactive") != .orderedSame
    }
}

// MARK: - Billing: custom charge line

/// A custom charge applied at completion / billing. `unit` is one of
/// km / hour / minute / person / toll / trip (kept for display). Mirrors
/// Android TravelDeskAppliedCharge. Codable because it rides on both the
/// billing request (encode) and the trip payload (decode).
struct FleetAppliedCharge: Codable, Hashable, Sendable {
    let label: String?
    let amount: Double?
    let unit: String?

    init(label: String?, amount: Double?, unit: String?) {
        self.label = label
        self.amount = amount
        self.unit = unit
    }
}

// MARK: - Encodable request drafts
//
// These mirror the Android request data classes (network/TravelDeskModels.kt).
// Field names match the wire keys exactly; optional fields are dropped when nil
// (Swift synthesises encodeIfPresent), which the backend treats as absent.

/// POST api/travel-desk/vehicles/update. `status` carries the active/inactive
/// change — Android folds status-change into this same route (no separate one).
struct FleetVehicleUpdateDraft: Encodable, Sendable {
    let id: String
    var vehicleNumber: String? = nil
    var type: String? = nil
    var capacity: Int? = nil
    var defaultDriverName: String? = nil
    var defaultDriverPhone: String? = nil
    var status: String? = nil
}

/// POST api/travel-desk/trips/finalize-billing.
struct FleetFinalizeBillingDraft: Encodable, Sendable {
    let siteVisitId: String
    let startKm: Double
    let endKm: Double
    var startPhotoIds: [String]? = nil
    var endPhotoIds: [String]? = nil
    var kmRate: Double? = nil
    var packageAmount: Double? = nil
    var beta: Double? = nil
    var beta2: Double? = nil
    var tollAmount: Double? = nil
    var hillCharge: Double? = nil
    var outstationCharge: Double? = nil
    var permitCharge: Double? = nil
    var permitTax: Double? = nil
    var standingCharge: Double? = nil
    var customCharges: [FleetAppliedCharge]? = nil
    var vehicleId: String? = nil
    var driverName: String? = nil
    var driverPhone: String? = nil
}

/// POST api/travel-desk/trips/evidence.
struct FleetEvidenceDraft: Encodable, Sendable {
    let siteVisitId: String
    var startPhotoIds: [String]? = nil
    var startKm: Double? = nil
    var endPhotoIds: [String]? = nil
    var endKm: Double? = nil
}

/// POST api/travel-desk/trips/status-update.
struct FleetStatusUpdateDraft: Encodable, Sendable {
    let siteVisitId: String
    let reasonCode: String
    var reasonText: String? = nil
    var voiceStorageId: String? = nil
    var voiceDurationMs: Int? = nil
    var scheduledDate: String? = nil
    var scheduledTime: String? = nil
}

/// POST api/{mms-fleet/dispatch,travel-desk/trips}/complete-offline.
struct FleetOfflineCompletionDraft: Encodable, Sendable {
    let siteVisitId: String
    var packageAmount: Double? = nil
    var kmRate: Double? = nil
    var distanceKm: Double? = nil
    var driverName: String? = nil
    var driverPhone: String? = nil
    var beta: Double? = nil
    var beta2: Double? = nil
    var tollAmount: Double? = nil
    var hillCharge: Double? = nil
    var outstationCharge: Double? = nil
    var permitCharge: Double? = nil
    var permitTax: Double? = nil
    var standingCharge: Double? = nil
    var fleetType: String? = nil
    var vehicleId: String? = nil
    var agencyName: String? = nil
    var standingTimeMinutes: Int? = nil
    var standingWithAc: Bool? = nil
    var startKm: Double? = nil
    var endKm: Double? = nil
    var startPhotoIds: [String]? = nil
    var endPhotoIds: [String]? = nil
}
